---
title: "When an Industrial Camera Control App Suddenly Crashes After a Month (Part 2) - What Application Verifier Is and How to Build Failure-Path Test Infrastructure"
date: "2026-03-11T10:30:00+09:00"
lang: en
translation_key: application-verifier-abnormal-test-foundation-part2
permalink: /en/blog/2026/03/11/003-application-verifier-abnormal-test-foundation-part2/
author: "Go Komura"
tags: [Windows Development, Debugging, Industrial Camera, Application Verifier, Failure-Path Testing, Handle Leak]
description: "A practical introduction to Application Verifier covering handle checks, heap checks, low-resource simulation, and how to use it to build a better failure-path test foundation."
---

# When an Industrial Camera Control App Suddenly Crashes After a Month (Part 2) - What Application Verifier Is and How to Build Failure-Path Test Infrastructure

Application Verifier is one of the most useful tools when you want to surface native-code and Win32-boundary problems **before** they become long-running production incidents.
It is especially effective when you need to test handle misuse, heap corruption, and failure paths under low-resource conditions.

## Contents

1. [Short version](#1-short-version)
2. [What Application Verifier is](#2-what-application-verifier-is)
3. [What it can do](#3-what-it-can-do)
4. [Why it mattered in this case](#4-why-it-mattered-in-this-case)
5. [How to simulate low-resource conditions](#5-how-to-simulate-low-resource-conditions)
6. [How to inspect handle problems](#6-how-to-inspect-handle-problems)
7. [How to build a practical failure-path test foundation](#7-how-to-build-a-practical-failure-path-test-foundation)
8. [Summary](#8-summary)

---

## 1. Short version

- Application Verifier is a runtime validation tool for **native and Win32-boundary misuse**
- Its value is not only finding bugs, but also **forcing rare failure paths to happen earlier**
- `Handles` catches invalid-handle behavior, `Heaps` helps surface heap corruption, and **Low Resource Simulation** injects failures that resemble memory or resource exhaustion
- For long-running EXEs, Application Verifier works best when combined with your own structured logs and resource-lifetime visibility
- If you want to test a DLL, the target you usually enable in Application Verifier is still the **test EXE** that loads it

## 2. What Application Verifier is

Application Verifier is a **runtime verification tool** for user-mode Windows applications.
It watches how the application uses OS APIs and resources, and it can both detect suspicious behavior and inject failures intentionally.

That makes it very different from static analysis or ordinary unit tests.  
It is about what happens **when the actual path runs**.

## 3. What it can do

Typical capabilities include:

- handle validation
- heap validation
- lock and memory checks
- page heap support
- low-resource simulation
- debugger integration through commands such as `!avrf` and `!htrace`

The practical benefit is that it can make ugly native-boundary bugs visible much earlier.

## 4. Why it mattered in this case

The goal here was not only "find one bug."  
The deeper goal was to confirm that, if another leak or failure-path mistake appears later, the system is already observable enough to explain what happened.

That is why Application Verifier was paired with:

- better process-level metrics
- explicit resource lifetime logs
- short reproducible harness scenarios

## 5. How to simulate low-resource conditions

One of the best features is **Low Resource Simulation**.

Instead of really exhausting the machine, you can make selected allocation or resource-creation paths fail artificially:

- `HeapAlloc`
- `VirtualAlloc`
- `CreateFile`
- `CreateEvent`
- other Win32 or OLE-related allocation paths

That is a very effective way to test error handling and cleanup logic.

## 6. How to inspect handle problems

For handle-heavy code, the important tools are:

- the `Handles` check
- `!htrace` to see open / close stacks
- your own logs that record operation context and resource lifetime

The big lesson is that Application Verifier should not replace your own logs.  
It works best when both are available.

## 7. How to build a practical failure-path test foundation

A useful pattern is:

1. create a harness EXE that drives the scenario repeatedly
2. separate normal verifier runs from low-resource fault-injection runs
3. collect debugger output, verifier logs, and structured application logs together
4. define pass / fail rules clearly

This makes failure-path testing repeatable instead of heroic.

## 8. Summary

Application Verifier is excellent at dragging unpleasant Windows-native bugs out into the open.
For systems that mix native SDKs, P/Invoke, Win32 APIs, and long-running operation, it is often one of the most practical tools you can add to your debugging toolbox.
