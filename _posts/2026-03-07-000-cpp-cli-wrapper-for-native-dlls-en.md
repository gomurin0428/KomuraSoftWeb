---
title: "Why a C++/CLI Wrapper Is Often the Best Way to Use a Native DLL from C# - A Practical Comparison with P/Invoke"
date: 2026-03-07 10:00
lang: en
translation_key: cpp-cli-wrapper-for-native-dlls
permalink: /en/blog/2026/03/07/000-cpp-cli-wrapper-for-native-dlls/
tags: [C++/CLI, C#, Windows Development, Native Interop]
author: Go Komura
description: "When calling a native DLL from C#, there are cases where P/Invoke is enough and cases where a thin C++/CLI wrapper becomes the cleaner option. This article organizes the boundary around ownership, exceptions, and C++ types."
---

# Why a C++/CLI Wrapper Is Often the Best Way to Use a Native DLL from C# - A Practical Comparison with P/Invoke

It is very common to want to use existing Windows assets or native DLLs from C#.
If the other side exposes a clean C-style interface, P/Invoke is usually enough.

The real trouble starts when the DLL is shaped more like a C++ library.
It has classes, ownership rules, exceptions, and natural use of `std::wstring` and `std::vector`.
At that point, forcing everything through P/Invoke often makes the boundary itself the hardest part of the project.

This article explains what becomes easier when you put **one thin C++/CLI wrapper layer** in the middle.
This is not an argument that P/Invoke is bad.
It is an argument that **the situations where P/Invoke is enough and the situations where C++/CLI helps are different**.

## Contents

1. [Short version](#1-short-version)
2. [Cases where P/Invoke is enough](#2-cases-where-pinvoke-is-enough)
3. [Where P/Invoke suddenly starts to hurt](#3-where-pinvoke-suddenly-starts-to-hurt)
4. [The structure with a C++/CLI wrapper](#4-the-structure-with-a-ccli-wrapper)
5. [What becomes easier with C++/CLI](#5-what-becomes-easier-with-ccli)
6. [Code excerpts](#6-code-excerpts)
7. [Cases where you still should not choose C++/CLI](#7-cases-where-you-still-should-not-choose-ccli)
8. [Summary](#8-summary)
9. [References](#9-references)

* * *

## 1. Short version

- **If the other side is a flat C API, P/Invoke is the natural choice**
- **If the other side is a C++ library, maintenance often becomes easier if you insert one thin C++/CLI wrapper**
- This is especially true when **classes, ownership, strings, arrays, exceptions, and callbacks** are involved

In other words, **do not bring the native DLL's constraints directly into C#**.
Let C++ absorb native-side constraints, and expose only a .NET-friendly surface.
When that split works, both the code and the debugging experience become much calmer.

## 2. Cases where P/Invoke is enough

The first important point is that if P/Invoke is enough, it is usually the simplest choice.
There is no reason to force C++/CLI into the solution.

P/Invoke fits well when:

- the DLL already exposes a flat `extern "C"` style function API
- arguments and return values are simple things like integers, pointers, and straightforward structs
- string encoding rules are clear and buffer ownership is simple
- resource management is explicit, such as `Create` / `Destroy`
- the C# side can express the boundary naturally with `SafeHandle` and `StructLayout`

When things are this clean, you mostly just declare the signatures and use them.
It feels close to calling Win32 APIs.

## 3. Where P/Invoke suddenly starts to hurt

The atmosphere changes once the other side is no longer "just a C API."

### 3.1. When you start dealing with C++ classes

If the native DLL is designed around C++ classes, what you really want from C# is to call methods.
But P/Invoke can only target **exported DLL functions** directly.

That means somewhere you still need a layer that flattens the C++ interface into C-style functions.
At that point, you are already writing a wrapper.
So instead of scattering `IntPtr` and release functions throughout C#, it is often more natural to keep that wrapper on the C++ side.

### 3.2. When ownership and lifetime become hard to see

In C++, questions like these are normal:

- who frees this object?
- is the returned pointer borrowed?
- is this a `const&` or ownership transfer?
- is there a hidden lifetime assumption because of internal caching?

Trying to express all of that directly through `IntPtr`-based C# code tends to become painful when you revisit it later.
Once "who destroys this pointer, and when?" becomes vague, the boundary muddies quickly.

### 3.3. When `std::wstring`, `std::vector`, callbacks, and exceptions appear

This is the zone where P/Invoke becomes "possible, but not pleasant."

- you want to deal with `std::wstring`
- you want to return `std::vector<T>`
- you want to receive native progress through callbacks
- native code throws C++ exceptions

At that point, the C# side starts to accumulate `MarshalAs`, manual buffers, delegate lifetime management, and error-code interpretation.
You can absolutely make it work.
But the hard part stops being the business logic and becomes the interop layer itself.

### 3.4. When you do not want native-side constraints to leak into C#

The native API surface is not always the API surface you want C# developers to use.

For example, the native side may assume:

- several method calls must be combined into one logical operation
- failures are returned through error codes and out parameters
- initialization order matters
- thread-safety has special rules

But on the C# side, you often want a cleaner, more idiomatic shape.
That translation layer is where C++/CLI is especially useful.

## 4. The structure with a C++/CLI wrapper

The overall shape is simple:

```mermaid
flowchart LR
    Cs["C# app"] -->|.NET-friendly API| Wrapper["C++/CLI wrapper DLL"]
    Wrapper -->|direct use of native headers and types| Native["Native C++ DLL"]
```

From C#, you expose only a **.NET-like API**.
The C++/CLI layer absorbs:

- string conversion
- vector and array conversion
- exception conversion
- ownership and lifetime cleanup
- error-code interpretation
- if needed, callbacks and thread-boundary adjustments

The important design point is not to let the C++/CLI project grow too much.
Its role should remain **translation and shaping**, not business logic.

## 5. What becomes easier with C++/CLI

### 5.1. You can handle C++ types as C++ types

This is a major advantage.
Inside C++/CLI, you can include the native headers and use the native C++ types directly.

That means you do not have to recreate the C++ world awkwardly in C#.
You receive `std::wstring` and `std::vector` as C++ types first, then convert them into the .NET shapes you actually want to expose.

### 5.2. You can reshape the API into something .NET-friendly

On the C# side, you can expose familiar shapes such as:

- `string`
- `byte[]`
- `List<T>`
- `IDisposable`
- exceptions

That sounds small, but it changes the ergonomics a lot.
Especially in team development, it means people who do not know native details can still use the API comfortably.

### 5.3. It becomes easier to organize error and exception responsibility

If the native side mixes exceptions and error codes, exposing that directly to C# is awkward.
In C++/CLI you can normalize it:

- convert native exceptions into .NET exceptions
- translate error codes into meaningful exceptions or result objects
- add the context you want in logs

Once the boundary translates failure into something meaningful, the caller side becomes much cleaner.

### 5.4. You can hide ABI instability from C#

C++ classes and methods do not behave like a plain C ABI.
If C# starts to depend on those details, exported functions and marshaling rules leak into the managed side.

With C++/CLI, **C++ constraints stay on the C++ side, and C# only sees a stable managed surface**.
That separation also helps when the native library evolves.

### 5.5. Gradual migration becomes easier

Rebuilding an existing native DLL all at once is often too heavy.
With a C++/CLI wrapper, you can wrap only the needed APIs first and let new C# screens or workflows start using them incrementally.

That is a very practical path when you want to keep Windows-native assets alive while gradually moving surrounding layers into .NET.

## 6. Code excerpts

These are not meant to be a complete runnable sample.
They are only here to show the shape of the boundary.

### 6.1. Native-side API image

```cpp
// NativeLib.hpp
#pragma once
#include <string>
#include <vector>

namespace NativeLib
{
    struct AnalyzeOptions
    {
        int threshold;
        std::wstring modelPath;
    };

    struct AnalyzeResult
    {
        bool ok;
        std::wstring message;
        std::vector<int> scores;
    };

    class Analyzer
    {
    public:
        explicit Analyzer(const std::wstring& licensePath);
        AnalyzeResult Analyze(const std::wstring& imagePath, const AnalyzeOptions& options);
    };
}
```

This is a perfectly ordinary native C++ API.
But using it directly from C# is not especially pleasant.

### 6.2. What a P/Invoke path starts to look like

To call it directly from C#, you first need to flatten it into a C-style API somewhere.

```cpp
extern "C"
{
    __declspec(dllexport) void* Analyzer_Create(const wchar_t* licensePath);
    __declspec(dllexport) void  Analyzer_Destroy(void* handle);

    __declspec(dllexport) int Analyzer_Analyze(
        void* handle,
        const wchar_t* imagePath,
        const AnalyzeOptionsNative* options,
        AnalyzeResultNative* result);
}
```

And the C# side then starts to grow things like:

```csharp
internal sealed class SafeAnalyzerHandle : SafeHandle
{
    private SafeAnalyzerHandle() : base(IntPtr.Zero, ownsHandle: true) { }

    public override bool IsInvalid => handle == IntPtr.Zero;

    protected override bool ReleaseHandle()
    {
        NativeMethods.Analyzer_Destroy(handle);
        return true;
    }
}
```

If that is all you need, fine.
But in real projects, you usually then add questions about variable-length data, string buffers, error details, and callback lifetime.

### 6.3. The same idea with C++/CLI

With C++/CLI, you absorb native concerns there and expose a .NET-shaped API upward.

```cpp
// AnalyzerWrapper.h
#pragma once
#include "NativeLib.hpp"

using namespace System;
using namespace System::Collections::Generic;

public ref class AnalysisOptions
{
public:
    property int Threshold;
    property String^ ModelPath;
};

public ref class AnalysisResult
{
public:
    property bool Ok;
    property String^ Message;
    property List<int>^ Scores;
};

public ref class AnalyzerWrapper : IDisposable
{
public:
    AnalyzerWrapper(String^ licensePath);
    ~AnalyzerWrapper();
    !AnalyzerWrapper();

    AnalysisResult^ Analyze(String^ imagePath, AnalysisOptions^ options);

private:
    NativeLib::Analyzer* _native;
};
```

```cpp
// AnalyzerWrapper.cpp
#include "AnalyzerWrapper.h"
#include <msclr/marshal_cppstd.h>

using msclr::interop::marshal_as;

AnalysisResult^ AnalyzerWrapper::Analyze(String^ imagePath, AnalysisOptions^ options)
{
    NativeLib::AnalyzeOptions nativeOptions{};
    nativeOptions.threshold = options->Threshold;
    nativeOptions.modelPath = marshal_as<std::wstring>(options->ModelPath);

    try
    {
        auto nativeResult = _native->Analyze(
            marshal_as<std::wstring>(imagePath),
            nativeOptions);

        auto managed = gcnew AnalysisResult();
        managed->Ok = nativeResult.ok;
        managed->Message = gcnew String(nativeResult.message.c_str());
        managed->Scores = gcnew List<int>();

        for (int score : nativeResult.scores)
        {
            managed->Scores->Add(score);
        }

        return managed;
    }
    catch (const std::exception& ex)
    {
        throw gcnew InvalidOperationException(gcnew String(ex.what()));
    }
}
```

Then the C# side becomes very ordinary:

```csharp
using var analyzer = new AnalyzerWrapper(@"C:\license.dat");

var result = analyzer.Analyze(
    @"C:\input.png",
    new AnalysisOptions
    {
        Threshold = 80,
        ModelPath = @"C:\model.bin"
    });
```

From C#, you see `string`, `List<int>`, and `IDisposable`.
You do not need to see `IntPtr`, release functions, or native string-buffer rules.

## 7. Cases where you still should not choose C++/CLI

Of course, C++/CLI is not always the right answer.

- **The native side already exposes a clean C API**
  - in that case, P/Invoke is usually the more direct choice
- **You need cross-platform support**
  - C++/CLI is a Windows-first tool
- **The boundary is tiny and the types are simple**
  - adding a wrapper DLL may cost more than it saves
- **You have very strict AOT or packaging constraints**
  - check the whole deployment story first

The real decision point is: **where is it most natural to translate the complexity of the native side?**
If the native side is simple, use P/Invoke.
If it is complex in a C++ way, C++/CLI is often the cleaner place to absorb it.

## 8. Summary

P/Invoke is still the standard way to use native DLLs from C# when the other side is a clean C API.
But if the native side is really designed as a C++ library, it is often cleaner to build **one thin C++/CLI wrapper** than to push every ownership rule and marshaling concern into C#.

This becomes especially practical when you have:

- class-based APIs
- ownership assumptions
- `std::wstring` and `std::vector`
- exception translation
- callbacks
- gradual migration from native UI or workflow layers into .NET

The work is not flashy.
But deciding **where to tidy the boundary** has a huge effect on long-term maintainability.
When you want Windows-native assets and .NET productivity to coexist, C++/CLI is still a very useful tool.

## 9. References

- [Mixed (Native and Managed) Assemblies - Microsoft Learn](https://learn.microsoft.com/en-us/cpp/dotnet/mixed-native-and-managed-assemblies?view=msvc-170)
- [.NET programming with C++/CLI - Microsoft Learn](https://learn.microsoft.com/en-us/cpp/dotnet/dotnet-programming-with-cpp-cli-visual-cpp?view=msvc-170)
- [Migrate C++/CLI projects to .NET - Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/core/porting/cpp-cli)
- [Using C++ Interop (Implicit PInvoke) - Microsoft Learn](https://learn.microsoft.com/en-us/cpp/dotnet/using-cpp-interop-implicit-pinvoke?view=msvc-170)
- [Platform Invoke (P/Invoke) - Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/standard/native-interop/pinvoke)
- [Overview of Marshaling in C++/CLI - Microsoft Learn](https://learn.microsoft.com/en-us/cpp/dotnet/overview-of-marshaling-in-cpp?view=msvc-170)
- [marshal_as - Microsoft Learn](https://learn.microsoft.com/en-us/cpp/dotnet/marshal-as?view=msvc-170)
- [Performance Considerations for Interop (C++) - Microsoft Learn](https://learn.microsoft.com/en-us/cpp/dotnet/performance-considerations-for-interop-cpp?view=msvc-170)
