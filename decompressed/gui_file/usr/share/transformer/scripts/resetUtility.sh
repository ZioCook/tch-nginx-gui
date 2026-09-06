#!/bin/sh
#
#	 Custom Gui for Technicolor Modem: utility script and modified gui for the Technicolor Modem
#	 								   interface based on OpenWrt
#
#    Copyright (C) 2018  Christian Marangi <ansuelsmth@gmail.com>
#
#    This file is part of Custom Gui for Technicolor Modem.
#    
#    Custom Gui for Technicolor Modem is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#    
#    Custom Gui for Technicolor Modem is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#    
#    You should have received a copy of the GNU General Public License
#    along with Custom Gui for Technicolor Modem.  If not, see <http://www.gnu.org/licenses/>.
#
#

showUsage() {
	echo "Reset Utility: run custom command to perform advanced reset."
	echo "Usage:"
	echo "	--help 		Show help message"
	echo "	--resetGui 	Restore original gui"
	echo "	--removeRoot 	Remove root and wipe overlay bank (factory reset)"
	echo "	--removeConfig 	Reset config. Modded gui is reinstalled"
}



restoreOriginalGui() {
	running_bank=""
	[ -f /proc/banktable/booted ] && running_bank=$(cat /proc/banktable/booted)
	overlay_base="/overlay"
	[ -n "$running_bank" ] && [ -d "/overlay/$running_bank" ] && overlay_base="/overlay/$running_bank"
	config_tmp=/tmp/config_tmp
	
	#Copying config simulating a firmware upgrade
	echo "Copying config files to config_tmp dir in RAM..."
	mkdir -p /tmp/config_tmp /tmp/shadow_file
	cp -r "$overlay_base"/etc/config/* $config_tmp/ 2>/dev/null
	[ -f "$overlay_base/etc/shadow" ] && cp "$overlay_base/etc/shadow" /tmp/shadow_file/
	
	#Saving root files
	emergencydir=/tmp/rootfile/emergency
	mkdir -p $emergencydir/etc/init.d $emergencydir/etc/rc.d $emergencydir/usr/bin $emergencydir/lib/upgrade $emergencydir/sbin
	[ -f "$overlay_base/lib/upgrade/platform.sh" ] && cp "$overlay_base/lib/upgrade/platform.sh" $emergencydir/lib/upgrade/
	[ -f "$overlay_base/sbin/sysupgrade" ] && cp "$overlay_base/sbin/sysupgrade" $emergencydir/sbin/
	[ -f "$overlay_base/etc/init.d/rootdevice" ] && cp "$overlay_base/etc/init.d/rootdevice" $emergencydir/etc/init.d/
	[ -f "$overlay_base/usr/bin/rtfd" ] && cp "$overlay_base/usr/bin/rtfd" $emergencydir/usr/bin/
	[ -f "$overlay_base/usr/bin/sysupgrade-safe" ] && cp "$overlay_base/usr/bin/sysupgrade-safe" $emergencydir/usr/bin/
	[ -f "$overlay_base/etc/rc.d/S94rootdevice" ] && cp -d "$overlay_base/etc/rc.d/S94rootdevice" $emergencydir/etc/rc.d/
	
	#Delete any change from running bank
	if [ -n "$running_bank" ] && [ -d "/overlay/$running_bank" ]; then
		rm -rf "/overlay/$running_bank"
	else
		for d in /overlay/*; do
			[ "$d" != "/overlay/homeware_conversion" ] && rm -rf "$d"
		done
	fi
	
	#Restore config to be converted
	if [ -d $config_tmp ]; then
		mkdir -p /overlay/homeware_conversion/etc/config
		cp $config_tmp/* /overlay/homeware_conversion/etc/config/ 2>/dev/null
		[ -f $config_tmp/modgui ] && cp $config_tmp/modgui /overlay/homeware_conversion/etc/modgui_old
		[ -f /tmp/shadow_file/shadow ] && cp /tmp/shadow_file/shadow /overlay/homeware_conversion/etc/
	fi
	
	#Root only
	mkdir -p "$overlay_base"
	cp -dr $emergencydir/* "$overlay_base"/
	reboot
}

resetConfig() {
	running_bank=""
	[ -f /proc/banktable/booted ] && running_bank=$(cat /proc/banktable/booted)
	if [ -n "$running_bank" ] && [ -d "/overlay/$running_bank" ]; then
		rm -rf "/overlay/$running_bank/etc/uci-defaults"
	else
		rm -rf /overlay/etc/uci-defaults
	fi
	rm -rf /etc/config/*
	cp -r /rom/etc/config/* /etc/config/ 2>/dev/null
	[ "$(pgrep "cwmpd")" ] && /etc/init.d/cwmpd stop
	[ -f /etc/cwmpd.db ] && rm -f /etc/cwmpd.db
	touch /root/.install_gui #this is needed to trigger GUI full install after reboot mainly to reapply all custom edits to stock config files needed by custom GUI
	reboot
}

resetCwmp() {
	[ "$(pgrep "cwmpd")" ] && /etc/init.d/cwmpd stop
	[ -f /etc/cwmpd.db ] && rm -f /etc/cwmpd.db
	[ "$(uci get -q env.var.provisioning_code)" ] && uci del env.var.provisioning_code
	/etc/init.d/cwmpd start
}

case "$1" in
		--help)
			showUsage
			;;
		--resetCWMP)
			resetCwmp
			;;
		--resetGui)
			restoreOriginalGui
			;;
		--removeRoot)
			/usr/share/transformer/scripts/hardreset.sh
			;;
		--removeConfig)
			resetConfig
			;;
		"")
			echo "resetUtility: provide an option. Use --help to show them." 1>&2
			;;
		*)
			echo "resetUtility: unknown option '$1'" 1>&2
			return 1
esac

