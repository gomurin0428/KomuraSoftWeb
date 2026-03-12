---
title: "What an HCP Chart Is - How to Use MakingHCPChartSkill to Turn HCP-DSL into Deterministic SVG"
date: 2026-02-22 10:00
lang: en
translation_key: what-is-hcp-chart-and-making-hcp-chart-skill
permalink: /en/blog/2026/02/22/000-what-is-hcp-chart-and-making-hcp-chart-skill/
tags: [HCP, Codex, SVG, Python, Design]
author: Go Komura
description: "An introduction to HCP charts and a practical walkthrough of how MakingHCPChartSkill turns HCP-DSL into deterministic SVG, including the basic idea, repository layout, hands-on steps, and how to read the results."
---

# What an HCP Chart Is - How to Use MakingHCPChartSkill to Turn HCP-DSL into Deterministic SVG

## Contents

1. [What an HCP chart is](#1-what-an-hcp-chart-is)
2. [What this repository solves](#2-what-this-repository-solves)
3. [The quickest way to understand the repository layout](#3-the-quickest-way-to-understand-the-repository-layout)
4. [A 10-minute hands-on example (GCD sample)](#4-a-10-minute-hands-on-example-gcd-sample)
5. [How to read the two sample outputs](#5-how-to-read-the-two-sample-outputs)
6. [What the skill does internally (HCP chart)](#6-what-the-skill-does-internally-hcp-chart)
7. [Summary](#7-summary)

---

If you want an HCP chart to work as **a diagram that can be read as a specification**, hand-drawn diagrams alone eventually become hard to maintain.  
`MakingHCPChartSkill` is a skill repository that **interprets HCP-DSL text according to the specification and returns deterministic SVG output**.

This article starts from the basic idea of HCP charts and goes all the way to actually running the tool.

## 1. What an HCP chart is

An HCP chart is a way to describe processing hierarchically.  
In this repository, the following writing rules are treated as required:

- the left side expresses **what is being achieved** (the purpose)
- the deeper indentation on the right expresses **how it is achieved** (means and detail)
- the top level (level 0) contains the purpose label

By writing the text along those rules, it becomes easier to read the relationship between design intent and implementation detail.

## 2. What this repository solves

Managing diagrams by hand tends to create common problems:

- the diagram drifts away from the specification text
- branching and hierarchy rules become ambiguous
- reviewing diffs becomes harder than it should be

`MakingHCPChartSkill` solves this by accepting HCP-DSL as a JSON request and letting `hcp_render_svg.py` validate and render it.  
Because the same input always produces the same output, the diagrams are easier to use in CI and review.

## 3. The quickest way to understand the repository layout

Target repository: `https://github.com/gomurin0428/MakingHCPChartSkill`

- `hcp-chart-svg-v2/SKILL.md`  
  explains how to use the skill and its constraints, such as not specifying `renderAllModules` and `module` at the same time
- `hcp-chart-svg-v2/scripts/hcp_render_svg.py`  
  the main renderer that validates JSON input, interprets HCP-DSL, and returns SVG responses
- `hcp-chart-svg-v2/references/`  
  specification references, sample request / response files, and sample SVGs
- `hcp-chart-svg-v2/scripts/hcp_xml_to_svg.py`  
  deprecated; use `hcp_render_svg.py` now

## 4. A 10-minute hands-on example (GCD sample)

### 4.1. Clone the repository

```powershell
git clone https://github.com/gomurin0428/MakingHCPChartSkill.git
cd .\MakingHCPChartSkill
```

### 4.2. Place the skill into local Codex

```powershell
Copy-Item -Recurse -Force .\hcp-chart-svg-v2 "$HOME\.codex\skills\hcp-chart-svg-v2"
```

### 4.3. Generate an SVG response from the sample input

```powershell
python .\hcp-chart-svg-v2\scripts\hcp_render_svg.py `
  --input .\hcp-chart-svg-v2\references\example-gcd-request.json `
  --output .\hcp-chart-svg-v2\references\example-gcd-response.json `
  --pretty
```

### 4.4. Extract the SVG from the response JSON

```powershell
$r = Get-Content -Raw .\hcp-chart-svg-v2\references\example-gcd-response.json | ConvertFrom-Json
$r.svg | Set-Content -NoNewline -Encoding utf8 .\hcp-chart-svg-v2\references\example-gcd.svg
```

### 4.5. Notes on input constraints

- when `renderAllModules=true`, you cannot also specify `module`
- if `diagnostics` contains an `error`, `svg` or `svgs` will be empty

## 5. How to read the two sample outputs

### 5.1. Euclidean algorithm (GCD)

- Input example: `example-gcd-request.json`
- Output example: `example-gcd-response.json`

![GCD sample HCP chart](/assets/images/hcp-chart-skill/example-gcd.svg)

The structure separates "accept input," "repeat," and "return the result" into different hierarchy layers, so it is easy to follow both the purpose and the means of the processing.

### 5.2. Order approval flow

- Input example: `example-order-approval-request.json`
- Output example: `example-order-approval-response.json`

![Order approval sample HCP chart](/assets/images/hcp-chart-skill/example-order-approval.svg)

Even for business flows, `fork` and `true/false` let you describe the intent of branching explicitly.

## 6. What the skill does internally (HCP chart)

If you express the processing flow inside `execute_request` in HCP-DSL, it looks like this:

```text
\module main
Receive the request and confirm the prerequisites
    Validate required fields in the input JSON
Parse the DSL and build structure
    Interpret modules and hierarchy
    Collect diagnostics
Choose the response path according to the diagnostic result
    \fork does an error exist
        \true yes
            Return an empty SVG payload
        \false no
            Decide which module or modules to render
            \fork is renderAllModules true
                \true yes
                    Generate SVG for all modules
                    Build a response JSON that contains svgs
                \false no
                    Generate SVG for a single module
                    Build a response JSON that contains svg
Return the result to the caller
```

Here is the diagram produced by actually rendering that DSL:

![HCP chart of the internal flow in MakingHCPChartSkill](/assets/images/hcp-chart-skill/skill-internal-flow.svg)

## 7. Summary

The strength of HCP charts is not only that they look easy to read as diagrams.  
It is that **they can be managed in a form that works as a specification**.

With `MakingHCPChartSkill`, you can validate HCP-DSL and generate SVG output in one consistent flow.

If you want to try it next, a good first step is to take one of your everyday processing specifications, write it in HCP-DSL, and refine it while watching `diagnostics`.

## References

- [MakingHCPChartSkill](https://github.com/gomurin0428/MakingHCPChartSkill)
- [hcp-chart-svg-v2/SKILL.md](https://github.com/gomurin0428/MakingHCPChartSkill/blob/main/hcp-chart-svg-v2/SKILL.md)
- [hcp-chart-svg-v2/scripts/hcp_render_svg.py](https://github.com/gomurin0428/MakingHCPChartSkill/blob/main/hcp-chart-svg-v2/scripts/hcp_render_svg.py)
