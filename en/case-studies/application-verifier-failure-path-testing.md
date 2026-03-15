---
layout: detail-page
lang: en
translation_key: case-study-application-verifier-failure-path-testing
permalink: /en/case-studies/application-verifier-failure-path-testing/
title: "Failure-Path Test Infrastructure with Application Verifier | KomuraSoft"
page_name: "Failure-Path Test Infrastructure with Application Verifier"
page_eyebrow: "Case Study"
schema_type: "WebPage"
breadcrumb_parent_label: "Case Studies"
breadcrumb_parent_url: "/en/case-studies/"
description: "Case-study page for building failure-path test infrastructure with Application Verifier so future investigation becomes easier."
page_keywords:
  - Case Study
  - Application Verifier
  - Failure-Path Testing
  - Bug Investigation
  - Recurrence Prevention
related_pages:
  - title: "Bug Investigation & Root Cause Analysis"
    url: "/en/services/bug-investigation/"
  - title: "Technical Consulting & Design Review"
    url: "/en/services/technical-consulting/"
  - title: "Case Studies"
    url: "/en/case-studies/"
related_articles:
  - title: "What Application Verifier Is and How to Build Failure-Path Test Infrastructure"
    url: "/en/blog/2026/03/11/003-application-verifier-abnormal-test-foundation-part2/"
  - title: "When an Industrial Camera Control App Suddenly Crashes After a Month (Part 1)"
    url: "/en/blog/2026/03/11/002-handle-leak-industrial-camera-long-run-crash-part1/"
---

## Case Overview

This case was not about shipping a one-off fix.
It was about building **failure-path test infrastructure first**, so that future incidents would be easier to surface and trace.

## Symptom

- ordinary tests did not expose failure-path problems early enough
- low-resource and handle-related failures were hard to reproduce safely
- investigation steps were at risk of becoming too manual and person-dependent

## Constraints

- exhausting real machine resources directly is costly and risky
- native / Win32 boundary failures had to be surfaced earlier than production incidents
- the result needed to remain useful for future investigations, not just the current one

## What We Observed

- Verifier settings such as `Handles`, `Heaps`, and `Low Resource Simulation`
- traces from `!htrace`, page heap, and Verifier stop points
- the relationship between custom lifecycle logs and verifier-side evidence

## How We Narrowed It Down

The work separated what could be understood from normal structured logs and what required Verifier-driven failure-path exposure.
That allowed the investigation to move from passive waiting to **active fault surfacing on a controlled harness path**.

## How We Improved It

- built a reusable failure-path testing foundation
- made handle and heap anomalies observable in shorter loops
- organized the observation points so later design review and recurrence prevention could build on them

## Services This Case Connects To

This case connects directly to **Bug Investigation & Root Cause Analysis** for reproducing and tracing difficult failures, and to **Technical Consulting & Design Review** for deciding how far abnormal-case testing and observation points should be built into the system design.
