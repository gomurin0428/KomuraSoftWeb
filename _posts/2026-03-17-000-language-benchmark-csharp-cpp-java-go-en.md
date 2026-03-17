---
title: "How to Measure and Compare Programming Language Speed Fairly - A Practical Guide for C#, C++, Java, and Go"
date: 2026-03-17 10:00
lang: en
translation_key: language-benchmark-csharp-cpp-java-go
permalink: /en/blog/2026/03/17/000-language-benchmark-csharp-cpp-java-go/
tags:
  - Benchmark
  - Performance
  - C#
  - C++
  - Java
  - Go
author: Go Komura
description: "A practical guide to comparing C#, C++, Java, and Go fairly, including benchmark design, warm-up, environment control, statistical reading, and concrete workload ideas."
consultation_services:
  - id: technical-consulting
    reason: "This topic fits technical consulting and design review well because benchmark design, workload selection, warm-up strategy, and statistical interpretation all shape whether the result is actually meaningful."
  - id: bug-investigation
    reason: "When language or version comparisons show unexpected performance gaps, validating the measurement method and isolating the real bottleneck often fits bug investigation and root-cause analysis directly."
---

"C++ is supposed to be fast."
"Go feels light in production."
"Java gets very fast once it runs long enough."
"C# can be stronger than people expect because the .NET JIT is good."

You hear this kind of thing all the time.  
The biggest mistake, though, is to **take numbers measured by different people on different environments and treat them as a direct ranking of programming languages**.

C# and Java are heavily affected by JIT behavior and warm-up.  
C++ and Go are usually ahead-of-time compiled.  
GC behavior differs. Standard library implementations differ. Surrounding libraries differ. Even on the same machine, power settings, heat, background activity, and input bias can move the result more than people expect.

This article organizes **how to compare C#, C++, Java, and Go as fairly as possible**.  
The most important conclusion is simple:

**do not try to decide "which language is fastest" from a single number.**

The point here is not to publish a fake ranking table built from environment-dependent numbers.  
The point is to organize **how to design a comparison that actually means something**.

## 1. The short answer

If you only keep a few points in your head, keep these.

1. **Decide what kind of speed you care about first**  
   Startup time, steady-state throughput, tail latency, and memory efficiency need different measurement shapes.

2. **Do not draw conclusions from one benchmark only**  
   CPU-heavy work, allocation-heavy work, parallel work, and startup-sensitive work can all tell different stories.

3. **Separate cold and warm results for C# and Java**  
   If you mix startup-sensitive runs and warmed-up steady-state runs, the result stops meaning one thing.

4. **Use the same algorithm, the same input, and the same correctness checks**  
   Benchmarking a different implementation of a different problem is not a language comparison.

5. **Separate language-native microbenchmarking from cross-language end-to-end benchmarking**  
   Language-specific harnesses are useful, but cross-language fairness usually needs an outer common runner.

6. **Look at medians and distributions, not just averages**  
   One GC spike or one noisy background event can wreck the average.

7. **Record the conditions as carefully as the numbers**  
   Benchmark results are not just speed records. They are experiment records.

## 2. Decide what "fast" means before you measure anything

Treating "fast" as a single word usually leads to a messy comparison.  
The first step is to decide **what kind of fast you actually mean**.

### 2.1 Do you care about startup time?

For CLI tools, short-lived jobs, or utility processes that start once and finish quickly, **cold start** and **process startup** matter.

On this axis, including or excluding JIT and class-loading cost changes the result a lot.

### 2.2 Do you care about long-running throughput?

For servers, workers, resident processes, or long-running transforms, **steady-state throughput** matters more.

In that case, the fact that a runtime is slower only at the first few executions may not be the main point at all.

### 2.3 Do you care about tail latency?

For APIs, UI-sensitive flows, or near-real-time processing, **p95 / p99 latency** can matter more than averages.

A result can look fast on average and still be painful in actual user experience or SLA terms.

### 2.4 Do you also care about memory efficiency?

CPU time alone can be misleading if you ignore:

- maximum RSS
- total allocation size
- allocation count
- GC count
- GC pause time

Sometimes "slightly slower but much lighter and more stable" is the better production answer.

So the real question is not:

> which language is fastest?

It is:

> for which workload, under which conditions, on which metric, which implementation performs better?

If you do not define that up front, the numbers will not settle into a useful conclusion later.

## 3. Why language comparison is hard

### 3.1 Mixing JIT and AOT changes the meaning of the experiment

