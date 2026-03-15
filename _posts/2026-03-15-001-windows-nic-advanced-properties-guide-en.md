---
title: "Windows NIC Advanced Properties Guide - Jumbo Frames, RSS, LSO, RSC, Flow Control, EEE, and Wake on LAN"
date: 2026-03-15 10:00
lang: en
translation_key: windows-nic-advanced-properties-guide
permalink: /en/blog/2026/03/15/001-windows-nic-advanced-properties-guide/
tags:
  - Windows
  - Networking
  - NIC
  - Ethernet
  - Performance Tuning
  - Windows Development
author: Go Komura
description: "A practical guide to Windows NIC advanced properties, including Speed & Duplex, jumbo frames, RSS, RSC, LSO, flow control, EEE, and Wake on LAN, with advice on when each setting actually matters."
consultation_services:
  - id: technical-consulting
    reason: "This topic is usually easier to solve when NIC settings are reviewed together with the traffic pattern, network path, power behavior, and long-run operating conditions."
  - id: bug-investigation
    reason: "Link drops, downshifts to 100 Mbps, resume failures, and throughput regressions fit well as bug investigation and root cause analysis work."
---

The **Advanced** tab on a Windows network adapter often looks much more powerful than it really is.  
`Jumbo Packet`, `Large Send Offload`, `Interrupt Moderation`, `Receive Side Scaling`, `Flow Control`, `Energy Efficient Ethernet`. The names all sound like they should make things faster, but in practice the right answer depends on what you are trying to improve.

- Do you want better throughput for large transfers?
- Lower latency for small request/response traffic?
- Lower CPU usage?
- Better sleep/resume behavior or reliable Wake on LAN?
- A cleaner way to isolate a driver or switch compatibility problem?

If that goal is vague, "turn everything on" is a very ordinary way to make things worse.

This article focuses on **wired Ethernet adapters on Windows 10, Windows 11, and Windows Server**.  
The aim is not to list every possible vendor-specific property, but to explain what the common advanced properties usually mean, what tends to happen when you raise, lower, enable, or disable them, and when each setting is actually worth touching.

Adapter vendors and driver packages do use different names.  
`Jumbo Packet` may appear as `Jumbo Frames`. `Receive Buffers` may show up as `Receive Descriptors`. `Priority & VLAN` may become `Packet Priority & VLAN`. In this article, settings with the same intent are grouped together.

## 1. Short version

Here is the practical summary first.

- **Speed & Duplex should usually stay on Auto.**
- **Checksum Offload, RSS, LSO, and RSC are usually best left enabled or at their defaults.**
- **Jumbo frames only make sense when the path is aligned end to end.**
- **Interrupt Moderation trades latency for lower CPU overhead.**
- **Flow Control can reduce drops, but it can also spread congestion.**
- **EEE, Green Ethernet, and Selective Suspend are power settings, not speed settings.**
- **VMQ and SR-IOV are mainly for Hyper-V and virtualization hosts.**
- **Wake on Pattern Match is often more trouble-prone than Wake on Magic Packet.**
- **Very old properties such as TCP Chimney Offload are usually not where you want to spend time.**

The main point is simple: NIC advanced properties are not a page where you enable everything that sounds strong.  
They are a page where you choose which trade-off you actually want: throughput, latency, CPU usage, power behavior, or compatibility.

## 2. Where to find the settings

### 2.1 In the GUI

You can get there from either path below.

#### From Network Connections

1. Run `ncpa.cpl`
2. Right-click the target adapter
3. Open **Properties** -> **Configure**
4. Open the **Advanced** tab

#### From Device Manager

1. Open Device Manager
2. Expand **Network adapters**
3. Right-click the NIC and open **Properties**
4. Open the **Advanced** tab

That is where most of the settings discussed in this article live.  
But the **Power Management** tab matters too, especially for resume and Wake on LAN behavior.

### 2.2 In PowerShell

PowerShell is better when you want to inventory current values or take a backup before changing anything.

```powershell
Get-NetAdapter

Get-NetAdapterAdvancedProperty -Name "Ethernet" |
  Sort-Object DisplayName |
  Format-Table DisplayName, DisplayValue, RegistryKeyword, RegistryValue -Auto
```

On some adapters the `RegistryKeyword` values are standardized enough to show names like `*RSS`, `*VMQ`, `*SRIOV`, or `*EEE`.  
But `DisplayName` and `DisplayValue` are still driver-defined, so it is safer to inspect the real adapter first before writing scripts against them.

