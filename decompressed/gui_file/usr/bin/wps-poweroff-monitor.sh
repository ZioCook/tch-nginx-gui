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
    UCI_RED=$(uci get -q ledfw.ctrl_power.red)
    UCI_GREEN=$(uci get -q ledfw.ctrl_power.green)
    [ -z "$RED_LED" ] && [ -n "$UCI_RED" ] && [ -d "/sys/class/leds/$UCI_RED" ] && RED_LED="/sys/class/leds/$UCI_RED"
    [ -z "$RED_LED" ] && return

    # 1. Suspend ledfw and status-led-eventing so they immediately stop controlling any LEDs
    killall -STOP ledfw.lua status-led-eventing.lua 2>/dev/null
    touch /var/run/wps_poweroff_ledfw_stopped.flag

    # 2. Turn off all other LEDs across the entire device (kill both trigger and brightness)
    for l in /sys/class/leds/*; do
        [ "$l" = "$RED_LED" ] && continue
        [ -n "$UCI_RED" ] && [ "$l" = "/sys/class/leds/$UCI_RED" ] && continue
        [ -f "$l/trigger" ] && echo none > "$l/trigger" 2>/dev/null
        [ -f "$l/brightness" ] && echo 0 > "$l/brightness" 2>/dev/null
    done

    # 3. Explicitly kill any multi-color/composite power leds (green, blue, orange, white, etc.)
    for p in /sys/class/leds/power:green /sys/class/leds/power:orange /sys/class/leds/power:blue /sys/class/leds/power:white /sys/class/leds/power:cyan /sys/class/leds/power:magenta; do
        if [ -d "$p" ] && [ "$p" != "$RED_LED" ]; then
            echo none > "$p/trigger" 2>/dev/null
            echo 0 > "$p/brightness" 2>/dev/null
        fi
    done
    if [ -n "$UCI_GREEN" ] && [ -d "/sys/class/leds/$UCI_GREEN" ] && [ "/sys/class/leds/$UCI_GREEN" != "$RED_LED" ]; then
        echo none > "/sys/class/leds/$UCI_GREEN/trigger" 2>/dev/null
        echo 0 > "/sys/class/leds/$UCI_GREEN/brightness" 2>/dev/null
    fi

    touch "$FLAG_COUNTDOWN"
    # 4. Fast strobe blinking on the pure red LED only (100ms ON / 100ms OFF)
    echo timer > "$RED_LED/trigger" 2>/dev/null
    echo 100 > "$RED_LED/delay_on" 2>/dev/null
    echo 100 > "$RED_LED/delay_off" 2>/dev/null
    if [ -n "$UCI_RED" ] && [ -d "/sys/class/leds/$UCI_RED" ] && [ "/sys/class/leds/$UCI_RED" != "$RED_LED" ]; then
        echo timer > "/sys/class/leds/$UCI_RED/trigger" 2>/dev/null
        echo 100 > "/sys/class/leds/$UCI_RED/delay_on" 2>/dev/null
        echo 100 > "/sys/class/leds/$UCI_RED/delay_off" 2>/dev/null
    fi
}

restore_normal_leds() {
    RED_LED=$(get_power_led)
    UCI_RED=$(uci get -q ledfw.ctrl_power.red)
    if [ -n "$RED_LED" ]; then
        echo none > "$RED_LED/trigger" 2>/dev/null
        echo 0 > "$RED_LED/brightness" 2>/dev/null
    fi
    if [ -n "$UCI_RED" ] && [ -d "/sys/class/leds/$UCI_RED" ]; then
        echo none > "/sys/class/leds/$UCI_RED/trigger" 2>/dev/null
        echo 0 > "/sys/class/leds/$UCI_RED/brightness" 2>/dev/null
    fi

    # Resume ledfw and status-led-eventing if they were suspended
    if [ -f /var/run/wps_poweroff_ledfw_stopped.flag ]; then
        rm -f /var/run/wps_poweroff_ledfw_stopped.flag
        killall -CONT ledfw.lua status-led-eventing.lua 2>/dev/null
    fi

    # Refresh all LEDs back to their correct active states
    if [ -x /usr/share/transformer/scripts/restart_leds.sh ]; then
        /usr/share/transformer/scripts/restart_leds.sh >/dev/null 2>&1 &
    elif [ -x /etc/init.d/ledfw ]; then
        /etc/init.d/ledfw restart >/dev/null 2>&1 &
    fi
    if [ -x /usr/share/transformer/scripts/check_ecoled.sh ]; then
        /usr/share/transformer/scripts/check_ecoled.sh >/dev/null 2>&1 &
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

    blink|test-blink)
        start_countdown_blink
        exit 0
        ;;

    restore|test-restore)
        restore_normal_leds
        exit 0
        ;;

    *)
        echo "Usage: $0 {start|stop [seen]|blink|restore}"
        exit 1
        ;;
esac
