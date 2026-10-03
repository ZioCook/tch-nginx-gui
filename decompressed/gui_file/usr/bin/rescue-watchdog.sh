#!/bin/sh
#
# Rescue Server Watchdog Daemon
# Monitors Nginx availability and automatically activates the standalone
# LuaSocket Rescue Console on port 8080 if Nginx or web services crash.
#

FAIL_COUNT=0
MAX_FAILS=3
CHECK_INTERVAL=30
RESCUE_PORT=8088
LOG_FILE="/tmp/rescue.log"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [RESCUE-WATCHDOG] $1"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null
    logger -t rescue_watchdog "$1" 2>/dev/null
}

check_nginx() {
    # Check if nginx process exists
    if ! pgrep nginx >/dev/null 2>&1; then
        return 1
    fi

    # Probe HTTP response on localhost
    local code=$(curl -s -m 5 -o /dev/null -w "%{http_code}" http://127.0.0.1/ 2>/dev/null)
    if [ "$code" = "200" ] || [ "$code" = "302" ] || [ "$code" = "301" ]; then
        return 0
    fi

    return 1
}

is_rescue_running() {
    pgrep -f "rescue_server.lua" >/dev/null 2>&1
}

log "Rescue watchdog daemon started (monitoring interval: ${CHECK_INTERVAL}s)..."

while true; do
    if check_nginx; then
        if [ "$FAIL_COUNT" -gt 0 ]; then
            log "Nginx health check restored (was $FAIL_COUNT failures)."
            FAIL_COUNT=0
        fi
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        log "WARNING: Nginx probe failed ($FAIL_COUNT/$MAX_FAILS)"

        if [ "$FAIL_COUNT" -ge "$MAX_FAILS" ]; then
            if ! is_rescue_running; then
                log "CRITICAL: Nginx unresponsive for $FAIL_COUNT consecutive checks!"
                log "Spawning standalone LuaSocket Rescue Server on port $RESCUE_PORT..."
                lua /www/lua/rescue_server.lua "$RESCUE_PORT" >/dev/null 2>&1 &
                sleep 2
                if is_rescue_running; then
                    log "Rescue Server successfully launched. Access emergency UI at http://<router-ip>:$RESCUE_PORT/"
                else
                    log "ERROR: Failed to launch rescue server!"
                fi
            fi
        fi
    fi

    sleep "$CHECK_INTERVAL"
done
