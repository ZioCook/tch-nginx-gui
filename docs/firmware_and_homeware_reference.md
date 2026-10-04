# Specifiche Tecniche Hardware & Gateway Technicolor/Vantiva

Schede tecniche dei gateway supportati basati su SoC Broadcom e stack Homeware.

---

## DGA4331 (`VCNT-3`)

```yaml
Hardware:
  Board ID: VCNT-3
  SoC: Broadcom BCM963138
  CPU: ARMv7-A Cortex-A9 Dual-Core @ 1.0 GHz (Little-Endian, armv7l)
  BogoMIPS: ~1990
  RAM: 430 MB (430520 kB)
  Flash: 256 MB NAND (EraseBlock: 128 KB)

Software & Kernel:
  Kernel: Linux 4.1.52 (SMP PREEMPT)
  Base OS: OpenWrt SNAPSHOT r14144 (glibc)
  Target: brcm6xxx-tch/VCNTD_502L07p1
  Homeware: 19.4 (build 19.4.1051)
  Daemons: Nginx 1.16.1, Dropbear v2019.78

MTD Layout (256 MB):
  mtd0: 10000000 (256 MB) "brcmnand.0"
  mtd1: 04da0000 (77.6 MB) "rootfs" (SquashFS)
  mtd2: 05a20000 (90.1 MB) "rootfs_data" (UBI overlay /)
  mtd3: 04fc0000 (79.7 MB) "bank_1"
  mtd4: 04fc0000 (79.7 MB) "bank_2"
  mtd5: 00020000 (128 KB)  "eripv2"
  mtd6: 00040000 (256 KB)  "rawstorage"

Sottosistemi Kernel:
  Packet Acceleration: Broadcom Runner (rdpa.ko, bdmf.ko, pktflow.ko, pktrunner.ko, wfd.ko, bcm_ingqos.ko)
  DSL Driver: adsldd.ko (VDSL2 Profile 35b)
  Dual-Bank: bankmgr.ko (gestione /proc/banktable/)
  Wireless: Broadcom BCM43684 (802.11ax Wi-Fi 6 4x4), driver BCA 17.10 RC121.39 (wl.ko)

Interfacce di Rete:
  eth0 - eth3 : Switch LAN Gigabit (10/100/1000 Mbps)
  eth4        : WAN Gigabit Ethernet dedicata
  wl0         : Radio Wi-Fi 2.4/5 GHz 802.11ax
  dsl0        : Interfaccia PTM/ATM modem DSL
  br-lan      : Bridge principale di rete locale
```

---

## DGA4132 (`VBNT-S`)

```yaml
Hardware:
  Board ID: VBNT-S
  SoC: Broadcom BCM63138
  CPU: ARMv7-A Cortex-A9 Dual-Core @ 1.0 GHz (Little-Endian, armv7l)
  BogoMIPS: ~1990
  RAM: 484 MB (484332 kB)
  Flash: 256 MB NAND (EraseBlock: 128 KB)

Software & Kernel:
  Kernel: Linux 4.1.52 (SMP PREEMPT)
  Base OS: OpenWrt SNAPSHOT r14144 (glibc)
  Target: brcm6xxx-tch/VBNTJ_502L07p1
  Homeware: 19.4 (build 19.4.1051, allineamento 2.4.x)
  Daemons: Nginx 1.16.1, Dropbear v2019.78

MTD Layout (256 MB):
  mtd0: 10000000 (256 MB) "brcmnand.0"
  mtd1: 04a00000 (74.0 MB) "rootfs" (SquashFS)
  mtd2: 05920000 (89.1 MB) "rootfs_data" (UBI overlay /)
  mtd3: 05000000 (80.0 MB) "bank_1"
  mtd4: 05000000 (80.0 MB) "bank_2"
  mtd5: 00020000 (128 KB)  "eripv2"
  mtd6: 00040000 (256 KB)  "rawstorage"

Sottosistemi Kernel:
  Packet Acceleration: Broadcom Runner (rdpa.ko, bdmf.ko, pktflow.ko, pktrunner.ko)
  SFP Subsystem: Gabbia ottica SFP GPON/1G su bus I2C (/dev/i2c-0)
  DSL Driver: adsldd.ko (VDSL2 Profile 35b)
  Dual-Bank: bankmgr.ko
  Wireless: BCM43602 (2.4 GHz) + Quantenna QSR1000 (5 GHz AC Wave 2), driver BCA 17.10 RC121.39

Interfacce di Rete:
  eth0 - eth3 : Switch LAN Gigabit
  eth4        : WAN Gigabit Ethernet dedicata
  eth5        : Interfaccia fisica SFP Cage
  wl0         : Radio Wi-Fi 2.4 GHz
  dsl0        : Interfaccia PTM/ATM modem DSL
  br-lan      : Bridge principale di rete locale
```

