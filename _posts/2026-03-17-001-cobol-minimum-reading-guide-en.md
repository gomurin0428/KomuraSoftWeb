---
title: "What You Need to Know Before Reading COBOL Source Suddenly - DIVISION, PIC, COMP-3, COPY, and PERFORM First"
date: 2026-03-17 10:00
lang: en
translation_key: cobol-minimum-reading-guide
permalink: /en/blog/2026/03/17/001-cobol-minimum-reading-guide/
tags:
  - COBOL
  - Legacy Technology
  - Business Systems
  - Maintenance
  - Mainframe
author: Go Komura
description: "A practical minimum reading guide for developers who suddenly need to inspect COBOL source, covering DIVISION, PIC, COMP-3, COPY, PERFORM, fixed format, and external boundaries."
consultation_services:
  - id: technical-consulting
    reason: "This topic fits technical consulting and design review well because understanding existing COBOL assets, identifying safe change points, and planning modernization all begin with being able to read the source calmly."
  - id: bug-investigation
    reason: "When you inherit a COBOL system during incident response or urgent maintenance, tracing where the inconsistency actually starts often fits bug investigation and root-cause analysis directly."
---

Handover work, production incidents, maintenance on a vendor package.  
In situations like that, one day a COBOL source file suddenly lands on your desk.

- the file names end in `.cbl` or `.cpy`
- every identifier is uppercase
- `01`, `05`, `77`, and `88` appear everywhere
- something like `PIC S9(7)V99 COMP-3` shows up and looks half like an accounting package, half like a spell
- and on top of that, the code is full of `COPY`, so the file you opened is not even the whole picture

That is usually the point where your brain turns slightly to dust.

The good news is that the map you need is not actually that large.  
There are dialect and product differences in COBOL, but the structural ideas you need first are surprisingly consistent across real business systems.

This article organizes the **minimum set of concepts for people who suddenly have to read COBOL source**.

## 1. The short answer

Here is the deliberately rough but very practical version.

- COBOL is not just a logic language; it is very strongly a **record-definition language**
- If you read only `PROCEDURE DIVISION`, you usually understand only half the program. Start with `DATA DIVISION`
- `PIC` describes **the shape of an item**
- `USAGE` describes **how the value is represented**
- `COMP-3` means packed decimal, and it appears constantly around money, counts, and rates
- `88` is not really a separate variable; it is a **condition name attached to the value of the previous item**
- `REDEFINES` means **view the same memory in another shape**, not copy it
- If the code uses `COPY`, then the file you opened is not the whole program yet
- If you can follow `PERFORM`, `IF`, `EVALUATE`, `READ`, `WRITE`, and `CALL`, you can usually recover the main flow
- In older source, fixed-format column positions matter. The spacing is not decorative

So if you remember only a small core, remember this:

**DIVISION, PIC, USAGE, COMP-3, REDEFINES, OCCURS, 88, COPY, and PERFORM.**

## 2. Think of COBOL first as a language of data shape

If you come from C# or Java, your instinct is often to follow `if`, loops, and calls first.  
With COBOL, it is usually faster to ask:

**what records enter, what records leave, and what working buffers exist?**

Typical business COBOL often looks like this:

1. read a record from a file or database
2. put it into working storage
3. branch on conditions
4. re-pack the data into another record shape
5. write it out

That is why **layout often comes before algorithm** when you read it.

## 3. Look for the four `DIVISION`s first

COBOL source is first divided into four major parts.

| DIVISION | First thing to look for |
|---|---|
| `IDENTIFICATION DIVISION` | Program name, old comments, origin clues |
| `ENVIRONMENT DIVISION` | Files, external resources, I/O assumptions |
| `DATA DIVISION` | Record definitions, working storage, parameters |
| `PROCEDURE DIVISION` | Actual processing steps |

In practice, these areas are especially important:

- `FILE SECTION`
- `WORKING-STORAGE SECTION`
- `LOCAL-STORAGE SECTION`
- `LINKAGE SECTION`

If you see `LINKAGE SECTION` and `PROCEDURE DIVISION USING ...`, the program may not be stand-alone at all. It may be receiving data from the outside as a subprogram.

## 4. Do not panic about fixed-format layout

In older COBOL, **the column position itself** can have meaning.

At a rough level:

- columns 1 to 6: sequence numbers
- column 7: indicator area
- columns 8 to 11: Area A
- columns 12 to 72: Area B

Column 7 matters especially:

