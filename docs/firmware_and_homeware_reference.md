# Riferimento Firmware, Homeware & Specifiche Gateway Technicolor/Vantiva

Questo documento raccoglie la conoscenza architetturale, le versioni firmware, i moduli kernel e le differenze hardware dei router Technicolor/Vantiva supportati dalla GUI Custom (**`tch-nginx-gui`**), basata sui dati ufficiali **Vantiva Homeware Regulatory OSS Reports** e sul repository **hack-technicolor**.

---

## 1. Mappatura Dispositivi & Generazioni Homeware

| Modello Commerciale | Nome Scheda / Board ID | CPU / Architettura | Kernel Linux | Versione Base Homeware | Note Firmware & Particolarità |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **DGA4331** *(TIM HUB+)* | `VCNT-3` (Broadcom BCM963138) | ARMv7l (Dual Core) | `4.1.38-rt19` | **Homeware 19.4** (`19.4.1051`) | Wi-Fi 6 (ax), Flash 256MB NAND, RAM 512MB, Dual-Bank OBP. Firmware stock TIM: serie `AGTHF` (da 1.0.0 a 1.3.6 finale). |
| **DGA4132** *(TIM HUB)* | `VBNT-S` (Broadcom BCM63138) | ARMv7l (Dual Core) | `4.1.52` / `4.1.38` | **Homeware 19.4** (da 2.4.x) / **17.2** | Gabbia SFP GPON/1G, Wi-Fi 5 (ac), Flash 128MB NAND, RAM 256MB. Firmware TIM: serie `AGTHP` (da 1.0.1 a 2.4.5 finale con base 19.4). |
| **DGA4130** *(Smart Modem Plus / Scolapasta Nero)* | `VBNT-K` (Broadcom BCM63138) | ARMv7l (Dual Core) | `4.1.52` / `4.1.38` | **Homeware 19.4** / **18.x** | Profilo EVDSL 35b (200M), VBNT-K. Firmware TIM: serie `AGTEF`/`AGTOT` (fino a 2.3.x/2.4.x). |
| **TG789vac v2** *(TIM Smart Modem / Scolapasta Bianco)* | `VANT-6` (BMIPS4350) | MIPS (Big Endian) | `3.4.11-rt19` | **Homeware 15.x / 16.x / 17.x** / **MST** | Flash 128MB NAND, RAM 128MB, OpenWrt 15.05.1. Spesso usato con **firmware generico MST** (`MST.TG789vac.v2-17.2.278`, `vant-6_16.3.7636`). |

---

## 2. Dettaglio Dispositivi & Comportamento GUI

### 🔹 DGA4331 (TIM HUB+) — `VCNT-3`
* **Firmware**: `AGTHF_1.0.0` $\rightarrow$ `AGTHF_1.3.6` (tutti su base Homeware 19.4.1051).
* **Dual-Bank & OBP**: Ha il sistema OBP (*One Boot Planning*) attivo su MTD. Lo script `rootdevice` valida il checksum OBP e previene boot-loop tramite contatori protetti.
* **Wi-Fi**: Chipset Broadcom BCM43684 (Wi-Fi 6 4x4 5GHz + 4x4 2.4GHz).
* **Peculiarità GUI**: Dispositivo primario, supporta la GUI ad alte prestazioni, con CPU ARM e memoria abbondante (RAM libera > 130MB).

### 🔹 DGA4132 (TIM HUB) — `VBNT-S`
* **Firmware**: Serie `AGTHP` (1.0.1 $\rightarrow$ 2.3.5 $\rightarrow$ 2.4.0 $\rightarrow$ 2.4.5 finale rilasciato a fine 2026).
* **Evoluzione Kernel**: Le versioni 2.4.x hanno introdotto l'allineamento all'ecosistema 19.4.1051 dopo 3 anni di manutenzione.
* **SFP**: Gestione del mini-ONT SFP (`AFM0002TIM`, `AFM0003TIM`) tramite comandi `sfp_helper` e mapping transformer dedicati.