## 3. Ground rules before changing anything

### 3.1 Decide what "better" actually means

"The network is slow" can describe several very different problems.

- Large file copies are slow  
  -> throughput, RSS, RSC, LSO, jumbo frames, buffers
- Small request/response traffic feels delayed  
  -> Interrupt Moderation, RSC, EEE, queue depth
- CPU usage is too high  
  -> offloads, RSS, RSC, interrupt behavior
- Things break after sleep/resume  
  -> Selective Suspend, Power Management, Wake on LAN
- The link sometimes drops or falls back to 100 Mbps  
  -> cable, peer device, Speed & Duplex, EEE, driver

If the goal is wrong, the tuning choice is usually wrong too.

### 3.2 Suspect the physical layer and peer device early

Some problems are not NIC-property problems at all.

- a bad cable
- a switch, dock, or router compatibility issue
- stale firmware
- insufficient power on a USB NIC
- port-side errors
- packet loss and retransmission elsewhere in the path

If the symptoms are "it negotiates at 100 Mbps", "the link flaps", or "large transfers are the only thing that breaks", the physical layer deserves attention before the Advanced tab does.

### 3.3 Change one thing at a time

If you change jumbo frames, LSO, RSC, RSS, and EEE together, you will not know what helped and what hurt.  
Write down the current state, change one property, and measure again.

### 3.4 Decide what you are going to measure

At minimum, it helps to watch:

- link speed
- throughput
- latency
- CPU usage
- NIC counters such as drops, errors, and shortages
- sleep/resume stability

Tuning by feeling alone is usually weaker than tuning with numbers.

## 4. Quick reference table

| Setting | What it does | What tends to happen when enabled or raised | What tends to happen when disabled or lowered | Default stance |
| --- | --- | --- | --- | --- |
| Speed & Duplex | Negotiates or fixes link speed and duplex | Can help with old peers, but mismatches can cause severe trouble | Auto is usually safest on modern networks | **Keep Auto** |
| Jumbo Packet / Jumbo Frames | Uses larger frames than standard MTU 1500 | Can reduce CPU and header overhead on large transfers | Maximum compatibility, but more packets | **Only when the path is aligned end to end** |
| Checksum Offload | Calculates IP/TCP/UDP checksums on the NIC | Usually lowers CPU cost | Moves checksum work back to the OS | **Usually enabled** |
| LSO / TSO | Lets the NIC segment large TCP sends | Often helps send-heavy throughput and CPU usage | Easier for compatibility isolation, but higher CPU cost | **Usually enabled** |
| RSC / LRO | Coalesces TCP receives | Often helps receive throughput and CPU usage | Finer packet granularity, sometimes better for latency-sensitive cases | **Evaluate by workload** |
| RSS | Spreads receive processing across CPUs | Better scalability on multi-core systems | Easier to bottleneck on one core | **Usually enabled** |
| Interrupt Moderation | Reduces interrupt frequency | Lower CPU overhead | Lower latency but more CPU / DPC cost | **Start at the default** |
| Receive / Transmit Buffers | Changes ring or queue depth | Better burst tolerance, sometimes better sustained throughput | Lower memory use, but easier to run short | **Increase only when needed** |
| Flow Control | Uses pause frames | Can reduce drops | Can expose or amplify congestion trade-offs elsewhere | **Treat as a network-wide choice** |
| Priority & VLAN | Applies 802.1p / 802.1Q behavior | Useful when VLAN/QoS is intentional | Simpler flat Ethernet behavior | **Use only when needed** |
| VMQ / SR-IOV | Helps virtualized networking | Useful on Hyper-V hosts | Simpler host behavior | **Mainly for virtualization** |
| EEE / Green Ethernet | Saves power when the link is idle | Lower power use | Often simpler and sometimes more stable | **This is a power choice, not a speed choice** |
| Selective Suspend | Puts the NIC into lower-power states | Lower power use | Often simpler resume behavior | **Good isolation candidate for resume issues** |
| Wake on Magic Packet / Pattern Match | Defines wake conditions | Remote wake is possible | Fewer unintended wakeups | **Enable only when needed** |

## 5. Link and frame-size settings

### 5.1 Speed & Duplex

