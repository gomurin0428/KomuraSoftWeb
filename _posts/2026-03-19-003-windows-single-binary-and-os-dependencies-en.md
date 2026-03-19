---
title: "How Far Can a Windows App Really Be a Single Binary? What Fits in One EXE and What Still Depends on Windows"
date: 2026-03-19 10:00
lang: en
translation_key: windows-single-binary-and-os-dependencies
permalink: /en/blog/2026/03/19/003-windows-single-binary-and-os-dependencies/
tags:
  - Windows
  - Deployment
  - Single Binary
  - .NET
  - C++
  - WebView2
  - WinUI
author: Go Komura
description: "A practical guide to what can really be bundled into one Windows executable, where OS dependencies remain, and how to decide before shipping."
consultation_services:
  - id: windows-app-development
    reason: "Windows application delivery becomes much easier when the team separates file count, runtime bundling, installer requirements, and OS-level integration before choosing the technology stack."
  - id: technical-consulting
    reason: "Requests such as 'make it a single binary' usually need a design review that separates deployment shape from operating-system dependencies and registration requirements."
---

This article grew out of the following post.

<script type="module" src="https://cdn.jsdelivr.net/npm/nostr-widgets/dist/nostr-widgets.js"></script><nostr-note data='{"content":"このまえ、雑談で「Windowsではどこまでをシングルバイナリと言っていいのか、NTDLLの先はどうか」みたいな話をしてたけど面白かった","created_at":1773882483,"id":"00ca8ead5c8600957b7bd4678a73673859b3cb3155ec887948b7498dbc2b7f5c","kind":1,"pubkey":"101b30ee88c27a13de68bf7c8c06368ea3e3e837641595c18675677d18a46a45","sig":"a980bf6a40e66054b927da92164e0be371555022a92f7bfa49cf386189da9e3633da7a163b46a14f0276693f91ab575a3ad72c68791807939ad83be23deefe17","tags":[["client","Damus"]]}'></nostr-note>

"If possible, we want to distribute it as one file" is a very normal request in Windows work. Internal tools, device-integration utilities, offline environments, field support tools, and teams that want to avoid full installers all push in that direction.

The problem is that the phrase "single binary" starts to blur several different goals together:

- making the deliverable one file
- avoiding preinstalled .NET or Visual C++ runtime requirements
- making the app work without an installer or admin privileges
- reducing differences across target Windows environments

Those are not the same thing.

The most practical statement is this:

> **You can often push a Windows app surprisingly far toward a single EXE.**  
> **But you cannot remove Windows itself from the dependency story.**

This article organizes that boundary in a practical way.

## 1. The short answer

If we compress the reality aggressively, it looks like this:

- ordinary desktop executables can often be pushed quite far toward single-binary delivery
- but **being one EXE** and **not depending on the target Windows environment** are completely different things
- once you include shell integration, Windows services, drivers, WebView2, or some WinUI 3 deployment shapes, the real problem becomes less about file count and more about **what must be registered, installed, or already present on Windows**
- the most important practical step is to separate these goals explicitly:
  - one deliverable
  - no separate runtime install
  - no installer
  - lower OS-side dependency

In other words:

- one deliverable: often very achievable
- bundled runtime: often achievable
- xcopy-style deployment: depends on app type
- zero Windows dependency: impossible

## 2. "Single binary" really means several different levels

### 2.1 Level A: the deliverable is one file

This is the surface-level meaning:

- one file to send
- one file to drop on a USB stick
- one file placed on the target machine

That is only about the visible delivery unit. An app can still extract things temporarily or depend heavily on the operating system and still satisfy this level.

### 2.2 Level B: no separate language runtime installation

This is where questions such as these appear:

- static linking in native C/C++
- self-contained deployment in .NET
- single-file publishing in .NET
- Native AOT in .NET

At this level, the app starts to feel much more self-contained.

### 2.3 Level C: no installer and no OS-side registration

This is where many conversations become harder.

A standalone EXE may run fine by itself, but the story changes if the app needs:

- shell extensions
- Windows service registration
- URL protocol registration
- file associations
- drivers
- components hosted by Explorer or Office

