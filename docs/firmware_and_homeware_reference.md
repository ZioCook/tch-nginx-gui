# Specifiche Tecniche Hardware, Firmware & Architettura Kernel Technicolor/Vantiva

Documento tecnico di riferimento per le piattaforme gateway basate su SoC Broadcom (ARMv7 e BMIPS) con stack software Homeware (OpenWrt base).

---

## 1. Tabella Comparativa Architetture Hardware

| Parametro Tecnico | DGA4331 | DGA4132 | TG789vac v2 (MST) |
| :--- | :--- | :--- | :--- |
| **Codename Scheda** | `VCNT-3` | `VBNT-S` | `VANT-6` |
| **SoC** | Broadcom BCM963138 | Broadcom BCM63138 | Broadcom BMIPS4350 V8.0 |
| **Architettura CPU** | ARMv7-A (Cortex-A9 Dual-Core @ 1.0 GHz) | ARMv7-A (Cortex-A9 Dual-Core @ 1.0 GHz) | MIPS32r2 (Dual-Core @ 400 MHz) |
| **Endianness** | Little-Endian (`armv7l` / `arm_cortex-a9`) | Little-Endian (`armv7l` / `arm_cortex-a9`) | Big-Endian (`mips`) |
| **BogoMIPS** | 1980.41 / 1990.65 | 1980.41 / 1990.65 | 397.31 / 403.45 |
| **Memoria RAM Totale** | 430.5 MB (`430520 kB`) | 484.3 MB (`484332 kB`) | 246.9 MB (`246924 kB`) |
| **Memoria Flash NAND** | 256 MB (NAND Flash `0x10000000`) | 256 MB (NAND Flash `0x10000000`) | 128 MB (NAND Flash `0x08000000`) |
| **EraseBlock Size** | 128 KB (`0x20000`) | 128 KB (`0x20000`) | 128 KB (`0x20000`) |
| **Kernel Linux** | `4.1.52` (SMP PREEMPT) | `4.1.52` (SMP PREEMPT) | `3.4.11-rt19` (SMP PREEMPT) |
| **Distribuzione Base** | OpenWrt SNAPSHOT `r14144` (glibc) | OpenWrt SNAPSHOT `r14144` (glibc) | OpenWrt Chaos Calmer `15.05.1` (r46610) |
| **Build Target** | `brcm6xxx-tch/VCNTD_502L07p1` | `brcm6xxx-tch/VBNTJ_502L07p1` | `brcm63xx-tch/VANTF` |
| **Homeware Release** | Homeware 19.4 (`19.4.1051`) | Homeware 19.4 (`19.4.1051`) | Homeware 17.2 (`17.2.0278`) |
| **Engine Accelerazione HW** | Broadcom Runner (`RDPA` + `BDMF`) | Broadcom Runner (`RDPA` + `BDMF`) | Broadcom FAP (`bcmfap` + `bcmarl`) |
| **Subsystem Wi-Fi** | BCM43684 (Wi-Fi 6 802.11ax 4x4) | BCM43602 + Quantenna QSR1000 (AC Wave 2) | BCM4360 + BCM43217 (Wi-Fi 5 AC1600) |
| **Driver Wi-Fi Principale** | Broadcom BCA `17.10 RC121.39` | Broadcom BCA `17.10 RC121.39` | Broadcom BCA `7.14 RC89.14` |
| **Interfacce WAN Fisiche** | DSL (VDSL2 35b), GbE WAN (`eth4`), GPON | DSL (VDSL2 35b), GbE WAN (`eth4`), SFP (`eth5`) | DSL (VDSL2 17a), GbE WAN (`eth4`) |
| **Web Server Daemon** | `nginx/1.16.1` | `nginx/1.16.1` | `nginx/1.10.1` |
| **SSH Daemon** | `Dropbear v2019.78` | `Dropbear v2019.78` | `Dropbear v2016.74` |

---

## 2. Struttura Partizioni Flash (MTD Layout)

