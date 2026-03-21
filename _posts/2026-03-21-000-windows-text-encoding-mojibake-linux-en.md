---
title: "Understanding Text Encodings on Windows - Why Mojibake Happens and What Breaks When Linux Gets Involved"
date: 2026-03-21 10:00
lang: en
translation_key: windows-text-encoding-mojibake-linux
permalink: /en/blog/2026/03/21/000-windows-text-encoding-mojibake-linux/
tags:
  - Windows
  - Mojibake
  - UTF-8
  - CP932
  - Linux
  - PowerShell
  - Unicode
author: Go Komura
description: "A practical guide to Windows text encodings, mojibake, and the common failure points that appear when CP932, UTF-8, UTF-16, PowerShell, and Linux locale assumptions collide."
consultation_services:
  - id: technical-consulting
    reason: "When Windows and Linux exchange CSV files, logs, and configuration text, many incidents come from unclear encoding assumptions, so defining the I/O contract early reduces rework."
  - id: windows-app-development
    reason: "Windows business tools often inherit a mix of CP932 and UTF-8 assets, and encoding decisions directly affect maintainability, supportability, and integration quality."
---

Mojibake on Windows does not happen because Japanese text is inherently difficult. In most cases, it happens because **the same byte sequence was decoded with the wrong encoding** or because **misread text was saved again under a different encoding assumption**.

The problem becomes much more visible when Windows and Linux meet. Windows still carries multiple text contexts such as CP932, UTF-8, UTF-16, console code pages, and PowerShell version differences, while Linux tooling usually assumes UTF-8 by default. Assumptions that stayed hidden on one machine start colliding the moment files move across that boundary.

This is less about "handling Japanese correctly" and more about **making the byte-level contract explicit**. In this article, I will sort out why mojibake happens on Windows and which failure modes become common once Linux enters the workflow.

## 1. The practical summary

If you want the short version first, these are the main points:

- **Mojibake is not really a character problem. It is a byte-interpretation problem.**
- **Windows still mixes Unicode paths and legacy code-page paths**, so the assumptions change depending on the tool and API.
- **Linux strongly leans toward UTF-8**, which makes CP932 and UTF-16 surprises show up quickly.
- **A display problem** and **actual data corruption after resaving** are not the same stage of failure.
- **Use UTF-8 as the default for new text**, but keep existing legacy files unchanged until migration is handled as its own task.
- **File encoding, editor encoding, console code pages, and in-memory string representation are separate layers.** If you merge those together, troubleshooting becomes confusing fast.

So when someone says, "The file got mojibake on Windows," that is still far too broad. At minimum, you need to separate:

- the file's actual encoding
- the encoding used when it was saved
- the editor's interpretation
- console input and output code pages
- the application's internal string format
- the locale and expected encoding on the Linux side

## 2. What mojibake actually is

At its core, mojibake is simple:

1. text is **encoded** into bytes
2. those bytes are **decoded** back into text
3. if the encoding and decoding assumptions differ, the resulting text changes

For example, if you save `あ` in UTF-8, the bytes are:

```text
E3 81 82
```

Decode those bytes as UTF-8 and you get `あ`. Decode them under a CP932-oriented assumption and you can end up with something like `縺�`. That is mojibake.

The important point is that the Japanese text did not "mysteriously break." The same bytes were simply interpreted under the wrong rules.

### 2.1 If the bytes are unchanged, recovery may still be possible

Some mojibake is still reversible. If the original bytes are intact, reopening the file with the correct encoding can restore the text.

The dangerous sequence looks like this:

1. a UTF-8 file is misread as CP932
2. the editor shows garbled text
3. someone saves what they see
4. the original UTF-8 byte sequence is lost

At that point, this is no longer just a display problem. It is actual data corruption.

### 2.2 The worse case is forcing unsupported characters into a narrow code page

Another common failure happens when a Unicode string is pushed into a legacy code page such as CP932.

If the target code page cannot represent certain characters, you may see:

- replacement with `?`
- replacement characters such as `�`
- conversion to a different but similar-looking character
- outright conversion failure

This is why the real question is not only "Can I read it?" but also "Can this text make a safe round trip through the chosen encoding?" If characters are lost once, knowing the correct encoding later will not reconstruct them.