- `*` or `/` means comment line
- `-` means continuation line
- `D` can indicate debugging lines

So what looks like old-fashioned indentation is not always just style.  
If you do not first check whether the file is fixed format or free format, modern editing or formatting can break things in a hurry.

## 5. The minimum you need from `DATA DIVISION`

### 5.1 Level numbers

COBOL builds hierarchy with **level numbers**, not indentation.

At minimum, remember this:

- `01`: top-level record or group
- `02` to `49`: nested levels below that
- `77`: independent elementary item
- `88`: condition name

The important mistake to avoid is thinking `88` is a separate Boolean variable.  
Usually it is just a readable name attached to a value of the preceding item.

### 5.2 `PICTURE` / `PIC`

`PIC` tells you the **shape** of the item.

The most common parts are:

- `X`: character
- `9`: numeric digit
- `S`: signed
- `V`: implied decimal point

For example:

- `PIC X(10)` means 10 characters
- `PIC 9(5)` means a 5-digit numeric field
- `PIC S9(7)V99` means signed, 7 integer digits, 2 decimal digits

The important part here is `V`: it usually means the decimal point is logical, not stored as a literal `.` character.

### 5.3 `USAGE`, `DISPLAY`, `COMP`, `COMP-3`

If `PIC` tells you the shape, `USAGE` tells you **how the value is represented**.

At minimum, keep these in mind:

| Form | Rough meaning | Reading caution |
|---|---|---|
| `DISPLAY` | external decimal / character style representation | on mainframe systems, EBCDIC may still matter |
| `COMP` / `BINARY` | binary representation | visible digit count and internal storage are not the same thing |
| `COMP-3` / `PACKED-DECIMAL` | packed decimal | it looks broken if you try to read it as plain text |

When you see `COMP-3`, the practical reaction is often:

- this is packed decimal
- it is probably money, counts, rates, or another business numeric field
- text-oriented inspection is going to mislead you

### 5.4 `REDEFINES`, `OCCURS`, `COPY`, `FILLER`

These are classic reading traps.

- `REDEFINES` means the same storage is viewed with another layout
- `OCCURS` means a table / array
- `COPY` means the source you opened is incomplete until you inspect the copybook too
- `FILLER` means unnamed storage that still takes space

If you ignore `COPY`, you are very often reading only half the map.

## 6. The minimum you need from `PROCEDURE DIVISION`

### 6.1 `PERFORM`

`PERFORM` is the first structural keyword you want to get comfortable with.

In rough terms, it can mean:

- execute another paragraph or section
- loop until a condition changes
- repeat a fixed number of times

If you can follow the main `PERFORM` chain, you can usually recover the backbone of the program.

### 6.2 `IF`, `EVALUATE`, and scope

Modern COBOL can use explicit terminators like `END-IF`, but older code can still make heavy use of periods as scope boundaries.

That means a single `.` can change:

- where an `IF` really ends
- how far a `PERFORM` body extends
- where control jumps next

When reading older COBOL, it is often safer to watch **periods** rather than end-of-line shape.

### 6.3 `READ`, `WRITE`, `CALL`

In business COBOL, these are part of the main reading path all the time.

- `READ`
- `WRITE`
- `REWRITE`
- `START`
- `CALL`

If you see `CALL 'SUBPGM' USING ...`, the next place to look is usually:

- the callee's `LINKAGE SECTION`
- the callee's `PROCEDURE DIVISION USING`

That is how you recover the data contract between programs.

## 7. Remember that important parts may live outside the source file

COBOL source often does **not** describe the whole world by itself.

Important pieces may sit outside the current file:

- file definitions
- runtime environment
- database access
- transaction environment
- job control

That is why "I still do not know where this file really comes from" is often not a failure of reading skill. It can simply mean you have not found the surrounding context yet.

## 8. A safe reading order

If COBOL suddenly lands in front of you, this order is usually safe:

1. find every `COPY`
2. list the top-level `01` records
3. read `PIC` and `USAGE`
4. search for `READ`, `WRITE`, `REWRITE`, `CALL`, `EXEC SQL`, and `EXEC CICS`
5. follow only the main path first
6. inspect `88` condition names and status fields
7. mark `REDEFINES`, `OCCURS DEPENDING ON`, and `COMP-3` as danger zones
8. if file I/O exists, inspect `FILE STATUS`

That order is much safer than trying to understand the whole source file line by line from the beginning.

## 9. Common places where people get stuck

### 9.1 Thinking `REDEFINES` is a separate variable

