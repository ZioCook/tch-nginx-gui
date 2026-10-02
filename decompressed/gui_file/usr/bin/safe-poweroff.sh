#!/bin/sh
# Safe Shutdown script for Technicolor Gateways
# Shuts down services, flushes flash cache, remounts read-only, and blinks red LED slowly

# 1. Stop webserver and background services that might write to flash
/etc/init.d/nginx stop 2>/dev/null
/etc/init.d/transformer stop 2>/dev/null
/etc/init.d/cron stop 2>/dev/null
/etc/init.d/syslog_fwd stop 2>/dev/null
/etc/init.d/log stop 2>/dev/null
/etc/init.d/ledfw stop 2>/dev/null
killall -9 ledfw.lua status-led-eventing.lua 2>/dev/null

# 2. Turn off all LEDs first
for l in /sys/class/leds/*; do
    [ -f "$l/brightness" ] && echo 0 > "$l/brightness" 2>/dev/null
    [ -f "$l/trigger" ] && echo none > "$l/trigger" 2>/dev/null
done

# 3. Flush all filesystem buffers to NAND/eMMC flash
sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
sync

# 4. Remount overlay and root filesystems in read-only mode
mount -o remount,ro /overlay 2>/dev/null
mount -o remount,ro /rom 2>/dev/null
mount -o remount,ro / 2>/dev/null
sync

# 5. Set red power/status LED to blink slowly (1000ms ON / 1000ms OFF)
RED_LED=""
for candidate in /sys/class/leds/power:red /sys/class/leds/*power*red* /sys/class/leds/*:red; do
    if [ -d "$candidate" ]; then
        RED_LED="$candidate"
        break
    fi
done

if [ -n "$RED_LED" ]; then
    echo timer > "$RED_LED/trigger" 2>/dev/null
    echo 1000 > "$RED_LED/delay_on" 2>/dev/null
    echo 1000 > "$RED_LED/delay_off" 2>/dev/null
else
    # Fallback for devices with numeric sysfs leds
    if [ -d "/sys/class/leds/0" ]; then
        echo timer > "/sys/class/leds/0/trigger" 2>/dev/null
        echo 1000 > "/sys/class/leds/0/delay_on" 2>/dev/null
        echo 1000 > "/sys/class/leds/0/delay_off" 2>/dev/null
    fi
fi

# 6. Stop network interfaces to prevent any network traffic
ifdown -a 2>/dev/null

# System is now safe in RAM with read-only flash.
