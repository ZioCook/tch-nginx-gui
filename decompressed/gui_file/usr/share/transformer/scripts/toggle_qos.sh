#!/bin/sh
# /usr/share/transformer/scripts/toggle_qos.sh
# Toggle QoS subsystem on/off cleanly and persistently

STATE="$1"

if [ "$STATE" = "1" ]; then
    logger -t "QoS" "Enabling QoS service..."
    uci -q set modgui.var.qos_enabled='1'
    uci -q commit modgui

    for dev in eth0 eth1 eth2 eth3 wl0 wl1; do
        uci -q set qos.${dev}.enable='1'
    done
    [ -n "$(uci -q get qos.eth4)" ] && uci -q set qos.eth4.enable='1'
    [ -n "$(uci -q get qos.ptm0)" ] && uci -q set qos.ptm0.enable='1'
    uci -q commit qos

    /etc/init.d/qos enable 2>/dev/null
    /etc/init.d/qos restart 2>/dev/null
    /etc/init.d/iqos enable 2>/dev/null
    /etc/init.d/iqos restart 2>/dev/null
    logger -t "QoS" "QoS service enabled."
else
    logger -t "QoS" "Disabling QoS service..."
    uci -q set modgui.var.qos_enabled='0'
    uci -q commit modgui

    for dev in ptm0 eth0 eth1 eth2 eth3 eth4 wl0 wl1; do
        uci -q set qos.${dev}.enable='0'
    done
    uci -q commit qos

    /etc/init.d/qos stop 2>/dev/null
    /etc/init.d/qos disable 2>/dev/null
    /etc/init.d/iqos stop 2>/dev/null
    /etc/init.d/iqos disable 2>/dev/null

    for dev in eth0 eth1 eth2 eth3 eth4 eth5 wl0 wl1; do
        if ip link show $dev >/dev/null 2>&1; then
            tc qdisc replace dev $dev root fq_codel 2>/dev/null || true
        fi
    done
    logger -t "QoS" "QoS service disabled."
fi