It is not.  
It is another interpretation of the same storage.

### 9.2 Thinking `88` is an independent Boolean

It usually is not.  
It is a readable name attached to a specific value of the previous item.

### 9.3 Ignoring `COPY`

That is basically walking into the mountains with half a map folded shut.

Field definitions, common flags, host variables, and shared layouts often live in copybooks.

### 9.4 Thinking `MOVE` is just simple assignment

`MOVE` is not always equivalent to raw memory copy.  
Depending on sender and receiver types, conversion, alignment, padding, truncation, or editing behavior may happen.

### 9.5 Underestimating the period

In older COBOL especially, the `.` is heavier than it first looks.

It can change the real control-flow scope far more than a newcomer expects.

### 9.6 Treating packed decimal or EBCDIC as random corruption

It may not be broken at all.  
It may simply not be plain text, or not be ASCII-based data.

## 10. A quick cheat sheet

| What you found | What to think first |
|---|---|
| `01` | Top-level record or group; start your map here |
| `88` | Named condition for a status or flag field |
| `PIC X(...)` | Character field |
| `PIC 9(...)` / `S9(...)V...` | Numeric field; check digits and decimal position |
| `COMP` | Binary representation |
| `COMP-3` | Packed decimal; often money or counts |
| `REDEFINES` | Same storage, different interpretation |
| `OCCURS` | Table / array |
| `OCCURS DEPENDING ON` | Variable-length table |
| `FILLER` | Unnamed storage that still takes space |
| `COPY` | You need the copybook too |
| `PERFORM` | Main structural flow |
| `READ` / `WRITE` / `REWRITE` | File I/O |
| `EXEC SQL` | Database boundary |
| `EXEC CICS` | Transaction boundary |
| `FILE STATUS` | I/O result code |

## 11. Wrap-up

COBOL is not difficult just because it is old.

What makes it feel hard at first is that **data definition, external files, and runtime context are tightly connected**, so the entrance can be easy to miss.

The minimum reading set is still fairly compact:

- use `DIVISION` to build the map
- read `DATA DIVISION` before chasing logic
- use `PIC` and `USAGE` to understand field shape
- mark `COMP-3`, `REDEFINES`, `OCCURS`, `88`, and `COPY`
- follow `PERFORM`, `READ`, `WRITE`, and `CALL`
- treat `FILE STATUS`, `EXEC SQL`, and `EXEC CICS` as external boundaries
- never underestimate the `.` in older code

Once that becomes visible, COBOL stops looking like some mysterious ancient spellbook and starts looking like what it often is:

**a language for business records and structured data movement.**

## 12. References

- IBM: [Reference format](https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=structure-reference-format)
- IBM: [Area A or Area B](https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=format-area-area-b)
- Micro Focus: [Fixed Format](https://www.microfocus.com/documentation/visual-cobol/vc60/DevHub/HRLHLHINTR01U904.html)
- IBM: [Level-numbers](https://www.ibm.com/docs/en/cobol-zos/6.3.0?topic=entry-level-numbers)
- IBM: [Format 2: condition-name value](https://www.ibm.com/docs/en/cobol-zos/6.3.0?topic=vc-format-2)
- IBM: [Examples: numeric data and internal representation](https://www.ibm.com/docs/en/cobol-zos/6.3.0?topic=data-examples-numeric-internal-representation)
- IBM: [PACKED-DECIMAL (COMP-3)](https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=v6-packed-decimal-comp-3)
- IBM: [REDEFINES clause](https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=entry-redefines-clause)
- IBM: [OCCURS DEPENDING ON clause](https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=clause-occurs-depending)
- IBM: [PERFORM statement](https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=statements-perform-statement)
- IBM: [FILE STATUS clause](https://www.ibm.com/docs/en/cobol-linux-x86/1.2.0?topic=section-file-status-clause)
- IBM: [Using file status keys](https://www.ibm.com/docs/en/cobol-zos/6.4.0?topic=operations-using-file-status-keys)
- IBM: [Scope terminators](https://www.ibm.com/docs/en/cobol-aix/5.1.0?topic=division-scope-terminators)
- IBM: [Elementary move rules](https://www.ibm.com/docs/en/cobol-zos/6.3.0?topic=moves-elementary-move-rules)
- IBM: [Coding COBOL programs to run under CICS](https://www.ibm.com/docs/en/cobol-zos/6.3.0?topic=cics-coding-cobol-programs-run-under)