This property controls **link speed and duplex negotiation**.  
It can appear as `Speed & Duplex`, `Link Speed`, or `Link Speed & Duplex`.

Typical choices include:

- Auto Negotiation
- 100 Mbps Full Duplex
- 1.0 Gbps Full Duplex
- 2.5 Gbps Full Duplex
- 10 Gbps Full Duplex

#### Practical guidance

**Auto is usually the right answer.**

Modern Ethernet gear is designed around negotiation. If one side is fixed and the other side is left on Auto, or if the peer is old and quirky, you can end up with a duplex mismatch, retransmissions, or poor performance that looks much stranger than the original problem.

If a link that should be 1 Gbps comes up at 100 Mbps, the usual suspects are:

- cable quality
- incomplete conductor wiring
- dock or USB NIC behavior
- switch-port problems
- EEE / Green Ethernet behavior
- driver age

Manual speed forcing is usually the last move, not the first one.

### 5.2 Jumbo Packet / Jumbo Frames

This property allows **larger Ethernet frames** than the normal 1500-byte MTU path.

#### What usually changes

When jumbo frames are truly supported end to end:

- packet count drops
- header overhead falls
- CPU cost can improve
- large transfer efficiency can improve

But there are traps:

- some drivers show values such as `9014 Bytes` as a frame size
- OS tools often describe the setting as `MTU 9000`
- switches may count tags and framing differently

So "9014" and "9000" are not necessarily the same number described in two ways. They may reflect different viewpoints.

#### Practical guidance

Use jumbo frames only when you control the path well enough to verify:

- your NIC
- the peer NIC
- the intermediate switches
- any VLAN tagging overhead
- any virtual switch or tunnel overhead

If one part of the path is still effectively at 1500, jumbo frames can turn into a debugging hole instead of a speed improvement.

### 5.3 Gigabit Master / Slave Mode

Some adapters, especially certain Intel models, expose a property related to **master/slave clocking on 1000BASE-T**.

#### Practical guidance

- Leave it on **Auto** unless there is a specific reason not to
- Think of it as a compatibility or negotiation rescue setting, not a performance tuning tool

### 5.4 Wait for Link and link-state properties

Properties such as `Wait for Link` and `Log Link State Event` are usually about **how the driver reports link readiness**, not about raw throughput.

#### Practical guidance

- Leave them at their defaults in normal desktop scenarios
- They can matter during troubleshooting, boot-time behavior, or failover validation
- They are usually not the first tuning knob to touch

## 6. Settings that affect CPU load, throughput, and latency

This group looks the most performance-related, and it often is. It is also where the trade-offs become real.

### 6.1 Checksum Offload

This moves IP, TCP, and UDP checksum work to the NIC.

#### Practical guidance

- Usually keep it **enabled**
- It often lowers CPU cost
- Apparent checksum errors in local packet capture are often just the visibility side effect of offload
- Disabling it temporarily can still be useful when isolating compatibility problems

### 6.2 Large Send Offload (LSO) / TSO

This lets the NIC break a large TCP send into smaller frames.

#### Practical guidance

- Usually keep it **enabled**
- It often helps send-heavy throughput and CPU usage
- If a specific application or driver path looks suspicious, temporarily disabling it can help isolate the issue

### 6.3 Receive Segment Coalescing (RSC) / LRO

This combines multiple received TCP segments before they move further up the stack.

#### Practical guidance

- Good for receive-side throughput and CPU efficiency
- Worth re-evaluating for low-latency or packet-visibility-sensitive workloads
- Not every "more efficient" receive path produces a better real-time feel

### 6.4 Newer UDP offloads (USO / URO)

Some newer NIC and OS combinations expose UDP-side offloads too.

#### Practical guidance

- If they appear, start by leaving them at their defaults
- Measure before changing them
- For ordinary troubleshooting, they are usually not the first place to go

### 6.5 Receive Side Scaling (RSS)

RSS spreads receive processing across multiple CPUs. On modern multi-core systems, it is one of the most important properties on the page.

#### Practical guidance

- **Usually enable it**
- If one CPU core is disproportionately busy while network throughput stalls, check RSS early

### 6.6 RSS queues / processors / profile

These properties control how much parallelism RSS can use.

#### Practical guidance

- Start at the default
- Increase only when measurements show a real bottleneck
- More queues can also mean more interrupt and DPC work