### DGA4331 (`VCNT-3`) & DGA4132 (`VBNT-S`) — 256 MB NAND
```text
mtd0: 10000000 00020000 "brcmnand.0"   (256 MB - Intera NAND fisica)
mtd1: 04da0000 00020000 "rootfs"        (SquashFS rootfs compressa di sistema)
mtd2: 05a20000 00020000 "rootfs_data"   (UBI volume montato in /overlay R/W)
mtd3: 04fc0000 00020000 "bank_1"        (Immagine completa Bank 1: kernel + rootfs)
mtd4: 04fc0000 00020000 "bank_2"        (Immagine completa Bank 2: kernel + rootfs)
mtd5: 00020000 00020000 "eripv2"        (128 KB - Certificati, calibrazioni, chiavi hardware)
mtd6: 00040000 00020000 "rawstorage"    (256 KB - Boot parameters, RIP, OBP flags)
```

### TG789vac v2 (`VANT-6`) — 128 MB NAND
```text
mtd0: 08000000 00020000 "brcmnand.0"   (128 MB - Intera NAND fisica)
mtd1: 02c40000 00020000 "rootfs"        (SquashFS rootfs compressa di sistema)
mtd2: 01f80000 00020000 "userfs"        (Partizione JFFS2 / UBIFS montata in /overlay R/W)
mtd3: 02e60000 00020000 "bank_1"        (Immagine completa Bank 1)
mtd4: 02e60000 00020000 "bank_2"        (Immagine completa Bank 2)
mtd5: 00020000 00020000 "eripv2"        (128 KB - Dati crittografici/RIP)
mtd6: 00040000 00020000 "rawstorage"    (256 KB - Parametri di avvio CFE)
mtd7: 00000003 00020000 "blversion"     (Versione bootloader)
```

---

## 3. Sottosistemi Kernel & Moduli Driver (`lsmod`)

### 3.1 Piattaforma ARMv7 BCM63138 (DGA4331 / DGA4132 / DGA4130)
* **Accelerazione Pacchetti (Broadcom Runner / RDPA)**:
  - `bdmf.ko` (~1.22 MB): *Broadcom Data Management Framework* (astrazione hardware di basso livello).
  - `rdpa.ko` (~1.30 MB): *Runner Data Path Architecture* (engine di packet processing su microcodice Runner).
  - `rdpa_cmd.ko`, `rdpa_gpl.ko`, `rdpa_mw.ko`, `rdpa_usr.ko`: Moduli di controllo e gestione filtri RDPA.
  - `pktrunner.ko` (40 KB) & `pktflow.ko` (230 KB): Gestione flusso e connessioni offloadate a livello hardware.
  - `bcm_ingqos.ko` (213 KB): Gestione Ingress QoS accelerata via RDPA.
* **Driver DSL / XTM / Ethernet**:
  - `adsldd.ko` (549 KB): Driver firmware modem xDSL (PHY DSP controller per ADSL2+, VDSL2 17a, 35b).
  - `bcmxtmcfg.ko` & `bcmxtmrtdrv.ko`: Driver di instradamento per ATM/PTM layers.
  - `bcm_enet.ko` (160 KB) & `bcmvlan.ko` (84 KB): Driver switch gigabit integrato e gestione trunking 802.1Q.
* **Stack Wi-Fi Broadcom**:
  - `wl.ko` (~6.04 MB): Driver monolitico Broadcom Wireless Architecture (BCA).
  - `wfd.ko` (27 KB): *Wireless Forwarding Driver* (inoltro diretto pacchetti Wi-Fi $\leftrightarrow$ Runner senza passare per la CPU host).
  - `emf.ko` (17 KB) & `igs.ko` (13 KB): *Efficient Multicast Forwarding* & *IGMP Snooping*.
  - `hnd.ko` (272 KB) & `bcmlibs.ko` (16 KB): Librerie hardware di supporto.
* **Gestione Dual-Bank & Sistema**:
  - `bankmgr.ko` (15.4 KB): Driver Technicolor per la lettura/scrittura atomica delle bank di boot (`/proc/banktable/booted`, `/proc/banktable/active`).

