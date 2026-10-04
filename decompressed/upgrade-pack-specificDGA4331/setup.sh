#!/bin/sh

. /etc/init.d/rootdevice

move_files_and_clean() {
  for file in $(find "$1"*/ -xdev | cut -d '/' -f4-); do
    if [ -d "$1$file" ] && [ ! -d "/$file" ]; then
      mkdir -p "/$file"
      continue
    fi
    [ ! -d "$1$file" ] && mv "$1$file" "/$file"
  done
  rm -rf "$1"
}

logecho "Installing specificDGA4331 package..."
move_files_and_clean /tmp/upgrade-pack-specificDGA4331/

# Install only the DGA4331 button and LED integration. Preserve existing
# credentials, remote-access settings, Wi-Fi channels and security settings.
chmod +x /etc/rc.button/BTN_1 /etc/rc.button/BTN_2 \
  /usr/sbin/infobutton.sh /usr/sbin/wireless_get_mac_addr.sh 2>/dev/null

if [ -f /etc/config/button ] && ! uci -q get button.info >/dev/null; then
  uci set button.info=button
  uci set button.info.button='BTN_1'
  uci set button.info.action='released'
  uci set button.info.handler='/usr/sbin/infobutton.sh'
  uci set button.info.min='0'
  uci set button.info.max='2'
  uci commit button
  /etc/init.d/button restart 2>/dev/null
fi

if [ -f /etc/config/ledfw ]; then
  for entry in 'power 23 20' 'broadband 102 103' 'internet 101 19' \
    'ethernet 13' 'wireless 6' 'wps 104 105' 'voip 100'; do
    set -- $entry
    section="ctrl_$1"
    if ! uci -q get "ledfw.$section" >/dev/null; then
      uci set "ledfw.$section=control"
      uci set "ledfw.$section.name=$1"
      uci set "ledfw.$section.green=$2"
      [ -n "$3" ] && uci set "ledfw.$section.red=$3"
    fi
  done
  uci commit ledfw
  /etc/init.d/ledfw restart 2>/dev/null
fi

if [ ! -f /etc/config/modgui ]; then
  touch /etc/config/modgui
fi
uci -q get modgui.app >/dev/null || uci set modgui.app=app
uci set modgui.app.specific_app='1'
uci commit modgui
logecho "DGA4331 specific package installed successfully."
