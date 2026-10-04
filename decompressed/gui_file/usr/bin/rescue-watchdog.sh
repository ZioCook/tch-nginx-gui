#!/bin/sh
#
# Rescue Server Watchdog Daemon
# Monitors Nginx availability and automatically activates the standalone
# LuaSocket Rescue Console on port 8088 if Nginx or web services crash.
#
# Target: BusyBox ash on OpenWrt (no bashisms, no arrays, no [[ ]]).
#
# Hardening overview:
#   * single instance (pidfile + /proc/<pid>/cmdline check)
#   * HTTP probe with connect + total timeouts (curl, or BusyBox wget as fallback)
#   * rescue server tracked by pidfile AND a strict pgrep pattern (no false matches on
#     editors / luac / shells that merely mention the file name)
#   * rescue server is considered healthy only if its port is really LISTENING
#     (parsed from /proc/net/tcp*, no netstat dependency)
#   * hysteresis before stopping the rescue console (avoids flapping, and leaves the
#     operator time to read the result of a recovery)
#   * graceful stop: TERM, wait, then KILL
#   * the launched Lua process gets clean stdio (/dev/null), nothing inherited
#   * interruptible sleep + traps, log rotation, clear diagnostics when the port is busy
#

export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CHECK_INTERVAL=30          # s between checks while everything is fine
FAST_INTERVAL=15           # s between checks while failures are being counted
                           #   (set equal to CHECK_INTERVAL for the old 90 s detection time)
MAX_FAILS=3                # consecutive failed probes before the rescue console is started
RECOVER_CHECKS=2           # consecutive healthy probes before the rescue console is stopped
RESCUE_PORT=8088
RESCUE_SCRIPT="/www/lua/rescue_server.lua"
NGINX_URL="http://127.0.0.1/"
PROBE_TIMEOUT=5            # s, total time of one HTTP probe
START_WAIT=8               # s to wait for the rescue console to start listening

LOG_FILE="/tmp/rescue.log"
LOG_MAX_BYTES=262144       # rotate above this size ...
LOG_KEEP_BYTES=65536       # ... keeping this many bytes of tail

WATCHDOG_PID_FILE="/var/run/rescue-watchdog.pid"
RESCUE_PID_FILE="/var/run/rescue_server.pid"

# Matches "lua[5.1] [/path/]rescue_server.lua ..." only (ERE for pgrep -f)
RESCUE_PGREP_PATTERN='^(/[^ ]*/)?lua[0-9.]* +[^ ]*rescue_server\.lua'

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [RESCUE-WATCHDOG] $1"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null
    logger -t rescue_watchdog "$1" 2>/dev/null
}

# /tmp is RAM: keep the shared log (also written by rescue_server.lua) bounded.
# cat > file keeps the same inode, so concurrent appenders are not left on a deleted file.
rotate_log() {
    [ -f "$LOG_FILE" ] || return 0
    local size tmp
    size=$(wc -c < "$LOG_FILE" 2>/dev/null)
    size=$(echo $size)
    [ -n "$size" ] || return 0
    [ "$size" -gt "$LOG_MAX_BYTES" ] 2>/dev/null || return 0
    tmp="${LOG_FILE}.wd.$$"
    if tail -c "$LOG_KEEP_BYTES" "$LOG_FILE" > "$tmp" 2>/dev/null; then
        cat "$tmp" > "$LOG_FILE" 2>/dev/null
    fi
    rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# Process helpers
# ---------------------------------------------------------------------------

# pid_alive_with PID PATTERN -> 0 if PID is alive (not a zombie) and its command line matches
pid_alive_with() {
    [ -n "$1" ] || return 1
    kill -0 "$1" 2>/dev/null || return 1
    [ -r "/proc/$1/cmdline" ] || return 1
    tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null | grep -q "$2"
}

# Print the PIDs of all running rescue servers (pidfile + strict pgrep), space separated
rescue_pids() {
    local pids="" p
    if [ -f "$RESCUE_PID_FILE" ]; then
        p=$(cat "$RESCUE_PID_FILE" 2>/dev/null)
        if pid_alive_with "$p" "rescue_server.lua"; then
            pids="$p"
        fi
    fi
    for p in $(pgrep -f "$RESCUE_PGREP_PATTERN" 2>/dev/null); do
        case " $pids " in
            *" $p "*) ;;
            *) pids="$pids $p" ;;
        esac
    done
    echo $pids
}

