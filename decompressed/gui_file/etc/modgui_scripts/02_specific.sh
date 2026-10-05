#!/bin/sh

. /etc/init.d/rootdevice

extract_with_check() {

  export RESTART_SERVICE=0
  MD5_CHECK_DIR=/tmp/md5check

  [ ! -d $MD5_CHECK_DIR ] && mkdir $MD5_CHECK_DIR

  for file in $(bzcat "$1" | tar -C $MD5_CHECK_DIR -xvf -); do

    if [ ! -f "$MD5_CHECK_DIR/$file" ]; then
      if [ ! -d "/$file" ]; then
        mkdir "/$file"
      fi
      continue
    fi

    case "$file" in
      *.md5sum*) continue ;;
    esac

    orig_file=/$file
    file=$MD5_CHECK_DIR/$file

    if [ -f "$orig_file" ]; then
      md5_file=$(md5sum "$file" | awk '{ print $1 }')
      md5_orig_file=$(md5sum "$orig_file" | awk '{ print $1 }')
      if [ "$md5_file" = "$md5_orig_file" ]; then
        rm "$file"
        continue
      fi
    fi

    cp "$file" "$orig_file"
    rm "$file"
    RESTART_SERVICE=1

  done

  [ -d $MD5_CHECK_DIR ] && rm -r $MD5_CHECK_DIR

  rm "$1"

  return $RESTART_SERVICE
}

#Some globals var to check the right things to install
device_type="$(uci get -q env.var.prod_friendly_name)"
marketing_version="$(uci get -q version.@version[0].marketing_version)"
cpu_type="$(uname -m)"

