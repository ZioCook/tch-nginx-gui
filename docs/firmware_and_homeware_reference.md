# Riferimento Firmware, Homeware & Specifiche Gateway Technicolor/Vantiva

Questo documento raccoglie la conoscenza architetturale, le versioni firmware, i moduli kernel, le configurazioni di sistema e le differenze hardware dei router Technicolor/Vantiva supportati dalla GUI Custom (**`tch-nginx-gui`**).

Le informazioni sono verificate direttamente tramite **interrogazione SSH live sui dispositivi di test reali**, integrate con i **Vantiva Regulatory Open Source Reports** e il repository **hack-technicolor**.

---

## 1. Quadro Comparativo Hardware dei Dispositivi di Test (Dati Reali Live)

| Parametro | DGA4331 (TIM HUB+) | DGA4132 (TIM HUB) | TG789vac v2 (MST Generic) |
| :--- | :--- | :--- | :--- |
| **IP Locale di Test** | `192.168.178.6` | `192.168.178.3` | `192.168.178.7` |
| **Hardware Version / Board** | `VCNT-3` (BCM963138) | `VBNT-S` (BCM963138) | `VANT-6` (BMIPS4350) |
| **Architettura CPU** | ARMv7l (Cortex-A9 Dual Core) | ARMv7l (Cortex-A9 Dual Core) | MIPS (BMIPS4350 Dual Core, Big-Endian) |
| **BogoMIPS** | ~1980 / 1990 | ~1980 / 1990 | ~397 / 403 |
| **Kernel Linux** | `4.1.52` (SMP PREEMPT) | `4.1.52` (SMP PREEMPT) | `3.4.11-rt19` (SMP PREEMPT) |
| **Distribuzione OpenWrt** | OpenWrt SNAPSHOT `r14144` (glibc) | OpenWrt SNAPSHOT `r14144` (glibc) | OpenWrt Chaos Calmer `15.05.1 r46610` |
| **Target Build** | `brcm6xxx-tch/VCNTD_502L07p1` | `brcm6xxx-tch/VBNTJ_502L07p1` | `brcm63xx-tch/VANTF` |
| **Memoria RAM Totale** | **430 MB** (`430520 kB`) | **484 MB** (`484332 kB`) | **246 MB** (`246924 kB`) |
| **Supporto `MemAvailable`** | Sì (Linux $\ge$ 3.14) | Sì (Linux $\ge$ 3.14) | **No** (richiede fallback `MemFree+Cached+Buffers`) |
| **Flash Overlay Libera** | ~61 MB (su 80MB) | ~52 MB (su 80MB) | ~30 MB (su 31.5MB) |
| **Firmware Attivo (Live)** | `AGTHF_1.3.6` (Homeware 19.4) | `AGTHP_2.4.4` (Homeware 19.4) | `17.2.0278` (Netlynk MST Homeware 17.2) |
| **Boot Bank Attiva** | `bank_2` (passiva: `bank_1`) | `bank_2` (passiva: `bank_1`) | `bank_2` (passiva: `bank_1`) |
| **Versione Nginx** | `nginx/1.16.1` | `nginx/1.16.1` | `nginx/1.10.1` |
| **Versione Dropbear** | `Dropbear v2019.78` | `Dropbear v2019.78` | `Dropbear v2016.74` *(richiede KEX SHA1)* |

---

## 2. Dettaglio Dispositivi & Comportamento di Sistema

