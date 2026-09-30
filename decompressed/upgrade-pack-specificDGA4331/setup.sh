#!/bin/sh

. /etc/init.d/rootdevice

move_files_and_clean(){
  for file in $(find "$1"*/ -xdev | cut -d '/' -f4-); do
    if [ -d "$1$file" ] && [ ! -d "/$file" ]; then
      mkdir -p "/$file"
      continue
    fi

    [ ! -d "$1$file" ] && mv "$1$file" "/$file"

  done
  rm -rf "$1"
}
logecho "Installing specificDGA4331 package (TIM HUB+ / AGMY2020)..."
move_files_and_clean /tmp/upgrade-pack-specificDGA4331/

kernel_ver="$(cat /proc/version | awk '{print $3}')"
logecho "DGA4331 Kernel: $kernel_ver"

# Wi-Fi 6 (BCM43684) & Network IRQ Affinity Tuning
# BCM4908 / Cortex-A53:
# Offload Wi-Fi 5GHz (wl1) and 2.4GHz (wl0) IRQs to Core 1 (bitmask 2)
# so Core 0 remains free for Nginx, Lua, Transformer, and routing.
wifi_irq_5g=$(awk '/wl1/{print $1}' /proc/interrupts 2>/dev/null | tr -d ':' | head -1)
wifi_irq_24g=$(awk '/wl0/{print $1}' /proc/interrupts 2>/dev/null | tr -d ':' | head -1)
if [ -n "$wifi_irq_5g" ] && [ -f "/proc/irq/$wifi_irq_5g/smp_affinity" ]; then
  logecho "Pinning Wi-Fi 5GHz IRQ $wifi_irq_5g (wl1) to Core 1..."
  echo 2 > "/proc/irq/$wifi_irq_5g/smp_affinity"
fi
if [ -n "$wifi_irq_24g" ] && [ -f "/proc/irq/$wifi_irq_24g/smp_affinity" ]; then
  logecho "Pinning Wi-Fi 2.4GHz IRQ $wifi_irq_24g (wl0) to Core 1..."
  echo 2 > "/proc/irq/$wifi_irq_24g/smp_affinity"
fi

# Ensure telnet configuration exists
if [ ! -f /etc/config/telnet ]; then
  touch /etc/config/telnet
  uci set telnet.general=telnet
  uci set telnet.general.enable='0'
  uci commit telnet
fi

# Ensure Dropbear SSH afg instance is enabled and configured for root
if [ -f /etc/config/dropbear ]; then
  uci -q set dropbear.afg.enable='1'
  uci -q set dropbear.afg.RootLogin='1'
  uci -q set dropbear.afg.PasswordAuth='on'
  uci -q set dropbear.afg.RootPasswordAuth='on'
  uci -q set dropbear.lan.enable='0'
  uci commit dropbear
fi

# Ensure root password, ash shell and SSH authorized_keys
echo root:root | chpasswd 2>/dev/null
sed -i 's#/root:.*$#/root:/bin/ash#' /etc/passwd 2>/dev/null

mkdir -p /root/.ssh /etc/dropbear
cat << 'EOF' > /root/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDnIdt/Nvf1r5gTcRSlOF3j2yboIthsEpkEfbtU4/0zNEfy5tYUUCpgYY2Wk+E5UyJjndGTyxusXezzPmlAS2gaHsVEe+ftH4NTqZOHmChnge3/fn7fh0b5WpQSSyQbWGWzRcjDDDs/KlbpeUQ7xFIXLicTphKeD31TunMqYCe189qzU0SVnqhAuWVUgZ4gytE7luV/yF2gthbVq4We+h4xHrj/QTRcpR4RpG/Law3IaNkSX8XWpjyj3g79F8+vj4O97NOCZhaWV0YntK4rBrzfDdyw176gAj2FrHmZr4Kw1Uwvazzv6oSTzHHkci0jaiaR0AwuPgIcTkHkfAflfG6D lorenzo@Laptop-Lorenzo
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHsVkGFWrvddVIvh+4/wYhitbcGyEwqSzy20/x5WYG+V lorenzo@Laptop-Lorenzo
EOF
cp /root/.ssh/authorized_keys /etc/dropbear/authorized_keys
chmod 700 /root/.ssh /etc/dropbear
chmod 600 /root/.ssh/authorized_keys /etc/dropbear/authorized_keys 2>/dev/null

# Restart Dropbear to apply
/etc/init.d/dropbear enable
/etc/init.d/dropbear restart 2>/dev/null

# Fix /etc/board symlink and country map for BCM43684 Wi-Fi 6
if [ -d "/etc/boards/VCNT-3" ]; then
  rm -f /etc/board /saferoot/etc/board 2>/dev/null
  ln -sf /etc/boards/VCNT-3 /etc/board
  ln -sf /etc/boards/VCNT-3 /saferoot/etc/board 2>/dev/null
fi
if [ -f /etc/wlan/brcm_country_map_2G ]; then
  sed -i 's/E0 700/E0 0/g' /etc/wlan/brcm_country_map_2G /etc/wlan/brcm_country_map_5G
fi

# Ensure Wi-Fi radios are enabled and running
uci -q set wireless.radio_2G.state='1'
uci -q set wireless.radio_5G.state='1'
uci -q set wireless.wl0.state='1'
uci -q set wireless.ap0.state='1'
uci -q set wireless.wl1.state='1'
uci -q set wireless.ap1.state='1'
uci commit wireless
rm -f /tmp/hostapd_init_once 2>/dev/null
/etc/init.d/wireless restart 2>/dev/null
/etc/init.d/hostapd restart 2>/dev/null
brctl addif br-lan wl0 2>/dev/null
brctl addif br-lan wl1 2>/dev/null
ifconfig wl0 up 2>/dev/null
ifconfig wl1 up 2>/dev/null

# Ensure specific_app status is committed
uci set modgui.app.specific_app="1"
uci commit modgui

logecho "DGA4331 specific package installed successfully."

