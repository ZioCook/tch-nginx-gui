#!/bin/sh

if [ "$(uci get -q ledfw.status_led.enable)" = "1" ]; then
	if [ "$(uci get -q ledfw.timeout.ms)" = "0" ] || [ -z "$(uci get -q ledfw.timeout.ms)" ]; then
		uci set ledfw.timeout.ms="5000"
		uci commit ledfw
	fi
	ubus send statusled '{"state":"enabled"}'
	ubus send statusled '{"state":"inactive"}'
	ubus send statusled '{"state":"active"}'
else
	ubus send statusled '{"state":"disabled"}'
	ubus send statusled '{"state":"inactive"}'
	if [ -x /usr/share/transformer/scripts/restart_leds.sh ]; then
		/usr/share/transformer/scripts/restart_leds.sh >/dev/null 2>&1 &
	fi
fi	
