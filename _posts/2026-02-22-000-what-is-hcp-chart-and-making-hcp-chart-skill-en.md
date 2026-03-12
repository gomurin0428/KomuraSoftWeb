---
title: "What an HCP Chart Is - Using MakingHCPChartSkill to Render HCP-DSL into Deterministic SVG"
date: 2026-02-22 10:00
lang: en
translation_key: what-is-hcp-chart-and-making-hcp-chart-skill
permalink: /en/blog/2026/02/22/000-what-is-hcp-chart-and-making-hcp-chart-skill/
tags: [HCP, Codex, SVG, Python, Design]
author: Go Komura
description: "An introduction to HCP charts and a practical walkthrough of MakingHCPChartSkill, which renders HCP-DSL text into deterministic SVG output."
---

# What an HCP Chart Is - Using MakingHCPChartSkill to Render HCP-DSL into Deterministic SVG

If you want an HCP chart to work as a real specification, hand-drawn diagrams eventually become hard to maintain.  
`MakingHCPChartSkill` is a skill repository that **interprets HCP-DSL text according to the rules and returns deterministic SVG output**.

## Contents

1. [What an HCP chart is](#1-what-an-hcp-chart-is)
2. [What this repository solves](#2-what-this-repository-solves)
3. [The repository structure at a glance](#3-the-repository-structure-at-a-glance)
4. [A quick 10-minute hands-on example](#4-a-quick-10-minute-hands-on-example)
5. [How to read the sample outputs](#5-how-to-read-the-sample-outputs)
6. [What the skill does internally](#6-what-the-skill-does-internally)
7. [Summary](#7-summary)

---

## 1. What an HCP chart is

An HCP chart is a way to describe processing hierarchically.  
In this repository, the following rules are treated as required:

- The left side expresses **what is being achieved**
- The deeper indentation on the right expresses **how it is achieved**
- The top level carries the main purpose label

That style makes it easier to read the relationship between design intent and implementation detail.

## 2. What this repository solves

Managing diagrams by hand tends to create common problems:

- the diagram drifts away from the specification text
- branching and nesting rules become ambiguous
- reviewing diffs becomes harder than it should be

`MakingHCPChartSkill` solves this by accepting HCP-DSL as JSON input and letting `hcp_render_svg.py` validate and render it.  
The same input produces the same output, which makes the diagrams easier to use in CI and code review.

## 3. The repository structure at a glance

Target repository: `https://github.com/gomurin0428/MakingHCPChartSkill`

- `hcp-chart-svg-v2/SKILL.md`
- `hcp-chart-svg-v2/scripts/hcp_render_svg.py`
- `hcp-chart-svg-v2/references/`
- `hcp-chart-svg-v2/scripts/hcp_xml_to_svg.py` (deprecated)

## 4. A quick 10-minute hands-on example

```powershell
git clone https://github.com/gomurin0428/MakingHCPChartSkill.git
cd .\MakingHCPChartSkill
Copy-Item -Recurse -Force .\hcp-chart-svg-v2 "$HOME\.codex\skills\hcp-chart-svg-v2"
python .\hcp-chart-svg-v2\scripts\hcp_render_svg.py `
  --input .\hcp-chart-svg-v2\references\example-gcd-request.json `
  --output .\hcp-chart-svg-v2\references\example-gcd-response.json `
  --pretty
```

Then extract the SVG from the response JSON:

```powershell
$r = Get-Content -Raw .\hcp-chart-svg-v2\references\example-gcd-response.json | ConvertFrom-Json
$r.svg | Set-Content -NoNewline -Encoding utf8 .\hcp-chart-svg-v2\references\example-gcd.svg
```

## 5. How to read the sample outputs

### Euclidean algorithm (GCD)

- Input: `example-gcd-request.json`
- Output: `example-gcd-response.json`

![GCD sample HCP chart](/assets/images/hcp-chart-skill/example-gcd.svg)

### Order approval flow

- Input: `example-order-approval-request.json`
- Output: `example-order-approval-response.json`

![Order approval sample HCP chart](/assets/images/hcp-chart-skill/example-order-approval.svg)

## 6. What the skill does internally

At a high level, the flow inside `execute_request` looks like this:

```text
\module main
Receive the request and validate the prerequisites
    Validate required JSON fields
Parse the DSL into a structured form
    Interpret modules and hierarchy
    Collect diagnostics
Select the response path based on diagnostics
    If any error exists, return an empty SVG payload
    Otherwise decide whether to render one module or all modules
Return the result
```

The rendered version of that internal flow is shown below.

![MakingHCPChartSkill internal flow](/assets/images/hcp-chart-skill/skill-internal-flow.svg)

## 7. Summary

The strength of an HCP chart is not only that it is easy to read as a diagram, but also that it can be **managed as an executable specification**.  
With `MakingHCPChartSkill`, you can validate HCP-DSL and produce SVG in one consistent flow.
