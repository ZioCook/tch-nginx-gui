#!/bin/sh
#
# Script: apply_service_modes.sh
# Purpose: Intelligently enable/disable system services according to the active network mode
#          (VDSL, ADSL, FTTH/Ethernet WAN, GPON/SFP, Bridge / Dumb AP switch).
#

logger -t "ServiceModeManager" "Starting service mode adjustment..."

# 1. Determine active mode
wan_mode=$(uci -q get network.config.wan_mode)
wan_proto=$(uci -q get network.wan.proto)
wan_auto=$(uci -q get network.wan.auto)
lan_gw=$(uci -q get network.lan.gateway)
l2type=$(uci -q get wansensing.global.l2type)
wan_ifname=$(uci -q get network.wan.ifname)

detected_mode=""

if [ "$wan_mode" = "bridge" ] || [ "$wan_proto" = "bridge" ] || { [ "$wan_proto" = "none" ] && [ "$wan_auto" = "0" ] && [ -n "$lan_gw" ]; }; then
    detected_mode="bridge"
elif [ "$l2type" = "ETH" ] || echo "$wan_ifname" | grep -qE "eth4|eth3"; then
    detected_mode="ftth"
elif [ "$l2type" = "SFP" ]; then
    detected_mode="gpon"
elif [ "$l2type" = "ADSL" ] || echo "$wan_ifname" | grep -q "atm"; then
    detected_mode="adsl"
elif [ "$l2type" = "VDSL" ] || echo "$wan_ifname" | grep -q "ptm"; then
    detected_mode="vdsl"
else
    # Fallback based on wan_mode or interface
    case "$wan_mode" in
        pppoe|dhcp|static)
            if [ -n "$l2type" ] && [ "$l2type" != "ETH" ] && [ "$l2type" != "SFP" ]; then
                detected_mode="vdsl"
            else
                detected_mode="ftth"
            fi
            ;;
        *)
            detected_mode="vdsl"
            ;;
    esac
fi

logger -t "ServiceModeManager" "Active detected mode: $detected_mode"

