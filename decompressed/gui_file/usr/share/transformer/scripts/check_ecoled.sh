#!/bin/sh
# DGA4131 Ambient LED support
if [ "$(uci get -q ledfw.ambient.active)" = "0" ]; then
	ubus send ambient.status '{"state":"inactive"}'
elif [ "$(uci get -q ledfw.ambient.active)" = "1" ]; then
	ubus send ambient.status '{"state":"active"}'
fi

if [ "$(uci get -q ledfw.status_led.enable)" = "1" ]; then
	if [ "$(uci get -q ledfw.timeout.ms)" = "0" ] || [ -z "$(uci get -q ledfw.timeout.ms)" ]; then
		uci set ledfw.timeout.ms="5000"
		uci commit ledfw
	fi
	ubus send statusled '{"state":"enabled"}'
	ubus send statusled '{"state":"inactive"}'
	ubus send statusled '{"state":"active"}'
	if [ "$(uci get -q ledfw.status_led.stealth)" = "1" ]; then
		for l in /sys/class/leds/*blue* /sys/class/leds/power:*; do
			[ -f "$l/brightness" ] && echo 0 > "$l/brightness" 2>/dev/null
		done
	fi
else
	ubus send statusled '{"state":"disabled"}'
	ubus send statusled '{"state":"inactive"}'
	if [ -x /usr/share/transformer/scripts/restart_leds.sh ]; then
		/usr/share/transformer/scripts/restart_leds.sh >/dev/null 2>&1 &
	fi
fi	
