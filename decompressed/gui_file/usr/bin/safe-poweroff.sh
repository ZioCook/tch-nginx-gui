#!/bin/sh
# Safe Shutdown script for Technicolor Gateways
# Shuts down services, flushes flash cache, remounts read-only, and blinks red LED slowly

LOG="/tmp/safe-poweroff.log"
exec > "$LOG" 2>&1

echo "=== Safe Poweroff initiated at $(date) ==="

# 0. Allow 2 seconds for HTTP response to reach the browser
echo "Step 0: Waiting 2 seconds for web client response..."
sleep 2

# 1. Stop background services that might write to flash
echo "Step 1: Stopping background services..."
/etc/init.d/nginx stop 2>/dev/null
/etc/init.d/cron stop 2>/dev/null
/etc/init.d/syslog_fwd stop 2>/dev/null
/etc/init.d/log stop 2>/dev/null
/etc/init.d/ledfw stop 2>/dev/null
killall -9 ledfw.lua status-led-eventing.lua 2>/dev/null
/etc/init.d/transformer stop 2>/dev/null

# 2. Turn off all LEDs first
echo "Step 2: Turning off all LEDs..."
for l in /sys/class/leds/*; do
    [ -f "$l/trigger" ] && echo none > "$l/trigger" 2>/dev/null
    [ -f "$l/brightness" ] && echo 0 > "$l/brightness" 2>/dev/null
done

# 3. Flush all filesystem buffers to NAND/eMMC flash
echo "Step 3: Flushing flash caches..."
sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
sync

# 4. Remount overlay and root filesystems in read-only mode
echo "Step 4: Remounting filesystems read-only..."
mount -o remount,ro /overlay 2>/dev/null
mount -o remount,ro /rom 2>/dev/null
mount -o remount,ro / 2>/dev/null
sync

# 5. Set red power/status LED to blink slowly (1000ms ON / 1000ms OFF)
echo "Step 5: Activating slow blinking red power LED..."
if [ ! -d /sys/class/leds/power:red ] && [ ! -d /sys/class/leds/0 ]; then
    insmod technicolor_led 2>/dev/null || insmod "/lib/modules/$(uname -r)/technicolor_led.ko" 2>/dev/null
fi
RED_LED=""
for candidate in /sys/class/leds/power:red /sys/class/leds/*power*red* /sys/class/leds/*:red; do
    if [ -d "$candidate" ]; then
        RED_LED="$candidate"
        break
    fi
done

UCI_RED=$(uci get -q ledfw.ctrl_power.red)
UCI_GREEN=$(uci get -q ledfw.ctrl_power.green)

# Ensure all other power LEDs (green, orange, blue, etc.) are explicitly turned off
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

if [ -n "$RED_LED" ]; then
    echo "Found red LED: $RED_LED"
    echo none > "$RED_LED/trigger" 2>/dev/null
    echo timer > "$RED_LED/trigger" 2>/dev/null
    echo 1000 > "$RED_LED/delay_on" 2>/dev/null
    echo 1000 > "$RED_LED/delay_off" 2>/dev/null
    if [ -n "$UCI_RED" ] && [ -d "/sys/class/leds/$UCI_RED" ] && [ "/sys/class/leds/$UCI_RED" != "$RED_LED" ]; then
        echo none > "/sys/class/leds/$UCI_RED/trigger" 2>/dev/null
        echo timer > "/sys/class/leds/$UCI_RED/trigger" 2>/dev/null
        echo 1000 > "/sys/class/leds/$UCI_RED/delay_on" 2>/dev/null
        echo 1000 > "/sys/class/leds/$UCI_RED/delay_off" 2>/dev/null
    fi
elif [ -n "$UCI_RED" ] && [ -d "/sys/class/leds/$UCI_RED" ]; then
    echo "Found UCI red LED: /sys/class/leds/$UCI_RED"
    echo none > "/sys/class/leds/$UCI_RED/trigger" 2>/dev/null
    echo timer > "/sys/class/leds/$UCI_RED/trigger" 2>/dev/null
    echo 1000 > "/sys/class/leds/$UCI_RED/delay_on" 2>/dev/null
    echo 1000 > "/sys/class/leds/$UCI_RED/delay_off" 2>/dev/null
else
    # Fallback for devices with numeric sysfs leds
    if [ -d "/sys/class/leds/0" ]; then
        echo "Falling back to /sys/class/leds/0"
        echo none > "/sys/class/leds/0/trigger" 2>/dev/null
        echo timer > "/sys/class/leds/0/trigger" 2>/dev/null
        echo 1000 > "/sys/class/leds/0/delay_on" 2>/dev/null
        echo 1000 > "/sys/class/leds/0/delay_off" 2>/dev/null
    fi
fi

# 6. Stop network interfaces to prevent any network traffic
echo "Step 6: Bringing down network..."
ifdown -a 2>/dev/null

echo "=== System is now safely parked in RAM with read-only flash. Ready for physical power off ==="

# 7. Sleep loop to keep kernel timers active (so timer-triggered LED blinks forever)
while true; do
    sleep 3600
done
