#!/bin/sh
# /usr/share/transformer/scripts/toggle_qos.sh
# Toggle QoS subsystem on/off cleanly and persistently

umask 022

STATE="$1"
case "$STATE" in 0|1) ;; *) echo "usage: $0 [0|1]" >&2; exit 2 ;; esac

LOCK_FILE="/var/lock/toggle_qos.lock"
WANT_FILE="/var/run/toggle_qos.want"
OWNER_FILE="/var/run/toggle_qos.owner"
DONE_FILE="/var/run/toggle_qos.done"
STATUS_FILE="/var/run/toggle_qos.status"
MAX_WAIT=120   # solo rinuncia (exit 1): non si rompe mai il lock di un owner vivo

# Rilevamento portabilita' timeout (BusyBox 1.23 richiede -t SECS, 1.31+ e GNU usano SECS posizionale)
if timeout --help 2>&1 | grep -q -- '-t SECS'; then
    TIMEOUT_HAS_T=1
else
    TIMEOUT_HAS_T=0
fi

run_timeout() {
    local sig="$1"
    local sec="$2"
    shift 2
    if [ "$TIMEOUT_HAS_T" -eq 1 ]; then
        timeout -t "$sec" -s "$sig" "$@"
    else
        timeout -s "$sig" "$sec" "$@"
    fi
}

# Rilevamento portabilita' non-blocking lock (/bin/lock -n supportato da OpenWrt 18+, assente in 15.05/17.2)
if /bin/lock 2>&1 | grep -E -q '(^[[:space:]]*-n|\[-[^]]*n)'; then
    LOCK_HAS_N=1
else
    LOCK_HAS_N=0
fi

try_acquire_lock() {
    local lockfile="$1"
    if [ "$LOCK_HAS_N" -eq 1 ]; then
        /bin/lock -n "$lockfile" 2>/dev/null
    else
        run_timeout 9 1 /bin/lock "$lockfile" 2>/dev/null
    fi
}

get_starttime() {
    local pid="$1" raw rest
    raw=$(cat "/proc/$pid/stat" 2>/dev/null) || return 1
    rest="${raw##*)}"
    echo "$rest" | awk '{print $20}'
}

write_status() {
    local content="$1"
    echo "$content" > "${STATUS_FILE}.tmp"
    mv -f "${STATUS_FILE}.tmp" "$STATUS_FILE"
}

MY_STARTTIME=$(get_starttime $$)

# Intento = "<stato> <pid richiedente> <starttime>"
echo "$STATE $$ $MY_STARTTIME" > "$WANT_FILE"

HAVE_LOCK=0
cleanup() {
    if [ "$HAVE_LOCK" -eq 1 ]; then
        rm -f "$OWNER_FILE" 2>/dev/null
        /bin/lock -u "$LOCK_FILE" 2>/dev/null
    fi
}
trap cleanup EXIT
trap 'exit 1' INT TERM

# Vera se esiste una richiesta di stato opposto, più recente, con richiedente
# vivo (stesso PID e stesso starttime) oppure già completato.
superseded() {
    local line w_state w_pid w_stime cur_stime
    line=$(cat "$WANT_FILE" 2>/dev/null)
    case "$line" in "0 "*|"1 "*) ;; *) return 1 ;; esac
    w_state=$(echo "$line" | awk '{print $1}')
    w_pid=$(echo "$line" | awk '{print $2}')
    w_stime=$(echo "$line" | awk '{print $3}')
    [ "$w_state" != "$STATE" ] || return 1
    [ "$w_pid" != "$$" ] || return 1

    if kill -0 "$w_pid" 2>/dev/null; then
        cur_stime=$(get_starttime "$w_pid")
        if [ -n "$w_stime" ] && [ -n "$cur_stime" ]; then
            [ "$cur_stime" = "$w_stime" ] && return 0
        else
            tr '\000' ' ' < "/proc/$w_pid/cmdline" 2>/dev/null | grep -q "toggle_qos" && return 0
        fi
    fi
    [ "$(cat "$DONE_FILE" 2>/dev/null)" = "$w_pid" ]
}

acquire_lock() {
    local absent=0 stale owner_pid daemon_pid
    local start_time now_time elapsed

    start_time=$(date +%s)

    while ! try_acquire_lock "$LOCK_FILE"; do
        now_time=$(date +%s)
        elapsed=$((now_time - start_time))
        [ $elapsed -lt 0 ] && elapsed=0
        owner_pid=$(cat "$OWNER_FILE" 2>/dev/null)
        daemon_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        stale=0

        if [ -n "$owner_pid" ]; then
            absent=0
            kill -0 "$owner_pid" 2>/dev/null || stale=1
        else
            # lock tenuto ma nessun owner: può essere la finestra tra lock e scrittura PID
            absent=$((absent + 1))
            [ $absent -ge 5 ] && stale=1
        fi

        if [ $stale -eq 1 ]; then
            sleep 2   # doppia lettura a distanza: se qualcuno ha appena riacquisito, i valori cambiano
            if [ -n "$daemon_pid" ]                && [ "$(cat "$OWNER_FILE" 2>/dev/null)" = "$owner_pid" ]                && [ "$(cat "$LOCK_FILE" 2>/dev/null)" = "$daemon_pid" ]                && [ "$(cat /proc/$daemon_pid/comm 2>/dev/null)" = "lock" ]                && { [ -z "$owner_pid" ] || ! kill -0 "$owner_pid" 2>/dev/null; }; then
                logger -t "QoS" "Stale lock (owner='$owner_pid'), killing helper $daemon_pid."
                kill -9 "$daemon_pid" 2>/dev/null
                sleep 1
            fi
            absent=0
            continue
        fi

        if [ $elapsed -ge $MAX_WAIT ]; then
            logger -t "QoS" "Giving up after ${elapsed}s: lock held by live owner $owner_pid."
            exit 1
        fi
        sleep 1
    done

    HAVE_LOCK=1
    echo "$$" > "$OWNER_FILE"
}

