---
title: "Where Unit Tests End and Integration Tests Begin - A Practical Boundary Guide"
date: 2026-03-25 10:00
lang: en
translation_key: unit-test-vs-integration-test-boundary-guide
permalink: /en/blog/2026/03/25/004-unit-test-vs-integration-test-boundary-guide/
tags:
  - Testing
  - Unit Testing
  - Integration Testing
  - Test Design
  - Windows Development
  - C#
  - .NET
author: Go Komura
description: "A practical guide to drawing the boundary between unit tests and integration tests by separating pure logic, formatting, wiring, environment differences, and time-dependent behavior."
consultation_services:
  - id: technical-consulting
    reason: "Deciding where to draw the unit-test / integration-test boundary is a natural topic for design review and test-strategy consulting before implementation starts."
  - id: windows-app-development
    reason: "In Windows applications, boundaries such as files, permissions, COM, and 32-bit / 64-bit behavior affect the test layer directly, so this topic fits implementation planning well."
---

One of the quietly difficult parts of test design is deciding how much should stay in unit tests and how much should move up into integration tests.

The risky extremes are familiar:

- make everything a unit test because you want the suite to run fast
- make everything an integration test because you want it to feel closer to production

The first leads to mock-heavy tests that miss the places where production actually breaks.  
The second leads to tests that are slow, brittle, and expensive to maintain.

In practice, the boundary becomes much clearer if you look at these four questions:

- are we verifying our own logic, or the glue to the outside world?
- does replacing the dependency with an in-memory fake still preserve the meaning of the test?
- are DB / files / HTTP / DI / configuration / framework behavior / OS behavior the real topic?
- do we need to run many input combinations quickly?

Once those four become visible, the boundary between unit tests and integration tests is much easier to draw.

This article is based on Microsoft Learn and Martin Fowler material that was available as of March 2026. [^integration-tests][^unit-best-practices][^test-pyramid]

## 1. The short answer

If we compress the answer into something practical, it looks like this:

1. **Pure logic belongs in unit tests**
2. **Connections, wiring, transformations, and environment differences belong in integration tests**
3. **If either layer could verify it, start with unit tests**
4. **Integration tests should be narrow and purposeful, not broad and heavy**

In one sentence, **unit tests are tests of judgment, and integration tests are tests of connection**.

Things like price calculation, state transitions, input validation, approval rules, and exception classification are usually best kept in unit tests, because they are complete without external resources and let you run many combinations quickly.  
By contrast, SQL execution, JSON / CSV serialization, routing, model binding, DI registration, file locks, permissions, COM registration, 32-bit / 64-bit behavior, and STA / MTA behavior are the kinds of things that can fail the moment they are actually connected, so they are usually safer in integration tests.

Microsoft Learn's [Integration tests in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/test/integration-tests?view=aspnetcore-10.0) also frames integration tests as something to keep focused on important infrastructure scenarios when unit tests are enough for the rest.

## 2. What I mean by unit tests and integration tests

For this article, the split is:

| Level | What it verifies | Typical setup |
| --- | --- | --- |
| Unit test | Correctness of one isolated responsibility | cut off external resources with fakes / mocks / stubs |
| Integration test | Interaction among multiple components, including infrastructure and framework behavior | real DB, real files, real serializer, real host, real pipeline, and so on |
| E2E / functional test | End-to-end user flow across the whole app | deployed app, multiple services, real browser or real process |

In .NET best-practice guidance, a good unit test is described as **fast / isolated / repeatable** and independent of outside factors such as the file system or a database. See [Unit testing best practices for .NET](https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-best-practices) for a clean summary.

Also, integration testing does not only mean "big, cross-process tests."  
Even inside one process, if you connect multiple real components and verify framework or infrastructure behavior, that is already moving into integration-test territory.

For example, when you unit test an ASP.NET Core controller action, you usually keep the scope to the action's own decision logic, while things like `routing`, `model binding`, and `filters` are better left to integration tests. Microsoft documents that split clearly in [Unit test controller logic in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/mvc/controllers/testing?view=aspnetcore-10.0).

## 3. A decision table on one page

Here is the most practical table first:

| What you want to verify | Main test layer | Notes |
| --- | --- | --- |
| Price calculation, discounts, state transitions, input validation | Unit test | You want lots of combinations |
| Exception classification, error-message selection, retry-or-not decisions | Unit test | The meaning is complete without real I/O |
| Repository SQL / ORM conversion, transaction behavior | Integration test | Real DB and real provider behavior matter |
| JSON / XML / CSV serialize / deserialize | Integration test | Fake objects rarely catch wire-format drift |
| Routing, model binding, filters, middleware | Integration test | The framework connection is the point |
| ViewModel or Presenter state transitions in WPF / WinForms | Unit test | The UI does not need to be running |
| Actual binding, dispatcher, control lifecycle, message loop | Integration test or UI test | Framework and thread behavior are the topic |
| File paths, permissions, locking, shared folders, line endings, encodings | Integration test | Real OS and file-system behavior is required |
| COM registration, 32-bit / 64-bit, STA / MTA, DLL loading | Integration test | Environment and process boundaries are the topic |
| App startup and primary-use-case smoke checks | E2E / smoke test | Keep the count low |