### 6.7 Interrupt Moderation / Interrupt Moderation Rate

This is one of the clearest trade-offs in the whole panel.

- Higher or adaptive moderation  
  -> usually lower CPU overhead, but higher latency
- Lower moderation or Off  
  -> usually lower latency, but more CPU / DPC cost

#### Practical guidance

- Start at the default or adaptive mode
- If you care about jitter or small-message latency, test lower settings
- If the main goal is bulk throughput, the default often behaves well

### 6.8 Receive Buffers / Descriptors and Transmit Buffers / Descriptors

These change queue depth.

#### Practical guidance

- They can help burst tolerance and sustained throughput
- They can also increase memory use and queueing delay
- Increase them when you have evidence such as drops or shortages, not just because a larger number exists

### 6.9 Flow Control

This is the pause-frame setting.

#### Practical guidance

- It may reduce drops in some environments
- It may also move congestion pressure somewhere else
- For latency-sensitive traffic, it deserves careful testing rather than automatic approval

## 7. VLAN, QoS, and virtualization-related settings

### 7.1 Priority & VLAN / Packet Priority & VLAN / NDIS QoS

These properties matter when VLAN tagging or priority tagging is intentional.

#### Practical guidance

- Leave them alone on a simple flat access network
- Treat them seriously when the network design actually depends on VLAN or QoS behavior

### 7.2 VMQ / VMMQ / SR-IOV

These are mainly **virtualization-host settings**, especially on Hyper-V.

#### Practical guidance

- They are not generic desktop speed settings
- Evaluate them together with vSwitch design, queue placement, and guest behavior

### 7.3 RDMA / DCB / PFC is another world

Once the conversation moves into SMB Direct, RDMA, PFC, or DCB, you are in a much more specialized design space.

#### Practical guidance

- Treat it as a separate subject from ordinary 1 GbE or 2.5 GbE desktop tuning
- Verify both the NIC side and the switch side together

## 8. Power-saving, sleep, and Wake on LAN settings

### 8.1 Energy Efficient Ethernet (EEE) / Green Ethernet

EEE is about **lower power usage when the link is idle**.

#### Practical guidance

- It is not a speed setting
- It can be perfectly fine in ordinary client use
- It is also a common isolation candidate when the symptoms are link instability, unexplained downshifts, or low-latency sensitivity

### 8.2 Selective Suspend / Device Sleep / standby-time link behavior

These settings define **how aggressively the NIC enters lower-power states**.

#### Practical guidance

- Reasonable to leave at default on laptops
- Very worth checking first when resume behavior is unreliable
- Sometimes easier to disable on industrial-control or always-on systems

### 8.3 Wake on Magic Packet / Wake on Pattern Match

These settings define how the machine is allowed to wake from network activity.

#### Practical guidance

- If you only need Wake on LAN, enable **Wake on Magic Packet**
- Disable wake features entirely if you do not need them
- Treat **Pattern Match** carefully because it can cause unintended wakeups

Remember that BIOS / UEFI settings and the Windows Power Management tab also matter here. The NIC setting alone is not always enough.

### 8.4 ARP Offload / NS Offload

These allow the NIC to answer a small amount of network traffic while the system sleeps.

#### Practical guidance

- Usually fine to leave enabled
- Most often touched temporarily during sleep/resume troubleshooting

### 8.5 The Power Management tab

The separate **Power Management** tab often matters just as much as the Advanced tab.

Common options include:

- **Allow the computer to turn off this device to save power**
- **Allow this device to wake the computer**
- **Only allow a magic packet to wake the computer**

#### Practical guidance

- If resume behavior is unstable, the first option is a very reasonable thing to inspect
- If unwanted wakeups are the problem, the magic-packet-only option is often the safer choice

## 9. Other settings that appear but are less common to tune

### 9.1 Network Address / Locally Administered Address

This manually overrides the MAC address.

#### Practical guidance

- It is not a performance setting
- Leave it alone unless you have a very specific test or migration need

### 9.2 Adaptive Inter-Frame Spacing

This is a fairly old property with more history than day-to-day value on modern switched full-duplex Ethernet.

#### Practical guidance

- Leave it at the default in ordinary environments
- Touch it only for a special legacy case or a vendor-directed workaround

### 9.3 Header Data Split

This is more relevant in certain server-oriented scenarios than on a typical client machine.

#### Practical guidance