## 3. Why Windows gets complicated

Windows is not complicated merely because it is old. It is complicated because **Unicode-era behavior and legacy code-page behavior still coexist**.

### 3.1 Windows APIs still expose both Unicode and code-page paths

At a high level, Windows APIs still come in two broad families:

- `W` APIs: wide-character APIs, effectively UTF-16 based
- `A` APIs: ANSI-style APIs that depend on a code page

That means Windows has always had both a Unicode path and a code-page path. Even on the same machine, assumptions can shift depending on which API or tool touched the data.

### 3.2 "Japanese on Windows" is not a single encoding story

In practice, four text contexts tend to get mixed together:

- **CP932** for legacy Japanese text assets on Windows
- **UTF-8** for newer source files, web assets, and cross-platform workflows
- **UTF-16LE** for parts of the Windows and tooling ecosystem
- **console code pages** for terminal input and output behavior

One thing matters a lot here: running `chcp 65001` does **not** mean your files suddenly became UTF-8. Changing a console code page and identifying the bytes already stored in a file are completely different issues.

Also, many teams casually say "Shift_JIS" when they really mean Windows-flavored Japanese legacy text. In practice, using the name **CP932** is often clearer because it keeps the discussion tied to the Windows context.

### 3.3 File names and file content are separate layers

If Japanese file names look fine on Windows, it is tempting to assume the contents must also be fine. That is a trap.

These are separate layers:

- the layer that handles paths and file names
- the layer that reads file contents
- the layer that displays text in a console

You can handle a Japanese path correctly while still misreading the file body. You can also have a perfectly valid UTF-8 file whose contents only look broken because the console output code page is wrong.

### 3.4 PowerShell and surrounding tools do not share one default

A very common source of trouble is that multiple output paths all feel like "writing text," but they do not produce the same bytes.

Typical examples:

- **Windows PowerShell 5.1** has inconsistent defaults depending on the command path
- some cmdlets and redirection routes produce **UTF-16LE**
- other routes still use the active ANSI code page
- **PowerShell 7 and later** default much more strongly toward UTF-8 without BOM

So "this was output from PowerShell" still does not tell you enough. You need to know **which PowerShell version, which cmdlet, and which write path** produced the file.

## 4. Typical failures once Linux is involved

A workflow that appears to "mostly work" inside Windows often breaks as soon as Linux touches the same files. The reason is simple: Linux tooling usually assumes UTF-8.

### 4.1 Windows writes CP932, Linux reads UTF-8

This is probably the most common failure:

- a legacy Windows app writes CSV, TXT, or log files in CP932
- a Linux script or tool reads the file under a UTF-8 locale assumption
- the result is a decode error, replacement characters, or unreadable Japanese text

The Linux side is not necessarily doing anything wrong. The real problem is that the file crossed the boundary without an explicit encoding contract.

### 4.2 Linux or VS Code creates UTF-8 without BOM, Windows treats it as ANSI

The opposite direction fails too:

- a script or config file is created on Linux or in VS Code as UTF-8 without BOM
- Windows PowerShell 5.1 or another legacy tool does not infer UTF-8 correctly
- only the Japanese or other non-ASCII lines break

This does not mean UTF-8 is bad. It means the reader is not reliably detecting BOM-less UTF-8.

### 4.3 Windows writes UTF-16LE, Linux tools see "not really text"

This is another frequent source of confusion:

- part of Windows PowerShell 5.1 or an older tool writes UTF-16LE
- Linux-side text tools assume a one-byte-oriented UTF-8 text stream
- the file looks binary-like because it contains lots of NUL bytes

UTF-16LE itself is not wrong. It is just a poor fit for many Linux text-processing paths unless that expectation is explicit.

### 4.4 BOM handling creates friction too

A BOM is not the encoding itself, but it still changes real behavior:

- some Windows-side tools are happier when a BOM is present
- some Unix-side tools treat the BOM as extra bytes at the start
- only the first line or first column appears broken, or invisible junk affects comparisons

With UTF-8 in particular, **UTF-8 with BOM and UTF-8 without BOM are different byte sequences**. Saying "we use UTF-8" is not enough for a reliable workflow.

### 4.5 Console output can mislead the investigation

