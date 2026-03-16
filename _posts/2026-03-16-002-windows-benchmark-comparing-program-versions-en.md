---
title: "How to Compare Program Versions on Windows Without Benchmarking the Wrong Thing"
date: 2026-03-16 10:00
lang: en
translation_key: windows-benchmark-comparing-program-versions
permalink: /en/blog/2026/03/16/002-windows-benchmark-comparing-program-versions/
tags:
  - Windows
  - Benchmark
  - Performance
  - Profiling
  - Power Management
author: Go Komura
description: "A practical guide to comparing program versions on Windows with better repeatability, covering power mode, power plans, thermal behavior, background noise, timing metrics, and when to move into ETW and WPR."
consultation_services:
  - id: technical-consulting
    reason: "This topic fits technical consulting well when the real need is designing a trustworthy performance comparison workflow, deciding what to control, and interpreting small differences without fooling ourselves."
  - id: bug-investigation
    reason: "When one version looks faster or slower and the question becomes whether the cause is code, power behavior, thermal throttling, or background noise, this maps naturally to bug investigation and root-cause analysis work."
---

If you want to compare program version A and version B on Windows, the easiest mistake is also the most common one:

run each version once on the same machine, see an 8% difference, and call that a result.

That 8% may really come from the code.  
But on Windows it may also come from **power mode, power plan, thermal state, background updates, indexing, antivirus scanning, CPU affinity, run order, or cache state**. That is a very ordinary benchmarking story.

This article is about how to compare program versions on Windows in a way that is **as close to the code difference as practical**.  
The examples mainly assume Windows 11, but most of the core tools such as `powercfg` and `start` apply just as well on Windows 10.

## The short version

If the goal is better repeatability, the biggest wins are usually these:

1. **Decide what you are actually comparing before you start**
   - "Did the code get faster?" and "Does the user experience feel faster?" are not the same benchmark.

2. **Record power mode and power plan separately**
   - If you blur them together, the benchmark can quietly turn into a comparison of Windows power behavior instead of program behavior.

3. **Treat cold runs and steady-state runs as different things**
   - First-run behavior and warmed-up behavior often tell different stories.

4. **Alternate versions instead of running all of A and then all of B**
   - Otherwise heat and background activity can bias one side.

5. **Look at medians and spread, not just averages**
   - One outlier can distort the whole picture.

6. **If the difference is small, move into ETW / WPR**
   - At that point, guessing from feel is usually not good enough.

## First decide what kind of comparison this is

"Performance comparison" sounds singular, but it usually means one of two very different things.

### 1. A code-difference benchmark

This is the case where you want to know whether an implementation change actually made the program lighter or faster:

- algorithm changes
- data-structure changes
- compiler optimization changes
- runtime upgrades

Here, the right move is to reduce environmental noise aggressively:

- dedicated benchmark session
- fixed power settings
- notifications suppressed
- indexing or syncing reduced
- clean boot if necessary

### 2. A real-user experience comparison

Sometimes the question is not "Did the code get faster in the lab?" but:

"Does the newer version feel faster under ordinary Windows usage?"

In that case, you should **not** remove every source of noise.  
OneDrive syncing, Defender, notifications, and ordinary power behavior are part of the environment the user actually lives in.

Mix those two benchmark types together and the conclusions start to twist:

- 12% faster in the lab, but meaningless in real use
- no CPU-time change, but noticeably faster in end-to-end experience

Those are both normal outcomes when the benchmark goal is not stated clearly.

## What usually causes variation on Windows

Before trying to control the environment, it helps to name the sources of drift.

| Layer | Source of variation | Typical example |
| --- | --- | --- |
| Hardware | CPU / GPU, memory, SSD, cooling | a thin laptop versus a well-cooled desktop |
| Firmware | BIOS / UEFI, OEM controls | fan behavior, power policy choices |
| OS | Windows build, driver versions, update state | same PC, different behavior after an update |
| Power | AC / battery, power mode, power plan | running on battery changes the whole world |
| Thermal state | room temperature, fan state, prior load | turbo on the first run, throttling later |
| Background work | Update, Defender, sync, notifications | scanning or syncing during the run |
| Scheduling | priority, affinity, NUMA placement | different CPU placement on different runs |
| Data / cache | OS cache, app cache | first run is slow, later runs are faster |
| Build conditions | Debug / Release, PGO, logging | accidentally comparing two different build realities |