is_rescue_running() {
    [ -n "$(rescue_pids)" ]
}

# Is anything LISTENING on $RESCUE_PORT? (state 0A in /proc/net/tcp and tcp6)
port_listening() {
    local hex files="" f
    hex=$(printf '%04X' "$RESCUE_PORT")
    for f in /proc/net/tcp /proc/net/tcp6; do
        [ -r "$f" ] && files="$files $f"
    done
    [ -n "$files" ] || return 1
    awk -v h=":$hex" '$4 == "0A" && substr($2, length($2) - 4) == h { found = 1 } END { exit !found }' $files 2>/dev/null
}

# Best-effort name of whatever holds the port (needs netstat -p), for diagnostics only
port_holder() {
    local h
    h=$(netstat -lntp 2>/dev/null | awk -v p=":$RESCUE_PORT" '$4 ~ p "$" { print $NF; exit }')
    echo "${h:-sconosciuto}"
}

# ---------------------------------------------------------------------------
# Health probe
# ---------------------------------------------------------------------------
http_probe() {
    local code=""
    if command -v curl >/dev/null 2>&1; then
        code=$(curl -s -m "$PROBE_TIMEOUT" --connect-timeout 3 -o /dev/null -w "%{http_code}" "$NGINX_URL" 2>/dev/null)
        case "$code" in
            2??|3??) return 0 ;;
        esac
        return 1
    fi
    # Fallback: BusyBox wget exits 0 on a 2xx answer (redirects are followed)
    wget -q -T "$PROBE_TIMEOUT" -O /dev/null "$NGINX_URL" >/dev/null 2>&1
}

check_nginx() {
    # Check if nginx process exists
    pgrep nginx >/dev/null 2>&1 || return 1
    # Probe HTTP response on localhost
    http_probe
}

# ---------------------------------------------------------------------------
# Rescue server control
# ---------------------------------------------------------------------------
LAST_RESCUE_PID=""

start_rescue() {
    local lua_bin pid i
    lua_bin=$(command -v lua || command -v lua5.1)
    if [ -z "$lua_bin" ]; then
        log "ERROR: interprete Lua non trovato, impossibile avviare il rescue server!"
        return 1
    fi
    if [ ! -r "$RESCUE_SCRIPT" ]; then
        log "ERROR: $RESCUE_SCRIPT non trovato o non leggibile!"
        return 1
    fi
    if port_listening; then
        log "ERROR: porta $RESCUE_PORT gia' occupata da un altro processo (holder: $(port_holder)). Rescue server NON avviato."
        return 1
    fi

    # Reap the previous (dead) child, if any, so no zombie is left behind
    if [ -n "$LAST_RESCUE_PID" ] && ! pid_alive_with "$LAST_RESCUE_PID" "rescue_server.lua"; then
        wait "$LAST_RESCUE_PID" 2>/dev/null
    fi

    "$lua_bin" "$RESCUE_SCRIPT" "$RESCUE_PORT" </dev/null >/dev/null 2>&1 &
    pid=$!
    LAST_RESCUE_PID="$pid"
    echo "$pid" > "$RESCUE_PID_FILE" 2>/dev/null

    # Success = process alive AND port really listening
    i=0
    while [ "$i" -lt "$START_WAIT" ]; do
        sleep 1
        i=$((i + 1))
        pid_alive_with "$pid" "rescue_server.lua" || break
        if port_listening; then
            return 0
        fi
    done
    return 1
}

