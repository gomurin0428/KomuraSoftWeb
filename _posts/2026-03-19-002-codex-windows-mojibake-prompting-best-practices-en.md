---
title: "Best Practices for Avoiding Mojibake with Codex on Windows - Clear Prompting Before Environment Tweaks"
date: 2026-03-19 10:00
lang: en
translation_key: codex-windows-mojibake-prompting-best-practices
permalink: /en/blog/2026/03/19/002-codex-windows-mojibake-prompting-best-practices/
tags:
  - Codex
  - Windows
  - Mojibake
  - UTF-8
  - CP932
  - AI Coding
author: Go Komura
description: "A practical guide to reducing mojibake accidents with Codex on Windows by defining safe read, write, and verification rules before editing files."
consultation_services:
  - id: technical-consulting
    reason: "When Windows development assets mix CP932, UTF-8, logs, CSV files, and generated text, AI usage becomes much safer if the team defines explicit read, write, and stop rules first."
  - id: windows-app-development
    reason: "Windows business tools often depend on Japanese text files, CSV exports, logs, and configuration files, so avoiding accidental re-encoding directly affects maintainability and delivery quality."
---

When you let Codex work with Japanese text files on Windows, the first thing that usually helps is not perfect editor or shell alignment. It is **telling Codex exactly how to read, how to write, and when to stop**.

The common failure cases are familiar:

- UTF-8, CP932, and UTF-16 files all exist in the same repository
- the text looks readable on screen, but the byte interpretation is already wrong
- a "small edit" silently resaves an existing file in a different encoding
- the real breakage happens in CSV, TXT, logs, Markdown, or config files rather than in source code
- a quick shell output gets copied into a real file and the damage becomes permanent

Codex works better when it is treated less like a one-off chatbot and more like a teammate that follows project rules. If the team already uses `AGENTS.md`, text-encoding rules are exactly the kind of thing that should be written down once and reused.

This article organizes a practical set of instructions for using Codex safely with Japanese text files on Windows.

## 1. The short answer

The most effective move is to define a **text-encoding workflow** before the editing task begins.

The rules that usually help the most are:

- before Codex reads an existing Japanese text file, make it check likely encoding, BOM presence, and newline style
- if mojibake is suspected, do not let it save the file on guesswork
- preserve the original encoding, BOM, and newline style for existing files
- let new files follow the repository convention, typically UTF-8 based
- only use write paths that give explicit encoding control
- after writing, reopen the file and verify representative Japanese lines

In practice, the short version looks like this:

- inspect before reading
- forbid speculative saves
- preserve existing files, standardize only new ones
- avoid ambiguous write paths
- verify after saving

The dangerous instructions are things like:

- "fix the mojibake"
- "make everything UTF-8"
- "export a CSV"
- "just align it somehow"
- "save it and see"

The problem with those prompts is that they do not tell Codex **where it is supposed to stop**.

## 2. Why Windows makes this easier to break

The root problem is usually not that Codex cannot handle Japanese. It is that Windows projects often contain **multiple encodings and multiple write paths at the same time**.

A real repository may include:

- newer source files and Markdown in UTF-8
- older CSV, TXT, logs, and configuration files in CP932
- some generated outputs in UTF-16
- different save paths through editors, shells, export tools, and office-driven workflows
- both LF and CRLF line endings

In that state, one incorrect interpretation is enough for Codex to treat unreadable text as if it had already understood it. Once the file is saved in that state, the problem stops being a display issue and becomes actual content damage.

That is why mojibake prevention is mainly an **I/O procedure problem**, not a vague language-quality problem.

## 3. Rules worth fixing in advance

### 3.1 Inspect encoding, BOM, and newlines before reading

The first rule should be explicit:

> Before reading or editing an existing text file that may contain Japanese, first determine likely encoding, BOM presence, and newline style.

This changes the workflow from "read the text first" to "understand the file conditions first."

### 3.2 Never allow speculative saves on suspicious files

This is the most important safety rule.

> If mojibake is suspected, keep the file read-only until the interpretation is credible.

If the agent cannot confidently read the file, it should not be allowed to save it.

### 3.3 Preserve existing files; standardize new files

"Convert everything to UTF-8" sounds clean, but it is often too destructive as part of an ordinary edit task.

A more stable operating rule is:

- preserve the original encoding for existing files
- let new files follow repository convention
- treat encoding migration as its own explicit task

### 3.4 Avoid ambiguous write paths

A lot of Windows encoding accidents come from casual output paths:

- shell redirection
- quick convenience commands
- temporary generated output copied into a real file

Those paths often do not make encoding behavior explicit, so they are poor defaults for mixed-encoding repositories.

### 3.5 Reopen and verify after writing

"The save succeeded" and "the file is intact" are not the same thing.

After writing, Codex should reopen the file and check representative Japanese lines for signs such as:

