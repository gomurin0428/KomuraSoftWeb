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
- it is a WPF app, WinForms app, resident process, or Windows service with low reproducibility
- COM, P/Invoke, native DLLs, or vendor SDKs are involved
- you have "the exception message," but not the lead-up that explains it

The honest statement up front is important:

**you cannot guarantee that the crashing process itself will always successfully write the final log.**

Once you include stack corruption, heap corruption, fast-fail paths, forced termination, and power loss, the final in-process log is fundamentally a *best effort* mechanism.

What works much better in practice is a design that does **not rely on the crashing process alone**.

The cleanest model is to think in three layers:

1. ordinary time-series logs during normal operation
2. a minimal final crash marker at crash time
3. crash evidence captured by the OS or by another process

This article organizes that approach for Windows desktop apps, resident tools, Windows services, and device-integration utilities.

## 1. The short answer

- The most important rule is: **do not bet everything on one in-process "last log" handler**
- The safest practical baseline is usually: **normal logs + final crash marker + WER LocalDumps**
- If the process runs for a long time, controls equipment, hosts plugins, or mixes in native SDKs, add a **watchdog / launcher / service-side supervisor**
- In crash handlers, keep the work minimal. Do not compress, upload, resolve DI services, open UI, or build heavyweight JSON there
- At crash time, write something short **locally only**. Do upload, compression, and user-facing recovery on next start or from another healthy process
- Using WinForms `ThreadException` or WPF `DispatcherUnhandledException` to keep a program limping forward after a programming error is usually dangerous
- In both .NET and native code, suspicious corruption-style failures are usually safer to **record and terminate** than to "recover"
- If you collect dumps, keep the matching PDBs and deployed binaries too, or the dump will not help much later

In short:

**do not try to do everything at the instant of failure. Split responsibilities across before-crash, at-crash, and after-restart phases.**

## 2. Why in-process logic alone cannot make this "guaranteed"

This point matters because the whole architecture becomes clearer once you stop pretending the crashing process is a trustworthy place.

### 2.1 The crashing thread context itself may already be damaged

Top-level exception handlers often execute in the context of the failing thread.

At that point, common problems include:

- the stack is already in questionable shape
- heap corruption makes new allocation risky
- held locks make waiting dangerous
- the logger depends on objects that may already be half-broken

That is why the last-chance handler should be treated not as a place where "anything is still possible," but as a place where **very little is truly safe**.

### 2.2 Fast-fail and corruption-style termination paths are designed to do very little

Some failures are intentionally designed to terminate quickly with very little in-process recovery behavior.

That is why it is natural to think like this:

- in-process final logging is lucky if it works
- primary crash evidence should come from the OS or another process

### 2.3 .NET unhandled-exception events are also not a safe recovery stage

Things like `.NET` `AppDomain.UnhandledException` are useful, but they are much safer as:

- **last notification hooks**

than as:

- **full recovery points**

Heavy logic there tends to create half-broken continuation paths, which are often worse than a clean stop with good evidence.

## 3. Recommended architecture - split crash-time and after-restart work

The cleanest structure is to separate:

- what you do at crash time
- what you do after restart or from a healthy supervisor

| Phase | Goal | Where it runs | What it should do |
| --- | --- | --- | --- |
| Normal operation | preserve context over time | inside the app | structured logs, heartbeat, boundary events |
| Crash time | leave minimal evidence | inside the app + OS | final crash marker, WER dump |
| Right after exit | detect abnormal termination | another process | record exit code, decide restart, notify if needed |
| After restart | do heavier follow-up | a healthy new process | compress, upload, notify user, rotate old logs |

This split tends to make the design calmer very quickly.

### 3.1 Minimal baseline

For a smaller business tool or internal WPF / WinForms app, this is often enough:

- ordinary append-only local logs
- one dedicated final crash marker file
- WER LocalDumps
- on next launch, a clear "the app terminated unexpectedly last time" path

### 3.2 Stronger baseline

If you have requirements like these:

- 24/7 running
- device control or monitoring
- a lot of COM / P/Invoke / native SDK involvement
- plugin or child-process hosting
- "stays down until a human comes" is unacceptable

then it is usually worth separating:

- worker process
- launcher / watchdog / service process
- WER LocalDumps on the worker side
- evidence collection by the supervisor or at next restart

## 4. Best practices for normal logs

Trying to win with only the last line at crash time is usually a losing strategy.  
What really carries investigations is the **ordinary log trail before the crash**.

### 4.1 Log for correlation, not for literary beauty

At minimum, normal logs should usually carry:

- UTC timestamp
- elapsed time since process start
- PID / TID
- app name, version, build number, commit or build identity
- session ID
- operation ID / job ID / correlation ID
- screen / module / worker name
- the last important external action
- exception type or error code when available
- a safe summary of key input parameters