- Leave it at the default unless the workload and vendor guidance clearly point to it

### 9.4 Low Latency Interrupts

Some vendors expose a property with a name like this.

#### Practical guidance

- Use it only if measurement says it wins
- Do not enable it just because the name sounds attractive

### 9.5 Old items such as TCP Chimney Offload / IPsec Task Offload

Some older drivers still surface very old offload properties.

#### Practical guidance

- In current Windows environments, these are generally not where you want to spend time
- Prefer current Microsoft guidance over old habit

## 10. Starting points by goal

### 10.1 Ordinary desktop or laptop use

- Speed & Duplex: **Auto**
- MTU / Jumbo: **1500 / disabled**
- Checksum Offload: **enabled**
- LSO: **enabled**
- RSC: **enabled**
- RSS: **enabled**
- Interrupt Moderation: **default / adaptive**
- Buffers: **default**
- Flow Control: **default**
- EEE / Green Ethernet: **default**
- Selective Suspend: **default**
- Wake on LAN: **only if needed**

The default posture is usually the right starting point.

### 10.2 NAS, backup, and large-copy workloads

- Speed & Duplex: **Auto**
- Jumbo: **evaluate only if the dedicated path can be aligned**
- Checksum Offload: **enabled**
- LSO: **enabled**
- RSC: **enabled**
- RSS: **enabled**
- RSS queues: **increase only if measurements justify it**
- Receive / Transmit Buffers: **increase only if counters show pressure**
- Interrupt Moderation: **default or slightly higher**
- EEE: **consider disabling if stability matters more**

These workloads often benefit from fewer packets, lower CPU overhead, and avoiding queue shortages.

### 10.3 Industrial cameras, device control, or low-latency paths

- Speed & Duplex: **Auto first, fixed only when the peer requires it**
- Jumbo: **only when camera, NIC, and switch all support it cleanly**
- Checksum Offload: **usually enabled first**
- LSO: **temporarily disable if send-side compatibility is suspicious**
- RSC: **often worth evaluating off**
- Interrupt Moderation: **test Low or Off**
- Buffers: **avoid oversizing without evidence**
- Flow Control: **test carefully**
- EEE / Green Ethernet: **often a disable candidate**
- Selective Suspend / power management: **often a disable candidate**

High-throughput optimizations do not automatically produce the best latency behavior.

### 10.4 Hyper-V host

- VMQ / VMMQ / SR-IOV: **evaluate with the overall design**
- RSS: **still important on the host side**
- RSC: **subject to virtual-switch constraints**
- QoS / VLAN: **match the vSwitch design**
- Flow Control / PFC: **evaluate with storage or RDMA design**

This is infrastructure design, not just adapter tuning.

### 10.5 Temporary troubleshooting profile

When the real goal is diagnosis, simpler behavior is better than theoretically optimal behavior.

- Speed & Duplex: **Auto**
- MTU: **1500**
- Jumbo: **disabled**
- EEE: **disabled**
- LSO: **temporarily disabled**
- RSC: **temporarily disabled**
- Interrupt Moderation: **default or lower**
- Wake / power save: **disabled if unnecessary**
- Save the original settings first

## 11. First places to look by symptom

### 11.1 It should be 1 Gbps or 2.5 Gbps, but it links at 100 Mbps

Check, in this general order:

1. cable quality
2. dock / USB NIC / adapter behavior
3. the switch port
4. driver updates
5. EEE / Green Ethernet
6. restore Speed & Duplex to Auto
7. only then try matching manual settings on both sides

### 11.2 Large transfers are slow, but ping looks normal

Look at:

- Checksum Offload
- LSO
- RSC
- RSS
- Receive / Transmit Buffers
- jumbo frames, if the path is dedicated
- NIC drop and error counters

This is usually a throughput problem, not a basic reachability problem.

### 11.3 Small request/response traffic feels slow or jittery

Look at:

- Interrupt Moderation
- RSC
- EEE
- Flow Control
- whether buffers are oversized

Batching-friendly optimizations can work against low-latency behavior.

### 11.4 The NIC disappears after sleep or takes several seconds to recover

Look at:

- Selective Suspend
- Device Sleep or standby-related settings
- the Power Management option that allows Windows to turn off the device
- dock or USB NIC firmware
- the wake-setting combination

Resume problems are very often power-management problems.

### 11.5 Packet capture shows many checksum errors