The useful mental model is: **which test layer is closest to the reason the code will break in production?**  
That is a better guide than the code location itself.

## 4. What belongs in unit tests

Unit tests are a great fit for **responsibilities that still make sense after you remove the outside world**.

Typical examples:

- business rules
- branching logic
- state transitions
- input validation
- error classification
- retry-policy decisions
- ViewModel / Presenter state changes
- transformation logic itself

The higher the number of combinations, the stronger the case for unit tests.

For example:

- coupon / no coupon
- in stock / out of stock
- first order / repeat order
- admin user / normal user
- valid value / boundary value / invalid value

As those combinations grow, it becomes too expensive to run every one of them through integration tests.  
Unit tests are the right place to split those cases finely.

It also matters that unit tests keep external factors under control:

- inject the current time
- make GUIDs or randomness replaceable
- do not sleep
- do not touch the real DB or real files
- do not go out to the real network

If those rules are in place, tests usually stay much more stable.

### 4.1. When mock counts start to explode

If you try to write a unit test and end up with:

- seven mocks
- a huge setup block
- arrange code longer than the actual assertion
- no clear idea of what you are really checking

then one of two things is usually happening:

1. **the class is doing too much**
2. **you are forcing wiring that should be tested as integration into a unit test**

Mocks are tools for cutting off the outside world. They are **not** tools for proving that the real connection is correct.  
If you blur that line, it becomes very easy to get "all green, still broken in production."

## 5. Four boundaries that usually belong in integration tests

The places that should move up into integration tests usually cluster around **format, wiring, environment, and time**.

### 5.1. The format boundary

By "format" here, I mean things like:

- JSON / XML / CSV
- DB schema and mapping
- nullable / precision / timezone behavior
- enum and date serialization
- encodings and BOM
- line endings