---

## DGA4130 (`VBNT-K`)

```yaml
Hardware:
  Board ID: VBNT-K
  SoC: Broadcom BCM63138
  CPU: ARMv7-A Cortex-A9 Dual-Core @ 1.0 GHz (Little-Endian, armv7l)
  BogoMIPS: ~1990
  RAM: 256 MB
  Flash: 128 / 256 MB NAND (EraseBlock: 128 KB)

Software & Kernel:
  Kernel: Linux 4.1.52 / 4.1.38 (SMP PREEMPT)
  Base OS: OpenWrt SNAPSHOT (glibc)
  Homeware: 19.4 / 18.x
  Daemons: Nginx 1.16.1, Dropbear v2019.78

Sottosistemi Kernel:
  Packet Acceleration: Broadcom Runner (rdpa.ko, bdmf.ko, pktflow.ko, pktrunner.ko)
  DSL Driver: adsldd.ko (VDSL2 Profile 35b)
  Dual-Bank: bankmgr.ko
  Wireless: Broadcom Wi-Fi 5 Dual-Band (BCM4360 5GHz + BCM43217 2.4GHz)

Interfacce di Rete:
  eth0 - eth3 : Switch LAN Gigabit
  eth4        : WAN Gigabit Ethernet
  wl0, wl1    : Radio Wi-Fi 2.4 / 5 GHz
  dsl0        : Interfaccia PTM/ATM modem DSL
  br-lan      : Bridge principale di rete locale
```

---

## TG789vac v2 (`VANT-6` - MST)

```yaml
Hardware:
  Board ID: VANT-6
  SoC: Broadcom BMIPS4350 V8.0
  CPU: MIPS32r2 Dual-Core @ 400 MHz (Big-Endian, mips)
  BogoMIPS: ~400
  RAM: 246 MB (246924 kB)
  Flash: 128 MB NAND (EraseBlock: 128 KB)

Software & Kernel:
  Kernel: Linux 3.4.11-rt19 (SMP PREEMPT)
  Base OS: OpenWrt Chaos Calmer 15.05.1 r46610 (musl/uClibc)
  Target: brcm63xx-tch/VANTF
  Homeware: 17.2 (Netlynk MST 17.2.0278)
  Daemons: Nginx 1.10.1, Dropbear v2016.74 (KEX: diffie-hellman-group14-sha1)

MTD Layout (128 MB):
  mtd0: 08000000 (128 MB)  "brcmnand.0"
  mtd1: 02c40000 (44.2 MB) "rootfs" (SquashFS)
  mtd2: 01f80000 (31.5 MB) "userfs" (UBIFS overlay /)
  mtd3: 02e60000 (46.4 MB) "bank_1"
  mtd4: 02e60000 (46.4 MB) "bank_2"
  mtd5: 00020000 (128 KB)  "eripv2"
  mtd6: 00040000 (256 KB)  "rawstorage"
  mtd7: 00000003 (3 Bytes) "blversion"

Sottosistemi Kernel:
  Packet Acceleration: Broadcom FAP (bcmfap.ko, bcmarl.ko, bcm_bpm.ko, bcm_ingqos.ko)
  DSL Driver: adsldd.ko (VDSL2 Profile 17a)
  Dual-Bank: bankmgr.ko
  Wireless: BCM4360 + BCM43217 (Wi-Fi 5 AC1600), driver BCA 7.14 RC89.14 (wl.ko)

Interfacce di Rete:
  eth0 - eth3 : Switch LAN (con mapping vlan_eth0 - vlan_eth3)
  eth4        : WAN Ethernet
  wl0, wl1    : Radio Wi-Fi 2.4 GHz / 5 GHz
  br-lan      : Bridge LAN principale
  br-guest    : Bridge isolato rete ospiti

Caratteristiche Kernel 3.4:
  Memoria: MemAvailable non supportato in /proc/meminfo (calcolo: MemFree + Cached + Buffers)
  Device Tree: /proc/device-tree/model non presente (identificazione tramite /proc/cpuinfo)
```
