---
title: "COM STA/MTA Basics - Threading Models and How to Avoid Hangs"
date: 2026-01-31 10:00
lang: en
translation_key: sta-mta-com-relationship
permalink: /en/blog/2026/01/31/000-sta-mta-com-relationship/
tags: [COM, Windows Development, STA, MTA, Threading]
author: Go Komura
description: "A practical introduction to COM STA/MTA covering the apartment model, UI threads, message loops, marshaling, and the typical hang patterns that show up in Windows development."
---

# COM STA/MTA Basics - Threading Models and How to Avoid Hangs

STA and MTA are hard to avoid once you start touching COM from Windows code or .NET.  
The most common questions are why UI threads are usually STA, what happens when a call crosses apartments, and why a program can hang even when the code looks innocent.

## Contents

1. [Short version](#1-short-version)
2. [Call patterns in the apartment model](#2-call-patterns-in-the-apartment-model)
3. [STA](#3-sta)
4. [MTA](#4-mta)
5. [Where STA / MTA are decided](#5-where-sta--mta-are-decided)
6. [A typical hang caused by the wrong STA setup](#6-a-typical-hang-caused-by-the-wrong-sta-setup)
7. [Rule-of-thumb guidance](#7-rule-of-thumb-guidance)
8. [Summary](#8-summary)

---

COM is not only about interfaces. It also defines **where an object lives and how calls are delivered to it**.  
That is what the apartment model is about.

## 1. Short version

- A COM object's calling rules are defined by **the apartment it belongs to**
- STA is easiest to understand as **one apartment per thread**
- MTA is easiest to understand as **multiple threads sharing one apartment**
- Calls that cross apartment boundaries are **marshaled by COM**

If you remember only one thing, remember this: **a COM call is not "just a method call" once apartments differ**.

## 2. Call patterns in the apartment model

There are three broad patterns you see in practice.

### Same STA thread

When the caller and the object are on the same STA thread, the call is direct and cheap.

<pre class="mermaid">
flowchart LR
    subgraph STA["STA thread"]
        Caller["Caller"]
        Obj["COM object"]
        Caller -->|Direct call| Obj
    end
</pre>

### Same MTA

When both sides are in the same MTA, calls are also direct, but **the object itself must be thread-safe**.

### Crossing apartments

When the caller and the object are in different apartments, COM transfers the call for you.

| Pattern | What usually happens |
| --- | --- |
| `IDispatch` / Automation style COM | The standard marshaler handles it |
| Registered type libraries | The type library marshaler often handles it |
| Custom `IUnknown`-based interfaces | You may need explicit proxy / stub support |

The key point is that **cross-apartment calls have real overhead and real delivery rules**.

## 3. STA

STA means **single-threaded apartment**.

- The object effectively belongs to one thread
- Calls from another thread are transferred back to that thread
- UI code maps naturally to STA because UI objects also have strong thread affinity

This is why WinForms and WPF are so comfortable with STA.  
Both the UI framework and COM assume that one thread owns the object and that a message loop is available.

### Why UI threads are typically STA

- UI controls are not generally thread-safe
- STA also assumes thread affinity
- UI threads already run a message loop, which is exactly what STA needs in order to receive transferred calls

## 4. MTA

MTA means **multi-threaded apartment**.

- Multiple threads may call the object concurrently
- The object must protect its own internal state
- This model fits server-side work and background processing better

## 5. Where STA / MTA are decided

The apartment is decided **per thread** when COM is initialized.

- `CoInitializeEx(..., COINIT_APARTMENTTHREADED)` creates STA
- `CoInitializeEx(..., COINIT_MULTITHREADED)` creates MTA

In .NET, the same idea appears through:

- `[STAThread]` and `[MTAThread]` on the entry point
- `Thread.SetApartmentState(...)` for manually created threads

The important part is simple: **the first initialization wins**.

## 6. A typical hang caused by the wrong STA setup

One of the easiest ways to hang a COM program is this:

1. Create an STA thread
2. Create a COM object on that thread
3. Never run a message loop there
4. Call the object from another thread

COM tries to deliver the call back to the STA thread, but the thread never pumps messages, so the caller waits forever.

```csharp
var ready = new AutoResetEvent(false);
object comObject = null;

var staThread = new Thread(() =>
{
    CoInitializeEx(IntPtr.Zero, COINIT_APARTMENTTHREADED);
    comObject = new SomeStaComObject();
    ready.Set();

    // No message loop here.
    Thread.Sleep(Timeout.Infinite);
});

staThread.SetApartmentState(ApartmentState.STA);
staThread.Start();
ready.WaitOne();

CallComObject(comObject); // Can hang here.
```

## 7. Rule-of-thumb guidance

- Use STA for UI-oriented COM components and code that depends on message pumping
- Use MTA for background or server-style components that are designed for concurrency
- Assume that apartment crossings are expensive compared with direct calls
- Do not create STA worker threads casually unless you also understand who pumps messages there

## 8. Summary

STA and MTA are not just labels. They are part of COM's execution contract.  
If you know where the object lives, whether the thread pumps messages, and whether a call crosses apartments, you can usually explain the weird behavior you are seeing.
