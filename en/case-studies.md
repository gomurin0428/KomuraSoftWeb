---
layout: detail-page
lang: en
translation_key: case-studies-hub
permalink: /en/case-studies/
title: "Case Studies | KomuraSoft"
page_name: "Case Studies"
page_eyebrow: "Case Studies"
schema_type: "CollectionPage"
description: "A collection page for KomuraSoft case studies covering defect investigation, communication stall analysis, long-run failures, and abnormal-case test infrastructure."
page_keywords:
  - Case Studies
  - Defect Investigation
  - Long-Run Failures
  - Communication Issues
related_pages:
  - title: "Company"
    url: "/en/company/"
  - title: "Go Komura Profile"
    url: "/en/profile/go-komura/"
  - title: "Topics"
    url: "/en/topics/"
related_articles:
  - title: "How We Isolated Multi-Second Communication Stalls in an Industrial Camera System"
    url: "/en/blog/2026/03/11/001-tcp-retransmission-rfc1323-industrial-camera/"
  - title: "How We Traced a Long-Run Crash to a Handle Leak"
    url: "/en/blog/2026/03/11/002-handle-leak-industrial-camera-long-run-crash-part1/"
  - title: "Failure-Path Test Infrastructure with Application Verifier"
    url: "/en/blog/2026/03/11/003-application-verifier-abnormal-test-foundation-part2/"
---

## What these case studies focus on

KomuraSoft case studies lean less toward ordinary bug fixing and more toward difficult investigation work:
field-only failures, communication problems that come and go, issues that appear only after long uptime, and the test infrastructure needed to make those problems traceable.

Typical examples include:

- isolating the real cause behind multi-second communication stalls
- tracing crashes that appear only after weeks of operation
- building abnormal-case test foundations that expose leaks and failure paths earlier

## Case study 1: Breaking down where communication stall time really comes from

In an industrial camera control system, a rare multi-second stop in communication was separated into retransmission wait behavior and OS-side communication conditions.
That made it possible to judge that the RFC1323 timestamp setting was materially involved in the stall profile.

## Case study 2: Turning a long-run crash into a leak investigation

For a crash that appeared only after about one month of continuous operation, the work centered on narrowing the observation points and making the logging useful enough to turn the issue into a handle-leak investigation.
This is a good example of investigation work where the key step is deciding what can be observed reliably.

## Case study 3: Building the failure-path foundation first

Using Application Verifier, we built a foundation that made unexpected failure paths easier to trace.
That kind of work is less about a one-off patch and more about making future investigations cheaper and more reliable.