# Graceful stop: TERM, wait up to 5 s, then KILL whatever is left
stop_rescue() {
    local pids p i
    pids=$(rescue_pids)
    [ -n "$pids" ] || { rm -f "$RESCUE_PID_FILE"; return 0; }

    for p in $pids; do
        kill "$p" 2>/dev/null
    done
    i=0
    while [ "$i" -lt 5 ]; do
        [ -z "$(rescue_pids)" ] && break
        sleep 1
        i=$((i + 1))
    done
    for p in $(rescue_pids); do
        log "Rescue Server (pid $p) non risponde a SIGTERM: invio SIGKILL."
        kill -9 "$p" 2>/dev/null
    done
    rm -f "$RESCUE_PID_FILE"
}

# ---------------------------------------------------------------------------
# Single instance, traps
# ---------------------------------------------------------------------------
SLEEP_PID=""

cleanup() {
    [ -n "$SLEEP_PID" ] && kill "$SLEEP_PID" 2>/dev/null
    # Remove our pidfile only if it is still ours
    [ "$(cat "$WATCHDOG_PID_FILE" 2>/dev/null)" = "$$" ] && rm -f "$WATCHDOG_PID_FILE"
}

if [ -f "$WATCHDOG_PID_FILE" ]; then
    OLD_PID=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null)
    if [ "$OLD_PID" != "$$" ] && pid_alive_with "$OLD_PID" "${0##*/}"; then
        echo "rescue-watchdog gia' in esecuzione (pid $OLD_PID)" >&2
        exit 1
    fi
fi
echo "$$" > "$WATCHDOG_PID_FILE" 2>/dev/null

trap 'exit 0' TERM INT HUP
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
FAIL_COUNT=0
OK_COUNT=0
NOPORT_COUNT=0
INTERVAL=$CHECK_INTERVAL

log "Rescue watchdog daemon started (monitoring interval: ${CHECK_INTERVAL}s)..."

while true; do
    rotate_log

    if check_nginx; then
        OK_COUNT=$((OK_COUNT + 1))
        NOPORT_COUNT=0
        if [ "$FAIL_COUNT" -gt 0 ]; then
            log "Nginx health check restored (was $FAIL_COUNT failures)."
            FAIL_COUNT=0
        fi
        if is_rescue_running && [ "$OK_COUNT" -ge "$RECOVER_CHECKS" ]; then
            log "Nginx and web services are healthy and operational. Stopping Rescue Server on port $RESCUE_PORT..."
            stop_rescue
        fi
        INTERVAL=$CHECK_INTERVAL
    else
        OK_COUNT=0
        if [ "$FAIL_COUNT" -lt "$MAX_FAILS" ]; then
            FAIL_COUNT=$((FAIL_COUNT + 1))
            log "WARNING: Nginx probe failed ($FAIL_COUNT/$MAX_FAILS)"
        fi
        INTERVAL=$FAST_INTERVAL

        if [ "$FAIL_COUNT" -ge "$MAX_FAILS" ]; then
            INTERVAL=$CHECK_INTERVAL
            if is_rescue_running; then
                # Process alive: make sure it is really serving on the port
                if port_listening; then
                    NOPORT_COUNT=0
                else
                    NOPORT_COUNT=$((NOPORT_COUNT + 1))
                    if [ "$NOPORT_COUNT" -ge 2 ]; then
                        log "WARNING: Rescue Server attivo ma la porta $RESCUE_PORT non e' in ascolto. Riavvio..."
                        stop_rescue
                        NOPORT_COUNT=0
                        if start_rescue; then
                            log "Rescue Server riavviato con successo."
                        else
                            log "ERROR: Failed to launch rescue server!"
                        fi
                    fi
                fi
            else
                log "CRITICAL: Nginx unresponsive for $FAIL_COUNT consecutive checks!"
                log "Spawning standalone LuaSocket Rescue Server on port $RESCUE_PORT..."
                if start_rescue; then
                    log "Rescue Server successfully launched. Access emergency UI at http://<router-ip>:$RESCUE_PORT/"
                else
                    log "ERROR: Failed to launch rescue server!"
                fi
            fi
        fi
    fi

    # Interruptible sleep: a TERM/INT is handled immediately instead of after $INTERVAL seconds
    sleep "$INTERVAL" &
    SLEEP_PID=$!
    wait "$SLEEP_PID" 2>/dev/null
    SLEEP_PID=""
done