Before assuming the wire is bad, confirm:

- whether Checksum Offload is enabled
- whether LSO is enabled
- whether the capture is seeing the packet before transmission or on the wire
- whether a mirror port or another host sees the same thing

Very often, local checksum errors are just the visible side of offload behavior.

### 11.6 Only Hyper-V VMs are slow, or CPU usage looks uneven

Then desktop-style RSS thinking is not enough. Look at:

- VMQ / VMMQ
- SR-IOV
- vSwitch binding
- VLAN / QoS
- how the host and guest divide queue work

In virtualized networking, drawing the packet path often helps more than changing random properties.

## 12. Practical PowerShell notes

### 12.1 Back up the current state first

```powershell
Get-NetAdapterAdvancedProperty -Name "Ethernet" |
  Select-Object Name, DisplayName, DisplayValue, RegistryKeyword, RegistryValue |
  Export-Csv .\nic-advanced-backup.csv -NoTypeInformation -Encoding UTF8
```

### 12.2 List the advanced properties

```powershell
Get-NetAdapterAdvancedProperty -Name "Ethernet" |
  Sort-Object DisplayName |
  Format-Table DisplayName, DisplayValue, RegistryKeyword -Auto
```

### 12.3 Check RSS, RSC, and statistics

```powershell
Get-NetAdapterRss -Name "Ethernet"
Get-NetAdapterRsc -Name "Ethernet"
Get-NetAdapterStatistics -Name "Ethernet"
```

### 12.4 Example changes

```powershell
# Example: change Jumbo Packet (actual values differ by NIC)
Set-NetAdapterAdvancedProperty -Name "Ethernet" `
  -DisplayName "Jumbo Packet" `
  -DisplayValue "9014 Bytes"
```

```powershell
# Example: set the RSS receive-queue count
Set-NetAdapterRss -Name "Ethernet" -NumberOfReceiveQueues 4
```

### 12.5 Jumbo path validation

```powershell
# Roughly equivalent to the standard MTU 1500 path
ping <peer-ip> -f -l 1472

# Roughly equivalent to an MTU 9000 path
ping <peer-ip> -f -l 8972
```

The important detail is that a driver value such as `9014 Bytes` is not the same number from the same viewpoint as these `ping` payload sizes.

### 12.6 Practical notes

- Some settings require disabling and re-enabling the adapter, or a reboot
- Display names may be localized
- The same vendor can rename items across driver versions
- If you automate changes, enumerate the real machine first and script second

## 13. Wrap-up

Windows NIC advanced properties look like a wall of powerful options.  
In reality they are a collection of trade-offs around throughput, latency, CPU use, power behavior, and compatibility.

If there is one way to approach them safely, it is this:

- decide what you are trying to improve
- change one property at a time
- compare the before and after with real measurements

That approach is much safer than relying on names that merely sound fast.

## 14. References

- Microsoft Learn: [NIC advanced properties](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/nic-advanced-properties)
- Microsoft Learn: [Network Adapter Performance Tuning in Windows Server](https://learn.microsoft.com/en-us/windows-server/networking/technologies/network-subsystem/net-sub-performance-tuning-nics)
- Microsoft Learn: [Hardware Only (HO) features and technologies](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/hardware-only-features)
- Microsoft Learn: [Overview of Single Root I/O Virtualization (SR-IOV)](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/overview-of-single-root-i-o-virtualization--sr-iov-)
- Microsoft Learn: [Standardized INF Keywords for NDIS QoS](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/standardized-inf-keywords-for-ndis-qos)
- Microsoft Learn: [Standardized INF Keywords for Power Management](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/standardized-inf-keywords-for-power-management)
- Microsoft Learn: [Setting RSS parameters](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/setting-rss-parameters)
- Microsoft Learn: [Overview of receive segment coalescing](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/overview-of-receive-segment-coalescing)
- Microsoft Learn: [How to optimize network adapter power management settings](https://learn.microsoft.com/en-us/troubleshoot/windows-client/networking/power-management-on-network-adapter)
- Microsoft Learn: [Deprecated networking features in Windows Server](https://learn.microsoft.com/en-us/windows-server/get-started/removed-deprecated-features-windows-server#deprecated-features)
- Intel Support: [Advanced Settings for Intel Ethernet Adapters](https://www.intel.com/content/www/us/en/support/articles/000005593/ethernet-products.html)
