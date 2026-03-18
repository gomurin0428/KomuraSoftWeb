---
title: "How to Preserve Crash Logs in Windows Apps Even When They Die from Programming Errors - Best Practices with WER, Final Markers, and Watchdog Design"
date: 2026-03-19 10:00
lang: en
translation_key: windows-app-crash-logging-best-practices
permalink: /en/blog/2026/03/19/000-windows-app-crash-logging-best-practices/
tags:
  - Windows Development
  - Exception Handling
  - Logging
  - WER
  - Crash Dumps
  - Bug Investigation
author: Go Komura
description: "A practical guide to preserving useful crash evidence in Windows apps by combining normal logs, final crash markers, WER LocalDumps, and watchdog-style supervision instead of trusting in-process recovery alone."
consultation_services:
  - id: bug-investigation
    reason: "This topic fits bug investigation and root-cause analysis directly when the problem is a low-repro crash, a customer-only failure, or an abnormal exit where only partial evidence remains."
  - id: windows-app-development
    reason: "Designing normal logs, WER LocalDumps, final crash markers, and watchdog-style supervision is a practical Windows application architecture concern for WPF, WinForms, services, and resident tools."
---

The most painful state in Windows application troubleshooting is this:

**you know the process crashed, but you do not know why, and the evidence is too thin to reconstruct it later.**

This becomes especially expensive in cases like:

- it only crashes in customer environments
- it crashes only after long runs
- it is a WPF app, WinForms app, Windows service, or resident application with low reproducibility
- COM, P/Invoke, native DLLs, or vendor SDKs are involved
- you have "the exception message," but not the context immediately before the crash

The honest statement up front is important:

**you cannot guarantee that the crashing process itself will always successfully write the final log.**

Once you include stack corruption, heap corruption, fast-fail paths, forced termination, and power loss, the final in-process log is fundamentally a *best effort* mechanism.

What works much better in practice is a design that does **not rely on the crashing process alone**.

In other words, think in three layers:

1. ordinary time-series logs during normal operation
2. a minimal final crash marker at the moment of failure
3. crash evidence captured by the OS or by another process

This article organizes that approach for Windows desktop apps, resident tools, Windows services, and device-integration utilities, with the goal of **not losing diagnosability even when the program dies because of a real programming error**.

## 1. The short answer

Here are the conclusions first.

- The single most important rule is: **do not bet everything on one in-process "last log" handler.**
- The safest baseline in real work is usually: **normal logs + final crash marker + WER LocalDumps**.
- If the application runs for a long time, controls equipment, loads plugins, or mixes in native SDKs, adding a **watchdog / launcher / service** makes the design much stronger.
- In crash handlers, the rule is: **do not do heavy work**. No compression, no HTTP upload, no DI resolution, no UI dialogs, no complicated JSON generation.
- At crash time, leave only a short local record. Push compression, upload, and notification to **the next launch or another healthy process**.
- Using WinForms `ThreadException` or WPF `DispatcherUnhandledException` to keep the app limping forward after a programming error is usually dangerous.
- In both .NET and native code, suspicious corruption-style failures are usually safer if the design says **record and terminate** rather than **recover and continue**.
- If you collect dumps, you also need to preserve the matching **PDBs and deployed binaries**, or the dump becomes much less useful later.

The practical best practice is:

**do not try to do everything at the instant of failure. Split the job across before-crash, at-crash, and after-restart stages.**

## 2. Why in-process logic alone can never be "guaranteed"

If this point stays fuzzy, the architecture also stays fuzzy.

### 2.1 The crashing thread context itself may already be damaged

Unhandled-exception hooks and top-level exception filters may execute in the context of the failing thread itself.

At that point, problems like these are very normal:

- the stack is already unsafe
- heap corruption makes additional allocation unsafe
- waiting may deadlock because the fault happened while a lock was held
- the logger depends on objects that may already be corrupted

So the last-chance handler should be treated not as a place where "anything is still possible," but as a place where **very little is genuinely safe**.

### 2.2 Fast-fail and corruption-style failures are designed around minimal in-process work

When memory corruption or a similarly fatal state is involved, it is often safer **not** to expect normal exception handling behavior.

Especially on the native side, `__fastfail`-style exits and corruption-suspicious failures are deliberately designed around the idea of:

**terminate immediately with as little additional work as possible**

That naturally leads to this mental model:

- if the last in-process log line is written, that is lucky
- the primary crash evidence should come from the OS or from another process