### 🔹 1. DGA4331 (TIM HUB+) — `VCNT-3`
* **SoC & Wi-Fi**: Broadcom BCM963138 con radio Wi-Fi 6 (BCM43684 4x4 5GHz + 4x4 2.4GHz).
* **Firmware Stock**: Serie `AGTHF` (da `1.0.0` fino all'ultima `1.3.6`), tutte basate su **Homeware 19.4** (`19.4.1051`).
* **Dual-Bank & OBP**: Sistema OBP (*One Boot Planning*) attivo su MTD con controllo integrità CRC/checksum nello script `rootdevice`.
* **Note GUI**: Piattaforma principale ad alte prestazioni, ottima disponibilità di RAM libera (> 160MB).

### 🔹 2. DGA4132 (TIM HUB) — `VBNT-S`
* **SoC & Interfacce**: Broadcom BCM63138, Wi-Fi 5 AC Wave 2, gabbia ottica SFP GPON (moduli Sercomm/Technicolor `AFM0002TIM` / `AFM0003TIM`).
* **Firmware Stock**: Serie `AGTHP` (da `1.0.1` alle recenti release `2.4.0` $\rightarrow$ `2.4.5`). Le serie 2.4.x sono state ricompilate sulla base kernel **Homeware 19.4.1051** (`4.1.52`).
* **Note GUI**: Piattaforma di riferimento matura, RAM abbondante (~250MB disponibili), mapping transformer completi per GPON/SFP.

### 🔹 3. DGA4130 (Smart Modem Plus / "Scolapasta Nero") — `VBNT-K`
* **SoC & Interfacce**: Broadcom BCM63138, profilo EVDSL 35b (200 Mbps).
* **Firmware Stock**: Serie `AGTOT` / `AGTEF` (aggiornato fino a 2.3.x/2.4.x su base Homeware 19.4).
* **Note GUI**: Condivide la stessa architettura ARMv7 Cortex-A9 del DGA4132, senza la porta SFP.

### 🔹 4. TG789vac v2 (Smart Modem con Firmware MST) — `VANT-6`
* **SoC & Architettura**: Broadcom **BMIPS4350** (Dual Core MIPS a 400 MHz, Big Endian).
* **Ambiente Firmware**: Esegue firmware generico **Netlynk MST** versione **`17.2.0278`** (base **Homeware 17.2** su OpenWrt Chaos Calmer 15.05.1), molto più leggero e aperto rispetto al firmware stock TIM `AGTEF`.
* **Particolarità e Criticità Tecniche**:
  1. **Architettura MIPS**: Qualsiasi binario C precompilato per ARM (`armv7l`) **non** può essere eseguito qui; i tool devono essere script POSIX `ash`, Lua 5.1 puro o binari MIPS dedicati.
  2. **Niente `MemAvailable`**: Il kernel Linux `3.4.11` non calcola `MemAvailable` in `/proc/meminfo`. L'installer deve sommare `MemFree + Cached + Buffers`.
  3. **No `/proc/device-tree/model`**: L'installer protegge la lettura del device tree con reindirizzamento `2>/dev/null` per non sporcare l'output.
  4. **Dropbear v2016.74**: Non supporta i moderni algoritmi KEX basati su elliptic-curves (Curve25519/ECDH); richiede client SSH con `KexAlgorithms +diffie-hellman-group14-sha1`.
  5. **Nginx 1.10.1**: Versione più leggera che beneficia al massimo della pre-compressione `gzip_static`.

---

## 3. Manifest Ufficiale Pacchetti Homeware 19.4 & 17.x (Vantiva OSS)

Dati estratti direttamente dai manifest ufficiali di conformità **Vantiva Homeware Regulatory**:

### 🛠️ Moduli Kernel Chiave (`kmod-*`)
* **`kmod-bcm6xxx-tch-runner-br`** (`4.1-`, GPL-v2): Driver di accelerazione hardware Broadcom Runner per il packet forwarding LAN $\leftrightarrow$ WAN $\leftrightarrow$ Wi-Fi.
* **`kmod-bankmgr`** (`4.1+1.0-`, GPL-v2): Modulo Technicolor di gestione delle partizioni dual-bank (`bootbank` / `altbank`).
* **`kmod-nf-flow`**, **`kmod-ipt-filter`**, **`kmod-ebtables`**: Moduli di accelerazione e filtraggio netfilter.
* **`kmod-l2tp`**, **`kmod-gre`**, **`kmod-pppoe`**: Stack di tunneling e connettività WAN.

### 🧩 Componenti Spazio Utente & Transformer
* **`lsqlite3`** (`0.9.5-1`, MIT): Driver SQLite per Lua, essenziale per transformer e per i database di monitoraggio traffico.
* **`libcares`** (`1.15.0-4`, MIT): Risolutore DNS asincrono usato da demoni di sistema e transformer.
* **`libipset`** (`7.3-1`, GPL-v2): Gestione delle tabelle IPset del firewall.
* **`odhcp6c`** / **`odhcpd`**: Stack client/server IPv6 e DHCPv6 Prefix Delegation.
* **`mwan`** (`4.1`, GPL-v2): Gestione multi-WAN e failover su connessioni mobili/LTE.

---

## 4. Regole di Ottimizzazione GUI (`tch-nginx-gui`)

1. **Gestione Versioni**:
   * Release **STABILE**: stringa versione pulita (es. `9.11.0`, senza hash commit).
   * Canale **DEV**: stringa con commit hash (es. `9.11.1-4632e31`).

2. **Compatibilità Shell (BusyBox `ash`)**:
   * Usare solo costrutti POSIX standard compatibili sia con BusyBox 1.23 (Chaos Calmer) sia con BusyBox 1.33+ (Snapshot).

3. **Performance CPU & Memory Footprint**:
   * Evitare chiamate `io.popen` ripetute nei file Lua; usare le API native `uci` e `ubus`.
   * Servire gli asset statici con estensione `.gz` pre-compressa per azzerare il carico CPU del webserver sui chip MIPS a 400 MHz.
   * Disabilitare i polling JavaScript ad alta frequenza quando la scheda o il modale non sono visibili a schermo.