Martin Fowler also points out that boundaries that involve serialize / deserialize are strong integration-test candidates. His [The Practical Test Pyramid](https://martinfowler.com/articles/practical-test-pyramid.html) is a useful reference.

Typical failures include:

- a DTO turned into JSON but field names changed
- CSV quoting or line breaks broke
- `decimal` values got rounded
- `DateTimeOffset` behaved differently in the DB
- `null` and empty string were treated differently than expected

Those are exactly the kinds of mistakes that unit tests often miss.

### 5.2. The wiring boundary

The wiring boundary covers things like:

- DI registration
- configuration binding
- routing
- model binding
- filters
- middleware
- host startup
- event wiring
- WPF binding and command wiring

At this layer, the question is not "is my function correct?"  
The real question is **"are multiple real components connected correctly?"**

ASP.NET Core's own guidance keeps controller-action unit tests focused on the action's decision logic, while `routing`, `model binding`, and `filters` are handled at the integration layer.  
The same idea applies outside web apps too: in desktop apps, ViewModel state transitions belong in unit tests, while actual XAML binding or Dispatcher behavior belongs closer to integration tests.

### 5.3. The environment boundary

This is a big one in Windows development.

- file permissions
- shared folders
- file locking
- renaming from temporary files
- administrator rights
- service-launch permissions
- COM registration
- 32-bit / 64-bit behavior
- STA / MTA behavior
- where a DLL is loaded from

These are all cases where **the OS or runtime environment itself** is the main subject.  
An in-memory fake loses too much meaning here, so integration tests are the safer choice.

In particular, if your system includes existing Windows software or COM / ActiveX pieces, it is very common for things to fail first because of **registration, bitness, thread model, or permissions** rather than because of business logic.  
Those are the kinds of failures that integration tests can catch and unit tests usually cannot.

### 5.4. The time boundary

Another easy one to miss is time and concurrency.

- timeout
- cancellation
- retry behavior in the real runtime
- timer-driven execution
- shutdown behavior of background work
- race conditions
- shutdown ordering

The important thing here is to **separate the decision from the real behavior**.

For example:

- how many retries are allowed
- which exceptions are retryable

can usually be unit tested.  
But things like:

- whether timeout really fires
- whether cancellation really propagates
- whether a timer races with async work
- whether handles or tasks are closed cleanly on shutdown

belong closer to integration tests.

## 6. Common mistakes

### 6.1. Being satisfied with a mocked repository

If you mock the entire repository layer, you still do not know:

- whether the SQL is correct
- whether the transaction behaves correctly
- whether the schema matches
- whether mapping drifts
- whether encodings or precision break

A repository is often less a logic unit and more a **boundary connection point**.  
In that case, integration tests usually deserve more weight than unit tests.

### 6.2. Trying to test the framework from a controller or endpoint unit test

In a controller-action unit test, the things you usually want to verify are:

- branching decisions
- return-value selection
- which dependency gets called

The following are different concerns:

- does the route hit
- does model binding succeed
- does the filter run
- what does the pipeline look like after middleware

Those belong to integration tests.  
If you mix the two, it becomes much harder to tell what actually broke.

### 6.3. Trying to brute-force all input combinations in integration tests

Integration tests are closer to the real world, so they are usually slower.  
That is why it is better to split things as **all the branching combinations in unit tests, representative boundary cases in integration tests**.

Microsoft's integration-test guidance also suggests narrowing DB or file-system tests to representative scenarios such as **read / write / update / delete**, rather than trying to run every possible pattern through the integration layer.

### 6.4. Hitting production SaaS or production APIs from CI

That is usually a bad idea.

Integration tests should feel real, but that does not mean they need to hit production SaaS or production APIs every time.  
Fowler's advice is to use a local service, a fake, or a dedicated test instance instead.

In practice, a good mix is:

- local DB
- temporary directories
- a test host
- a dedicated test environment
- a fake service with a fixed contract

## 7. A practical structure that works well

There is no absolute correct ratio.  
That said, a very reusable structure is a three-layer model:

| Layer | Main test type | What goes here |
| --- | --- | --- |
| Core layer | Heavy unit testing | business rules, state transitions, validation, error classification |
| Boundary layer | Narrow integration tests | DB, files, HTTP, serializer, DI, configuration, COM, permissions |
| Whole-app layer | A small number of smoke / E2E tests | startup checks, major user flows, regression protection for serious failures |

The rule of thumb is simple: **unit tests grow by quantity, while integration tests grow by boundary realism**.

A good way to proceed is:

1. list the boundaries in the app
2. push the logic into shapes that can be separated from the outside world
3. keep at least one happy path and one representative failure path for each boundary
4. keep the end-to-end path small
5. when a bug appears, add the test in **the cheapest layer that can reproduce the bug**

The last step matters a lot.

- if the bug is in the rule, add a unit test
- if the bug is in SQL / binding / configuration / permissions / registration, add an integration test
- if the bug spans startup or deployment, add a smoke or E2E test

That way, test responsibility stays much clearer.

## 8. Five questions to ask when you are unsure

When you are stuck, these five questions help a lot:

1. **If I replace the dependency with an in-memory fake, does the meaning of the test still remain?**
   - If yes, it leans toward a unit test.

2. **When this fails, do I suspect logic first, or connection / configuration first?**
   - If connection or configuration is the real risk, it leans toward an integration test.

3. **Are DB / files / serializer / DI / routes / model binding / OS / permissions / bitness / threads the real subject?**
   - If yes, it leans toward an integration test.

4. **Do I need to run lots of input combinations quickly?**
   - If yes, it leans toward a unit test.

5. **When this test fails, can I immediately tell what I need to fix?**
   - If not, the test layers are probably mixed together.

This is a good way to avoid the sloppy "it feels real, so it must be integration" / "it feels fast, so it must be unit" kind of decision.

## 9. Summary

The boundary between unit tests and integration tests is best decided not by where the code lives, but by **which kind of uncertainty you want to reduce**.

The practical summary is:

- **unit tests are tests of judgment**
- **integration tests are tests of connection**
- **branching combinations belong in unit tests**
- **format, wiring, environment, and time belong in integration tests**
- **end-to-end verification should stay small and selective**

The biggest mistakes to avoid are:

- thinking mocks prove the real connection
- trying to cover every branch through integration tests
- mixing unit-test and integration-test responsibilities

When in doubt, ask: **is the failure really about judgment, or is it about connection?**  
That one question clears up a surprising number of cases.

## 10. Related articles

- [Minimum Windows Application Security Checklist]({% post_url 2026-03-14-001-windows-app-security-minimum-checklist-en %})
- [How Far Can a Windows App Really Be a Single Binary?]({% post_url 2026-03-19-003-windows-single-binary-and-os-dependencies-en %})
- [When Does a Windows App Really Need Administrator Privileges?]({% post_url 2026-03-23-001-windows-admin-privilege-when-required-en %})
- [What Is Reg-Free COM?]({% post_url 2026-03-16-011-what-is-reg-free-com-en %})

## 11. References

[^integration-tests]: Microsoft Learn, [Integration tests in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/test/integration-tests?view=aspnetcore-10.0)
[^unit-best-practices]: Microsoft Learn, [Unit testing best practices for .NET](https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-best-practices)
[^test-pyramid]: Martin Fowler, [The Practical Test Pyramid](https://martinfowler.com/articles/practical-test-pyramid.html)