### 2.3 .NET unhandled-exception events are not a place for heavy recovery logic either

`.NET` `AppDomain.UnhandledException` is useful, but it is much safer to treat it as a place for **short final recording only**.

For example:

- it may still be affected by locks held at the crash point
- it is not a universal safe place for every corruption-style failure
- forcing a continuation policy there tends to keep the program alive in a half-broken state

So:

**"unhandled exception event" means "last notification point," not "safe recovery point."**

## 3. Recommended architecture - split crash-time work and after-restart work

The cleanest model is to separate:

- what you try to do while the process is failing
- what you do only after restart or from another healthy process

| Phase | Goal | Where it runs | What it should do |
| --- | --- | --- | --- |
| Normal operation | preserve time-series context | inside the app | structured logs, heartbeat, boundary events |
| Crash time | leave minimum evidence | app + OS | final crash marker, WER dump |
| Right after exit | detect unexpected termination | another process | record exit code, decide restart, notify if needed |
| After restart | do heavier follow-up | a healthy new process | compress, upload, notify user, rotate old logs |

Once you split the work that way, the design becomes much more stable.

### 3.1 Minimal baseline

For a smaller business tool or internal WPF / WinForms application, the following is often enough:

- ordinary logs in a local append-only file
- one dedicated final crash marker file
- WER LocalDumps
- on the next launch, "the previous run ended abnormally; diagnostic information is available"

### 3.2 Stronger baseline

If your requirements look more like this:

- 24/7 operation
- device control, monitoring, or resident operation
- heavy use of COM / P/Invoke / native SDKs
- child processes, plugins, or script execution
- "it must not stay down in customer environments"

then it is usually worth separating:

- the worker process for the main work
- a launcher / watchdog / service for supervision, exit recording, and restart
- WER LocalDumps on the worker side
- crash-evidence collection either at the next launch or from the watchdog side

That is a much more production-oriented shape.

## 4. Best practices for normal logs

If you try to win with only the final line at crash time, you usually lose.  
What really pays off is the **ordinary log trail immediately before the crash**.

### 4.1 Log for later correlation, not for literary beauty

At minimum, ordinary logs should include:

- UTC timestamp
- elapsed time since process start
- PID / TID
- app name, version, build number, and commit/build identity
- session ID
- operation ID / job ID / correlation ID
- module / screen / worker name
- the external side effect immediately before the event
  - file write
  - DB update
  - device command send
  - network request
- exception type, HRESULT / Win32 error / exception code
- a safe summary of the important input parameters
- target IDs or object IDs as long as they do not expose secrets

The most practical formats are usually:

- JSON Lines
- or a one-event-per-line key=value style

Long prose is less useful than making it possible to **correlate three different evidence files later**.

### 4.2 Flush critical boundary events deliberately

Making every log entry fully synchronous is often too expensive.  
But pushing **everything** through an async buffer means the final interesting segment can vanish with the crash.

So a practical split is:

- small informational events may stay buffered
- `Warning` and above should flush earlier
- critical boundary events should be written **synchronously**

Typical critical boundary events include:

- `ProcessStart`
- `ConfigLoaded`
- `WorkerStarted`
- `ExternalCommandSent`
- `TransactionCommitted`
- `RecoveryStarted`
- `FatalPathEntered`

The idea is simple:

**important business and system boundaries should be dropped onto disk deliberately.**

### 4.3 Keep the normal log and the final crash marker separate

This is more important than it first looks.

If you try to put everything into one rolling log, problems like these appear:

- rotation happened at the wrong time
- the async queue still held the final events
- the logger itself died right after the exception
- the final line was truncated halfway through

So it is much safer to keep at least two separate artifacts:

- `app-<session>.jsonl`  
  the ordinary time-series log
- `fatal-last.log` or `fatal-<session>.log`  
  a file dedicated only to the final crash marker

Just making **"where the last line should go"** explicit helps a lot in practice.

### 4.4 Keep the crash-time destination local, not network-based

Depending on a UNC path, NAS, HTTP endpoint, or cloud API at crash time is risky because all of these can get involved:

- transient network loss
- DNS delay
- expired credentials
- UI-thread waiting
- service-account permission issues

At crash time, write to a **local fixed path first**.  
Send or upload the evidence only **after restart or from another process**.

### 4.5 Put a session identity into the filename

A date is not enough when the app may restart several times in one day.

A practical naming style is something like:

```text
Logs\
  MyApp_20260318_101530_pid1234_session-4f1c.jsonl
  MyApp_fatal_20260318_101533_pid1234_session-4f1c.log
  MyApp_watchdog_20260318.jsonl
```

Being able to answer **"which launch instance does this belong to?"** makes investigation dramatically faster.

## 5. Best practices for the final crash marker

This is **not** the place to build a full-featured logger.

This is the place to write **one short line, once, as reliably as possible**.

### 5.1 The purpose is not full diagnosis; it is a stable entry point

The final crash marker should contain a tightly chosen set of information:

- UTC time of failure
- PID / TID
- session ID
- version / build number
- which hook you came from
  - `AppDomain.UnhandledException`
  - `Application.ThreadException`
  - `DispatcherUnhandledException`
  - `SetUnhandledExceptionFilter`
  - `_set_invalid_parameter_handler`
  - `set_terminate`
- exception type or exception code
- a short message if it is safe to emit one
- the last operation ID
- the ordinary log filename
- the expected dump folder

That is enough.

### 5.2 Things you should not do in a crash handler

These are very likely to become traps:

- resolve a logger from a DI container
- use async / await
- fire off tasks
- wait on locks
- build complex JSON
- touch COM objects
- show UI dialogs
- compress files
- send HTTP / SMTP / Slack / Teams notifications
- analyze the dump in-process
- swallow the exception and continue

A crash handler is **not just the continuation of ordinary control flow**.  
Bias it toward "do a minimum local write and stop."

### 5.3 What the crash handler should do

The sequence should stay brutally simple:

1. prevent re-entry
2. write one short record
3. flush it
4. terminate

If possible, use:

- a folder created ahead of time
- a path already validated for existence
- a location whose ACLs have already been checked

Unlike ordinary logs, the fatal marker is so low-volume that it is reasonable to flush it aggressively.

### 5.4 Do not try to keep the process alive

For unexpected exceptions caused by programmer mistakes, it is usually safer to treat the final handler as a **recording device**, not a **recovery device**.

Especially if the failure happened:

- midway through shared-state updates
- on the UI thread
- in a monitoring or parent loop
- as `AccessViolationException`
- as `StackOverflowException`
- across native boundaries
- through CRT invalid-parameter / purecall / terminate paths

The instinct not to crash is understandable, but a half-broken process is often worse operationally and diagnostically than a cleanly terminated one.

## 6. Framework-specific cautions

### 6.1 .NET in general: `AppDomain.CurrentDomain.UnhandledException`

This is useful as a **last notification** point.

But the safer usage pattern is still:

- write the final crash marker
- optionally record one minimum message to Windows Event Log
- do not continue
- do not perform waiting or retry loops there

Treat it as the last notification, not as a place where the process becomes healthy again.

### 6.2 WinForms: `Application.ThreadException`

This one is tricky because it can make the app appear to continue on the UI thread.

That can be acceptable for explicitly handled, expected UI-side error cases, but it is usually a bad foundation for **unexpected programmer-error crashes**.

If investigation quality matters more than the illusion of survival, it is usually safer to:

- record the minimum evidence
- or bias toward `UnhandledExceptionMode.ThrowException`
- then terminate and keep the logs and dump

### 6.3 WPF: `Application.DispatcherUnhandledException`

WPF has the same temptation:

- it targets UI-thread exceptions
- `Handled = true` makes apparent continuation possible
- but state can easily diverge between the screen and the application internals

So in WPF too, it is often safer to use it as a **recording entry point**, not a life-support mechanism.

### 6.4 Do not make `TaskScheduler.UnobservedTaskException` your primary path

This is not your "final crash line" route.

It is useful for discovering task-exception observation mistakes, especially during development, but it is weak as a primary crash-evidence mechanism.

Use it to surface design mistakes, not as the main crash-recording backbone.

### 6.5 Native Win32 / C++: do not over-trust `SetUnhandledExceptionFilter`

In native code, it is very tempting to expect too much from `SetUnhandledExceptionFilter`.

But it still runs in the context of the faulting thread, and can be affected by:

- invalid stack
- deep recursion
- already-broken heap state
- locks held at the crash point

So it is best treated as:

**a best-effort final notification hook, not a universal recovery mechanism**

### 6.6 Native C++ should also cover CRT / C++ runtime termination routes

If you only look at unhandled SEH, you miss important termination paths.

In practice, you also want to think about things like:

- `_set_invalid_parameter_handler`
- `_set_purecall_handler`
- `set_terminate`

These represent **runtime-level termination paths** from the C or C++ runtime side.

The safe pattern is still:

- write a minimal crash marker there too
- avoid heavy work
- terminate
- let WER / dumps carry the main evidence

## 7. Use WER LocalDumps as the foundation

This is one of the strongest practical choices on Windows.

### 7.1 First recommendation: WER LocalDumps

In terms of **leaving meaningful evidence after a crash with decent reliability**, WER LocalDumps is usually the best first tool.

The reasons are simple:

- the OS can leave the dump
- it is easy to introduce without extra tooling
- it can be configured per application
- it moves the main crash artifact outside the failing process

And unlike plain logs, dumps can answer questions such as:

- which thread failed
- what the stack looked like
- where the module boundary was
- whether the likely issue is managed, native, COM, or SDK-related

### 7.2 Typical configuration

For example, to store dumps for `MyApp.exe` under `C:\CrashDumps\MyApp`:

```bat
reg add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\MyApp.exe" /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\MyApp.exe" /v DumpFolder /t REG_EXPAND_SZ /d "C:\CrashDumps\MyApp" /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\MyApp.exe" /v DumpCount /t REG_DWORD /d 10 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\MyApp.exe" /v DumpType /t REG_DWORD /d 2 /f
```

A reasonable starting view is:

| Value | First recommendation |
| --- | --- |
| `DumpFolder` | a dedicated folder |
| `DumpCount` | 5 to 10 |
| `DumpType` | `2` on dev machines, `1` or `2` in the field depending on size and sensitivity constraints |

### 7.3 Always verify the dump folder ACLs

Just like logs, dumps are useless if the process cannot write to the configured folder.

This matters especially for:

- Windows services
- privilege-separated child processes
- restricted accounts on field machines
- UAC-related layouts

So the dump destination should be:

- created ahead of time
- write-tested
- bounded by retention count
- operationally reachable for whoever actually needs to retrieve it

### 7.4 If you want to attach log files to WER reports

If you use Microsoft WER report flow or your own WER-based operations, `WerRegisterFile` can help register current log files as related report artifacts.

But this should be treated as an **additional path**, not a replacement for local persistence.

The practical priority order is usually:

1. local ordinary log
2. local fatal marker
3. local dump
4. optional WER-side related-file registration

### 7.5 Keep version and symbol discipline with the dumps

If you collect dumps but later discover that you do not have:

- the matching EXE / DLL
- the matching PDB
- the build identity

then the dump gets much weaker.

At minimum, preserve:

- deployed binaries
- matching PDBs
- version
- build timestamp
- commit/build identity
- installer or package identity

Dump collection and symbol retention need to be treated as one operational unit.

## 8. How to think about `MiniDumpWriteDump` and custom crash reporters

There are real cases where custom work makes sense:

- you want a "save diagnostics" UI path
- you want to bundle logs and config files
- you have multiple child processes
- you want custom masking before upload

But the most important rule remains:

**do not make the crashing process carry too much of the dump work either.**

### 8.1 Prefer out-of-process dump creation over self-dump

`MiniDumpWriteDump` is powerful, but it is usually safer when called from **another process** instead of from the crashing process itself.

A common shape is:

- the worker detects a fatal path if possible
- it notifies a helper through an event, named pipe, or another simple mechanism
- the helper creates the dump for the worker
- the helper bundles the tail of the log and config files
- the helper queues the evidence for later upload

That way, the helper is still healthy even if the worker is not.

### 8.2 If you absolutely must stay in-process, bias toward a dedicated dump thread

If a separate process is impossible, a dedicated dump thread can still be better than arbitrary fault-thread logic.

But even then, the result stays *best effort*.  
Custom dump logic does not magically turn crash handling into a guaranteed path.

### 8.3 Move heavy work to next start or to the helper side

Things custom reporters often tempt people to do at crash time include:

- zip compression
- symbol-aware summarization
- server upload
- screenshot capture
- database queries for more context

All of that is usually safer **after restart or from the helper side**, not at crash time.

## 9. What changes when you add a watchdog process

For long-running systems, a watchdog or supervisor helps a lot.

### 9.1 What the watchdog can record

A watchdog / launcher / parent service can preserve things like:

- child-process start time
- startup arguments
- PID
- monitored version
- last heartbeat time
- exit time
- exit code
- restart count
- whether a dump exists
- whether a restart happened