acquire_lock

# Soppressione iniziale all'acquisizione del lock
if superseded; then
    logger -t "QoS" "Suppressed stale toggle request (state=$STATE), newer request pending ($(cat "$WANT_FILE" 2>/dev/null))."
    exit 0
fi

# Coalescenza backend: se lo stato in UCI coincide già con STATE e nessun intento contrario è pendente
cur_state=$(uci -q get modgui.var.qos_enabled)
if [ "$cur_state" = "$STATE" ]; then
    logger -t "QoS" "State already $STATE, skipping redundant service reload."
    echo "$$" > "$DONE_FILE"
    write_status "done:$STATE:0:0:$(date +%s)"
    exit 0
fi

write_status "running:$STATE:$$:0:$(date +%s)"

run_service_step() {
    local svc="$1"
    local action="$2"
    local to_sec=15

    run_timeout 9 $to_sec /etc/init.d/$svc $action >/dev/null 2>&1
    local rc=$?

    if [ $rc -ne 0 ]; then
        if [ "$svc" = "qos" ]; then
            killall -9 qos 2>/dev/null
            sleep 1
            if [ -z "$(pidof qos 2>/dev/null)" ]; then
                rm -f /tmp/run/qos.lock 2>/dev/null
            fi
        fi
        logger -t "QoS" "$svc $action returned rc=$rc (timed out or failed), process handled."
        return $rc
    fi
    return 0
}

apply_toggle() {
    local target="$1"
    if [ "$target" = "1" ]; then
        logger -t "QoS" "Enabling QoS service..."
        uci -q set modgui.var.qos_enabled='1'
        uci -q commit modgui

        for dev in eth0 eth1 eth2 eth3 wl0 wl1; do
            uci -q set qos.${dev}.enable='1'
        done
        [ -n "$(uci -q get qos.eth4)" ] && uci -q set qos.eth4.enable='1'
        [ -n "$(uci -q get qos.ptm0)" ] && uci -q set qos.ptm0.enable='1'
        uci -q commit qos

        run_service_step qos restart
        qos_rc=$?

        superseded && logger -t "QoS" "Newer request pending ($(cat "$WANT_FILE" 2>/dev/null)); completing this toggle, it will follow."

        run_service_step iqos restart
        iqos_rc=$?

        if [ $qos_rc -eq 0 ] && [ $iqos_rc -eq 0 ]; then
            logger -t "QoS" "QoS service enabled."
        else
            logger -t "QoS" "QoS configuration enabled; service start failed/timed out (qos_rc=$qos_rc, iqos_rc=$iqos_rc)."
        fi
    else
        logger -t "QoS" "Disabling QoS service..."
        uci -q set modgui.var.qos_enabled='0'
        uci -q commit modgui

        for dev in ptm0 eth0 eth1 eth2 eth3 eth4 wl0 wl1; do
            uci -q set qos.${dev}.enable='0'
        done
        uci -q commit qos

        /etc/init.d/qos disable 2>/dev/null
        /etc/init.d/iqos disable 2>/dev/null

        run_service_step qos stop
        qos_rc=$?

        superseded && logger -t "QoS" "Newer request pending ($(cat "$WANT_FILE" 2>/dev/null)); completing this toggle, it will follow."

        run_service_step iqos stop
        iqos_rc=$?

        for dev in eth0 eth1 eth2 eth3 eth4 eth5 wl0 wl1; do
            if ip link show $dev >/dev/null 2>&1; then
                tc qdisc replace dev $dev root fq_codel 2>/dev/null || true
            fi
        done

        if [ $qos_rc -eq 0 ] && [ $iqos_rc -eq 0 ]; then
            logger -t "QoS" "QoS service disabled."
        else
            logger -t "QoS" "QoS configuration disabled; service stop failed/timed out (qos_rc=$qos_rc, iqos_rc=$iqos_rc)."
        fi
    fi
}

apply_toggle "$STATE"
echo "$$" > "$DONE_FILE"
write_status "done:$STATE:$qos_rc:$iqos_rc:$(date +%s)"

# Rete di sicurezza (Punto 5): prima di rilasciare il lock, controlla se l'intento in .want
# è di stato opposto e il suo richiedente è morto senza aver completato
check_recovery() {
    local line w_state w_pid w_stime cur_stime
    line=$(cat "$WANT_FILE" 2>/dev/null)
    case "$line" in "0 "*|"1 "*) ;; *) return 0 ;; esac
    w_state=$(echo "$line" | awk '{print $1}')
    w_pid=$(echo "$line" | awk '{print $2}')
    w_stime=$(echo "$line" | awk '{print $3}')

    [ "$w_state" != "$STATE" ] || return 0
    [ "$w_pid" != "$$" ] || return 0
    [ "$(cat "$DONE_FILE" 2>/dev/null)" != "$w_pid" ] || return 0

    if kill -0 "$w_pid" 2>/dev/null; then
        cur_stime=$(get_starttime "$w_pid")
        if [ -n "$w_stime" ] && [ -n "$cur_stime" ] && [ "$cur_stime" = "$w_stime" ]; then
            return 0
        fi
    fi

    logger -t "QoS" "Newer requester $w_pid for state $w_state died in queue; recovering and applying state $w_state."
    write_status "running:$w_state:$$:0:$(date +%s)"
    apply_toggle "$w_state"
    STATE="$w_state"
    echo "$$" > "$DONE_FILE"
    write_status "done:$STATE:$qos_rc:$iqos_rc:$(date +%s)"
}

check_recovery