C# and Java usually involve JIT behavior.  
C++ and Go are typically ahead-of-time compiled.

So if you measure the very first execution, you are measuring not just program logic, but also runtime startup, class loading, and JIT preparation.

If you measure only after sufficient warm-up, now you are asking a different question:

how strong is the steady-state optimized runtime?

Both questions are valid.  
They are just **not the same experiment**.

### 3.2 Implementation differences are often larger than language differences

Even for something as simple as sorting, results can change a lot if:

- one implementation uses the standard library
- another uses a custom implementation
- one makes extra copies
- one regenerates the input every time

And for JSON, compression, crypto, or regex-style work, the real difference may come more from **library implementation** than from the language itself.

That is how a supposed "language benchmark" quietly turns into a "library benchmark."

### 3.3 C++ has a very specific optimization trap

In microbenchmarks especially, the compiler may decide:

"nobody uses this result, so I can delete the work."

Then the code looks fast not because it is efficient, but because it is effectively doing nothing.

This is especially visible in C++, which is why result usage, checksums, or benchmark-framework anti-optimization helpers matter so much.

### 3.4 GC is not automatically "bad"; it is a runtime characteristic

C#, Java, and Go all involve GC, but treating that as a simple disadvantage is far too crude.

What matters more is often:

- how short-lived objects behave
- heap sizing
- GC frequency and pause behavior
- object layout
- allocation patterns in the surrounding code

On the other hand, C++ gives you tighter manual control, but it also makes implementation quality vary more sharply.

So memory-management style is not a direct proxy for good or bad by itself.

## 4. What not to do in a comparison

### 4.1 Never mix Debug and Release

This should not need saying, but it always does.

Every comparison target needs to be built in a **production-equivalent optimized configuration**.

### 4.2 Do not benchmark different problems

Different input formats, different output behavior, missing error handling in one version, or different buffer reuse policies will turn a performance comparison into a requirement mismatch.

### 4.3 Do not run once and decide from that

A single run is usually just noise mixed with:

- JIT
- page cache state
- CPU boost behavior
- thermal state
- background tasks
- GC
- first-time file loading

### 4.4 Do not mix warm-up into the same bucket

For C# and Java especially, you need to decide whether first-run cost is part of the question.

**Cold and warm are different categories**, not just different samples.

### 4.5 Do not skip correctness validation

A benchmark must prove **the implementations produce the same result** before it proves anything about speed.

Checksums or output hashes make this much easier to manage.

### 4.6 Do not let one microbenchmark define your worldview

Winning a tight loop does not prove you win a real service.  
Losing startup time does not prove you lose steady-state throughput.

## 5. The basic strategy for comparing C#, C++, Java, and Go

The cleanest approach is usually a **two-layer structure**.

### 5.1 Use language-native benchmark harnesses for language-internal work

Each language already has tools that understand its own runtime behavior.

- C#: BenchmarkDotNet
- Java: JMH
- Go: `go test -bench` and `benchstat`
- C++: Google Benchmark

These tools are excellent for:

- comparing implementations inside the same language
- investigating specific hot paths
- understanding runtime-specific behavior

### 5.2 Use an outer common runner for cross-language comparison

What you should not do is take a BenchmarkDotNet result and a JMH result and line them up as though they were automatically equivalent.

For true cross-language comparison, it is usually better to build each implementation as a CLI-driven executable or runner with a shared contract, for example:

```text
bench --scenario sort_int32 --dataset data/sort_10m.bin --mode warm
bench --scenario group_words --dataset data/words_100mb.txt --mode cold
bench --scenario parallel_hash --dataset data/blob_1gb.bin --threads 8
```

Then the outer runner can take responsibility for:

- randomizing execution order
- separating cold and warm runs
- feeding the same dataset
- validating checksums
- recording wall-clock time and memory
- saving raw results as CSV or JSON

That makes it easier to preserve both:

- best practice inside each language
- fairness across languages

## 6. What workloads you should prepare

If someone says "compare C#, C++, Java, and Go," the safest approach is not one benchmark, but **three or four workloads with different personalities**.

For example:

- CPU-heavy numeric work
- allocation-heavy text or parsing work
- startup-sensitive CLI work
- parallel work with a fixed thread count

The point is not to create a beauty contest where one language wins every round.  
The point is to expose which runtime characteristics matter for which workload shape.

## 7. Conditions you need to align per language

The comparison gets much cleaner if you make these choices explicit:

- release / optimization build only
- exact compiler or runtime version
- exact build flags
- same algorithm
- same input and output contract
- same checksum or correctness rule
- explicit cold vs warm definition

