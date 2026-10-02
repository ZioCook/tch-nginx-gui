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
    [ -f "$l/brightness" ] && echo 0 > "$l/brightness" 2>/dev/null
    [ -f "$l/trigger" ] && echo none > "$l/trigger" 2>/dev/null
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
RED_LED=""
for candidate in /sys/class/leds/power:red /sys/class/leds/*power*red* /sys/class/leds/*:red; do
    if [ -d "$candidate" ]; then
        RED_LED="$candidate"
        break
    fi
done

if [ -n "$RED_LED" ]; then
    echo "Found red LED: $RED_LED"
    echo timer > "$RED_LED/trigger" 2>/dev/null
    echo 1000 > "$RED_LED/delay_on" 2>/dev/null
    echo 1000 > "$RED_LED/delay_off" 2>/dev/null
else
    # Fallback for devices with numeric sysfs leds
    if [ -d "/sys/class/leds/0" ]; then
        echo "Falling back to /sys/class/leds/0"
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