- replacement characters
- suspicious growth of `?`
- unintended BOM changes
- unintended newline-only diffs
- unchanged business text being silently damaged

### 3.6 Report anomalies before forcing a repair

For text-encoding incidents, stopping early is often better than forcing a repair.

Typical stop signals:

- increasing `U+FFFD`
- increasing `?`
- unexpected BOM changes
- huge newline-only diffs
- large unnatural changes only on Japanese lines

## 4. A short instruction block that works well

For day-to-day tasks, something this short is often enough:

```text
In this task, prioritize avoiding text-encoding accidents.

- Before reading an existing file that may contain Japanese, check likely encoding, BOM presence, and newline style.
- If mojibake is suspected, do not save based on guesswork.
- Preserve encoding, BOM, and newline style for existing files.
- Follow repository convention for new files.
- Use only write paths with explicit encoding control.
- After writing, reopen the file and verify representative Japanese lines.
- If replacement characters, suspicious `?`, unintended BOM changes, unintended newline conversion, or whole-file diffs appear, stop and report.
```

If the target files are known, adding one more line helps even more:

```text
Target files: <paths> / Representative strings: "<examples>"
```

Representative strings give Codex a concrete set of text that must survive unchanged.

## 5. A practical `AGENTS.md` template

If the same warning has to be repeated often, it belongs in `AGENTS.md`. A practical template looks like this:

```md
# Text Encoding Rules

## Scope
This repository may contain Japanese text and mixed legacy encodings.
Avoid mojibake and accidental re-encoding above all else.

## Mandatory Rules
- Before reading or editing an existing text file that may contain Japanese, first determine:
  - likely encoding
  - BOM presence
  - newline style
- If mojibake is suspected, do not save the file until the encoding interpretation is credible.
- Preserve the original encoding, BOM, and newline style for existing files.
- Treat "convert to UTF-8" as a separate, explicit task.
- New files should follow repository convention. If there is no clear rule, prefer UTF-8 and state whether BOM is used.
- Do not use ambiguous write paths by default, such as shell redirection or convenience commands without explicit encoding control.
- After writing, reopen the file and verify representative Japanese lines.
- If any of the following appears, stop and report:
  - replacement characters
  - unexpected `?`
  - unintended BOM change
  - unintended newline conversion
  - whole-file diffs without a business reason

## Reporting Format
For each changed text file, report:
- path
- detected or preserved encoding
- BOM presence
- newline style
- how verification was performed
- whether representative Japanese text remained intact
```

Two lines are especially powerful:

- `If mojibake is suspected, do not save ...`
- `Treat "convert to UTF-8" as a separate, explicit task.`

Those two rules alone prevent a surprising number of accidents.

## 6. Bad prompts and better prompts

The wording matters a lot in this kind of task.

| Weak prompt | Better prompt |
| --- | --- |
| Fix the mojibake | First determine whether the file itself is damaged or whether this is only a display-side issue. Do not save on guesswork. |
| Make everything UTF-8 | Preserve existing files as they are, use repository convention only for new files, and treat conversion as a separate task. |
| Export a CSV | Match the expected encoding, make the write path explicit, and verify Japanese columns after output. |
| Fix what looks readable | If you are not confident in the interpretation, do not save; report the candidates and reasoning first. |
| Just align it somehow | Do not change BOM, newline style, or encoding without explicit reason; keep diffs limited to the intended business change. |

The pattern is consistent: good prompts specify both **the preconditions before editing** and **the checks after saving**.

## 7. Review checklist

After Codex finishes, it helps if the reviewer checks:

- whether encoding, BOM, and newline handling was reported for each file
- whether Japanese lines changed more than the business change requires
- whether there are suspicious newline-only diffs
- whether replacement characters or unusual `?` have appeared
- whether CSV, log, or config structure has drifted
- whether the diff includes unrelated whole-file rewriting

For encoding safety, catching suspicious diffs early is more valuable than pushing one more edit through.

## 8. Wrap-up

On Windows, the first step toward safer Japanese text editing with Codex is usually not environment perfection. It is **making the editing rules explicit**.

The five ideas worth remembering are:

- inspect encoding, BOM, and newlines before reading
- do not allow speculative saves when mojibake is suspected
- preserve existing files and standardize only new ones
- avoid ambiguous write paths
- reopen and verify representative Japanese lines after saving

And if you have to say that repeatedly, write it into `AGENTS.md`.

Mojibake prevention is not really about saying "please handle Japanese carefully." It is about **defining the conditions under which saving is allowed, and the conditions under which the agent must stop**.

## 9. References

- OpenAI Codex docs, [Best practices](https://developers.openai.com/codex/learn/best-practices/)
- OpenAI Codex docs, [Custom instructions with AGENTS.md](https://developers.openai.com/codex/guides/agents-md/)
- OpenAI Codex docs, [Windows](https://developers.openai.com/codex/windows)