For C# and Java in particular, document how warm-up is handled.

For C++, document the optimization configuration clearly.

For Go, record the toolchain version and whether you are benchmarking directly through the Go testing framework or through an external runner.

## 8. How to align the execution environment

Even when the code is controlled, the environment can still move the result.

At minimum, it helps to align:

- machine
- OS version
- CPU topology
- memory size
- power settings
- thermal conditions
- background task load
- execution order

If you want cleaner results, alternate or randomize execution order instead of running all samples for one language first and all samples for another later.

That reduces bias from heat and background noise.

## 9. What to measure

At least these are usually worth recording:

- wall-clock time
- CPU time
- maximum RSS
- allocation size or allocation count if available
- GC count / GC pause if the runtime exposes it
- median
- p95 / p99
- min / max
- standard deviation or another spread indicator

Average alone is usually too weak to trust.

## 10. A practical execution flow

Here is a realistic order of work.

1. Decide the workload shape.
2. Fix the common dataset.
3. Validate correctness first.
4. Fix build conditions.
5. Separate cold and warm runs.
6. Alternate or randomize execution order.
7. Run enough times to make noise visible.
8. Save raw data, not just summaries.
9. Profile only after you see a meaningful difference.

That last step matters.

When a difference appears, that is when you go deeper with:

- CPU profiles
- allocation profiles
- GC logs
- flame graphs
- OS traces

That is how the conversation moves from:

"which language is faster?"

to:

"why does this workload behave this way?"

## 11. How to read the results

If C# or Java is slow only on the first execution, that often points to JIT, class loading, or initialization.

If C++ dominates a tight loop, that may reflect low-level optimization and low runtime overhead, but it does not automatically prove it will dominate a whole production workload.

If Go looks attractive on startup or packaging, that can reflect its runtime shape and deployment simplicity, but not every CPU-heavy workload will favor it.

If C# or Java catches up or overtakes in steady state, that may simply mean JIT optimization is doing its job, which is not unusual at all.

If allocation-heavy workloads show large differences, the biggest factor is often not the language name itself, but:

- memory layout
- map or string behavior
- GC patterns
- extra copying

## 12. A recording template

At minimum, it is useful to save something like:

```text
timestamp,language,scenario,run_kind,cold_or_warm,elapsed_ms,cpu_ms,max_rss_mb,alloc_bytes,gc_count,checksum
compiler_or_runtime,compiler_version,flags,os,cpu,threads,input_id,notes
```

The deeper truth is that a benchmark is valuable not just when you can run it, but when you can still interpret it later.

## 13. Wrap-up

The real key to comparing C#, C++, Java, and Go is not asking a vague question like:

**which language is fastest?**

It is turning that into a real experiment:

**for which workload, under which conditions, on which metric, how do the implementations behave?**

The safest core points are:

- separate startup from steady state
- use the same algorithm, input, and correctness checks
- never conclude from one benchmark alone
- separate language-internal benchmarking from cross-language benchmarking
- look at medians and distributions, not just averages
- save conditions and raw data

And maybe the most important point of all:

**do not try too hard to declare a universal winner by language name alone.**

Real-world performance comes from the combined effect of language, runtime, libraries, build settings, data shape, OS, and hardware.

"C++ is fast," "Java is strong," "Go is light," and "C# is plenty fast" can all be true in some sense.

The critical question is always:

**under which conditions are you saying that?**

## 14. References

- BenchmarkDotNet Getting Started  
  [https://benchmarkdotnet.org/articles/guides/getting-started.html](https://benchmarkdotnet.org/articles/guides/getting-started.html)

- OpenJDK JMH Project  
  [https://openjdk.org/projects/code-tools/jmh/](https://openjdk.org/projects/code-tools/jmh/)

- JMH GitHub Repository / README  
  [https://github.com/openjdk/jmh](https://github.com/openjdk/jmh)

- Go `testing` package  
  [https://pkg.go.dev/testing](https://pkg.go.dev/testing)

- Go `benchstat`  
  [https://pkg.go.dev/golang.org/x/perf/cmd/benchstat](https://pkg.go.dev/golang.org/x/perf/cmd/benchstat)

- Google Benchmark User Guide  
  [https://google.github.io/benchmark/user_guide.html](https://google.github.io/benchmark/user_guide.html)

- [How to Compare the Execution Speed of Different Versions of a Program on Windows](/en/blog/2026/03/16/002-windows-benchmark-comparing-program-versions/)
