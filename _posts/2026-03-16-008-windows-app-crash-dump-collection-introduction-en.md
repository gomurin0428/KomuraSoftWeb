---
title: "Windows Crash Dump Collection for Apps: When to Start with WER, ProcDump, or WinDbg"
date: 2026-03-16 10:00
lang: en
translation_key: windows-app-crash-dump-collection-introduction
permalink: /en/blog/2026/03/16/008-windows-app-crash-dump-collection-introduction/
tags:
  - Windows Development
  - Bug Investigation
  - Crash Dumps
  - WER
  - ProcDump
  - WinDbg
author: Go Komura
description: "An introductory guide to collecting Windows application crash dumps, including when to use WER LocalDumps, ProcDump, or MiniDumpWriteDump, how to choose between mini and full dumps, and what to look at first in WinDbg."
consultation_services:
  - id: bug-investigation
    reason: "This topic fits bug investigation very naturally because crash dumps become most valuable when combined with logs, reproduction conditions, and long-run failure analysis in hard-to-reproduce environments."
  - id: technical-consulting
    reason: "If the real question is what to collect in production, how to combine dumps with logs, and how to set retention, access control, and symbol handling policy, this fits technical consulting and design review well."
---

Once a Windows application starts doing the "it only crashes sometimes" routine, logs alone often stop being enough.

That is especially true when:

- the crash happens only in a customer environment
- you have the exception message but not enough calling context
- the system crosses managed code, COM, P/Invoke, native DLLs, or vendor SDKs
- the failure only appears after long running time

This is where crash dumps become useful.  
If you capture the process state at the moment of failure, you can inspect the exception code, the crashing thread, the stack, the loaded modules, and sometimes much more of the process state afterward.

On Windows, the easiest way to think about dump collection is usually:

- start with **WER LocalDumps**
- add **ProcDump** when the triggering conditions need more control
- reach for **MiniDumpWriteDump** only when you genuinely need your own collection path

This article is an introduction to that first decision layer for desktop apps, resident apps, Windows services, and device-integration tools.

## 1. The short version

- For a first production-safe baseline, **configure WER LocalDumps per application**.
- If you need low-repro investigation, first-chance exception capture, or hang capture, **ProcDump** is usually the next tool.
- Think about **self-managed dump collection last**, not first.
- Dumps are only part of the story; **PDBs and the exact shipped binaries matter just as much**.
- **Full dumps are powerful, but they are also large and more likely to contain sensitive information.** Retention, storage, and access policy should be decided early.

The simplest starting matrix often looks like this:

| Environment | First practical setup |
| --- | --- |
| development / test machine | app-specific WER LocalDumps, usually `DumpType=2` for full dumps |
| customer / field machine | choose `DumpType=1` or `2` based on storage and sensitivity, add ProcDump only when needed |
| long-run or hang investigation | WER plus ProcDump options like `-h` or `-e 1` |
| custom diagnostic workflow | consider `MiniDumpWriteDump`, ideally from another process |

In short:

**start with WER, then ProcDump, then custom collection.**

## 2. What a crash dump can actually tell you

A crash dump is a snapshot of the process at a specific moment.

It is good at telling you things like:

- which exception code occurred
- which thread crashed
- what the stack looked like at that point
- which modules were loaded
- depending on dump size, some or all of the memory state

It is much weaker at telling you things like:

- the full time sequence that led there
- slow degradation over several hours
- the external system state at the time
- the complete business context immediately before the crash

That is why dumps work best when combined with logs, heartbeat data, or other telemetry rather than treated as the only source of truth.

## 3. The main collection choices

At an introductory level, four collection routes matter most:

| Method | Best fit | Strength | Caution |
| --- | --- | --- | --- |
| WER LocalDumps | first always-on crash capture | built into Windows, easy to scope per app | mainly crash-oriented; less flexible for hangs or custom triggers |
| ProcDump | low-repro cases, hangs, first-chance exceptions | many useful trigger modes, field-friendly | extra tool and operational workflow |
| Task Manager dump | one-off manual capture | simple GUI path | not automatic |
| `MiniDumpWriteDump` | custom product-integrated diagnostics | can bundle logs and metadata | easy to implement badly if done carelessly |

The most important practical decision is often not "which tool" but:

- under what conditions to capture
- where to store the dump
- how large the dump should be

## 4. The easiest first step: WER LocalDumps

### 4.1 The registry values that matter first

Windows Error Reporting provides **LocalDumps** for user-mode dump capture.  
It is a very practical first step because it requires no extra tool distribution.

The base key is:

```text
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps
```

In practice, it is usually cleaner to use an application-specific subkey:

```text
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\MyApp.exe
```

The first three values to care about are:

| Value | Meaning | Good first default |
| --- | --- | --- |
| `DumpFolder` | output directory | dedicated dump folder |
| `DumpCount` | retention count | start around 5 to 10 |
| `DumpType` | 0=custom, 1=mini, 2=full | start at 2 unless size forces 1 |

### 4.2 Example application-specific setup

For example, to keep up to 10 full dumps for `MyApp.exe` in `C:\CrashDumps\MyApp`:

```bat
reg add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\MyApp.exe" /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\MyApp.exe" /v DumpFolder /t REG_EXPAND_SZ /d "C:\CrashDumps\MyApp" /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\MyApp.exe" /v DumpCount /t REG_DWORD /d 10 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\MyApp.exe" /v DumpType /t REG_DWORD /d 2 /f
```

The useful details here are:

- scope it to **one executable**
- write to a dedicated folder
- start with **full dumps** when the goal is actual investigation
- limit the retained count

If production storage is tight, reduce `DumpType` to 1 for mini dumps.

### 4.3 Verify the collection path before waiting for a real incident

Do not wait for the first real customer crash to find out the collection path was wrong.

At minimum, verify:

1. a `.dmp` file appears in the expected folder
2. the size fits the operational expectation
3. WinDbg can open it
4. the Application log shows the crash clearly

Event Viewer entries such as `Application Error` and WER reporting events are useful for confirming that the failure path is at least visible to the system.

## 5. When ProcDump is the better tool

WER is often enough, but ProcDump becomes attractive when you need more control:

- you do not want a persistent registry-based setup
- you only want to watch an already-running process
- you want to wait for the next launch
- you need first-chance exceptions
- you need hang capture
- you need conditional trigger behavior

### 5.1 Common options worth memorizing early

| Option | Meaning |
| --- | --- |
| `-ma` | full dump |
| `-mp` | MiniPlus dump |
| `-e` | dump on unhandled exception |
| `-e 1` | dump on first-chance / second-chance exception |
| `-h` | dump when the window is hung |
| `-w` | wait for the target process to start |
| `-x` | start the target process under ProcDump |
| `-n` | maximum dump count |
| `-accepteula` | auto-accept the initial EULA prompt |

For an introductory mental model:

- crashes -> `-e`
- early exception observation -> `-e 1`
- hangs -> `-h`
- full dumps first -> `-ma`
- cap the dump count -> `-n`

### 5.2 Common command examples

#### Attach to an already running process and capture full dumps on unhandled exception

```bat
procdump -accepteula -ma -e 1234 C:\CrashDumps\MyApp
```

#### Wait for the next launch and capture full dumps on unhandled exception

```bat
procdump -accepteula -ma -e -w MyApp.exe C:\CrashDumps\MyApp
```

#### Launch it under ProcDump and monitor immediately

```bat
procdump -accepteula -ma -e -x C:\CrashDumps\MyApp MyApp.exe
```

#### Capture first-chance exceptions too

```bat
procdump -accepteula -ma -n 3 -e 1 MyApp.exe C:\CrashDumps\MyApp
```

#### Capture hangs

```bat
procdump -accepteula -h MyApp.exe C:\CrashDumps\MyApp
```

### 5.3 Why `-i` should not be the first move

ProcDump can install itself as the postmortem debugger with `-i`, but that affects machine-wide crash behavior.  
That makes it a heavier first step than it may first appear.

On a shared machine or a customer system, it is usually safer to start with:

- app-specific WER LocalDumps
- or ProcDump attached through `-w`, `-x`, or a PID

## 6. When to think about `MiniDumpWriteDump`

Self-managed dump collection makes sense in cases like:

- a UI button for "save diagnostic data"
- bundling logs, settings, and a dump together
- collecting related helper-process data too
- applying your own masking or packaging before upload

The main API for that path is `MiniDumpWriteDump`.

But two practical rules matter immediately:

1. **prefer calling it from another process if possible**
2. **treat the DbgHelp family as effectively single-threaded infrastructure**

The crashed process is already in an unstable state. Asking that same process to do its own careful dump-writing is often not the safest design. A separate helper process is usually a better rescue model.

## 7. Choosing between mini dumps and full dumps

This is one of the most common questions.

| Dump type | Best fit | Good side | Caution |
| --- | --- | --- | --- |
| mini dump | broad deployment, easier transfer | smaller, easier to share | weaker for heap or deep state analysis |
| full dump | cause-first investigation, native or heap suspicion | much richer process state | large size, higher sensitivity risk |
| middle-sized custom dump | when mini is too small and full is too heavy | balance | requires more knowledge to tune well |

The beginner-friendly practical rule is:

- **full dump on development and test machines**
- **mini or full in customer environments depending on storage and sensitivity**
- **prefer full dumps when native DLLs, COM, P/Invoke, memory corruption, or long-run state issues are involved**

## 8. Decide the operational rules early

Dump collection often fails operationally before it fails technically.

### 8.1 Keep the exact PDBs and shipped binaries

This is the most important point.

You need to retain:

- the exact shipped EXE / DLL versions
- the matching PDBs
- the build or commit identity that produced them

Without that, even a perfectly captured dump can be much harder to read.

### 8.2 Decide where dumps go and how many stay

Full dumps get large very quickly.

Decide early:

- do not keep them indefinitely on the system drive
- use a dedicated folder
- cap count with `DumpCount` or ProcDump `-n`
- separate short-term staging from long-term retention if needed

### 8.3 Decide who is allowed to access them

Full dumps can contain sensitive information:

- plaintext settings
- connection strings
- tokens or credentials
- recently handled business data
- paths and user names

So "who may read or receive dumps" needs a policy, not just a folder.

### 8.4 Pair dumps with logs

Dumps are stronger when you also preserve things like:

- version information
- startup arguments
- operation or job IDs
- the last important log events
- target endpoint or device summary state

### 8.5 Verify the flow with a Release build

Real failures are usually happening in Release builds, not Debug builds.

Collection should therefore be validated in a Release-like environment too.

## 9. The shortest useful analysis path after collection

### 9.1 Install WinDbg

These days WinDbg is easy to get through the Store or `winget`:

```bat
winget install Microsoft.WinDbg
```

### 9.2 Open the dump

```bat
windbg -z C:\CrashDumps\MyApp\MyApp_YYMMDD_HHMMSS.dmp
```

The analysis machine does not need to be the same machine that crashed.

### 9.3 Set up symbols

Start with Microsoft public symbols, then add your own PDB location:

```text
.symfix C:\Symbols\Microsoft
.sympath+ C:\Symbols\MyApp
.reload
```

### 9.4 Start with the automatic analysis

```text
!analyze -v
```

Then inspect:

- the exception code
- the faulting module
- how much of your own code is visible in the stack
- whether other threads also show suspicious waits or blocking

## 10. Common traps

### 10.1 The dump exists, but the PDBs do not

This is extremely common.  
Collection succeeded, but the analysis material is incomplete.

### 10.2 Nobody checked the ACL on `DumpFolder`

Services and separated-privilege processes fail here often.  
Verify that the crashing process can actually write there.

### 10.3 Full dumps keep filling the system drive

This is a classic operational accident.  
Retention limits and isolated dump folders should be planned up front.

### 10.4 Expecting WER alone to solve hang investigation

WER LocalDumps is a strong first crash-capture tool.  
Hangs and first-chance exception scenarios often fit ProcDump better.

### 10.5 Leaving `-e 1` on forever

First-chance exception capture is powerful and noisy.  
Use it with limits, time windows, or targeted scope.

### 10.6 Forgetting about custom crash reporters already in the app

If the application already has its own crash-reporting path, assuming WER will behave exactly as expected can lead to confusion. In that case, ProcDump or a custom path may be more direct.

## 11. Wrap-up

Crash dumps are one of the strongest observation points for low-repro Windows failures.  
They become even more valuable when COM, P/Invoke, native DLLs, or long-run behavior are part of the system.

A clean starting order is:

1. **start with app-specific WER LocalDumps**
2. **add ProcDump when trigger control matters**
3. **move to `MiniDumpWriteDump` only when you truly need a custom collection workflow**

That order keeps the solution practical and avoids making the first step heavier than it needs to be.

## 12. References

- [Collecting User-Mode Dumps - Win32 apps | Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/wer/collecting-user-mode-dumps)
- [ProcDump v11.1 - Sysinternals | Microsoft Learn](https://learn.microsoft.com/en-us/sysinternals/downloads/procdump)
- [MiniDumpWriteDump function - Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/api/minidumpapiset/nf-minidumpapiset-minidumpwritedump)
- [User-mode dump files - Microsoft Learn](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/user-mode-dump-files)
- [Analyzing a user-mode dump file - Microsoft Learn](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/analyzing-a-user-mode-dump-file)
- [Install WinDbg - Microsoft Learn](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/)
- [Symbol path for Windows debuggers - Microsoft Learn](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/symbol-path)
- [!analyze (WinDbg) - Microsoft Learn](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/-analyze)
- [Troubleshoot processes by using Task Manager - Microsoft Learn](https://learn.microsoft.com/en-us/troubleshoot/windows-server/support-tools/support-tools-task-manager)
- [Enabling Postmortem Debugging - Microsoft Learn](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/enabling-postmortem-debugging)
