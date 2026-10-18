# Technicolor / Vantiva Gateways Hardware & Kernel Technical Specifications

[Versione in italiano](firmware_and_homeware_reference.md)

Technical reference specification sheets for Broadcom SoC-based gateways running the Homeware software stack (OpenWrt base).

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

Kernel Subsystems:
  Packet Acceleration: Broadcom Runner (rdpa.ko, bdmf.ko, pktflow.ko, pktrunner.ko, wfd.ko, bcm_ingqos.ko)
  DSL Driver: adsldd.ko (VDSL2 Profile 35b)
  Dual-Bank: bankmgr.ko (controls /proc/banktable/)
  Wireless: Broadcom BCM43684 (802.11ax Wi-Fi 6 4x4), BCA driver 17.10 RC121.39 (wl.ko)

Network Interfaces:
  eth0 - eth3 : Switch LAN Gigabit (10/100/1000 Mbps)
  eth4        : Dedicated Gigabit Ethernet WAN
  wl0         : Wi-Fi Radio 2.4/5 GHz 802.11ax
  dsl0        : PTM/ATM DSL Modem Interface
  br-lan      : Primary LAN bridge
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
  Homeware: 19.4 (build 19.4.1051, 2.4.x alignment)
  Daemons: Nginx 1.16.1, Dropbear v2019.78

MTD Layout (256 MB):
  mtd0: 10000000 (256 MB) "brcmnand.0"
  mtd1: 04a00000 (74.0 MB) "rootfs" (SquashFS)
  mtd2: 05920000 (89.1 MB) "rootfs_data" (UBI overlay /)
  mtd3: 05000000 (80.0 MB) "bank_1"
  mtd4: 05000000 (80.0 MB) "bank_2"
  mtd5: 00020000 (128 KB)  "eripv2"
  mtd6: 00040000 (256 KB)  "rawstorage"

Kernel Subsystems:
  Packet Acceleration: Broadcom Runner (rdpa.ko, bdmf.ko, pktflow.ko, pktrunner.ko)
  SFP Subsystem: SFP Cage GPON/1G optical transceiver over I2C bus (/dev/i2c-0)
  DSL Driver: adsldd.ko (VDSL2 Profile 35b)
  Dual-Bank: bankmgr.ko
  Wireless: BCM43602 (2.4 GHz) + Quantenna QSR1000 (5 GHz AC Wave 2), BCA driver 17.10 RC121.39

Network Interfaces:
  eth0 - eth3 : Switch LAN Gigabit
  eth4        : Dedicated Gigabit Ethernet WAN
  eth5        : SFP Cage physical interface
  wl0         : Wi-Fi Radio 2.4 GHz
  dsl0        : PTM/ATM DSL Modem Interface
  br-lan      : Primary LAN bridge
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

Kernel Subsystems:
  Packet Acceleration: Broadcom Runner (rdpa.ko, bdmf.ko, pktflow.ko, pktrunner.ko)
  DSL Driver: adsldd.ko (VDSL2 Profile 35b)
  Dual-Bank: bankmgr.ko
  Wireless: Broadcom Wi-Fi 5 Dual-Band (BCM4360 5GHz + BCM43217 2.4GHz)

Network Interfaces:
  eth0 - eth3 : Switch LAN Gigabit
  eth4        : Gigabit Ethernet WAN
  wl0, wl1    : Wi-Fi Radio 2.4 / 5 GHz
  dsl0        : PTM/ATM DSL Modem Interface
  br-lan      : Primary LAN bridge
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

Kernel Subsystems:
  Packet Acceleration: Broadcom FAP (bcmfap.ko, bcmarl.ko, bcm_bpm.ko, bcm_ingqos.ko)
  DSL Driver: adsldd.ko (VDSL2 Profile 17a)
  Dual-Bank: bankmgr.ko
  Wireless: BCM4360 + BCM43217 (Wi-Fi 5 AC1600), BCA driver 7.14 RC89.14 (wl.ko)

Network Interfaces:
  eth0 - eth3 : Switch LAN (mapped via vlan_eth0 - vlan_eth3)
  eth4        : Ethernet WAN
  wl0, wl1    : Wi-Fi Radio 2.4 GHz / 5 GHz
  br-lan      : Primary LAN bridge
  br-guest    : Isolated Guest bridge

Kernel 3.4 Specifics:
  Memory: MemAvailable is not supported in /proc/meminfo (computed as: MemFree + Cached + Buffers)
  Device Tree: /proc/device-tree/model is not present (identified via /proc/cpuinfo)
```