The practical takeaway is simple:

**"same Windows machine" is not the same thing as "same benchmark conditions."**

## Power mode and power plan are not the same thing

This is one of the easiest Windows benchmarking mistakes to make.

There is the modern **Power mode** setting from the Windows Settings app, and there is the traditional **Power plan** that shows up through `powercfg`.

They are related, but they are not the same thing.  
If you treat them as one knob, the benchmark can get messy very quickly.

At minimum, record these three things:

- whether the machine was on AC or battery
- which Power mode was selected
- which Power plan was active

If a benchmark result does not include those, it gets much harder to interpret later.

### Practical power rules

1. **Use AC power on laptops**
   - Battery testing is a different benchmark world.

2. **Fix Power mode**
   - For code-focused benchmarking, `Best performance` is a reasonable starting point.

3. **Record the active power plan**

```powershell
powercfg /list
powercfg /getactivescheme
```

4. **Switch plans deliberately if needed**

```powershell
# Balanced
powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e

# High performance
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
```

### When "High performance" is not available

That is not automatically a broken machine.

On devices built around Modern Standby, Windows may effectively allow only Balanced or plans derived from it.  
So "High performance is missing" can be a design characteristic of the system rather than an error.

## Reduce background noise before it reduces your credibility

Windows is never just sitting there doing nothing.  
That is usually good for the user, but it is inconvenient when you want a controlled benchmark.

### Reboot, then wait

After changing settings, reboot the machine and avoid benchmarking immediately after sign-in.  
The first few minutes can still be full of update activity, indexing, syncing, antivirus scanning, and startup work.

### Use clean boot when the comparison is serious

If the difference is small enough to argue about, clean boot is often worth considering.  
It is much more appropriate for **code-difference benchmarking in a lab-style environment** than for user-experience benchmarking.

### Silence notifications

Notification banners are not only visually annoying.  
They can also shift focus behavior and trigger work in the background at inconvenient moments.

### Suppress indexing and sync where it matters

If the benchmark reads or writes many files, repeatedly creates directories, or rebuilds large trees, search indexing and cloud sync can matter more than people expect.

Typical cleanup steps are:

- exclude the benchmark directory from indexing
- pause OneDrive, Dropbox, or similar sync tools
- close browsers and chat tools

### With Defender, define the rule instead of guessing

The right answer is not automatically "disable Defender."

If Defender materially disturbs a benchmark, use carefully scoped exclusions for the exact benchmark directory or process and record that fact with the result.  
Otherwise, you may end up benchmarking an environment that no longer represents real Windows use.

## If you do not control thermal state, you may just be benchmarking heat

Cold silicon and warmed-up silicon are not the same machine in practice.  
This is especially obvious on laptops, mini PCs, and compact desktops.

Useful rules are:

- keep room temperature as stable as practical
- keep the laptop placement consistent
- keep dock, display, and power-adapter setup consistent
- avoid heavy work immediately before the benchmark
- separate first-run and steady-state measurements

### Alternate the execution order

Running A ten times and then B ten times is asking for thermal bias.

Better patterns are:

- `A B A B A B ...`
- `A B B A A B B A ...`
- a pre-generated randomized order

The point is to avoid one version always seeing the cooler machine and the other always seeing the warmer one.

## "Faster" depends on what you measure

Trying to collapse everything into a single number usually causes trouble.  
On Windows, three measurement types are especially useful.

### 1. Wall-clock time

This is what the user waits for.  
It is the closest to end-to-end experience, so it is usually the first thing to look at.

On Windows, the right base primitive is `QueryPerformanceCounter` (QPC).  
In managed code, that usually means `Stopwatch`.

### 2. CPU time

This comes from `GetProcessTimes` and tells you how much CPU time the process actually consumed in user mode and kernel mode.

