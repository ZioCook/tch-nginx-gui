# Technicolor Nginx GUI (Enhanced Edition)

[![Donate](https://img.shields.io/badge/Donate-PayPal-green.svg)](https://www.paypal.me/AnsuelS)
[![License](https://img.shields.io/github/license/ZioCook/tch-nginx-gui.svg?style=flat)](https://github.com/ZioCook/tch-nginx-gui/blob/master/LICENSE)
[![Build & Release GUI](https://github.com/ZioCook/tch-nginx-gui/actions/workflows/build.yml/badge.svg)](https://github.com/ZioCook/tch-nginx-gui/actions/workflows/build.yml)
[![Latest Dev Build](https://img.shields.io/github/v/release/ZioCook/tch-nginx-gui?include_prereleases&label=DEV%20version)](https://github.com/ZioCook/tch-nginx-gui/releases)
[![Stable Release](https://img.shields.io/github/v/release/ZioCook/tch-nginx-gui?label=STABLE%20version)](https://github.com/ZioCook/tch-nginx-gui/releases)

A highly modified, modern and universal GUI for Technicolor modem/routers based on OpenWrt / OpenResty Nginx.

Originally created by **Ansuel** and the **ilpuntotecnico** community, this enhanced edition introduces smart service orchestration, Bridge / Dumb AP mode optimizations, QoS control with CPU overhead reduction, advanced Guest Wi-Fi management, OpenResty Lua taint fixes, and modernized GitHub Actions automated builds.

---

## 📱 Supported Devices

Compatible with (and not limited to) the following Technicolor gateways:
- **DGA4132** (TIM HUB) / `VBNT-S`
- **DGA4131** (Fastweb Fastgate) / `VBNT-O`
- **DGA4130** (Smart Modem Plus) / `VBNT-K`
- **TG589vac** / `VANT-E`
- **TG788vn v2** / `VDNT-W`
- **TG789vac v2 HP** / `VBNT-L`
- **TG789vac v2** / `VANT-6`
- **TG789vac (v1)** / `VANT-D`
- **TG789vac XTREAM 35B** / `VBNT-F`
- **TG799vac** / `VANT-F`
- **TG799vac XTREAM** / `VBNT-H`
- **TG800vac** / `VANT-Y`

---

## 🚀 Key Features & New Enhancements

### 🆕 New in this Edition:
- **Intelligent Service Orchestration (`apply_service_modes.sh`)**:
  - Automatic, clean start/stop and enable/disable of system services when switching operating modes (VDSL, ETH WAN, Bridge / Dumb AP Switch).
  - In **Bridge / AP Mode**, redundant daemons (`pppd`, firewall/NAT rules, routing daemons, CWMP/TR-069, QoS, IGMP proxy, cupsd, telstra) are safely shut down, liberating **50–70+ MB of RAM** and removing background CPU load.
- **Reworked Broadband ("Banda Larga") & Internet Access Cards**:
  - In Bridge / Dumb AP mode, the Broadband card cleanly displays **Parametri Rete Locale (AP)** (AP IP Address, Subnet Mask, Default Gateway, DNS Servers, DHCP Lease Time) without confusing GPON/SFP noise.
  - Safe detection of optional SFP modules to prevent UI errors when SFP interfaces are unconfigured.
  - Correct live extraction and formatting of active DNS servers.
- **QoS Master Switch & CPU Overhead Reduction**:
  - Dedicated **ON/OFF master toggle** directly in the QoS card header and configuration modal.
  - Clean fallback to Linux kernel `fq_codel` queue discipline when QoS is turned off, instantly eliminating Broadcom QoS packet processing overhead with **zero CPU load** and without requiring a reboot.
- **Advanced Wi-Fi Guest Network Management**:
  - Full toggle control over Guest Wi-Fi networks in Wireless settings.
  - **Dynamic Card Visibility**: when Guest networks are deactivated (`state = 0`), guest SSIDs are completely hidden from the main dashboard Wireless card and modal tabs. When enabled (`state = 1`), they appear with live status LEDs (green when transmitting, gray when radio is turned off).
- **OpenResty / Lua Taint Sanitization**:
  - Comprehensive `untaint()` normalization across cards and modals, eliminating spurious `"tainted string"` UI labels and fixing table key lookups for AP isolation and SSIDs.
- **Modern CI/CD Build Pipeline (GitHub Actions)**:
  - Automated build and packaging with `inizialize_gui.sh`, generating both `GUI.tar.bz2` (STABLE) and `GUI_dev.tar.bz2` (DEV) archives with MD5/SHA256 checksums and automated GitHub Releases.

### 🌟 Core Features:
- **Quick-glance statistics page & dashboard cards**
- **DLNA media server support**
- **CPU & RAM usage monitoring**
- **VoIP SIP credentials display** directly in the web UI
- **Firmware Upgrade / Downgrade** and config backup/restore from GUI
- **Eco settings** for CPU frequency governor and LED control
- **Traffic monitoring** with interactive real-time bandwidth charts
- **DoS protection & Fast Cache** acceleration options
- **Comprehensive xDSL stats** and selectable xDSL drivers
- **Modular extension installers**: LuCI Web UI, Transmission, Aria2, and more
- **Multiple customizable GUI themes** (including Fritz!Box skin)
- **CWMP / TR-069 firmware version spoofing** to prevent unwanted ISP overwrites

---

## 📦 Installation Instructions

### Prerequisites
You need **root access** on your Technicolor Gateway. For guides on gaining root access, refer to the community topics:
- [DGA4132 (TIM HUB)](https://www.ilpuntotecnico.com/forum/index.php/topic,78162.html)
- [DGA4130 (TIM Smart Modem Plus)](https://www.ilpuntotecnico.com/forum/index.php/topic,77325.html)
- [TG789vac v2 (TIM)](https://www.ilpuntotecnico.com/forum/index.php/topic,77981.0.html)
- [TG789vac v2 (Tiscali)](https://www.ilpuntotecnico.com/forum/index.php/topic,77988.html)
- [Universal Gateway Guide (Any ISP)](https://hack-technicolor.rtfd.io)
- [Il Punto Tecnico - Official GUI Topic](https://www.ilpuntotecnico.com/forum/index.php/topic,81461.0.html)

---

### Quick Install via SSH (Internet connection required)

Log into your router via SSH (`ssh root@192.168.1.1` or your router's IP) and run:

#### Option A: Latest Development Build (Recommended - includes all new features)
```bash
curl -k -L https://raw.githubusercontent.com/ZioCook/tch-nginx-gui/master/compressed/GUI_dev.tar.bz2 --output /tmp/GUI.tar.bz2
bzcat /tmp/GUI.tar.bz2 | tar -C / -xvf -
/etc/init.d/rootdevice force
```

#### Option B: Latest Stable Build
```bash
curl -k -L https://raw.githubusercontent.com/ZioCook/tch-nginx-gui/master/compressed/GUI.tar.bz2 --output /tmp/GUI.tar.bz2
bzcat /tmp/GUI.tar.bz2 | tar -C / -xvf -
/etc/init.d/rootdevice force
```

You can also download pre-built packages directly from [GitHub Releases](https://github.com/ZioCook/tch-nginx-gui/releases).

---

### Offline / Manual Install (No Internet connection)

1. Download `GUI_dev.tar.bz2` (or `GUI.tar.bz2`) from the [Releases page](https://github.com/ZioCook/tch-nginx-gui/releases) or the `compressed/` directory of this repository to your computer.
2. Upload the file to the router's `/tmp` directory using SCP / WinSCP:
   ```bash
   scp GUI_dev.tar.bz2 root@192.168.1.1:/tmp/GUI.tar.bz2
   ```
3. Connect via SSH and run:
   ```bash
   bzcat /tmp/GUI.tar.bz2 | tar -C / -xvf -
   /etc/init.d/rootdevice force
   ```

---

## 🛠️ Building from Source

To package the GUI manually on Linux or WSL:

```bash
# Clone the repository
git clone https://github.com/ZioCook/tch-nginx-gui.git
cd tch-nginx-gui

# Build the Development package (compressed/GUI_dev.tar.bz2)
./inizialize_gui.sh dev

# Or build the Stable package (compressed/GUI.tar.bz2)
./inizialize_gui.sh
```

On Windows, you can double-click `create_zip_dev.bat` or `create_zip.bat` (requires Git Bash in PATH).

---

## 🤝 Contributing & Bug Reports

If you encounter a bug or have an idea for an enhancement:
1. Open an issue on the [GitHub Issue Tracker](https://github.com/ZioCook/tch-nginx-gui/issues).
2. Attach system logs (run `logread` via SSH) and relevant screenshots.
3. Make sure to remove any personal information (public IP, passwords, MAC addresses) before posting.

---

## 💖 Credits & Donations

This project builds upon the immense work of **Ansuel**, the **ilpuntotecnico.com** forum community, and all open-source contributors.

If you would like to support the original creator of this modified GUI:
[![paypal](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif)](https://www.paypal.me/AnsuelS)
