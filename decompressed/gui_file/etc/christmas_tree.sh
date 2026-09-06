#!/bin/sh

PIDFILE="/var/run/christmas_tree.pid"

if [ "$(date +'%m%d')" != "1224" ] && [ "$(date +'%m%d')" != "1225" ]; then
    echo "Date not correct cleaning and exiting..."
    sed -i '/christmas_tree/d' /etc/crontabs/root
    rm -f "$PIDFILE"
    sh -c "sleep 2 && /usr/share/transformer/scripts/restart_leds.sh &"
    killall christmas_tree.sh 2>/dev/null
    exit 0
fi

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
    echo "Already running, exiting..."
    exit 0
fi
echo $$ > "$PIDFILE"

trap 'trap "" EXIT; kill 0 2>/dev/null; rm -f "$PIDFILE"; exit' EXIT INT TERM HUP

randd(){
	grep -m1 -ao '[1-7]' /dev/urandom | head -n1
}

powerOnOffRandom(){
	while [ 1 ]; do
		rand=$(randd)
		echo 255 > "$1"/brightness
		echo powering up "$1" for $rand seconds
		sleep $(( $rand - 1 ))
		echo 0 > "$1"/brightness
		sleep $(( $rand - 1 ))
	done
}

for filename in /sys/class/leds/*; do
	( powerOnOffRandom "$filename" ) &
done

wait