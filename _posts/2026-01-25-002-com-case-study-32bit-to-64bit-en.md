---
title: "How to Call a 64-bit DLL from a 32-bit Application - A Practical COM Bridge Case Study"
date: 2026-01-25 11:00
lang: en
translation_key: com-case-study-32bit-to-64bit
permalink: /en/blog/2026/01/25/002-com-case-study-32bit-to-64bit/
tags: [COM, Windows Development, 32-bit, 64-bit]
author: Go Komura
description: "When a 32-bit application cannot directly load a 64-bit DLL, an out-of-process COM bridge is often the cleanest solution. This article walks through the Windows constraint, the architecture, and the call flow."
consultation_services:
  - id: legacy-asset-migration
    reason: "This is directly about bridging a 32-bit legacy asset to newer 64-bit functionality, which is a core staged-migration problem."
  - id: technical-consulting
    reason: "If the immediate need is to compare COM bridge options and process boundaries before implementation, this also fits technical consulting and design review."
---

# How to Call a 64-bit DLL from a 32-bit Application - A Practical COM Bridge Case Study

Needing to call a 64-bit DLL from a 32-bit application is a very common Windows requirement.
When you want to keep an existing 32-bit asset alive and use only the new functionality that exists on the 64-bit side, a COM bridge is often the most practical answer.

## Contents

1. [Assumed situation](#1-assumed-situation)
2. [Solution](#2-solution)
3. [Processing flow (sequence diagram)](#3-processing-flow-sequence-diagram)
4. [Sample code (conceptual)](#4-sample-code-conceptual)
5. [Complete sample code](#5-complete-sample-code)
6. [References](#6-references)

---

## 1. Assumed situation

The case here is simple: you want to keep an existing 32-bit application, but **you also need to use logic that lives inside a 64-bit DLL**.  
The problem is that a 32-bit process cannot load a 64-bit DLL. That restriction exists at the OS level.

Typical conditions look like this:

- The existing 32-bit application is too large to migrate immediately
- The 64-bit DLL contains new functionality, or one of its dependencies is available only in 64-bit form
- You want to call the functionality from the 32-bit side **with a typed interface**

In this situation, **calling the DLL inside the same process is impossible**.

## 2. Solution

The basic solution is to **separate the two worlds by using out-of-process COM (an EXE server)**.  
The 64-bit DLL is loaded by a 64-bit COM server (an EXE), and the 32-bit application uses that server through COM.

The flow is:

1. Prepare a 64-bit COM LocalServer (EXE) that internally calls the 64-bit DLL
2. Share a COM interface (IDL / TypeLib) so the types are published in a stable way
3. Let the 32-bit application call COM through that typed interface, with proxy / marshaling handling the boundary

There are a few important cautions:

- **32-bit and 64-bit registration are separate** and involve `WOW6432Node`
- **Custom structs require explicit marshaling design**
- **IPC adds overhead**, so very high-frequency calls need extra care

So the standard approach is to **move the 64-bit work into another process and bridge to it through COM**.

## 3. Processing flow (sequence diagram)

The following shows the flow when a 32-bit application calls functionality inside a 64-bit DLL.

<pre class="mermaid">
sequenceDiagram
    participant App as 32-bit client application
    box rgba(100,100,255,0.1) Handled automatically by COM (no manual work for the developer)
        participant Proxy as COM Proxy<br/>(32-bit side)
        participant RPC as RPC/IPC<br/>(inter-process transport)
        participant Stub as COM Stub<br/>(64-bit side)
    end
    participant Server as 64-bit COM Server<br/>(EXE)
    participant DLL as 64-bit DLL

    App->>Proxy: ICalcService.Add(1, 2)
    rect rgba(100,100,255,0.1)
        Note over Proxy: Marshal parameters
        Proxy->>RPC: Serialized data
        RPC->>Stub: Transfer across the process boundary
        Note over Stub: Unmarshal parameters
    end
    Stub->>Server: Add(1, 2)
    Server->>DLL: Native function call
    DLL-->>Server: Result: 3
    Server-->>Stub: Result: 3
    rect rgba(100,100,255,0.1)
        Note over Stub: Marshal return value
        Stub-->>RPC: Serialized result
        RPC-->>Proxy: Transfer across the process boundary
        Note over Proxy: Unmarshal return value
    end
    Proxy-->>App: Result: 3
</pre>

**Key points:**

- The 32-bit application can call through the `ICalcService` interface in a type-safe way
- The COM runtime automatically generates and manages the proxy / stub layer
- Because inter-process calls have overhead, batching is usually better than making many tiny calls

## 4. Sample code (conceptual)

The following is a **conceptual sketch**. In a real project you still need registration, TypeLib generation, and surrounding setup.

```csharp
// Shared interface (equivalent to the IDL contract)
[ComVisible(true)]
[Guid("7A4B5B23-0A2F-4D2B-9D4D-8A2A92B8B001")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ICalcService
{
    int Add(int a, int b);
}

// 64-bit COM LocalServer (EXE side)
[ComVisible(true)]
[Guid("1C9B6F4D-1E9A-4E61-9A4F-6A0F1D2D9A11")]
[ClassInterface(ClassInterfaceType.None)]
public class CalcService : ICalcService
{
    public int Add(int a, int b)
    {
        // The 64-bit DLL is called here
        return a + b;
    }
}

// 32-bit application side (client)
Type t = Type.GetTypeFromProgID("KomuraSoft.CalcService");
var calc = (ICalcService)Activator.CreateInstance(t);
int result = calc.Add(1, 2);
```

With this structure, the 32-bit side can keep using the service **through a typed API**.  
COM handles the proxy / stub work internally and routes the call through IPC.

## 5. Complete sample code

I have published a working sample of this approach on GitHub.

**[Call64bitDLLFrom32bitProc - GitHub](https://github.com/gomurin0428/Call64bitDLLFrom32bitProc)**

The repository includes:

- **Call64bitDLLFrom32bitProc/** - the 64-bit COM LocalServer (EXE)
- **X64DLL/** - the 64-bit DLL that contains the actual implementation
- **X86App/** - the 32-bit client application (WinForms)
- **scripts/** - scripts for registering and unregistering the COM server

If you build and register the sample by following the README, you can verify the actual behavior of calling a 64-bit DLL from a 32-bit process.

## 6. References

- Component Object Model (COM) portal  
  https://learn.microsoft.com/en-us/windows/win32/com/component-object-model--com--portal
- Registering `LocalServer32`  
  https://learn.microsoft.com/en-us/windows/win32/com/localserver32
- COM fundamentals  
  https://learn.microsoft.com/en-us/windows/win32/com/the-component-object-model
- COM Interop from .NET  
  https://learn.microsoft.com/en-us/dotnet/standard/native-interop/cominterop