# opkg also reads /etc/opkg/*.conf. Check each source name separately so
# partially configured feeds are completed without duplicating custom feeds.
append_missing_opkg_feeds() {
  local feed_type feed_name feed_url config
  set -- "$opkg_file"
  for config in "$opkg_config_dir"/*.conf; do
    [ ! -f "$config" ] || set -- "$@" "$config"
  done
  while read -r feed_type feed_name feed_url; do
    if ! awk -v name="$feed_name" '
      ($1 == "src" || $1 == "src/gz") && $2 == name { found = 1 }
      END { exit !found }
    ' "$@"; then
      printf '%s %s %s\n' "$feed_type" "$feed_name" "$feed_url" >> "$opkg_file"
    fi
  done
}

apply_right_opkg_repo() {
  logecho "Checking opkg feeds..."

  opkg_file="/etc/opkg.conf"
  opkg_config_dir="/etc/opkg"
  grep -q "check_certificate" $opkg_file 2>/dev/null || echo "option check_certificate 0" >> $opkg_file
  grep -q "check_certificate" /etc/wgetrc 2>/dev/null || echo "check_certificate = off" >> /etc/wgetrc
  grep -q "check_certificate" /root/.wgetrc 2>/dev/null || echo "check_certificate = off" >> /root/.wgetrc

  if [ "$cpu_type" = "armv7l" ]; then
    case $marketing_version in
    "19."* | "2."*)
      [ ! -e /usr/lib/libjson-c.so.2 ] && [ -f /usr/lib/libjson-c.so.4 ] && ln -sf /usr/lib/libjson-c.so.4 /usr/lib/libjson-c.so.2
      sed -i '/homeware\/18\/brcm63xx-tch/d' /etc/opkg.conf #remove old setted feeds
      sed -i '/Ansuel\/GUI_ipk\/kernel-4.1/d' /etc/opkg.conf #remove old setted feeds
      sed -i '/repository\.macoers\.com\/homeware\/19\/brcm6xxx-tch/d' /etc/opkg.conf #remove broken 19 macoers feeds
      if ! grep -q "Ansuel/GUI_ipk/kernel-4.1" $opkg_file; then
        cat <<EOF >>$opkg_file
arch all 100
arch arm_cortex-a9 200
arch arm_cortex-a9_neon 300
src/gz chaos_calmer_base https://raw.githubusercontent.com/Ansuel/GUI_ipk/kernel-4.1/base
src/gz chaos_calmer_packages https://raw.githubusercontent.com/Ansuel/GUI_ipk/kernel-4.1/packages
src/gz chaos_calmer_luci https://raw.githubusercontent.com/Ansuel/GUI_ipk/kernel-4.1/luci
src/gz chaos_calmer_routing https://raw.githubusercontent.com/Ansuel/GUI_ipk/kernel-4.1/routing
src/gz chaos_calmer_telephony https://raw.githubusercontent.com/Ansuel/GUI_ipk/kernel-4.1/telephony
src/gz chaos_calmer_core https://raw.githubusercontent.com/Ansuel/GUI_ipk/kernel-4.1/target/packages
EOF
      fi
      sed -i '/repository\/homeware\/18\/brcm63xx-tch/d' /etc/opkg.conf #remove old setted feeds
      append_missing_opkg_feeds <<EOF
src/gz chaos_calmer_base_macoers https://repository.macoers.com/homeware/18/brcm63xx-tch/VANTW/base
src/gz chaos_calmer_packages_macoers https://repository.macoers.com/homeware/18/brcm63xx-tch/VANTW/packages
src/gz chaos_calmer_luci_macoers https://repository.macoers.com/homeware/18/brcm63xx-tch/VANTW/luci
src/gz chaos_calmer_routing_macoers https://repository.macoers.com/homeware/18/brcm63xx-tch/VANTW/routing
src/gz chaos_calmer_telephony_macoers https://repository.macoers.com/homeware/18/brcm63xx-tch/VANTW/telephony
EOF
      ;;
    "18."*)
      if ! grep -q "Ansuel/GUI_ipk/kernel-4.1" $opkg_file; then
        cat <<EOF >>$opkg_file
arch all 100
arch arm_cortex-a9 200
arch arm_cortex-a9_neon 300
src/gz chaos_calmer_base https://raw.githubusercontent.com/Ansuel/GUI_ipk/kernel-4.1/base
src/gz chaos_calmer_packages https://raw.githubusercontent.com/Ansuel/GUI_ipk/kernel-4.1/packages
src/gz chaos_calmer_luci https://raw.githubusercontent.com/Ansuel/GUI_ipk/kernel-4.1/luci
src/gz chaos_calmer_routing https://raw.githubusercontent.com/Ansuel/GUI_ipk/kernel-4.1/routing
src/gz chaos_calmer_telephony https://raw.githubusercontent.com/Ansuel/GUI_ipk/kernel-4.1/telephony
src/gz chaos_calmer_core https://raw.githubusercontent.com/Ansuel/GUI_ipk/kernel-4.1/target/packages
EOF
      fi
      sed -i '/repository\/homeware\/18\/brcm63xx-tch/d' /etc/opkg.conf #remove old setted feeds
      append_missing_opkg_feeds <<EOF
src/gz chaos_calmer_base_macoers https://repository.macoers.com/homeware/18/brcm63xx-tch/VANTW/base
src/gz chaos_calmer_packages_macoers https://repository.macoers.com/homeware/18/brcm63xx-tch/VANTW/packages
src/gz chaos_calmer_luci_macoers https://repository.macoers.com/homeware/18/brcm63xx-tch/VANTW/luci
src/gz chaos_calmer_routing_macoers https://repository.macoers.com/homeware/18/brcm63xx-tch/VANTW/routing
src/gz chaos_calmer_telephony_macoers https://repository.macoers.com/homeware/18/brcm63xx-tch/VANTW/telephony
EOF
      ;;
    "17.3"*)
      sed -i '/roleo\/public\/agtef\/brcm63xx-tch/d' /etc/opkg.conf #remove old setted feeds
      if ! grep -q "roleo/public/agtef/1.1.0/brcm63xx-tch" $opkg_file; then
        cat <<EOF >>$opkg_file
src/gz chaos_calmer_base https://repository.ilpuntotecnico.com/files/roleo/public/agtef/1.1.0/brcm63xx-tch/packages/base
src/gz chaos_calmer_packages https://repository.ilpuntotecnico.com/files/roleo/public/agtef/1.1.0/brcm63xx-tch/packages/packages
src/gz chaos_calmer_luci https://repository.ilpuntotecnico.com/files/roleo/public/agtef/1.1.0/brcm63xx-tch/packages/luci
src/gz chaos_calmer_routing https://repository.ilpuntotecnico.com/files/roleo/public/agtef/1.1.0/brcm63xx-tch/packages/routing
src/gz chaos_calmer_telephony https://repository.ilpuntotecnico.com/files/roleo/public/agtef/1.1.0/brcm63xx-tch/packages/telephony
src/gz chaos_calmer_management https://repository.ilpuntotecnico.com/files/roleo/public/agtef/1.1.0/brcm63xx-tch/packages/management
EOF
      fi
      ;;
    "16.3"* | "17.1"* | "17.2"*)
      sed -i '/roleo\/public\/agtef\/1.1.0\/brcm63xx-tch/d' /etc/opkg.conf #remove old setted feeds
      if ! grep -q "roleo/public/agtef/brcm63xx-tch" $opkg_file; then
        cat <<EOF >>$opkg_file
src/gz chaos_calmer_base https://repository.ilpuntotecnico.com/files/roleo/public/agtef/brcm63xx-tch/packages/base
src/gz chaos_calmer_packages https://repository.ilpuntotecnico.com/files/roleo/public/agtef/brcm63xx-tch/packages/packages
src/gz chaos_calmer_luci https://repository.ilpuntotecnico.com/files/roleo/public/agtef/brcm63xx-tch/packages/luci
src/gz chaos_calmer_routing https://repository.ilpuntotecnico.com/files/roleo/public/agtef/brcm63xx-tch/packages/routing
src/gz chaos_calmer_telephony https://repository.ilpuntotecnico.com/files/roleo/public/agtef/brcm63xx-tch/packages/telephony
src/gz chaos_calmer_management https://repository.ilpuntotecnico.com/files/roleo/public/agtef/brcm63xx-tch/packages/management
EOF
      fi
      ;;
    "16.2"* | "16.1"*)
      if ! grep -q "FrancYescO/789vacv2_opkg/xtream35b" $opkg_file; then
        cat <<EOF >>$opkg_file
src/gz base https://raw.githubusercontent.com/FrancYescO/789vacv2_opkg/xtream35b/packages
EOF
      fi
      ;;
    *)
      logecho "No known ARM feeds for this version $marketing_version"
      ;;
    esac
  elif [ "$cpu_type" = "mips" ]; then
    case $marketing_version in
    "16."* | "17."*)
      if ! grep -q "chaos_calmer/15.05.1/brcm63xx" $opkg_file; then
        sed -i '/FrancYescO\/789vacv2/d' /etc/opkg.conf #remove old setted feeds
        cat <<EOF >>$opkg_file
src/gz chaos_calmer_base http://archive.openwrt.org/chaos_calmer/15.05.1/brcm63xx/generic/packages/base
src/gz chaos_calmer_packages http://archive.openwrt.org/chaos_calmer/15.05.1/brcm63xx/generic/packages/packages
src/gz chaos_calmer_luci http://archive.openwrt.org/chaos_calmer/15.05.1/brcm63xx/generic/packages/luci
src/gz chaos_calmer_routing http://archive.openwrt.org/chaos_calmer/15.05/brcm63xx/generic/packages/routing
src/gz chaos_calmer_telephony http://archive.openwrt.org/chaos_calmer/15.05/brcm63xx/generic/packages/telephony
src/gz chaos_calmer_management http://archive.openwrt.org/chaos_calmer/15.05.1/brcm63xx/generic/packages/management

arch all 100
arch brcm63xx 200
arch brcm63xx-tch 300
EOF
      fi
      ;;
    *)
      logecho "No known MIPS feeds for this version $marketing_version"
      ;;
    esac
  else
    logecho "CPU '$cpu_type' UNKNOWN, feeds not found for this version $marketing_version"
  fi

  # Remove non-existent hardcoded distfeed to avoid 404 on opkg update
  [ -f /etc/opkg/distfeeds.conf ] && {
    sed -i '/15.05.1\/brcm63xx-tch/d' /etc/opkg/distfeeds.conf
    sed -i '/targets\/brcm6xxx-tch\/VBNTJ_502L07p1/d' /etc/opkg/distfeeds.conf
    sed -i '/targets\/brcm6xxx-tch\/VCNTD_502L07p1/d' /etc/opkg/distfeeds.conf
  }
}

ledfw_extract() {
  if [ -f "/tmp/ledfw_support-specific$1.tar.bz2" ]; then
    extract_with_check "/tmp/ledfw_support-specific$1.tar.bz2"
    if [ $? -eq 1 ]; then
      /usr/share/transformer/scripts/restart_leds.sh
      ubus send fwupgrade '{"state":"upgrading"}' #avoid losing the flashing-state when service restarted
    fi
  fi
}

ledfw_rework_TG788() {
  if [ ! "$(uci get -q button.info)" ] || [ "$(uci get -q button.info)" = "BTN_3" ]; then
    logecho "Setting up status (wifi) button..."
    uci del button.easy_reset
    uci set button.info=button
    uci set button.info.button='BTN_1'
    uci set button.info.action='released'
    uci set button.info.handler='logger INFO button pressed ; ubus send infobutton '\''{"state":"active"}'\'''
    uci set button.info.min='0'
    uci set button.info.max='2'
    uci set button.eco.min='2'
    uci set button.eco.max='5'
    uci set button.acl.min='5'
    uci set ledfw.iptv.check='0'
    uci commit ledfw
  fi

  ledfw_extract "TG788"
}

ledfw_rework_TG799() {
  if [ ! "$(uci get -q button.info)" ]; then
    logecho "Setting up status (power) button..."
    uci del button.easy_reset
    uci set button.info=button
    uci set button.info.button='BTN_3'
    uci set button.info.action='released'
    uci set button.info.handler='logger INFO button pressed ; ubus send infobutton '\''{"state":"active"}'\'''
    uci set button.info.min='0'
    uci set button.info.max='2'
    uci set ledfw.iptv.check='0'
    uci commit ledfw
  fi

  ledfw_extract "TG799"
}

ledfw_rework_TG800() {
  if [ ! "$(uci get -q button.info)" ]; then
    logecho "Setting up status (wifi) button..."
    uci del button.easy_reset
    uci set button.info=button
    uci set button.info.button='BTN_1'
    uci set button.info.action='released'
    uci set button.info.handler='logger INFO button pressed ; ubus send infobutton '\''{"state":"active"}'\'''
    uci set button.info.min='0'
    uci set button.info.max='2'
    uci set button.wifi_on_off_toggle.min='2'
    uci set button.wifi_on_off_toggle.max='8'
    uci set ledfw.iptv.check='0'
    uci commit ledfw
  fi

  ledfw_extract "TG800"
}

#wifi_fix_24g() {
#	#Set wifi to perf mode
#	wl down
#	wl obss_prot set 0
#	wl -i wl0 gmode Performance
#	wl -i wl0 up
#
#}

install_specific() {
  logecho "Applying specific model fixes..."
  /usr/share/transformer/scripts/appInstallRemoveUtility.sh install specificapp "$1"
}

remove_wizard_5ghz() {
  if [ -n "$(find /www/wizard-cards/ -iname '*wireless_5G*')" ]; then
    logecho "Removing 5GHz config from wizard..."
    rm /www/wizard-cards/*wireless_5G*
  fi
}

apply_right_opkg_repo

if [ ! "$(uci get -q modgui.app.specific_app)" ]; then
  uci set modgui.app.specific_app="0"
fi

# TODO: make all specifc package generic (mips/arm)
# TODO: avoid replacing nginx/miniupnpd/dlnad in DGA pack if unneeded (deprecate the TG800 package)
# A case similar to this one is in the modgui-modal.lp for who installed offline
# and should be linked to the package download, make sure to reflect changes in the modal
case $marketing_version in
"16.1"* | "16.2"*)
  [ "$cpu_type" = "armv7l" ] && install_specific TG789Xtream35B
  [ "$cpu_type" = "mips" ] && install_specific TG789
  ;;
"16."* | "17."*)
  [ "$cpu_type" = "armv7l" ] && {
    [ -z "${device_type##*TG800*}" ] && install_specific TG800 || install_specific DGA
  }
  [ "$cpu_type" = "mips" ] && install_specific TG789
  ;;
"18."*)
  [ "$cpu_type" = "armv7l" ] && install_specific DGA
  [ "$cpu_type" = "mips" ] && logecho "Unknown what specific_app to install on $marketing_version $cpu_type"
  ;;
*)
  uci set modgui.app.specific_app="1" #no specific package for this firmware
  logecho "No specific_app package for $marketing_version $cpu_type"
  ;;
esac

uci commit modgui

[ -z "${device_type##*DGA4130*}" ] && ledfw_extract "DGA"
[ -z "${device_type##*DGA4132*}" ] && ledfw_extract "DGA"
[ -z "${device_type##*DGA4131*}" ] && ledfw_extract "DGA4131"
[ -z "${device_type##*DGA4331*}" ] && ledfw_extract "DGA4331"
[ -z "${device_type##*TG788*}" ] && ledfw_extract "TG788"
[ -z "${device_type##*TG788*}" ] && ledfw_rework_TG788
[ -z "${device_type##*TG789*}" ] && ledfw_extract "TG789"
[ -z "${device_type##*TG789*}" ] && [ -f /rom/usr/lib/lua/transformer/shared/WLANConfigurationCommon.lua ] && cp -f /rom/usr/lib/lua/transformer/shared/WLANConfigurationCommon.lua /usr/lib/lua/transformer/shared/WLANConfigurationCommon.lua
[ -z "${device_type##*TG589*}" ] && ledfw_rework_TG799
[ -z "${device_type##*TG799*}" ] && ledfw_rework_TG799
[ -z "${device_type##*TG800*}" ] && ledfw_rework_TG800
#[ -z "${device_type##*DGA413*}" ] && wifi_fix_24g

rm -f /tmp/ledfw* 2>/dev/null #clean ledfw bz2 from /tmp

[ -z "${device_type##*TG788*}" ] && remove_wizard_5ghz

if [ -f /proc/rip/0122 ]; then
  logecho "WARNING! RIP_ID_RESTRICTED_DOWNGR_TS detected!!"
fi
if [ -f /proc/rip/0123 ]; then
  logecho "WARNING! RIP_ID_RESTRICTED_DOWNGR_OPT detected!!"
fi

#Fix led issues
if grep -q "os.exit(0)" /sbin/ledfw.lua 2>/dev/null || grep -q "exit 0" /etc/init.d/ledfw 2>/dev/null; then
  [ -f /rom/sbin/ledfw.lua ] && cp -f /rom/sbin/ledfw.lua /sbin/ledfw.lua 2>/dev/null
  [ -f /rom/etc/init.d/ledfw ] && cp -f /rom/etc/init.d/ledfw /etc/init.d/ledfw 2>/dev/null
  [ -f /rom/etc/init.d/led ] && cp -f /rom/etc/init.d/led /etc/init.d/led 2>/dev/null
fi

if [ -z "${device_type##*DGA4131*}" ]; then
  if [ ! "$(uci get -q ledfw.ambient.active)" ]; then
    uci set ledfw.ambient=led
    uci set ledfw.ambient.active='1'
    uci commit ledfw
  fi
else
  if [ ! "$(uci get -q ledfw.status_led.enable)" ]; then
    uci set ledfw.status_led=status_led
    uci set ledfw.status_led.enable='0'
    uci commit ledfw
  fi
  if [ ! "$(uci get -q ledfw.wifi.nsc_on)" ]; then
    uci set ledfw.wifi=service
    uci set ledfw.wifi.nsc_on='1'
    uci commit ledfw
  fi
fi

detect_homeware() {
  local kernel_ver=$(uname -r)
  local fw_version=$(uci -q get env.var.friendly_sw_version_activebank || cat /proc/banktable/activeversion 2>/dev/null)
  
  if echo "$kernel_ver" | grep -q "4.1."; then
    echo "hw19"
  elif echo "$kernel_ver" | grep -q "3.4."; then
    if echo "$fw_version" | grep -qi "AGTEF_2\|AGTHP_2"; then
      echo "hw18"
    else
      echo "hw18"
    fi
  else
    echo "hw18" # Default fallback
  fi
}

hw_ver=$(detect_homeware)
logecho "Detected Homeware Version: $hw_ver"
if [ -f "/tmp/upgrade-pack-${hw_ver}.tar.bz2" ]; then
  logecho "Installing optimizations for $hw_ver..."
  extract_with_check "/tmp/upgrade-pack-${hw_ver}.tar.bz2"
fi

# IRQ Affinity tuning (HW19 / Kernel 4.1 dual-core only)
# On DGA4132 (VBNT), WiFi traffic (wl0) is pinned to Core 0 by default,
# starving Nginx/Transformer. Moving it to Core 1 (bitmask 0x2)
# leaves Core 0 free for latency-sensitive GUI and routing tasks.
# IMPORTANT: On DGA4331 (VCNT-3 / BCM43684 FullMAC DHD), PCIe interrupts are tightly
# coupled with Broadcom Runner/HWA packet flow acceleration on Core 0. Migrating
# dhdpcie IRQ 92/93 away from Core 0 causes flow ring desynchronization and fatal dongle traps!
if [ "$hw_ver" = "hw19" ]; then
  local board_m="$(uci get -q env.rip.board_mnemonic)"
  local prod_name="$(uci get -q env.var.prod_friendly_name)"
  if [ "$board_m" != "VCNT-3" ] && [ "$prod_name" != "MediaAccess DGA4331" ]; then
    for iface in wl0 wl1; do
      wifi_irq=$(awk "/$iface/{print \$1}" /proc/interrupts 2>/dev/null | tr -d ':' | head -1)
      if [ -n "$wifi_irq" ] && [ -f "/proc/irq/$wifi_irq/smp_affinity" ]; then
        logecho "Pinning WiFi IRQ $wifi_irq ($iface) to Core 1..."
        echo 2 > "/proc/irq/$wifi_irq/smp_affinity"
      fi
    done
  else
    for iface in wl0 wl1; do
      wifi_irq=$(awk "/$iface/{print \$1}" /proc/interrupts 2>/dev/null | tr -d ':' | head -1)
      if [ -n "$wifi_irq" ] && [ -f "/proc/irq/$wifi_irq/smp_affinity" ]; then
        echo 1 > "/proc/irq/$wifi_irq/smp_affinity" 2>/dev/null
      fi
    done

    # Patch Broadcom hostapd on DGA4331 to prevent FullMAC country & radio abort traps
    local hapd_bin="/usr/sbin/hostapd"
    local hapd_stock_md5="12897f282cb303c499e88c5d9e7b9f05"
    if [ -f "$hapd_bin" ]; then
      local cur_md5=$(md5sum "$hapd_bin" | awk '{print $1}')
      if [ "$cur_md5" = "$hapd_stock_md5" ]; then
        logecho "Patching hostapd for DGA4331 Broadcom FullMAC ioctls..."
        [ ! -f /overlay/upper/usr/sbin/hostapd ] && cp -f /rom/usr/sbin/hostapd /usr/sbin/hostapd
        printf '\x21\x00\x00\xea' | dd of="$hapd_bin" bs=1 seek=554736 count=4 conv=notrunc 2>/dev/null
        printf '\x21\x00\x00\xea' | dd of="$hapd_bin" bs=1 seek=598408 count=4 conv=notrunc 2>/dev/null
        printf '\x00\x00\xa0\xe1' | dd of="$hapd_bin" bs=1 seek=599872 count=4 conv=notrunc 2>/dev/null
        printf '\x00\x00\xa0\xe1' | dd of="$hapd_bin" bs=1 seek=602444 count=4 conv=notrunc 2>/dev/null
        chmod +x "$hapd_bin"
        /etc/init.d/hostapd restart
      fi
    fi

    # Fix invalid PMF values and ensure safe initial 5GHz channel if set to auto
    local uci_changed=0
    for ap in ap0 ap1; do
      if [ "$(uci get -q wireless.$ap.pmf)" = "optional" ]; then
        uci set wireless.$ap.pmf='disabled'
        uci_changed=1
      fi
    done
    if [ "$(uci get -q wireless.radio_5G.channel)" = "auto" ]; then
      uci set wireless.radio_5G.channel='36'
      uci set wireless.radio_5G.channelwidth='20/40/80'
      uci set wireless.radio_5G.acs_state='disabled'
      uci_changed=1
    fi
    if [ "$uci_changed" = "1" ]; then
      uci commit wireless
    fi

    # Ensure telnet support and symlinks exist on DGA4331
    if [ -f /bin/busybox_telnet ] && [ ! -x /usr/sbin/telnetd ]; then
      ln -sf /bin/busybox_telnet /usr/sbin/telnetd
    fi
    if [ -f /etc/init.d/telnet ] && [ ! -f /etc/init.d/telnetd ]; then
      ln -sf /etc/init.d/telnet /etc/init.d/telnetd
    elif [ -f /etc/init.d/telnetd ] && [ ! -f /etc/init.d/telnet ]; then
      ln -sf /etc/init.d/telnetd /etc/init.d/telnet
    fi
  fi
fi