Just that already tells you far more clearly:

- whether it was really a crash
- whether the OS was shutting down
- whether the user closed it
- whether it was killed after a hang
- whether it entered a restart loop

### 9.2 When it is especially worth it

It is especially attractive when you have:

- a worker wrapping vendor SDKs
- image processing, video processing, or device I/O
- a monitoring or polling parent loop
- script or plugin execution
- COM / ActiveX legacy hosting
- 32-bit / 64-bit bridges or other interop-heavy boundaries

Putting the dangerous part into a dedicated worker makes both crash evidence and restart policy much easier to design.

## 10. Common anti-patterns

### 10.1 `catch (Exception)` -> log -> continue

This is common, and dangerous.

It often leads to:

- partial changes left behind
- corrupted shared state
- secondary failures
- blurred root cause

You get one more log line, but often at the cost of a much longer incident.

### 10.2 Trusting only the async logger queue

Async logging itself is not bad.

The problem is when the fatal path also just enqueues and returns.  
If the worker dies immediately, the queue dies with it.

The fatal path should have a direct-write escape route.

### 10.3 Uploading from the crash handler

This is tempting, but risky because it drags in:

- DNS
- TLS
- proxies
- authentication
- timeouts
- retry waits

Do the sending **after restart** instead.

### 10.4 Dumps exist, but they do not correlate with the normal logs

This is common too.

- dump filename has no session identity
- the normal log has no PID or session
- the watchdog log has no PID
- build numbers do not line up

The result is that the three evidence streams look like different stories.

### 10.5 Using WinForms / WPF unhandled-exception events as life support

At first this feels attractive, because the app appears to "stop crashing."

But in reality it often creates zombie states like:

- the screen still exists
- the worker logic is dead
- the UI still exposes active buttons
- nobody knows whether the save actually happened

### 10.6 Ignoring native runtime termination paths

If you only think about `SetUnhandledExceptionFilter`, you can miss:

- invalid parameter
- purecall
- terminate
- fast fail

Native C++ designs are stronger when they recognize CRT / C++ runtime termination routes explicitly too.

## 11. Minimum implementation checklist

If you satisfy the following, the design is already quite practical.

- [ ] ordinary logs are one event per line
- [ ] every log carries UTC, PID, TID, version, and session
- [ ] `ProcessStart` and `ProcessExit` are recorded
- [ ] important boundary events are flushed synchronously
- [ ] there is a dedicated final crash marker file
- [ ] the fatal path does not rely only on the async logger
- [ ] WER LocalDumps is configured per application
- [ ] the dump-folder ACL has been verified
- [ ] PDBs and deployed binaries are preserved
- [ ] the next launch can detect the previous abnormal termination
- [ ] compression / upload / notification happens after restart or from another process
- [ ] native C++ also covers invalid parameter / purecall / terminate routes
- [ ] you have deliberately crashed the app in test and confirmed that the evidence really remains

That last line matters especially:

**the design is not real until you have tested that the evidence is actually left behind.**

## 12. How far to test

Recommended test cases include:

| Test | What to confirm |
| --- | --- |
| managed unhandled exception | ordinary log, fatal marker, and dump all appear |
| UI-thread exception | WinForms / WPF event paths behave as expected |
| worker-thread exception | it reaches the intended top-level path and the watchdog detects the exit |
| native exception | WER dump is actually collected |
| invalid parameter / terminate | runtime-side termination still leaves the expected minimum evidence |
| forced kill | even if in-process logging fails, the watchdog records unexpected exit |
| restart | next-launch notification, collection, and upload behavior work |

The key is to confirm:

**under this failure condition, these exact files remain**

not just:

"it should probably log something."

## 13. Wrap-up

If you want enough evidence to investigate programmer-error crashes in Windows apps later, the core idea is actually quite simple:

- **do not trust only the crashing process**
- **split evidence between ordinary logs, a final crash marker, and OS / other-process evidence**
- **keep crash-time work short and local**
- **move heavy work to the next start or another process**
- **use WER LocalDumps as the foundation**
- **bias toward record-and-terminate rather than continue-and-hope**

In other words:

**instead of trying to make the last single log line heroic, build a design that remains diagnosable even if that last line is missing.**

You still want the last line, so keep a short final crash marker in its own file.  
But let the main crash evidence live in **WER dumps plus the ordinary logs leading up to the failure**.

That is a much more stable pattern in real Windows application work.