case "$detected_mode" in
    bridge)
        # --- BRIDGE / DUMB AP SWITCH MODE ---
        # 1. Disable & Stop xDSL and XTM PHY/driver
        if [ -x /etc/init.d/xdsl ]; then
            /etc/init.d/xdsl stop 2>/dev/null
            /etc/init.d/xdsl disable 2>/dev/null
        fi
        if [ -x /etc/init.d/xtm ]; then
            /etc/init.d/xtm stop 2>/dev/null
            /etc/init.d/xtm disable 2>/dev/null
        fi
        killall -9 xdslctl xdslctl1 2>/dev/null

        # 2. Disable & Stop WAN Sensing
        if [ -x /etc/init.d/wansensing ]; then
            /etc/init.d/wansensing stop 2>/dev/null
            /etc/init.d/wansensing disable 2>/dev/null
        fi
        uci -q set wansensing.global.enable='0'
        uci commit wansensing 2>/dev/null

        # 3. Disable & Stop UPnP Gateway daemon
        if [ -x /etc/init.d/miniupnpd-tch ]; then
            /etc/init.d/miniupnpd-tch stop 2>/dev/null
            /etc/init.d/miniupnpd-tch disable 2>/dev/null
        fi

        # 4. Disable & Stop Multicast Routing Proxies
        if [ -x /etc/init.d/igmpproxy ]; then
            /etc/init.d/igmpproxy stop 2>/dev/null
            /etc/init.d/igmpproxy disable 2>/dev/null
        fi
        if [ -x /etc/init.d/mldproxy ]; then
            /etc/init.d/mldproxy stop 2>/dev/null
            /etc/init.d/mldproxy disable 2>/dev/null
        fi

        # 5. Prevent rogue DHCP server and rogue IPv6 RA on LAN
        dhcp_changed=0
        if [ "$(uci -q get dhcp.lan.ignore)" != "1" ]; then
            uci -q set dhcp.lan.ignore='1'
            dhcp_changed=1
        fi
        if [ "$(uci -q get dhcp.lan.ra)" != "disabled" ]; then
            uci -q set dhcp.lan.ra='disabled'
            dhcp_changed=1
        fi
        if [ "$(uci -q get dhcp.lan.dhcpv6)" != "disabled" ]; then
            uci -q set dhcp.lan.dhcpv6='disabled'
            dhcp_changed=1
        fi
        if [ "$(uci -q get dhcp.lan.ndp)" != "disabled" ]; then
            uci -q set dhcp.lan.ndp='disabled'
            dhcp_changed=1
        fi
        if [ "$dhcp_changed" = "1" ]; then
            uci commit dhcp
            /etc/init.d/dnsmasq restart 2>/dev/null
            /etc/init.d/odhcpd restart 2>/dev/null
        fi

        # 6. Ensure IGMP Snooping on br-lan is active for smooth multicast/IPTV
        if [ "$(uci -q get network.lan.igmp_snooping)" != "1" ]; then
            uci -q set network.lan.igmp_snooping='1'
            uci commit network
        fi

        # 7. Manage QoS in bridge mode according to user preference (default off in bridge)
        qos_pref=$(uci -q get modgui.var.qos_enabled)
        if [ "$qos_pref" != "1" ]; then
            /usr/share/transformer/scripts/toggle_qos.sh 0
        fi
        ;;

    ftth|gpon)
        # --- FTTH / ETHERNET WAN / GPON SFP ROUTED MODE ---
        # 1. Disable & Stop xDSL and XTM
        if [ -x /etc/init.d/xdsl ]; then
            /etc/init.d/xdsl stop 2>/dev/null
            /etc/init.d/xdsl disable 2>/dev/null
        fi
        if [ -x /etc/init.d/xtm ]; then
            /etc/init.d/xtm stop 2>/dev/null
            /etc/init.d/xtm disable 2>/dev/null
        fi
        killall -9 xdslctl xdslctl1 2>/dev/null

        # 2. Enable & Start UPnP Gateway daemon
        if [ -x /etc/init.d/miniupnpd-tch ]; then
            /etc/init.d/miniupnpd-tch enable 2>/dev/null
            /etc/init.d/miniupnpd-tch start 2>/dev/null
        fi

        # 3. Enable & Start Multicast Routing Proxies
        if [ -x /etc/init.d/igmpproxy ]; then
            /etc/init.d/igmpproxy enable 2>/dev/null
            /etc/init.d/igmpproxy start 2>/dev/null
        fi

        # 4. Enable DHCP Server on LAN
        dhcp_changed=0
        if [ "$(uci -q get dhcp.lan.ignore)" != "0" ]; then
            uci -q set dhcp.lan.ignore='0'
            dhcp_changed=1
        fi
        if [ "$dhcp_changed" = "1" ]; then
            uci commit dhcp
            /etc/init.d/dnsmasq restart 2>/dev/null
        fi
        ;;

    vdsl|adsl)
        # --- VDSL / ADSL MODEM ROUTED MODE ---
        # 1. Enable & Start xDSL and XTM
        if [ -x /etc/init.d/xdsl ]; then
            /etc/init.d/xdsl enable 2>/dev/null
            /etc/init.d/xdsl start 2>/dev/null
        fi
        if [ -x /etc/init.d/xtm ]; then
            /etc/init.d/xtm enable 2>/dev/null
            /etc/init.d/xtm start 2>/dev/null
        fi

        # 2. Enable & Start UPnP Gateway daemon
        if [ -x /etc/init.d/miniupnpd-tch ]; then
            /etc/init.d/miniupnpd-tch enable 2>/dev/null
            /etc/init.d/miniupnpd-tch start 2>/dev/null
        fi

        # 3. Enable & Start Multicast Routing Proxies
        if [ -x /etc/init.d/igmpproxy ]; then
            /etc/init.d/igmpproxy enable 2>/dev/null
            /etc/init.d/igmpproxy start 2>/dev/null
        fi

        # 4. Enable DHCP Server on LAN
        dhcp_changed=0
        if [ "$(uci -q get dhcp.lan.ignore)" != "0" ]; then
            uci -q set dhcp.lan.ignore='0'
            dhcp_changed=1
        fi
        if [ "$dhcp_changed" = "1" ]; then
            uci commit dhcp
            /etc/init.d/dnsmasq restart 2>/dev/null
        fi
        ;;
esac

logger -t "ServiceModeManager" "Service mode adjustment completed for $detected_mode."
exit 0