Here the main issue is no longer "how many files do we ship?" but "what does Windows need to know about this component?"

### 2.4 Level D: no dependence on the target Windows environment

This is not realistic on Windows.

A Windows application still depends on:

- the Windows API surface
- the system loader
- system DLLs
- OS security and privilege rules
- device and service infrastructure

Single-binary packaging can reduce application-side deployment complexity. It does not turn Windows into a self-contained part of the application.

## 3. Where single-binary delivery is comparatively realistic

These are the kinds of apps that are usually easier to push toward one EXE:

- standalone desktop tools
- internal business apps that own both UI and processing
- communication, monitoring, logging, and device-control utilities
- apps that do not need Explorer or Office hosting
- apps that do not require browser runtime integration

For these, you can often keep together:

- your own code
- resources
- manifest data
- default configuration
- templates
- some third-party libraries
- the language runtime itself

And even when you do not literally force everything into one file, **app-local deployment** is still a very practical Windows pattern:

- `app.exe`
- or `app.exe` plus a few adjacent DLLs
- no heavy installer
- no administrator requirement

That can be a better operational compromise than over-optimizing for a strict one-file result.

## 4. Windows dependencies that do not disappear

### 4.1 OS version and architecture

A single EXE still has a target environment:

- which Windows version is supported
- whether Windows Server is included
- whether x64 or Arm64 matters
- which API baseline you expect

Those decisions still need to be explicit.

### 4.2 System DLLs and loader behavior

Even if your application ships as one executable, it still uses the operating system's loader and system components:

- `kernel32.dll`
- `user32.dll`
- `advapi32.dll`
- COM infrastructure
- service infrastructure

The operating system remains part of the real runtime.

### 4.3 Security and registration model

These do not disappear just because the app is packaged tightly:

- UAC
- ACLs
- service control manager
- registry usage
- driver-signing rules

If the app needs those subsystems, the packaging shape does not remove that need.

### 4.4 Host or runtime dependencies

The design gets much more dependent on external pieces when it is hosted or runtime-driven:

- WebView2 means dealing with WebView2 Runtime
- some Windows App SDK / WinUI deployment shapes introduce extra packaging considerations
- shell extensions require Explorer-facing registration

This is why UI and integration technology choices directly affect deployment complexity.

## 5. Technology-by-technology reality

### 5.1 Native C/C++

Native C/C++ is one of the friendlier places for single-binary goals because static-linking choices exist. For ordinary standalone tools, it can work very well.

But even there, the important real decisions are often:

- static versus dynamic CRT strategy
- whether third-party DLLs can stay app-local
- how tightly you can define target CPU and OS support

### 5.2 .NET

.NET gives you several useful knobs:

- framework-dependent
- self-contained
- single-file
- Native AOT

These help a lot with the shape of the deliverable. But they do not remove Windows-side dependencies such as OS APIs, loader behavior, architecture targeting, or subsystem requirements.

### 5.3 WebView2

Once WebView2 enters the picture, the real question stops being "can I make the EXE one file?" and becomes:

- do I rely on an existing WebView2 Runtime?
- do I use Evergreen?
- do I ship a fixed version?
- how do I handle offline environments?

That is a deployment-contract question more than a file-count question.

### 5.4 WinUI 3 / Windows App SDK

WinUI 3 can absolutely be the right technical choice, but it changes deployment assumptions. If one-file delivery is a hard requirement, UI technology selection itself should be reviewed early rather than late.

## 6. Areas where OS-side registration is the main issue

### 6.1 Shell extensions

Explorer-loaded shell extensions are not really part of the same problem space as a normal standalone EXE. They are about **how Windows loads and recognizes the component**.

### 6.2 Windows services

A service executable may itself be just one file, but deployment still includes:

- service registration
- account and privilege decisions
- recovery policy
- update procedure

So for services, installation design matters more than pure binary count.

### 6.3 Drivers

Drivers are even more explicit:

- INF
- signing
- package structure
- installation path

This is not a "squeeze it into one EXE" problem. It is a "fit the Windows driver model correctly" problem.