It is useful when you want to know whether the implementation itself became lighter, even if wall-clock time is affected by waiting, I/O, or scheduling.

### 3. Cycle count

`QueryProcessCycleTime` gives process-level CPU cycle counts.

This is another helpful way to see whether the actual CPU work changed, even when end-to-end time is influenced by other factors.

### A practical rule of thumb

| Question | Main metric to look at |
| --- | --- |
| How long the user waits | Wall-clock time |
| Whether the implementation is lighter | CPU time / cycle count |
| Whether tail latency got worse | Median plus p95 / p99 |
| Whether long-running behavior degrades | Throughput or time trend in steady state |

If you must choose one, choose wall-clock time.  
If you want to understand the difference instead of only reporting it, wall-clock plus CPU time is already much stronger.

## Priority, affinity, and NUMA are last-resort tools

These settings can matter.  
They can also create a benchmark that no longer resembles real Windows execution.

### Start with the default scheduler behavior

If a meaningful difference is visible under ordinary execution, that result already has value.  
Jumping straight to `/high` or `/affinity` can create a benchmark condition that users will never actually run.

### If you use them, be explicit about why

- **/high**: reduce interference from other processes
- **/affinity**: pin CPU placement for consistency
- **NUMA control**: align large multi-socket or high-core-count systems more carefully

Windows `start` can be used like this:

```cmd
start "" /high /wait myapp.exe --bench case1.json
start "" /affinity F /high /wait myapp.exe --bench case1.json
```

### Avoid `/realtime`

`/realtime` exists, but it is the wrong tool for ordinary benchmarking.  
It is much better at creating system-level problems than at creating trustworthy measurements.

## A practical benchmark procedure

If you want a repeatable workflow, this is a good starting point.

### Lab-style comparison flow

1. **Fix the compared artifacts**
   - commit hash / build number
   - compiler and runtime version
   - Debug / Release
   - logging, assertions, trace settings

2. **Fix the machine conditions**
   - Windows build
   - BIOS / UEFI version
   - driver versions
   - AC power
   - room temperature and placement

3. **Fix the power conditions**
   - choose Power mode
   - record the active power plan

4. **Reboot**

5. **Wait a few minutes**

6. **Use clean boot if necessary**

7. **Include warm-up runs**
   - JIT, DLL loading, and cache creation should not be confused with steady-state execution

8. **Alternate A and B**

9. **Run enough samples**
   - short benchmarks: around 30+ runs
   - medium benchmarks: 10 to 20 runs
   - long benchmarks: even 5 to 10 runs can work, but still alternate versions

10. **Keep median, min, max, and p95**

11. **Save the raw data**

12. **If the difference is small, capture ETW / WPR**

## What to record with the result

At minimum, it helps to keep something like:

```text
timestamp,version,scenario,elapsed_ms,user_ms,kernel_ms,cycles,power_mode,power_plan,ac_or_dc,room_temp_c,notes
```

If possible, more context is even better:

```text
cpu_package_temp_start_c,cpu_package_temp_end_c,affinity_mask,priority_class,windows_build,driver_version
```

Benchmarking is not only about measuring quickly.  
It is also about being able to explain the result later.

## Look at medians and distributions, not only averages

Averages are easy to read and easy to break.

One Defender scan, one notification, or one unrelated SSD-heavy process can pull the average away from what the rest of the data is really saying.

Useful views include:

- **median**: usually the first thing to trust
- **p95 / p99**: helpful for tail behavior
- **min / max**: helps show how ugly the outliers are
- **box plots or scatter plots**: useful when differences are small

If the improvement is 10%, it is usually visible.  
If it is 1 to 3%, the shape of the distribution matters much more.

## How to read the outcome

The interpretation becomes clearer when you combine metrics.

### Wall-clock improves, but CPU time does not

That may indicate an improvement in I/O, waiting, cache behavior, or scheduling rather than in raw computation cost.

### CPU time and cycle count both improve

That is a strong sign that the implementation itself got lighter.

### Only the first run differs

Think about cold-versus-warm behavior:

- startup
- initialization
- cache creation
- JIT

### Later runs get worse

Think about:

- thermal throttling
- memory pressure
- background work

Once the difference becomes hard to explain from the top-level numbers alone, it is time to move into ETW / WPR.

## Use ETW / WPR when you need the reason, not just the number

When the difference is small or the cause is unclear, the standard Windows answer is to use ETW-based tooling.

`Windows Performance Recorder` (WPR), included in the Windows ADK, can capture:

- CPU activity
- I/O
- context switches
- page faults

A minimal flow looks like this:

```cmd
wpr -start CPU -filemode

REM Run the benchmark here

wpr -stop trace.etl
```

Once you analyze the trace in WPA, the conversation can move from:

"Version B is about 3% faster"

to something much more useful, such as:

"Version B reduced ready time by lowering lock contention"

or:

"Version A performs extra file opens and loses time during cold start"

That is where the fog starts to lift.

## Wrap-up

On Windows, trustworthy version-to-version benchmarking is usually not about clever tricks.  
It is about a small set of boring habits that make the result repeatable:

- fix and record AC / power mode / power plan
- separate cold and warm behavior
- alternate A and B
- look at medians and spread
- use clean boot when the comparison is sensitive
- use ETW / WPR when the difference is small and the reason matters

The single most important habit is to write down **what you fixed and what you did not**.

A benchmark result is not only a speed claim.  
It is also a record of experimental conditions.

An optimization report without conditions can be entertaining, but it is not very dependable.  
A carefully documented result still has value even when the difference is small.

## References

- [Microsoft Support: Change the power mode for your Windows PC](https://support.microsoft.com/en-us/windows/change-the-power-mode-for-your-windows-pc-c2aff038-22c9-f46d-5ca0-78696fdf2de8)
- [Microsoft Learn: Power Policy Settings](https://learn.microsoft.com/en-us/windows/win32/power/power-policy-settings)
- [Microsoft Learn: Customize the Windows performance power slider](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/customize-power-slider)
- [Microsoft Learn: Powercfg command-line options](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options)
- [Microsoft Support: How to perform a clean boot in Windows](https://support.microsoft.com/en-us/topic/how-to-perform-a-clean-boot-in-windows-da2f9573-6eec-00ad-2f8a-a97a1807f3dd)
- [Microsoft Support: Notifications and Do Not Disturb in Windows](https://support.microsoft.com/en-us/windows/notifications-and-do-not-disturb-in-windows-feeca47f-0baf-5680-16f0-8801db1a8466)
- [Microsoft Support: Search indexing in Windows](https://support.microsoft.com/en-us/windows/search-indexing-in-windows-da061c83-af6b-095c-0f7a-4dfecda4d15a)
- [Microsoft Learn: Configure custom exclusions for Microsoft Defender Antivirus](https://learn.microsoft.com/en-us/defender-endpoint/configure-exclusions-microsoft-defender-antivirus)
- [Microsoft Support: Device Security in the Windows Security App](https://support.microsoft.com/en-us/windows/device-security-in-the-windows-security-app-afa11526-de57-b1c5-599f-3a4c6a61c5e2)
- [Microsoft Learn: QueryPerformanceCounter function](https://learn.microsoft.com/en-us/windows/win32/api/profileapi/nf-profileapi-queryperformancecounter)
- [Microsoft Learn: Acquiring high-resolution time stamps](https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps)
- [Microsoft Learn: GetProcessTimes function](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getprocesstimes)
- [Microsoft Learn: QueryProcessCycleTime function](https://learn.microsoft.com/en-us/windows/win32/api/realtimeapiset/nf-realtimeapiset-queryprocesscycletime)
- [Microsoft Learn: start command](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/start)
- [Microsoft Learn: SetPriorityClass function](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-setpriorityclass)
- [Microsoft Learn: SetProcessAffinityMask function](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-setprocessaffinitymask)
- [Microsoft Learn: Processor Groups](https://learn.microsoft.com/en-us/windows/win32/procthread/processor-groups)
- [Microsoft Learn: Windows Performance Recorder](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/windows-performance-recorder)
- [Microsoft Learn: WPR Command-Line Options](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/wpr-command-line-options)