JSON Lines or structured key-value logs are often much easier to correlate later than long human-style prose entries.

### 4.2 Flush important boundary events deliberately

Not every log line needs synchronous disk behavior.

But if **everything** is only buffered asynchronously, the most valuable last segment can disappear with the crash.

A practical split is:

- fine-grained informational noise can stay buffered
- warnings and higher severity flush earlier
- critical boundary events are written more deliberately

Examples of useful boundary events:

- process start
- config loaded
- worker started
- external command sent
- transaction committed
- recovery started
- fatal path entered

### 4.3 Keep normal logs and the final crash marker separate

This matters a lot.

If you push everything into one rolling log, you can lose clarity because:

- rotation was in progress
- the async queue still held the final records
- the logger itself died mid-write
- the last entry was truncated halfway through

A much safer pattern is to keep at least:

- one ordinary session log
- one dedicated final crash marker file

That makes the "last known crash breadcrumb" explicit.

### 4.4 Use local disk first, not network paths

At crash time, relying on UNC paths, NAS, cloud endpoints, or HTTP uploads is risky.

Crashes are the worst time to discover:

- DNS delay
- temporary network loss
- credential issues
- UI-thread blocking
- service-account permission trouble

Crash-time evidence should go to a **local fixed path first**.  
Upload or forwarding belongs later.

## 5. Best practices for the final crash marker

This is not where you build a full-featured logger.

This is where you try to **leave one short, stable breadcrumb**.

### 5.1 The goal is not full diagnosis; it is a fixed entry point

The final crash marker should usually contain a small, stable set:

- UTC time
- PID / TID
- session ID
- version / build identity
- which hook caught it
- exception type or exception code if available
- a short message if it is safe
- the correlation ID or last operation ID
- the ordinary log filename
- the dump directory or expected dump location

This marker is not the whole answer.
It is the entrance to the answer.

### 5.2 Keep the handler brutally small

At crash time, the rule is:

**less logic, not more**

Avoid things like:

- compression
- HTTP upload
- dependency injection
- UI dialogs
- complex serialization
- long lock chains

If it feels architecturally elegant but operationally heavy, it probably does not belong in the crash path.

## 6. WER LocalDumps should do the heavy crash-evidence work

On Windows, WER LocalDumps are one of the strongest practical tools because the dump is produced by the OS-side mechanism, not by your half-broken process trying to save itself heroically.

That is why a very practical baseline is:

- app writes ordinary logs during normal operation
- app writes a tiny final crash marker if possible
- WER LocalDumps captures the real crash dump

This is often much more dependable than trying to build a rich in-process crash exporter.

## 7. When a watchdog or supervisor helps

A second process is especially useful when:

- long uptime matters
- restart behavior matters
- a crash must be detected immediately
- one process dying must not leave the whole system silent

A watchdog or launcher can help with things like:

- recording exit code
- recognizing unexpected exit vs normal stop
- deciding whether to restart
- leaving a supervisor-side log entry
- noticing repeated crash loops

That gives you evidence from a context that is still healthy when the worker dies.

## 8. Dangerous anti-patterns

### 8.1 Trying to fully recover after obvious programmer-error crashes

For many application bugs, especially around native boundaries, "keep running anyway" often creates a more dangerous half-corrupted state than a clean stop.

### 8.2 Doing heavy work inside the crash hook

This is the most common mistake:

- uploading
- zipping
- resolving services
- opening dialogs
- doing complex JSON generation

All of those belong later.

### 8.3 Depending on one magical final handler

If the architecture says:

"this one handler will always save us"

then the architecture is already too fragile.

### 8.4 Keeping dumps without symbol discipline

Crash dumps are only as useful as your ability to read them later.

That means keeping:

- the matching binaries
- the matching PDBs
- clear build identity

at the same time.

## 9. A simple operational checklist

- Are ordinary logs structured and correlated?
- Is there a separate final crash marker path?
- Are important boundary events flushed intentionally?
- Is crash-time output local-first?
- Is WER LocalDumps configured?
- Are PDBs and deployed binaries preserved alongside build identity?
- If uptime matters, is there a watchdog or launcher?
- Are upload, compression, and user messaging moved out of the crash hook?
- Are repeated crash loops detectable?

If the answer to those is mostly yes, the crash architecture is already much stronger than average.

## 10. Wrap-up

The real best practice is not:

**make one in-process crash handler do everything**

It is:

**split evidence collection across before-crash, at-crash, and after-restart stages**

The most practical baseline is often:

- structured normal logs
- one small final crash marker
- WER LocalDumps
- optional watchdog / launcher supervision when uptime matters

That structure is much less glamorous than heroic recovery logic, but it is also much more likely to leave the evidence you will actually need.

In Windows application work, the winning move is usually not "recover from everything."

It is:

**record what matters, terminate safely, and make the next healthy context responsible for the heavy follow-up.**