## 7. A practical decision table

| Target | One-EXE reality | What to decide first |
| --- | --- | --- |
| Standalone Win32 / C++ tool | High | static link strategy, target OS and architecture |
| Standalone WinForms / WPF tool | High | self-contained, single-file, Native AOT fit |
| WinUI 3 / Windows App SDK app | Medium | deployment mode and additional dependencies |
| WebView2 desktop UI | Low to medium | WebView2 Runtime strategy |
| Explorer context-menu or preview integration | Low | COM and registry registration |
| Windows service | Medium | SCM registration, privileges, update path |
| App bundled with a driver | Low | INF, signing, installation flow |

The most important lesson in that table is this:

**binary count and deployment responsibility are different things.**

## 8. What to decide before implementation

If single-binary delivery matters, these questions should be answered early.

### 8.1 What exactly do you want to make "single"?

- one deliverable?
- no separate runtime install?
- no installer?
- easier offline update?

The answer changes the technology choice.

### 8.2 What is the minimum supported Windows target?

Single-file and Native AOT outputs are still platform-specific. If the supported OS and architecture stay vague for too long, the project tends to discover incompatible assumptions late.

### 8.3 What is bundled, and what is assumed?

Writing this down helps a lot:

- bundled with the app
  - main EXE
  - your own DLLs
  - configuration templates
  - self-contained runtime
- left to Windows
  - system DLLs
  - core OS APIs
  - SCM / registry / Explorer
  - driver infrastructure
- external prerequisites
  - WebView2 Runtime
  - VC++ Redistributable
  - Office / Excel
  - device-specific drivers

### 8.4 If you want stronger single-binary behavior, reduce host integration

This is one of the most effective levers:

- prefer a normal EXE over a shell extension
- avoid service installation unless it is truly needed
- avoid browser-runtime dependence if possible
- keep COM usage inside your own process if you can

Reducing OS-hosted integration usually moves you much closer to practical single-binary delivery.

## 9. Wrap-up

Windows allows a lot of progress toward single-binary delivery, but the right mental model is still this:

> **You can make the application one EXE.**  
> **You cannot make the operating system disappear from the application's dependency graph.**

The five points worth remembering are:

- ordinary standalone executables can often be delivered in a very compact form
- static-linking in C/C++, .NET single-file, and Native AOT are all useful tools
- OS version, architecture, system DLLs, and Windows security model still remain
- shell extensions, services, drivers, WebView2, and some WinUI cases are really about registration or external runtime assumptions
- success depends on defining what "single" means before implementation starts

If one-file delivery is a hard priority, choosing technologies with **lower operating-system integration pressure** usually matters more than squeezing one more DLL into the package.

## 10. References

- Microsoft Learn, [Create a single file for application deployment](https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview)
- Microsoft Learn, [Native AOT deployment overview](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)
- Microsoft Learn, [C runtime (CRT) and C++ standard library (STL) lib files](https://learn.microsoft.com/en-us/cpp/c-runtime-library/crt-library-features?view=msvc-170)
- Microsoft Learn, [Dynamic-link library search order](https://learn.microsoft.com/en-us/windows/win32/dlls/dynamic-link-library-search-order)
- Microsoft Learn, [Targeting your application for Windows](https://learn.microsoft.com/en-us/windows/win32/sysinfo/targeting-your-application-at-windows-8-1)
- Microsoft Learn, [Creating Registration-Free COM Objects](https://learn.microsoft.com/en-us/windows/win32/sbscs/creating-registration-free-com-objects)
- Microsoft Learn, [Registering Shell Extension Handlers](https://learn.microsoft.com/en-us/windows/win32/shell/reg-shell-exts)
- Microsoft Learn, [CreateServiceW function](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-createservicew)
- Microsoft Learn, [Overview of INF Files](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/overview-of-inf-files)
- Microsoft Learn, [Windows driver signing tutorial](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/windows-driver-signing-tutorial)
- Microsoft Learn, [Distribute your app and the WebView2 Runtime](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution)
- Microsoft Learn, [Windows App SDK deployment guide for self-contained apps](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps)
