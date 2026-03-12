---
title: "When an Industrial Camera Control App Suddenly Crashes After a Month (Part 1) - Finding Handle Leaks and Designing Better Logs"
date: "2026-03-11T10:00:00+09:00"
lang: en
translation_key: handle-leak-industrial-camera-long-run-crash-part1
permalink: /en/blog/2026/03/11/002-handle-leak-industrial-camera-long-run-crash-part1/
author: "Go Komura"
tags: [Windows Development, Debugging, Industrial Camera, Handle Leak, Logging]
description: "A practical case study on investigating a Windows control application that crashed only after long-running operation, where the real cause turned out to be a handle leak rather than a memory leak."
---

# When an Industrial Camera Control App Suddenly Crashes After a Month (Part 1) - Finding Handle Leaks and Designing Better Logs

When a Windows application suddenly crashes only after long-running operation, many people instinctively suspect a memory leak first.  
In practice, the real culprit is sometimes a **handle leak** that only becomes visible as a secondary failure weeks later.

This case involved a Windows application controlling an industrial camera that crashed after roughly one month of continuous operation.  
The real cause turned out to be **a handle leak on a reconnect failure path**.

## Contents

1. [Short version](#1-short-version)
2. [What a handle leak means here](#2-what-a-handle-leak-means-here)
3. [The case itself](#3-the-case-itself)
4. [How we narrowed it down](#4-how-we-narrowed-it-down)
5. [What logs were needed](#5-what-logs-were-needed)
6. [Summary](#6-summary)

---

## 1. Short version

- In long-running control applications, do not look only at `Private Bytes`; always look at **`Handle Count`** as well
- Handle leaks often hide in timeout, reconnect, early-return, and partial-failure paths rather than in the normal path
- The line that crashes later is often **not** the line that leaked the resource earlier
- The minimum useful logs are operation context, process `Handle Count`, open / close pairs, and native error information
- Instead of waiting a month for reproduction, build a short loop that exercises connect, disconnect, reconnect, and failure paths repeatedly

## 2. What a handle leak means here

The "handles" in this article are Windows resource handles such as:

- events
- mutexes
- threads
- files
- device or SDK-related handles

The dangerous pattern is often:

1. create a temporary resource
2. hit a failure in the middle of initialization
3. return from the failure path without closing the resource

That is easy to miss in review because the success path still looks correct.

## 3. The case itself

The symptom looked deceptively simple:

- the application ran 24/7
- it behaved normally most of the time
- after about a month, it suddenly crashed
- restarting it made the problem disappear for a while again

The problem was that the crash location was not perfectly consistent.  
That is a strong hint that the final crash may only be a **secondary effect**.

The actual leak came from an **event handle created during camera reconnect initialization** and left unclosed on a failure path.

## 4. How we narrowed it down

The first useful observation was the resource trend:

| Metric | What we saw |
| --- | --- |
| `Handle Count` | slowly increased after reconnects and did not return |
| `Private Bytes` | changed, but did not show the same clear monotonic slope |
| `Thread Count` | mostly flat |

That shifted the hypothesis from "heap growth" to "resource lifetime asymmetry."

The key lessons were:

- shorten reproduction by repeatedly driving reconnect and failure paths
- watch the **slope** of `Handle Count`
- log open / create and close / dispose pairs
- search for the place that leaks, not only the place that crashes

## 5. What logs were needed

The most useful logs were:

- operation or session context
- process-level `Handle Count`
- resource open / close pairs
- Win32, HRESULT, or SDK error codes
- reconnect and failure-path transitions

The point was not to log everything.  
It was to make resource lifetime observable.

## 6. Summary

Long-run crashes are often misleading because the visible crash is only the last victim of a much older leak.

When the problem takes weeks to surface, the fastest path is usually:

1. make resource growth visible
2. force the suspicious failure paths quickly
3. log lifetime symmetry explicitly

That is how the handle leak stopped being a vague long-run mystery and became an ordinary debugging problem.