### 3.2 Piattaforma MIPS BMIPS4350 (TG789vac v2)
* **Accelerazione Pacchetti (Broadcom FAP)**:
  - `bcmfap.ko` (205 KB): *Fast Access Packet* (coprocessore MIPS integrato per packet acceleration).
  - `bcmarl.ko` (6 KB) & `bcm_bpm.ko` (9.8 KB): *Address Resolution Logic* e *Buffer Pool Manager*.
  - `bcm_ingqos.ko` (9.2 KB): Ingress QoS per architettura FAP.
* **Driver DSL / Ethernet / Wi-Fi**:
  - `adsldd.ko` (362 KB): Driver modem xDSL legacy per kernel 3.4.
  - `bcm_enet.ko` (245 KB): Driver Ethernet switch BMIPS.
  - `wl.ko`: Driver Broadcom Wi-Fi legacy (BCA `7.14.89.14`).

---

## 4. Specifiche Network Stack & Interfacce

### Mappatura Dispositivi di Rete Kernel (`ip link`)

#### DGA4132 / DGA4331 (Broadcom BCM63138)
* `eth0`, `eth1`, `eth2`, `eth3`: Porte LAN 1-4 dello switch integrato (Gigabit Ethernet 10/100/1000).
* `eth4`: Porta WAN Ethernet dedicata (Gigabit Ethernet RJ-45).
* `eth5` *(solo DGA4132)*: Interfaccia fisica per modulo transceiver SFP (`/dev/i2c-0`).
* `wl0`: Radio Wi-Fi 2.4 GHz (Broadcom b/g/n/ax).
* `wl1` / `qtn`: Radio Wi-Fi 5 GHz (Broadcom BCM43684 o Quantenna AC).
* `dsl0`: Interfaccia PTM/ATM di livello 2 legata al modem DSL interno.
* `bcmsw`: Switch di management interno Broadcom.
* `br-lan`: Bridge software principale contenente `eth0-3`, `wl0`, `wl1`.

#### TG789vac v2 (Broadcom BMIPS4350)
* `eth0`, `eth1`, `eth2`, `eth3`: Porte LAN switch Fast/Gigabit.
* `eth4`: Porta WAN Ethernet.
* `vlan_eth0`..`vlan_eth3`: Interfacce VLAN 802.1Q agganciate allo switch hardware.
* `wl0`: Radio Wi-Fi 2.4 GHz.
* `wl1`: Radio Wi-Fi 5 GHz (BCM4360).
* `br-lan` & `br-guest`: Bridge di isolamento rete principale e rete ospiti.

---

## 5. Dettagli Runtime & Differenze Interpreti/Demoni

| Sottosistema | Piattaforme Homeware 19.4 (DGA4331, DGA4132, DGA4130) | Piattaforma Homeware 17.2 / MST (TG789vac v2) |
| :--- | :--- | :--- |
| **C Library** | `glibc` | `musl` / `uClibc` |
| **Shell di Sistema** | BusyBox `ash` (v1.33+) | BusyBox `ash` (v1.23) |
| **Interprete Lua** | Lua 5.1 con moduli `lsqlite3`, `luci`, `cjson`, `ubus` | Lua 5.1 con moduli `lsqlite3`, `ubus` |
| **IPC & Data Model** | `transformer` demone + `ubus` broker IPC | `transformer` demone + `ubus` broker IPC |
| **Configurazione Persistente** | UCI (`/etc/config/*`) | UCI (`/etc/config/*`) |
| **Metodo Controllo Memoria** | `/proc/meminfo` campo `MemAvailable` | `/proc/meminfo` fallback `MemFree + Cached + Buffers` |
| **Device Model Path** | `/proc/device-tree/model` presente | `/proc/device-tree/model` assente (usare `/proc/cpuinfo`) |
| **KEX SSH Supportati** | `curve25519-sha256`, `ecdh-sha2-*`, `rsa-sha2-*` | `diffie-hellman-group14-sha1`, `diffie-hellman-group1-sha1` |