### 🔹 DGA4130 (Smart Modem Plus) — `VBNT-K`
* **Firmware**: Serie `AGTEF` e `AGTOT`.
* **Architettura**: Molto simile al DGA4132 ma senza porta SFP dedicata e con radio Wi-Fi 5 wave 1. Nelle release finali condivide la base Homeware 19.4.

### 🔹 TG789vac v2 — `VANT-6` (con Firmware MST)
* **Firmware MST**: `MST.TG789vac.v2-17.2.278-0901008.rbi` oppure `vant-6_16.3.7636-2921002`.
* **Peculiarità Hardware**:
  - **Architettura MIPS**: binari e moduli devono essere compilati per target MIPS (non compatibili con i binari ARM dei DGA).
  - **Kernel 3.4.11-rt19**: non dispone di `/proc/device-tree/model` (reindirizzamento protetto nell'installer).
  - **Memoria RAM ridotta (128MB)**: `MemAvailable` non è presente nei kernel 3.4; il calcolo della memoria libera deve usare la formula fallback `MemFree + Cached + Buffers`.
  - **Dropbear Vintage**: accetta solo Key Exchange `diffie-hellman-group14-sha1` (richiede direttiva KEX nei client SSH moderni).

---

## 3. Manifest Pacchetti & Moduli Kernel (Homeware 19.4 vs 17.x)

Dati estratti dai report normativi ufficiali **Vantiva Regulatory OSS**:

### Moduli Kernel Critici (`kmod-*`):
* **`kmod-bcm6xxx-tch-runner-br`** (`4.1-`, GPL-v2): Driver di accelerazione hardware per il packet forwarding tra WAN, LAN e Wi-Fi (Broadcom Runner HW flow offload).
* **`kmod-bankmgr`** (`4.1+1.0-`, GPL-v2): Gestore Technicolor delle partizioni dual-bank (`bootbank`, `altbank`).
* **`kmod-nf-flow`**, **`kmod-ipt-filter`**, **`kmod-ebtables`**: Moduli di filtraggio firewall e offload netfilter.
* **`kmod-l2tp`**, **`kmod-gre`**, **`kmod-pppoe`**: Stack di tunneling e incapsulamento WAN.

### Componenti Spazio Utente & Transformer:
* **`lsqlite3`** (`0.9.5-1`, MIT): Driver SQLite per Lua, utilizzato da transformer e dai database di configurazione (`traffic_mon`, statistiche).
* **`libcares`** (`1.15.0-4`, MIT): Libreria di risoluzione DNS asincrona per transformer e demoni di rete.
* **`libipset`** (`7.3-1`, GPL-v2): Gestione delle tabelle IPset del firewall.
* **`odhcp6c`** / **`odhcpd`**: Demoni per l'assegnazione e il routing IPv6 / DHCPv6 / PD.
* **`mwan`** (`4.1`, GPL-v2): Gestione multi-WAN e failover mobile (chiavette 4G/LTE).

---

## 4. Regole per lo Sviluppo della GUI (`tch-nginx-gui`)

1. **Gestione Versione**:
   - Canale **STABILE**: stringa versione pulita (es. `9.11.0`, senza hash commit).
   - Canale **DEV**: stringa con commit hash (es. `9.11.1-4632e31` o `9.11.1-dev`).

2. **Compatibilità Shell (BusyBox `ash`)**:
   - Non usare bashismi (`[[ ... ]]`, `${var//...}`, `<<<`, array).
   - Usare sempre costrutti POSIX standard (`[ ... ]`, `case`, `read -r`).

3. **Compatibilità Kernel & Memoria**:
   - Leggere la RAM tramite parser di `/proc/meminfo` con fallback per kernel pre-3.14.
   - Non assumere la presenza di `/proc/device-tree/model`; usare sempre il fallback a `/proc/cpuinfo` o `/etc/board.json`.

4. **Web Server & Lua Performance**:
   - Evitare `io.popen` ripetuti nei loop Lua per chiamate shell; preferire `uci`, `ubus` o lettura diretta da `/proc`/`/sys`.
   - Mantenere la pre-compressione gzip degli asset statici (`.gz`) per non sovraccaricare la CPU MIPS del TG789vac v2.
