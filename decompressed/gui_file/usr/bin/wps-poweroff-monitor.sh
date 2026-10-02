#!/bin/sh
# WPS Button Press-and-Hold Poweroff Monitor
# Triggered by /etc/hotplug.d/button/50-safe-poweroff

PID_FILE="/var/run/wps_poweroff_monitor.pid"
FLAG_COUNTDOWN="/var/run/wps_poweroff_countdown.flag"
FLAG_RESTORE_GREEN="/var/run/wps_poweroff_restore_green.flag"

get_power_led() {
    # Ensure kernel led driver is loaded
    if [ ! -d /sys/class/leds/power:red ] && [ ! -d /sys/class/leds/0 ]; then
        insmod technicolor_led 2>/dev/null || insmod "/lib/modules/$(uname -r)/technicolor_led.ko" 2>/dev/null
    fi

    for candidate in /sys/class/leds/power:red /sys/class/leds/*power*red* /sys/class/leds/power:orange /sys/class/leds/0; do
        if [ -d "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

start_countdown_blink() {
    RED_LED=$(get_power_led)
    [ -z "$RED_LED" ] && return

    # If green power LED is on, save state and turn it off temporarily
    if [ -f /sys/class/leds/power:green/brightness ]; then
        CURR_G=$(cat /sys/class/leds/power:green/brightness 2>/dev/null)
        if [ "$CURR_G" -gt 0 ] 2>/dev/null; then
            echo "$CURR_G" > "$FLAG_RESTORE_GREEN"
            echo 0 > /sys/class/leds/power:green/brightness 2>/dev/null
        fi
    fi

    touch "$FLAG_COUNTDOWN"
    # Set fast blinking (100ms ON / 100ms OFF)
    echo timer > "$RED_LED/trigger" 2>/dev/null
    echo 100 > "$RED_LED/delay_on" 2>/dev/null
    echo 100 > "$RED_LED/delay_off" 2>/dev/null
}

restore_normal_leds() {
    RED_LED=$(get_power_led)
    if [ -n "$RED_LED" ]; then
        echo none > "$RED_LED/trigger" 2>/dev/null
        echo 0 > "$RED_LED/brightness" 2>/dev/null
    fi

    # Restore green if it was saved
    if [ -f "$FLAG_RESTORE_GREEN" ]; then
        PREV_G=$(cat "$FLAG_RESTORE_GREEN" 2>/dev/null)
        [ -n "$PREV_G" ] && echo "$PREV_G" > /sys/class/leds/power:green/brightness 2>/dev/null
        rm -f "$FLAG_RESTORE_GREEN"
    fi

    # Trigger ledfw to refresh state if running
    if [ -x /etc/init.d/ledfw ]; then
        /etc/init.d/ledfw restart >/dev/null 2>&1 &
    fi
}

case "$1" in
    start)
        # Prevent duplicate instances
        if [ -f "$PID_FILE" ]; then
            OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
            if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
                kill -9 "$OLD_PID" 2>/dev/null
            fi
            rm -f "$PID_FILE"
        fi

        echo "$$" > "$PID_FILE"
        rm -f "$FLAG_COUNTDOWN" "$FLAG_RESTORE_GREEN"

        # Phase 1: Wait 10 seconds
        i=0
        while [ $i -lt 10 ]; do
            sleep 1
            [ ! -f "$PID_FILE" ] && exit 0
            i=$((i + 1))
        done

        # Phase 2: At 10s, initiate countdown visual feedback (fast strobe)
        start_countdown_blink

        # Wait remaining 5 seconds (reaching 15s total)
        j=0
        while [ $j -lt 5 ]; do
            sleep 1
            if [ ! -f "$PID_FILE" ]; then
                restore_normal_leds
                rm -f "$FLAG_COUNTDOWN" "$PID_FILE"
                exit 0
            fi
            j=$((j + 1))
        done

        # Phase 3: 15 seconds completed! Trigger safe shutdown
        logger -t wps-poweroff "WPS button held for 15s - initiating safe poweroff!"
        rm -f "$PID_FILE" "$FLAG_COUNTDOWN" "$FLAG_RESTORE_GREEN"
        /bin/sh /usr/bin/safe-poweroff.sh &
        exit 0
        ;;

    stop)
        SEEN="$2"
        # If safe-poweroff.sh is already running or holding was >= 15s, do not cancel
        if [ -n "$SEEN" ] && [ "$SEEN" -ge 15 ] 2>/dev/null; then
            exit 0
        fi

        if [ -f "$PID_FILE" ]; then
            MON_PID=$(cat "$PID_FILE" 2>/dev/null)
            rm -f "$PID_FILE"
            [ -n "$MON_PID" ] && kill -9 "$MON_PID" 2>/dev/null
        fi

        if [ -f "$FLAG_COUNTDOWN" ]; then
            logger -t wps-poweroff "WPS button released early (${SEEN}s) - poweroff cancelled"
            restore_normal_leds
            rm -f "$FLAG_COUNTDOWN" "$FLAG_RESTORE_GREEN"
        fi
        exit 0
        ;;

    *)
        echo "Usage: $0 {start|stop [seen]}"
        exit 1
        ;;
esac
