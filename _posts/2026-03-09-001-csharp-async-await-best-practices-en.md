---
title: "C# async/await Best Practices - A Practical Decision Guide for Task.Run and ConfigureAwait"
date: 2026-03-09 10:00
lang: en
translation_key: csharp-async-await-best-practices
permalink: /en/blog/2026/03/09/001-csharp-async-await-best-practices/
tags: [C#, async/await, .NET, Design]
author: Go Komura
description: "A practical guide to async/await in modern C# covering I/O-bound work, CPU-bound work, Task.Run, ConfigureAwait(false), fire-and-forget, and how to choose the right pattern."
---

# C# async/await Best Practices - A Practical Decision Guide for Task.Run and ConfigureAwait

We use `async` / `await` every day in C#, but the real confusion is usually not the syntax itself.  
The confusion is **which pattern to choose in which situation**.

## Contents

1. [Short version](#1-short-version)
2. [Key terms](#2-key-terms)
3. [The first decision table](#3-the-first-decision-table)
4. [Basic rules](#4-basic-rules)
5. [Common anti-patterns](#5-common-anti-patterns)
6. [Summary](#6-summary)

---

## 1. Short version

- `async` / `await` is about **not blocking a thread while waiting**, not about automatically making work faster
- First separate **I/O-bound** work from **CPU-bound** work
- For I/O-bound work, the default is to **await the async API directly**
- For CPU-bound work, decide carefully **where that CPU work should run**
- For independent async operations, consider **`Task.WhenAll`** before writing serial `await`s
- Treat fire-and-forget with care; if the work truly outlives the caller, use a managed place such as `Channel` or `HostedService`
- Default to `Task` / `Task<T>` for return types; choose `ValueTask` only when measurement justifies it
- `ConfigureAwait(false)` is especially useful in reusable library code, not as a blanket rule everywhere

## 2. Key terms

| Term | Meaning |
| --- | --- |
| I/O-bound | HTTP, DB, file, socket, or other work that mostly waits for an external system |
| CPU-bound | compression, hashing, image processing, parsing, or other work where the CPU itself is the bottleneck |
| fire-and-forget | starting work without awaiting its completion |

The important distinction is that **asynchrony and parallelism are not the same thing**.

## 3. The first decision table

| Situation | First tool to consider |
| --- | --- |
| waiting on HTTP / DB / file I/O | await the async API directly |
| heavy CPU work in a UI app | `Task.Run` |
| ASP.NET Core request handling | plain `await`, not immediate `Task.Run` wrapping |
| a few independent async operations | `Task.WhenAll` |
| many operations with a concurrency limit | `Parallel.ForEachAsync` or `SemaphoreSlim` |
| ordered background flow | `Channel<T>` |
| periodic async processing | `PeriodicTimer` |
| progressive async streams | `IAsyncEnumerable<T>` |

The biggest mistakes often come from reaching for:

- "just use `Task.Run`"
- "just fire and forget"
- "just use `ConfigureAwait(false)` everywhere"

## 4. Basic rules

- Return `Task` / `Task<T>` by default
- Use `async void` only for event handlers
- Accept `CancellationToken` and pass it downstream
- Keep an async API async all the way instead of mixing in synchronous blocking at the end
- When LINQ creates tasks, materialize them with `ToArray()` or `ToList()` before `Task.WhenAll`

## 5. Common anti-patterns

- wrapping already-async I/O in `Task.Run`
- awaiting independent work one item at a time in sequence
- using fire-and-forget without an owner for lifetime and exceptions
- applying `ConfigureAwait(false)` blindly in UI-facing application code
- using `ValueTask` only because it "sounds lighter"

## 6. Summary

The most useful mindset is not "which keyword do I remember," but:

1. what is this code actually waiting for?
2. who owns the lifetime of this work?
3. where is concurrency limited?

Once those three questions are clear, async / await design becomes much easier to review and maintain.