The console path becomes even more confusing across Windows, Linux, WSL, SSH, containers, and CI.

- Windows consoles have input and output code pages
- Linux terminals usually run under a UTF-8 locale
- intermediate layers may transform what you see before you inspect the actual file

That is why "it looked correct in the console" and "the file is correct" are not interchangeable statements.

### 4.6 A simple failure table

| Situation | Actual bytes | Reader assumption | Typical symptom |
| --- | --- | --- | --- |
| CSV saved by a legacy Windows app | CP932 | Linux expects UTF-8 | decode errors, replacement characters, unreadable Japanese |
| File created in Linux or VS Code | UTF-8 without BOM | Windows PowerShell 5.1 treats it as ANSI | only Japanese lines break |
| Output from some Windows PowerShell 5.1 paths | UTF-16LE or ANSI | Linux expects UTF-8 text | NUL bytes, binary-like behavior |
| UTF-8 file with BOM | UTF-8 plus BOM | Unix-side tools expect plain UTF-8 | first-column or first-line glitches |
| Investigation relies only on console display | file bytes and console assumptions differ | reviewer trusts the screen | wrong root-cause diagnosis |

## 5. Four questions that make mojibake investigation faster

When the problem is still fuzzy, these four questions usually shorten the investigation.

### 5.1 What are the actual bytes right now?

Start with the bytes, not the visual impression.

- Is it UTF-8?
- UTF-8 with BOM?
- CP932?
- UTF-16LE?
- Has it already been resaved into a different form?

### 5.2 Who wrote it first, and under what assumption?

Identify the original writer:

- a legacy Windows application
- PowerShell 5.1 or PowerShell 7
- a Linux script
- VS Code
- an Excel-driven export
- middleware, batch jobs, or CI

If this stays vague, encoding guesses become luck.

### 5.3 Who is reading it now, and under what assumption?

The reader matters just as much as the writer:

- is the editor auto-detecting?
- is PowerShell looking for a BOM?
- is Linux following the current locale and assuming UTF-8?
- is a library using its own default encoding?
- is the code explicitly passing `Encoding.UTF8` or `cp932`?

This is where mojibake usually begins.

### 5.4 Has the misread content already been saved?

Finally, determine whether the damage is still only on display or has already become persistent:

- are the original bytes still intact?
- did someone save the garbled text?
- do diffs now contain `?` or `�`?
- has the whole file been rewritten under a different encoding?

Once those four questions are answered, the cause is often much easier to see.

## 6. Operating rules that reduce incidents

For real Windows and Linux mixed environments, a few operating rules prevent a surprising number of accidents.

### 6.1 Prefer UTF-8 for new text files

For new text assets, UTF-8 is usually the safest first choice. But the decision is incomplete if you stop there. You also need a BOM policy.

A practical rule set is:

- **text mostly consumed on Linux**: prefer UTF-8 without BOM
- **scripts or files consumed by Windows legacy tools or Windows PowerShell 5.1**: decide BOM presence explicitly based on the actual consumer
- **cases that really require UTF-16LE**: document that requirement as part of the interface

If the rule is only "standardize on UTF-8," the BOM debate returns later.

### 6.2 Preserve existing legacy files until migration is explicit

If an existing file is CP932, casually converting it to UTF-8 during an unrelated feature change is often risky.

The more stable rule is:

- preserve the original encoding, BOM, and newline style for existing files
- treat encoding conversion as a separate migration task
- verify downstream consumers before a bulk conversion

Many encoding incidents begin with a well-meaning "while I was here, I converted it to UTF-8."

### 6.3 Treat encoding as part of the interface

For CSV files, logs, configuration files, and lightweight text protocols, the encoding is part of the interface contract, not a cosmetic detail.

At minimum, the specification should say:

- whether the file is UTF-8, CP932, or UTF-16LE
- whether UTF-8 files include a BOM
- whether line endings are LF or CRLF
- whether Windows or Linux is the producer or consumer
- whether any intermediate ETL or batch process rewrites the file

"We exchange text files" is not a sufficient specification.

### 6.4 Do not trust defaults when writing

Whether you are in application code or scripts, explicit encodings are safer than defaults.

Risky assumptions sound like this:

