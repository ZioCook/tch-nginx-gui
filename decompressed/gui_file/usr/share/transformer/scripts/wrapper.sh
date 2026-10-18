#!/bin/sh

#
#  wrapper.sh - generic runner for WebUI maintenance commands (tch-nginx-gui)
#
#  Usage:  wrapper.sh "<command with args>"      (single string, legacy callers)
#          wrapper.sh <command> [arg ...]        (already split arguments)
#
#  Contract with the WebUI (commandlogread.lua polls state + /tmp/command_log):
#    Requested -> (child may set Downloading/Extracting/...) -> Complete | Failed
#    then, after a grace period, back to Idle and the log is removed.
#
#  - the child's exit status is honoured: non-zero => Failed (unless the child
#    already reported Failed/Error itself); zero => Complete (unless the child
#    already set its own final state, which is never overwritten with Complete)
#  - stdout+stderr go to the SAME open file description (> log 2>&1)
#  - the final state is only published AFTER the last log line is on disk
#  - on failure the log is kept for a longer grace period and a copy survives
#    in $LOG_LOCATION.failed (also sent to syslog) so the error can be read
#  - one run at a time: a second invocation waits for the first, so a late
#    "Idle + rm log" of run A can never wipe the log/state of run B

LOG_LOCATION="${LOG_LOCATION:-/tmp/command_log}"
LOCKDIR="${LOCKDIR:-/tmp/wrapper.lock}"
GRACE_OK="${GRACE_OK:-3}"        # s Complete stays visible (poll is 500 ms)
GRACE_FAIL="${GRACE_FAIL:-10}"   # s Failed stays visible with the log
LOCK_WAIT="${LOCK_WAIT:-15}"     # s a second invocation waits for the first
STATE_PATH='rpc.system.modgui.executeCommand.state'

LOCK_HELD=0
STATE_OPEN=0      # 1 once we published "Requested" and until a final state
child=""
INTERRUPTED=0

############TRANSFORMER UTILITY##################
# datamodel.set returns nil,err on rejection (e.g. error 9007, value not in the
# enumeration) but the lua process would still exit 0: turn it into a real
# exit status so callers can react.
set_transformer() {
  lua -e "local ok, err = require('datamodel').set('$1','$2'); if not ok then io.stderr:write(tostring(err), '\n'); os.exit(1) end"
}

get_transformer() {
  lua -e "local r = require('datamodel').get('$1'); if type(r) == 'table' and r[1] then io.write(tostring(r[1].value)) end" 2>/dev/null
}
#################################################

set_state() {
  set_transformer "$STATE_PATH" "$1" && return 0
  logger -t wrapper "WARNING: datamodel rejected state '$1'"
  return 1
}

# Failure state. 'Failed'/'Error' must be in the enumeration of
# system.modgui.map; if an older map rejects both, fall back to Complete
# (with an explicit line in the log) rather than leave the WebUI spinning.
set_failed() {
  set_state Failed && return 0
  set_state Error && return 0
  logger -t wrapper "WARNING: add \"Failed\" and \"Error\" to the state enumeration in system.modgui.map"
  echo "[wrapper] FAILED - the state 'Failed' is not supported by system.modgui.map, reported as Complete. See the messages above." >>"$LOG_LOCATION"
  sync
  set_state Complete
}

if [ $# -eq 0 ]; then
  echo "Usage: $0 \"<command [args]>\" | <command> [args...]" >&2
  exit 2
fi

acquire_lock() {
  waited=0
  while :; do
    if mkdir "$LOCKDIR" 2>/dev/null; then
      echo $$ >"$LOCKDIR/pid"
      LOCK_HELD=1
      return 0
    fi
    owner="$(cat "$LOCKDIR/pid" 2>/dev/null)"
    # owner gone => stale lock
    if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
      rm -rf "$LOCKDIR"
      continue
    fi
    if [ "$waited" -ge "$LOCK_WAIT" ]; then
      # pid file never written (crash between mkdir and echo): break it once
      if [ -z "$owner" ]; then
        rm -rf "$LOCKDIR"
        if mkdir "$LOCKDIR" 2>/dev/null; then
          echo $$ >"$LOCKDIR/pid"
          LOCK_HELD=1
          return 0
        fi
      fi
      return 1
    fi
    waited=$((waited + 1))
    sleep 1
  done
}

cleanup() {
  # Safety net: never leave the WebUI spinning on an intermediate state.
  if [ "$STATE_OPEN" = 1 ]; then
    STATE_OPEN=0
    echo "[wrapper] terminated unexpectedly" >>"$LOG_LOCATION" 2>/dev/null
    sync
    set_failed
  fi
  [ "$LOCK_HELD" = 1 ] && rm -rf "$LOCKDIR"
}

on_signal() {
  INTERRUPTED=1
  [ -n "$child" ] && kill "$child" 2>/dev/null
}

trap cleanup EXIT
trap on_signal INT TERM HUP

if ! acquire_lock; then
  logger -t wrapper "ERROR: another command is still running, refusing: $*"
  echo "Wrapper: another command is still running, aborting." >&2
  exit 1
fi

if [ -f "$LOG_LOCATION" ]; then
  logger -t wrapper "stale $LOG_LOCATION found (previous run did not finish cleanly), truncating"
fi
rm -f "$LOG_LOCATION.failed"
: >"$LOG_LOCATION"

STATE_OPEN=1
set_state Requested

# Single string => split on whitespace WITHOUT glob expansion; several
# arguments => use them untouched. (Quotes inside a single string are not
# interpreted, exactly as with the old unquoted $1.)
if [ $# -eq 1 ]; then
  unset IFS   # default field splitting: space, tab, newline
  set -f
  # shellcheck disable=SC2086
  set -- $1
  set +f
fi

"$@" </dev/null >"$LOG_LOCATION" 2>&1 &
child=$!
wait "$child"
rc=$?
if [ "$INTERRUPTED" = 1 ]; then
  wait "$child" 2>/dev/null
  rc=143
  echo "[wrapper] interrupted by signal" >>"$LOG_LOCATION"
fi
child=""

# Decide the final state. The child may own it (upgradegui sets its own).
state="$(get_transformer "$STATE_PATH")"
outcome=ok
if [ "$rc" -ne 0 ]; then
  outcome=fail
  echo "[wrapper] command exited with status $rc" >>"$LOG_LOCATION"
  final=Failed
  case "$state" in Failed | Error) final="" ;; esac
else
  case "$state" in
  Failed | Error)
    outcome=fail
    final=""
    ;;
  Complete) final="" ;;
  *) final=Complete ;;
  esac
fi

if [ "$outcome" = fail ]; then
  cp "$LOG_LOCATION" "$LOG_LOCATION.failed" 2>/dev/null
  logger -t wrapper "FAILED (status $rc): $*"
  tail -n 20 "$LOG_LOCATION" 2>/dev/null | logger -t wrapper
fi

# Log must be fully on disk BEFORE the state tells the browser it is final.
sync
case "$final" in
Failed) set_failed ;;
'') ;;
*) set_state "$final" ;;
esac
STATE_OPEN=0

# Grace period: every polling client sees the final state and the last log
# block. Lock is still held, so a new run cannot be clobbered by what follows.
if [ "$outcome" = fail ]; then sleep "$GRACE_FAIL"; else sleep "$GRACE_OK"; fi

set_state Idle
rm -f "$LOG_LOCATION"
exit "$rc"
