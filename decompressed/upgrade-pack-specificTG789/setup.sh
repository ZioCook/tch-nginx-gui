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
logecho "Installing specificTG789 package..."
move_files_and_clean /tmp/upgrade-pack-specificTG789/

#needed to fix "can't execute 'openssl'" on opkg update from https feed
if [ -f /tmp/openssl-util_1.0.2g-1_brcm63xx-tch.ipk ]; then
  opkg install /tmp/openssl-util_1.0.2g-1_brcm63xx-tch.ipk
  rm -f /tmp/openssl-util_1.0.2g-1_brcm63xx-tch.ipk
fi

if [ ! -f /etc/config/telnet ]; then
  touch /etc/config/telnet
  uci set telnet.general=telnet
  uci set telnet.general.enable='0'
  uci commit telnet
fi

if [ -f /bin/busybox_telnet ]; then
  ln -sf /bin/busybox_telnet /usr/sbin/telnetd
fi

if [ -f /etc/init.d/telnet ] && [ ! -f /etc/init.d/telnetd ]; then
  ln -sf /etc/init.d/telnet /etc/init.d/telnetd
elif [ -f /etc/init.d/telnetd ] && [ ! -f /etc/init.d/telnet ]; then
  ln -sf /etc/init.d/telnetd /etc/init.d/telnet
fi