- the default save path should be fine
- the OS will probably choose something sensible
- the console displayed it correctly, so the file must be fine
- auto-detection will figure it out

Defaults vary across Windows, Linux, runtimes, editors, and PowerShell versions. If you do not make the write path explicit, success is often accidental.

### 6.5 Validate the console path and the file path separately

This rule is simple but effective:

- verify what the console shows
- reopen the actual file and verify it separately

Even if the terminal display looks fine, the saved file may still be wrong. And even if the display is broken, the file may still be perfectly valid.

### 6.6 Git does not fix encoding mistakes for you

Git tracks bytes. It does not rescue you from bad bytes.

So if you see symptoms like:

- huge diffs even though the business change was small
- strange diffs only on Japanese lines
- only the first line changing
- newline and encoding shifts happening together

then suspect accidental re-encoding before you assume the content itself changed meaningfully.

## 7. A minimum checklist

In mixed Windows and Linux work, this is the kind of checklist worth standardizing early.

### 7.1 Before editing

- What is the current encoding of this file?
- Is there a BOM?
- Are line endings LF or CRLF?
- Did we note two or three representative Japanese lines?
- Do we know whether Windows or Linux is the final consumer?

### 7.2 While editing

- Are we avoiding write paths that hide encoding behavior?
- Are we avoiding blind save operations based on auto-detection?
- Are we being careful with shell redirection and PowerShell output?
- Are we remembering that "looks readable" is not the same thing as "is stored correctly"?

### 7.3 After editing

- Did we reopen the saved file?
- Do representative Japanese lines still look correct on both sides?
- Did `?` or `�` appear in the diff?
- Did the first line or first column break unexpectedly?
- Did this turn into a newline-only or BOM-only diff without business reason?

### 7.4 Tasks that deserve their own migration track

- bulk conversion from CP932 to UTF-8
- standardizing a UTF-8 BOM policy
- auditing scripts that still depend on Windows PowerShell 5.1 behavior
- documenting text flows through CI, containers, WSL, and SSH
- aligning save settings across editors, formatters, and batch tools

## 8. Wrap-up

If you reduce the Windows encoding problem to one sentence, it is this: **Unicode-era behavior and legacy code-page behavior still live side by side**.

Linux makes the tension more visible because many Linux-side paths assume UTF-8, while Windows projects may still contain CP932, UTF-16, console code-page behavior, and PowerShell-version differences.

The five ideas worth remembering are:

- mojibake is a byte-interpretation mismatch
- display breakage and persistent data corruption are different stages
- on Windows, file content, editor behavior, console behavior, and API behavior should be treated as separate layers
- text exchanged with Linux should usually start from a UTF-8-first mindset
- converting existing legacy files should be separated from normal maintenance edits

If you are stuck, come back to four questions:

- What are the bytes?
- Who wrote them?
- Who is reading them?
- Has the misread content already been saved?

Encoding work can look like a minor detail, but between Windows and Linux it is really part of the **I/O contract**. Making that contract explicit prevents far more trouble than trying to guess correctly after the fact.

## 9. References

### Windows / Microsoft

- [Code Pages - Win32 apps | Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/intl/code-pages)
- [Code Page Identifiers - Win32 apps | Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/intl/code-page-identifiers)
- [Unicode in the Windows API - Win32 apps | Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/intl/unicode-in-the-windows-api)
- [Console Code Pages - Windows Console | Microsoft Learn](https://learn.microsoft.com/en-us/windows/console/console-code-pages)
- [chcp | Microsoft Learn](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/chcp)
- [Use UTF-8 code pages in Windows apps | Microsoft Learn](https://learn.microsoft.com/en-us/windows/apps/design/globalizing/use-utf8-code-page)

### PowerShell / VS Code

- [about_Character_Encoding | Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_character_encoding)
- [Understanding file encoding in VS Code and PowerShell | Microsoft Learn](https://learn.microsoft.com/en-us/powershell/scripting/dev-cross-plat/vscode/understanding-file-encoding)

### GNU / Linux locale

- [GNU gettext manual: Header Entry](https://www.gnu.org/software/gettext/manual/html_node/Header-Entry.html)
- [Debian Reference, Chapter 8. I18N and L10N](https://www.debian.org/doc/manuals/debian-reference/ch08.en.html)
