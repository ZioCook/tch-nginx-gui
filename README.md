[![Donate](https://img.shields.io/badge/Donate-PayPal-green.svg)](https://www.paypal.me/AnsuelS) [![License](https://img.shields.io/github/license/ZioCook/tch-nginx-gui.svg?style=flat)](https://github.com/ZioCook/tch-nginx-gui/blob/master/LICENSE) [![Build & Release GUI](https://github.com/ZioCook/tch-nginx-gui/actions/workflows/build.yml/badge.svg)](https://github.com/ZioCook/tch-nginx-gui/actions/workflows/build.yml) [![Latest Release](https://img.shields.io/github/v/release/ZioCook/tch-nginx-gui?include_prereleases&label=DEV%20version)](https://github.com/ZioCook/tch-nginx-gui/releases) [![Stable Release](https://img.shields.io/github/v/release/ZioCook/tch-nginx-gui?label=STABLE%20version)](https://github.com/ZioCook/tch-nginx-gui/releases)

<h3><strong>This is a highly modified and universal version of the GUI installed on all Technicolor Modem/Routers compatible with (and probably not only):</strong></h3>
  <ul>
  <li>DGA4132 / VBNT-S</li>
  <li>DGA4131 / VBNT-O</li>
  <li>DGA4130 / VBNT-K</li>
  <li>TG589vac / VANT-E</li>
  <li>TG788vn v2 / VDNT-W</li>
  <li>TG789vac v2 HP / VBNT-L</li>
  <li>TG789vac v2 / VANT-6</li>
  <li>TG789vac (v1) / VANT-D</li>
  <li>TG789vac XTREAM 35B / VBNT-F</li>
  <li>TG799vac / VANT-F</li>
  <li>TG799vac XTREAM / VBNT-H</li>
  <li>TG800vac / VANT-Y</li>
  </ul>
with many fixes and features like:
<ul>
<li><b>Quick glance statistics page</b></li>
<li>DLNA Fully working</li>
<li>Visualise CPU & RAM load</li>
<li>Show VoIP Password directly on the GUI</li>
<li>Upgrade/Downgrade firmware from the GUI</li>
<li>Export and Save modem configuration from the GUI</li>
<li>Ability to select two channels for the update (DEV or Stable)</li>
<li>Eco settings for the CPU and LEDs</li>
<li>Easy set up for Bridge or Voice Mode</li>
<li><b>Bridge / Dumb AP Mode</b>: reworked broadband card showing dedicated Local Network parameters and hiding unused GPON/SFP sections</li>
<li><b>Smart Service Orchestration</b>: automatically stops idle daemons in Bridge mode to free 50-70+ MB of RAM and reduce CPU overhead</li>
<li><b>QoS Master Switch</b>: global ON/OFF toggle on card and modal with fq_codel fallback (zero CPU overhead)</li>
<li><b>Wi-Fi Guest Management</b>: enable/disable guest networks with dynamic card visibility</li>
<li>Traffic monitoring with Interactive Charts</li>
<li>Fast Cache Options</li>
<li>DoS Protect Options</li>
<li>Improved Traffic Graph</li>
<li>Dozens of xDSL Stats & selectable xDSL drivers</li>
<li>Ability to install LuCI GUI or sharing services like transmission / aria2</li>
<li>Spoofing of firmware version to bypass CWMP controls</li>
<li>Select many skins for the GUI, like the Fritz!Box one</li>
<li>And many others...</li>
</ul>

> **AVVERTENZA / DISCLAIMER**:
> Le modifiche e le personalizzazioni presenti in questo repository sono state realizzate esclusivamente per le mie necessità personali. Il progetto viene condiviso "così com'è": **non risolverò bug né aggiungerò feature su richiesta**. Per i dettagli delle modifiche di ciascuna versione, consultare il changelog nella [sezione Releases](https://github.com/ZioCook/tch-nginx-gui/releases).

<h2><strong>Basic installation instructions:</strong></h2>

<h3><strong>First you need to get root access to your Gateway</strong></h3>
Some Topics to help you get root access:
<ul>
<li>DGA4130 TIM: https://www.ilpuntotecnico.com/forum/index.php/topic,77325.html</li>
<li>DGA4132 TIM: https://www.ilpuntotecnico.com/forum/index.php/topic,78162.html</li>
<li>789vac v2 TIM: https://www.ilpuntotecnico.com/forum/index.php/topic,77981.0.html</li>
<li>789vac v2 Tiscali: https://www.ilpuntotecnico.com/forum/index.php/topic,77988.html</li>
<li>789vac v1/2/3, 799vac, 800vac and 797n v3 Any ISP: https://hack-technicolor.rtfd.io</li>
</ul>
General GUI Topic: https://www.ilpuntotecnico.com/forum/index.php/topic,81461.0.html

<h3>Then execute these commands (Active WAN/Internet connection required):</h3>

```bash
curl -k https://raw.githubusercontent.com/ZioCook/tch-nginx-gui/master/compressed/GUI_dev.tar.bz2 --output /tmp/GUI.tar.bz2
bzcat /tmp/GUI.tar.bz2 | tar -C / -xvf -
/etc/init.d/rootdevice force
```

Tutti i pacchetti compilati (inclusi archivi `.zip` e `.tar.bz2`) e il changelog dettagliato sono disponibili nella sezione **[Releases](https://github.com/ZioCook/tch-nginx-gui/releases)**.

Se riscontri errori durante il download o il modem non ha accesso a Internet, scarica manualmente il pacchetto dalla pagina Releases, trasferiscilo in `/tmp/GUI.tar.bz2` via SCP ed esegui i comandi `bzcat` e `rootdevice`.

Stats:
<img src="https://i.ibb.co/XjhF629/modemstats.jpg">

Cards:
<img src="https://i.ibb.co/5BDrRnx/odemcards.jpg">

<h2><strong>Donation</strong></h2>

If you want to donate to the original developer of this modified GUI (Ansuel):

[![paypal](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif)](https://www.paypal.me/AnsuelS)
