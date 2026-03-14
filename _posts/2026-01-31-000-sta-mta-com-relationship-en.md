---
title: "COM STA/MTA Basics - Threading Models and How to Avoid Hangs"
date: 2026-01-31 10:00
lang: en
translation_key: sta-mta-com-relationship
permalink: /en/blog/2026/01/31/000-sta-mta-com-relationship/
tags: [COM, Windows Development, STA, MTA, Threading]
author: Go Komura
description: "A practical introduction to COM STA/MTA covering the apartment model, UI threads, message loops, marshaling, and the kind of hang patterns that appear in Windows development."
consultation_services:
  - id: technical-consulting
    reason: "Clarifying STA / MTA, message loops, and marshaling usually belongs to design review before the structure hardens."
  - id: legacy-asset-migration
    reason: "These COM threading concerns are also common in legacy-asset migration work where old boundaries still matter."
---

# COM STA/MTA Basics - Threading Models and How to Avoid Hangs

STA and MTA are hard to avoid once you start touching COM from Windows code or from .NET.
The most common questions are why UI threads are usually STA, what happens when a call crosses apartments, and why a program can hang even when the code looks innocent.

## Contents

1. [Short version](#1-short-version)
2. [Call patterns in the apartment model](#2-call-patterns-in-the-apartment-model)
   - [2.1. Pattern 1: calling within the same STA thread](#21-pattern-1-calling-within-the-same-sta-thread)
   - [2.2. Pattern 2: calling within the same MTA](#22-pattern-2-calling-within-the-same-mta)
   - [2.3. Pattern 3: crossing apartments](#23-pattern-3-crossing-apartments)
   - [2.4. A rough feel for marshaling overhead](#24-a-rough-feel-for-marshaling-overhead)
3. [STA (Single-Threaded Apartment)](#3-sta-single-threaded-apartment)
   - [3.1. Why UI threads use STA](#31-why-ui-threads-use-sta)
4. [MTA (Multi-Threaded Apartment)](#4-mta-multi-threaded-apartment)
5. [Where STA / MTA are decided](#5-where-sta--mta-are-decided)
   - [5.1. STA / MTA in .NET](#51-sta--mta-in-net)
6. [A concrete hang example caused by getting STA wrong](#6-a-concrete-hang-example-caused-by-getting-sta-wrong)
   - [6.1. A common situation](#61-a-common-situation)
   - [6.2. What actually happens](#62-what-actually-happens)
   - [6.3. Pseudocode for the typical failure pattern](#63-pseudocode-for-the-typical-failure-pattern)
   - [6.4. Key avoidance points](#64-key-avoidance-points)
   - [6.5. What does "pump the message loop" really mean?](#65-what-does-pump-the-message-loop-really-mean)
   - [6.6. A healthier direction (roughly)](#66-a-healthier-direction-roughly)
   - [6.7. Another hang pattern: callback during a synchronous call](#67-another-hang-pattern-callback-during-a-synchronous-call)
7. [Rough rule-of-thumb guidance](#7-rough-rule-of-thumb-guidance)
8. [Summary](#8-summary)
9. [References](#9-references)

---

When you use COM, **which thread the object runs on** is not optional knowledge.  
At the center of that is the **apartment model (STA / MTA)**.

STA and MTA are **threading models defined for COM**.  
They are not the same thing as the general notion of Windows threads. They exist to define the calling rules for COM objects.

This article organizes the relationship between STA, MTA, and COM **with diagrams**, and connects that directly to **why hangs happen**.

## 1. Short version

- **The calling rules of a COM object are determined by the apartment it belongs to**
- STA is easiest to understand as **one apartment per thread**
- MTA is easiest to understand as **multiple threads sharing one apartment**
- When calls cross apartments, **COM marshals them through proxy / stub infrastructure**

## 2. Call patterns in the apartment model

There are three broad patterns in COM object calls.

### 2.1. Pattern 1: calling within the same STA thread

If the caller and object live on the same STA thread, the call is **direct** and has essentially no marshaling overhead.

<pre class="mermaid">
flowchart LR
    subgraph STA[STA thread]
        Caller[Caller code]
        Obj[COM object]
        Caller -->|Direct call| Obj
    end
</pre>

### 2.2. Pattern 2: calling within the same MTA

Inside the same MTA, multiple threads can also **call directly**.  
But in return, the object itself **must be designed to be thread-safe**.

<pre class="mermaid">
flowchart LR
    subgraph MTA[MTA - one apartment]
        Thread1[Worker thread 1]
        Thread2[Worker thread 2]
        Obj[COM object]
        Thread1 -->|Direct call| Obj
        Thread2 -->|Direct call| Obj
    end
</pre>

### 2.3. Pattern 3: crossing apartments

Between different apartments, **COM forwards the call using proxy / stub machinery**.  
For standard interfaces, the COM runtime usually handles this for you.

**Important note:** this does not mean proxy / stub code is "generated automatically for everything."  
But in many real projects, you do not need to generate it explicitly.

| Pattern | How proxy / stub support is typically provided |
|---|---|
| `IDispatch`-based Automation | handled by `oleaut32.dll` |
| type-library-based interfaces | handled by the type-library marshaler |
| .NET COM interop | usually handled through the type library |
| custom `IUnknown`-derived interfaces | may require MIDL-generated proxy / stub registration |

So the place where explicit MIDL-generated proxy / stub code tends to matter is **custom `IUnknown`-based interfaces that are not using Automation**.  
That is much less common than many people think in everyday .NET and scripting-oriented COM use.

<pre class="mermaid">
flowchart LR
    subgraph STA[STA thread]
        StaCaller[Caller code]
    end

    subgraph RT[COM runtime]
        Proxy[Proxy]
        RPC[RPC / transfer]
        Stub[Stub]
        Proxy --> RPC --> Stub
    end

    subgraph MTA[MTA thread]
        MtaObj[COM object]
    end

    StaCaller -->|Call| Proxy
    Stub -->|Forward| MtaObj
</pre>

**Key point:**  
Once you cross apartments, **marshaling overhead appears**.  
If the call is high-frequency, that overhead becomes a real design concern.

### 2.4. A rough feel for marshaling overhead

The following is only a rough feel, not a benchmark. Actual cost varies a lot with implementation details and parameter complexity.

| Call pattern | Rough time scale | Relative feel |
|---|---|---|
| same apartment (direct) | 10 to 100 nanoseconds | close to an ordinary function call |
| different apartments, same process | 1 to 10 microseconds | roughly 100 to 1000 times more expensive |
| different process (out-of-proc) | 100 to 1000 microseconds | roughly 10,000 to 100,000 times more expensive |

Relative intuition:

- same apartment: like a normal memory-level call
- different apartment: more like a system-call-level boundary
- different process: closer to local host RPC / heavy interprocess communication

If you call something ten thousand times inside a loop, this difference becomes very visible.

## 3. STA (Single-Threaded Apartment)

STA is the model where **one thread owns one apartment**.

- COM objects in that apartment are basically executed **on that thread**
- if another thread calls them, **COM transfers the call via message queue / RPC**
- UI threads in WinForms / WPF often use STA because the UI itself already has strong single-thread affinity and a message loop

### 3.1. Why UI threads use STA

The design of UI threads and STA aligns very closely.

- **UI controls are not generally thread-safe**  
  Buttons, text boxes, and other UI elements are only safe to manipulate from the thread that created them
- **STA also assumes strong thread affinity**  
  COM objects run directly only on their owning thread
- **UI threads always pump a message loop**  
  That is required for window events, and it also matches STA's message-pump assumption

That is why WinForms and WPF UI threads are **STA by default**.

The trade-off is that STA has strong thread affinity, so **it is easy to create congestion if too many things depend on one thread**.

## 4. MTA (Multi-Threaded Apartment)

MTA is the model where **multiple threads share one apartment**.

- COM objects may be called from multiple threads at the same time
- the object implementation itself **must be thread-safe**
- it is a better fit for server-style and background processing

The trade-off is the opposite of STA:  
MTA offers more concurrency, but **the implementation has to carry more responsibility**.

## 5. Where STA / MTA are decided

COM apartments are decided **per thread**, at initialization time.

- `CoInitialize` / `CoInitializeEx` determines the apartment for that thread
- STA uses `COINIT_APARTMENTTHREADED`
- MTA uses `COINIT_MULTITHREADED`

### 5.1. STA / MTA in .NET

.NET exposes this through `[STAThread]`, `[MTAThread]`, and `ApartmentState`, but these are really just ways of configuring **COM's apartment model**.

- `[STAThread]`  
  applied to the entry-point `Main` method; COM will initialize that thread as STA when COM is used
- `[MTAThread]`  
  same idea, but for MTA
- `Thread.SetApartmentState(ApartmentState.STA)`  
  used for additional threads that you create manually; it must be set **before** the thread starts

Important details:

- `[STAThread]` has no practical effect until COM is actually used
- `[STAThread]` does not affect additional threads
- after a thread's apartment is initialized, you cannot later change it

So in .NET too, **the first COM initialization is everything**.

## 6. A concrete hang example caused by getting STA wrong

The following structure is a very realistic way to create a hang.

### 6.1. A common situation

- you create a background STA thread and instantiate a COM object there
- that thread **does not pump a message loop**
- another thread calls the COM object

The other thread can be STA or MTA. The key point is simply that it is **not the same thread**.

### 6.2. What actually happens

A COM object in STA **must process the call on its owning STA thread**.  
So when another thread calls it, COM transfers the call back to that STA thread.

But if the STA thread is **not processing messages**, the transferred call cannot be accepted.
The caller waits, and the program looks hung.

### 6.3. Pseudocode for the typical failure pattern

```csharp
var ready = new AutoResetEvent(false);
var done = new AutoResetEvent(false);

object comObj = null;
var staThread = new Thread(() =>
{
    // Initialize as STA
    CoInitializeEx(IntPtr.Zero, COINIT_APARTMENTTHREADED);

    comObj = new SomeStaComObject();
    ready.Set();

    // Waiting without a message loop -> fatal
    done.WaitOne();
});

staThread.SetApartmentState(ApartmentState.STA);
staThread.Start();

ready.WaitOne();

// Another thread (STA or MTA) calls into the object
// COM transfers the call back to the STA thread
// but the STA thread is not pumping messages
CallComObject(comObj);
```

<pre class="mermaid">
sequenceDiagram
    participant Main as Main thread
    participant STA as STA thread
    participant COM as COM runtime

    Main->>STA: Start thread
    STA->>STA: CoInitializeEx (STA)
    STA->>STA: Create COM object
    STA->>Main: ready.Set()
    STA->>STA: Wait on done.WaitOne()
    Note over STA: No message loop<br/>stuck here

    Main->>COM: CallComObject()
    COM->>STA: Try to transfer the call
    Note over COM: Transfer through message / marshaling path
    Note over STA: Cannot process it while blocked
    Note over Main: Caller keeps waiting
    Note over Main,STA: Both sides end up waiting -> hang
</pre>

The important assumptions behind STA are these:

- **the COM object executes on the STA thread that created it**
- **that STA thread pumps messages so transferred calls can be delivered**

So if you create **an STA thread that does not pump messages**, it cannot receive those transferred calls.
That is why the caller can wait forever.

UI threads, by contrast, already pump messages for window processing.
So they satisfy STA's fundamental requirement without you having to add anything extra.

### 6.4. Key avoidance points

- **If the STA object may be called from other threads**, the STA thread must pump a message loop
- if possible, create and use the object **on the UI thread itself**, because the UI thread already has a message loop
- if you do not actually need STA, **start with MTA instead**

### 6.5. What does "pump the message loop" really mean?

It is the usual Win32 message loop:

```csharp
while (GetMessage(out var msg, IntPtr.Zero, 0, 0))
{
    TranslateMessage(ref msg);
    DispatchMessage(ref msg);
}
```

In STA, transferred calls arrive through the message / dispatch mechanism.  
So this loop is exactly what receives those calls and lets them run.

### 6.6. A healthier direction (roughly)

If you really want a background STA thread to host COM, the shape is more like this:

```csharp
var ready = new AutoResetEvent(false);
object comObj = null;

var staThread = new Thread(() =>
{
    CoInitializeEx(IntPtr.Zero, COINIT_APARTMENTTHREADED);

    comObj = new SomeStaComObject();
    ready.Set();

    // Keep pumping messages while the STA thread is alive
    Application.Run();

    CoUninitialize();
});

staThread.SetApartmentState(ApartmentState.STA);
staThread.Start();

ready.WaitOne();
CallComObject(comObj);
```

And yes, forgetting `CoInitializeEx` / `CoUninitialize` is a very ordinary way to create bad time.

### 6.7. Another hang pattern: callback during a synchronous call

STA problems are not only about forward calls.
Sometimes a COM server **calls back into the client during a synchronous call**, and that can create a deadlock pattern very easily.

<pre class="mermaid">
sequenceDiagram
    participant UI as UI thread (STA)
    participant Server as COM server

    UI->>Server: DoWork() (synchronous call)
    Note over UI: Waiting for DoWork to return<br/>not processing messages
    Server->>UI: ProgressCallback()
    Note over UI: Cannot receive callback while blocked
    Note over Server: Waiting for callback to finish
    Note over UI,Server: Each side waits for the other -> deadlock
</pre>

Why this deadlocks so easily:

1. the UI thread makes a **synchronous** call to `DoWork()`
2. the UI thread waits for the return and does not pump messages
3. the server sends `ProgressCallback()` back to the UI thread
4. the UI thread cannot accept that callback while blocked
5. the server waits for the callback to complete
6. both sides end up waiting forever

This has nothing to do with the total processing time.  
The real problem is **"callback arrives during a synchronous call."**

There are COM mechanisms that can pump or reenter in some situations, so the exact behavior depends on the component and calling pattern.
Still, this is a pattern you generally want to avoid rather than rely on.

## 7. Rough rule-of-thumb guidance

- **UI involvement -> STA**
- **high parallel background processing -> MTA**
- **neither clearly fits -> follow the requirement of the COM server or existing library**

## 8. Summary

What STA / MTA are:

- STA / MTA are **threading models for COM**, not general Windows thread concepts
- STA is **one thread = one apartment**, while MTA is **multiple threads sharing one apartment**
- when a call crosses apartments, **COM transfers it through proxy / stub and marshaling infrastructure**

STA assumptions and pitfalls:

- when calls can arrive from other threads, **an STA thread is expected to pump messages**
- calling into an STA thread that is not pumping messages **easily causes hangs**
- **callbacks during synchronous calls** are a very common deadlock pattern

The relationship between UI threads and STA:

- UI threads already have single-thread affinity and a message loop
- that is why they naturally satisfy STA's assumptions and pair well with STA-style COM

Design-time caution:

- cross-apartment calls have **real marshaling overhead**
- if the call frequency is high, apartment design becomes a performance topic as well

## 9. References

- [COM Apartments](https://learn.microsoft.com/en-us/windows/win32/com/com-apartments)
- [CoInitializeEx](https://learn.microsoft.com/en-us/windows/win32/api/objbase/nf-objbase-coinitializeex)

---

[Download the Word version of this article](/assets/downloads/2026-01-31-sta-mta-com-relationship.docx)
