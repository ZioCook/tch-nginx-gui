<div align="center">

# GUI per Gateway Technicolor
### *Fork aggiornato della GUI Ansuel per router OpenWrt / Homeware*

[![Donazione ad Ansuel](https://img.shields.io/badge/Donazione-Autore%20Originale%20(Ansuel)-green.svg)](https://www.paypal.me/AnsuelS)
[![Licenza](https://img.shields.io/github/license/ZioCook/tch-nginx-gui.svg?style=flat)](https://github.com/ZioCook/tch-nginx-gui/blob/master/LICENSE)
[![Build & Release](https://github.com/ZioCook/tch-nginx-gui/actions/workflows/build.yml/badge.svg)](https://github.com/ZioCook/tch-nginx-gui/actions/workflows/build.yml)
[![Canale DEV](https://img.shields.io/github/v/release/ZioCook/tch-nginx-gui?include_prereleases&label=Canale%20DEV)](https://github.com/ZioCook/tch-nginx-gui/releases)
[![Canale STABLE](https://img.shields.io/github/v/release/ZioCook/tch-nginx-gui?label=Canale%20STABLE)](https://github.com/ZioCook/tch-nginx-gui/releases)

<p align="center">
  <b>Interfaccia web universale, aggiornata e ottimizzata per modem/router Technicolor basati su OpenWrt / Homeware.</b>
</p>

</div>

---

> [!NOTE]
> **Note di Sviluppo & Disclaimer:**  
> Questo repository è mantenuto con il supporto di AI pair programming e verificato direttamente su dispositivi fisici Technicolor. Il software viene condiviso a scopo amatoriale "così com'è", senza alcuna garanzia: l'installazione e l'utilizzo avvengono sotto la propria esclusiva responsabilità.

---

## 📡 Dispositivi Supportati

* **DGA4331** (TIM HUB+ / AGMY2020 / VCNT-3)
* **DGA4132** (TIM HUB / VBNT-S)
* **DGA4131** (Fastweb FastGate / VBNT-O)
* **DGA4130** (Smart Modem Plus / VBNT-K)
* **TG789vac v2** (VANT-6) & **TG789vac v2 HP** (VBNT-L)
* **TG789vac v1** (VANT-D)
* **TG789vac XTREAM 35B** (VBNT-F)
* **TG799vac** (VANT-F) & **TG799vac XTREAM** (VBNT-H)
* **TG800vac** (VANT-Y)
* **TG589vac** (VANT-E)
* **TG788vn v2** (VDNT-W)

---

## ✨ Miglioramenti Principali rispetto alla GUI Originale

* 🛡️ **Spegnimento Sicuro Hardware e Software (Safe Shutdown):** Arresto pulito dei servizi, svuotamento della cache flash (`sync`) e rimontaggio di `/overlay` in **sola lettura (`ro`)** per proteggere la flash NAND da corruzioni del filesystem. Attivabile da Web (modale Gateway) o tramite **tasto fisico WPS** (pressione prolungata per 15s con countdown visivo a 10s via strobe rapido LED).
* 🆕 **Supporto Nativo per DGA4331 (TIM HUB+):** Integrazione completa per Broadcom BCM63178 / BCM43684 (`VCNT-3` / `AGMY2020`), con pacchetto dedicato, Wi-Fi 6 (802.11ax), patch ioctl FullMAC, gestione corretta dei LED e recovery SSH dropbear.
* ⚡ **Ottimizzazione Prestazioni Web & Richieste AJAX:** Ristrutturazione del ciclo di aggiornamento asincrono delle card e del binding Knockout.js. Risolte le corruzioni visive e le duplicazioni delle card durante le transizioni rapide, aggiunto cache-busting per i modali e alleggeriti gli asset web core (-31% su CSS/JS).
* 🚀 **Calcolo CPU Real-Time Zero-Fork:** Monitoraggio del carico CPU tramite lettura diretta di `/proc/stat` con calcolo del delta senza generare sottoprocessi shell (azzeramento dell'overhead CPU causato dal monitoraggio).
* 🌉 **Modalità Bridge / Dumb AP Ottimizzata:** Riorganizzazione della scheda di rete locale e spegnimento automatico dei demoni router inutilizzati (risparmio reale di oltre **50–70 MB di RAM** e azzeramento del carico CPU a riposo).
* 🚦 **QoS Master Switch Globale:** Interruttore generale ON/OFF rapido su card e modale, con fallback efficiente su `fq_codel` a zero overhead di processore.
* 🌐 **Localizzazione Completa al 100%:** Traduzioni interamente revisionate per Italiano (`it-it`) e Tedesco (`de-de`) con oltre 1.800 stringhe corrette, eliminando etichette mancanti e fallback forzati in inglese in tutti i menu e modali.
* 👥 **Gestione Rapida Wi-Fi Guest:** Interruttore dedicato e comparsa/scomparsa dinamica automatica delle schede per le reti ospiti inattive.
* 📶 **Sblocco Ampiezza Wi-Fi 80 MHz & Canali DFS:** Ampiezza di banda a 80 MHz e canali DFS (36–112) sbloccati su radio Broadcom 5GHz per massime prestazioni wireless.
* 🔄 **Supporto Completo DGA4132 su Homeware 19.4+:** Piena compatibilità con i firmware più recenti (2.4.4+ / kernel Linux 4.1.52), link di compatibilità `libjson-c.so.2` e interrogazione condizionale modulo SFP.
* 📡 **Supporto Nativo EasyMesh / Multi-AP:** Integrazione delle card e delle modali di configurazione EasyMesh per i gateway compatibili, con sincronizzazione fronthaul e nodi mesh.
* 🔐 **Normalizzazione Sicurezza & Permessi Sudo:** Regola dedicata in `/etc/sudoers.d/nobody`, bit SUID verificato per `sudo` e normalizzazione automatica dei permessi di esecuzione (`chmod 755`) per tutti gli script di sistema via `postreq`.
* 💡 **Gestione LED Avanzata & Fix Stealth:** Caricamento dinamico del driver kernel `technicolor_led.ko` e gestione affidabile dello spegnimento LED e stealth mode su tutte le generazioni di router.
* ⚙️ **Automazione CI/CD con GitHub Actions:** Pipeline per la compilazione automatica multi-architettura e il rilascio continuo e tracciato dei canali DEV e STABLE.

---

## 📦 Installazione

### 1. Prerequisiti
Il gateway deve avere i permessi di **root (SSH)** abilitati:
* [Guida universale sblocco Technicolor (hack-technicolor.rtfd.io)](https://hack-technicolor.rtfd.io)
* [Forum IlPuntoTecnico](https://www.ilpuntotecnico.com/forum/)

---

### 2. Installazione Rapida Online (via SSH)
Connettiti via SSH come utente `root` ed esegui:

```sh
curl -kfL https://github.com/ZioCook/tch-nginx-gui/releases/latest/download/GUI.tar.bz2 --output /tmp/GUI.tar.bz2
bzcat /tmp/GUI.tar.bz2 | tar -C / -xvf -
/etc/init.d/rootdevice force
```

> [!TIP]
> **Installazione Offline:** Se il gateway non ha accesso a Internet, scarica il file `GUI.tar.bz2` dalla sezione [Releases](https://github.com/ZioCook/tch-nginx-gui/releases), caricalo in `/tmp/` tramite SCP/WinSCP ed esegui i comandi `bzcat` e `rootdevice`.

---

## 🛡️ Guida Rapida allo Spegnimento Sicuro

Per evitare corruzioni alla memoria flash NAND/eMMC, il sistema può essere parcheggiato in sicurezza prima di spegnere l'alimentazione:

| Modalità | Procedura | Indicatore di Completamento |
| :--- | :--- | :--- |
| **Web GUI** | Card *Gateway* ➔ Sezione riavvio ➔ Clicca **"Arresto di sicurezza" (Spegni)** | Il LED Power lampeggia **lentamente di colore rosso** (1s acceso / 1s spento). Il router è parcheggiato ed è pronto per essere spento dall'interruttore. |
| **Tasto WPS (Hardware)** | Tieni premuto il tasto **WPS per 15 secondi**.<br>*(A 10s il LED Power inizia a lampeggiare velocemente come countdown; rilasciando prima dei 15s l'operazione si annulla)* | Il LED Power passa al lampeggio **lento rosso**. L'alimentazione può essere interrotta in sicurezza. |

---

## 📸 Schermate

<div align="center">
  <img src="https://i.ibb.co/XjhF629/modemstats.jpg" alt="Statistiche Modem" width="85%">
  <br><br>
  <img src="https://i.ibb.co/5BDrRnx/odemcards.jpg" alt="Schede Modem" width="85%">
</div>

---

## 💖 Ringraziamenti & Riconoscimenti

* Un doveroso ringraziamento ad **Ansuel**, ideatore e creatore originario della GUI modificata per i gateway Technicolor:
  <div align="center">

  [![Donazione ad Ansuel](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif)](https://www.paypal.me/AnsuelS)

  </div>

* Ringraziamenti alla community di **[IlPuntoTecnico](https://www.ilpuntotecnico.com/forum/)** e a tutti i contributori del progetto OpenWrt.
