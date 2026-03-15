---
title: "What to Check Before Migrating .NET Framework to .NET - A Practical Premigration Checklist"
date: 2026-03-15 16:00
lang: en
translation_key: dotnet-framework-to-dotnet-premigration-checklist
permalink: /en/blog/2026/03/15/003-dotnet-framework-to-dotnet-premigration-checklist/
tags:
  - .NET
  - .NET Framework
  - C#
  - Modernization
  - Windows Development
  - Migration
author: Go Komura
description: "A practical premigration checklist for moving from .NET Framework to modern .NET, covering project types, unsupported technologies, NuGet dependencies, PackageReference, SDK-style projects, ASP.NET, WPF, WinForms, WCF, EF6, configuration, CI/CD, and operations."
consultation_services:
  - id: legacy-asset-migration
    reason: "This topic maps directly to legacy modernization work where Web Forms, WCF, COM or ActiveX, old NuGet conventions, and Windows-only assumptions all need to be untangled before implementation starts."
  - id: technical-consulting
    reason: "If the main need is to decide migration scope, staging strategy, and how much Windows-only behavior to keep for now, this fits technical consulting and design review well."
---

Changing `TargetFramework` to `net10.0`, updating a few NuGet packages, and calling the migration done would be a very calm story.

In real projects, it is usually not that calm.

Old `.NET Framework` systems often carry assumptions that nobody thinks about until migration starts: `System.Web`, WCF, Web Forms, old `packages.config`, `web.config.install.xdt`, native DLLs, COM or ActiveX, third-party controls that only behave at design time, hidden `x86` assumptions, designer-dependent ResX usage, and older serializers.

That is why the most important part of a .NET Framework to .NET migration is often not the implementation phase. It is the inventory phase before implementation starts.  
If you can split the problem into clear tracks early, the migration stops being one large gamble and starts becoming a series of deliberate decisions.

This article is aimed at **existing .NET Framework 4.x business applications** that are being considered for migration to **current .NET**. The main targets are:

- class libraries
- console applications
- Windows services
- WinForms / WPF applications
- ASP.NET Framework applications, including MVC, Web API, and Web Forms
- applications that use WCF
- applications that use EF6

The point-in-time for this article is **March 15, 2026**. Support timelines and official tooling guidance can change, so if you are reading this later, check the current Microsoft documentation as well.

## 1. Short version

Here are the conclusions that are hardest to avoid in practice.

- **Clean up the .NET Framework side first.** Microsoft's own premigration guidance pushes the same direction: raise the Framework target to **4.7.2 or later**, move toward `PackageReference`, move toward SDK-style projects, and update dependencies before attempting the real port.
- Difficulty is driven more by the **application model** than by total code size. Class libraries and console tools are often manageable. **ASP.NET Framework, Web Forms, WCF servers, and Workflow Foundation** tend to be much heavier.
- **WinForms and WPF can move to .NET and still remain Windows-only.** If that expectation is wrong, teams often discover too late that the migrated app still cannot move into Linux containers or cross-platform hosting.
- **ASP.NET Framework to ASP.NET Core is effectively an architecture migration.** Small systems can sometimes move in one shot, but larger production systems are usually safer with staged migration.
- **WCF and EF6 do not always have to move on the same schedule as the runtime.** WCF clients have supported packages on modern .NET, and EF6 can sometimes remain in place while the runtime moves first and EF Core comes later.
- **AppDomain creation, .NET Remoting, CAS, COM+, Workflow Foundation, and BinaryFormatter dependency are red flags.** If you find them late, effort usually explodes late.
- **`packages.config`, `install.ps1`, XDT transforms, content assets, native DLLs, COM or ActiveX, and hidden `x86` assumptions** are exactly the kinds of things that still fail after a successful build, especially at runtime or design time.
- As of **March 2026**, **.NET 10 is the current LTS**. For new migration landing zones, the current LTS is usually the clean default.
- **A migration without tests, baseline measurements, and rollback thinking is dangerous.** In practice, migration is less about typing changes and more about making hidden assumptions visible one by one.

## 2. Decide whether this system should move now

The first decision is not "how do we migrate?"  
The first decision is **whether this specific application should move now at all**.

If that question stays vague, teams often end up with a migration that is technically sensible but too heavy for the business, or the opposite: a system that obviously should move gets postponed too long because the problem was never framed clearly.

### 2.1 Staying on .NET Framework can still be a rational choice

`.NET Framework 4.8.1` remains supported as long as it runs on supported versions of Windows. That means the situation is not simply "everything must move to modern .NET immediately or it is automatically unsafe."

But staying also has visible constraints:

- you remain Windows-only
- older server and application models remain in place
- newer .NET runtime, language, and tooling improvements are harder to benefit from
- the system drifts further away from current cloud, container, and CI/CD assumptions

On the other hand, staying on `.NET Framework 4.8.1` for a while can be a very normal decision if the application depends heavily on things like:

- a large Web Forms UI surface
- strict WCF server compatibility requirements
- deep Workflow Foundation or COM+ usage
- third-party design-time components that are not ready for modern .NET
- business constraints that do not tolerate broad behavioral change

### 2.2 The landing zone matters more than the desire to migrate

It helps to separate the main landing-zone choices early.

| Choice | What improves | What remains or is lost | Best fit |
| --- | --- | --- | --- |
| Stay on .NET Framework 4.8.1 | Stable operation with minimal disruption to existing assets | Windows-only, older application models, limited modernization upside | Heavy legacy dependency, business priority on stability right now |
| Move to modern .NET but stay on Windows | Runtime, tooling, SDK-style projects, and developer experience improve | Windows API dependency remains, no cross-platform benefit yet | WinForms, WPF, Windows Service, and Windows-API-heavy systems |
| Move to modern .NET with future Linux, containers, or cloud in mind | More deployment freedom and a more current operating model | Windows-specific APIs and app-model assumptions must be peeled away | Systems that are also trying to modernize infrastructure and hosting |

The key question is not "do we want migration?"  
It is **where exactly do we want the system to land after migration?**

## 3. Four decisions to make before the first migration task

### 3.1 Pick the target .NET version

At the time of writing, **.NET 10 is the current LTS**.  
Meanwhile **.NET 8 LTS** and **.NET 9 STS** are both scheduled to reach end of support on **November 10, 2026**.

So if you are starting a fresh migration effort now, the default choice is usually the **current LTS** unless there is a strong reason not to.

That practical rule usually looks like this:

- for a small migration, land directly on the current LTS
- for a long-lived core system, the current LTS is still the safest baseline
- if you want the previous LTS because of dependency constraints, decide with actual support dates in front of you

### 3.2 Decide whether Windows-only is acceptable for the landing zone

This decision changes the whole inventory.

- If **Windows-only is acceptable**, you can often take a pragmatic path: move the runtime first and keep WPF, WinForms, and selected Windows APIs in place for now.
- If **cross-platform later matters**, then Windows-specific APIs need to be surfaced early: `System.Drawing.Common`, registry access, WMI, Event Log, Windows Service APIs, COM, Office Interop, and similar areas.

If you do not decide this early, the project often gets pulled in two directions halfway through.

### 3.3 Decide between one-shot and staged migration

Broadly, migrations tend to fall into three patterns:

- a near in-place migration
- a side-by-side migration where old and new run in parallel
- a staged migration by route, service, or library

This matters especially for ASP.NET Framework systems. Microsoft's own guidance explicitly describes **incremental migration**. If uptime matters, surrounding dependencies are wide, or the feature surface is large, it is usually safer to assume a staged path from the beginning.

### 3.4 Decide what is intentionally out of scope

Migrations become dangerous when too many large changes are bundled together.

The following combinations are especially heavy:

- .NET Framework to .NET
- ASP.NET Framework to ASP.NET Core
- EF6 to EF Core
- Windows Server hosting to Linux containers
- authentication platform changes
- logging and observability platform changes
- database migration

Even if all of those things may eventually be necessary, they do not all need to be in the same migration phase. A more stable sequence is often:

1. modernize the runtime and project structure first
2. move the application model next
3. update the ORM, authentication, cloud shape, and observability later

## 4. Prepare the ground before porting

Microsoft's premigration guidance is refreshingly practical. The idea is simple:  
**pull the existing .NET Framework project toward more modern conventions before you ask it to cross the runtime boundary.**

### 4.1 Move the Framework side to 4.7.2 or later first

The official guidance recommends targeting **.NET Framework 4.7.2 or later** before porting. That makes it easier to move away from older API assumptions and align better with `.NET Standard 2.0` sharing.

In practice, if you can reach **4.8.1**, that is often the clearest baseline.

- it is the natural final stable point on the Framework side
- support posture is easier to explain
- it helps separate "this is old Framework noise" from "this is a real modern .NET compatibility issue"

### 4.2 Move toward `PackageReference`

Microsoft's porting guidance also recommends moving package references toward **`PackageReference`**.

That helps because:

- package references live in `csproj`
- transitive dependencies become easier to understand
- restore behavior gets closer to modern .NET expectations
- CLI and CI workflows get cleaner

But this step is not just a format conversion. The NuGet documentation calls out real constraints when moving from `packages.config`:

- the built-in Visual Studio migration path does not apply to ASP.NET projects
- packages that rely on `install.ps1` or `uninstall.ps1` may not behave the same
- some `content` assets may be ignored
- XDT transforms such as `web.config.install.xdt` are not applied
- older package layouts can resolve differently

Classic ASP.NET systems are especially prone to surprises here because package installation often used to rewrite `web.config` behind the scenes.

### 4.3 Move toward SDK-style projects

Moving toward **SDK-style project files** also pays off earlier than many teams expect.

It usually means:

- a much simpler `csproj`
- better alignment with `PackageReference`
- easier multi-targeting
- easier `dotnet build`, `dotnet test`, and `dotnet publish` workflows
- fewer structural differences left for the actual runtime move

In other words, an old-style `csproj` plus old NuGet management plus a runtime jump is often too much drift at once.

### 4.4 Update dependencies before the real port

The official guidance also recommends moving dependencies toward their **latest practical versions**, ideally versions that already support `.NET Standard` or modern .NET.

This matters because it reveals the real blockers early:

- which packages can already work on modern .NET
- which packages are the real dead ends
- which shared libraries can realistically move to `netstandard2.0`
- which parts of the later migration can focus on code rather than dependency archaeology

### 4.5 Check the assumptions behind Microsoft's current tooling guidance

As of March 2026, Microsoft's migration guidance places much more emphasis on **GitHub Copilot app modernization** workflows.  
That means the tooling conversation is no longer only about a single migration assistant. It is about assessment, planning, code changes, and validation as one guided flow.

But the official assumptions still matter. The current guidance is written around:

- **Visual Studio 2026 or a currently supported Visual Studio 2022 line**
- **GitHub Copilot**
- **C# codebases**

This matters because it changes what level of automation a team should expect. It also helps surface early whether a team needs IDE upgrades, extension updates, or whether a solution with VB.NET in it should assume more manual work.

## 5. Estimate difficulty by project type, not by one generic "migration"

People often talk about ".NET Framework to .NET migration" as if it were one move.  
In practice, each project type is a different game.

### 5.1 A rough difficulty map

| Project type | Typical difficulty | Main concerns |
| --- | --- | --- |
| Class library | Low to medium | API compatibility, dependencies, target splitting |
| Console / batch / some Windows services | Low to medium | deployment model, native dependency, configuration |
| WinForms / WPF | Medium | still Windows-only, designer behavior, third-party UI, BinaryFormatter-adjacent cases |
| ASP.NET MVC / Web API | Medium to high | app-model migration to ASP.NET Core, auth, session, configuration, DI |
| ASP.NET Web Forms | High | large UI-model mismatch, UI replacement is usually part of the story |
| WCF client | Medium | package replacement, contract and configuration review |
| WCF server | High | CoreWCF or gRPC / HTTP redesign |
| EF6 to EF Core at the same time | High | different ORM behavior, migration history, semantics drift |

### 5.2 Class libraries depend on whether they are truly shareable

Class libraries are often the easiest-looking part, but only if they are actually separated like libraries.

Difficulty rises quickly when the library touches things like:

- `System.Web`
- `HttpContext.Current`
- WPF or WinForms types in public APIs
- registry, WMI, Event Log, or other Windows APIs
- `AppDomain` or Remoting assumptions

The easiest libraries to move are the ones that truly contain business rules, contracts, calculations, and transformations rather than application-model behavior.

### 5.3 WinForms and WPF move, but they stay Windows-only

WinForms and WPF can move to .NET, but they remain **Windows-only frameworks**.

That means migration can still bring real benefits:

- current runtime and language features
- more modern project structure and CI/CD
- better dependency and publishing workflows

But some things do not magically disappear:

- Windows-only hosting assumptions
- designer and third-party control compatibility issues
- ActiveX, COM, and native-DLL dependency

There is also a specific class of risk around **BinaryFormatter-related behavior**, especially where clipboard, drag-and-drop, ResX, or designer serialization of custom types is involved.

### 5.4 ASP.NET Framework is not only a runtime move

Migrating ASP.NET Framework to ASP.NET Core is not just a rename exercise. Microsoft's documentation explicitly treats it as **non-trivial** because the architecture shifts:

- hosting model
- middleware pipeline
- request processing
- session and caching
- authentication and authorization
- configuration
- dependency injection
- logging and monitoring

That means the real questions are:

- which routes or endpoints can move first
- whether `System.Web` can be peeled away from shared libraries
- how auth, session, error handling, and logging will line up during transition
- whether zero-downtime or low-risk staged migration is required

### 5.5 Web Forms should be treated as a responsibility split problem

Web Forms is not the same application model as ASP.NET Core.  
So it is usually safer not to estimate it as if UI assets can simply move across.

A more realistic first move is often:

- split screen logic from business logic
- decompose responsibilities buried in `Page`, `UserControl`, and `ViewState`
- move business and data layers into shared libraries
- rebuild the UI in a different model such as MVC, Razor Pages, or Blazor

In other words, Web Forms migration is usually about **responsibility extraction before runtime migration**.

### 5.6 Treat WCF clients and WCF servers separately

This separation matters.

#### WCF client

WCF clients have **supported packages on modern .NET**, so calling an existing WCF service can be much less dramatic than people expect.

#### WCF server

Hosting the service is different. Microsoft's guidance typically leads toward one of two paths:

- **CoreWCF** for stronger compatibility with existing WCF clients
- **gRPC or another modern HTTP/RPC model** if redesign is acceptable

CoreWCF is not a full drop-in replica of everything WCF server-side ever had. It is a subset, and it still assumes code change and testing.

## 6. Find the technologies that do not come across cleanly

This is one of the most important parts of the premigration pass. Microsoft maintains guidance on **technologies that existed in .NET Framework but are unavailable or significantly different in .NET 6 and later**.

### 6.1 Common red-flag technologies

| Technology | Status on modern .NET | What that usually means |
| --- | --- | --- |
| `AppDomain.CreateDomain` and similar AppDomain creation patterns | Not supported | isolation needs a different model such as process boundaries, containers, or `AssemblyLoadContext` |
| .NET Remoting | Not supported | redesign toward IPC, HTTP, gRPC, sockets, or pipes |
| CAS / Security Transparency | Not supported as a security boundary | use OS, container, and privilege boundaries instead |
| `System.EnterpriseServices` / COM+ | Not supported | redesign or isolate COM+ assumptions |
| Workflow Foundation | Not supported | treat as a separate estimate, possibly with alternatives such as CoreWF |
| WCF server | No built-in direct continuation | choose between CoreWCF and a new service model |
| BinaryFormatter | Runtime implementation throws on .NET 9+ | migration of serialization formats and auditing of ResX, clipboard, drag-and-drop scenarios |

### 6.2 AppDomain is about intent, not only symbol search

AppDomain is slightly tricky because some API surface still exists on modern .NET, but **creating new AppDomains for isolation** is not supported in the old sense.

So the real migration question is not only "does the word AppDomain appear?"  
It is **why was AppDomain used in the first place?**

Typical reasons include:

- plugin isolation
- unloading dynamically loaded code
- partial-trust isolation
- disposable execution sandboxes

Each of those needs a different replacement conversation.

### 6.3 Remoting can hide behind older patterns

Remoting is not only about obvious namespace references. Older behavior patterns such as delegate `BeginInvoke()` / `EndInvoke()` can be part of the migration audit too.

Useful search terms include:

- `System.Runtime.Remoting`
- `MarshalByRefObject`
- `RealProxy`
- `BeginInvoke(`
- `EndInvoke(`

### 6.4 BinaryFormatter often hides in more places than expected

Older systems can use BinaryFormatter without much visible awareness. The audit needs to think about:

- persisted state
- caches
- session storage
- plugin state
- older WCF or SOAP contracts
- ResX
- clipboard and drag-and-drop behavior

On `.NET 9` and later, BinaryFormatter is not just discouraged. The runtime implementation is gone and the API path throws `PlatformNotSupportedException`. That makes it a **premigration** issue, not an afterthought.

### 6.5 Search terms that are worth running before any estimate

Even a simple whole-solution search for the following terms can change the migration picture quickly:

```text
System.Web
HttpContext.Current
System.Runtime.Remoting
MarshalByRefObject
AppDomain
BinaryFormatter
ServiceHost
ChannelFactory
System.EnterpriseServices
Workflow
packages.config
web.config.install.xdt
install.ps1
DllImport
AxInterop
Microsoft.Office.Interop
```

Finding one of these terms is not an automatic failure.  
It is a map of where the migration can follow the normal path and where it becomes a different workstream.

## 7. Decide how much Windows-only behavior is acceptable

One very common misunderstanding is that moving to ".NET" automatically means cross-platform.  
There is no such magic. If the application is deeply tied to Windows, it will remain a Windows application after migration.

### 7.1 Staying Windows-only can be a valid first landing zone

Microsoft provides the **Windows Compatibility Pack**, which helps modern .NET use many Windows-centric APIs such as registry access, WMI, Event Log, Windows Service APIs, and Directory Services.

That matters a lot in cases where the real short-term goal is:

- move to modern .NET first
- stay on Windows for now
- accept Windows API dependency as a temporary or even long-term condition

That can be a perfectly reasonable migration shape.

### 7.2 But Windows-specific APIs are still future debt

The Windows Compatibility Pack is helpful, but it does not erase trade-offs.

If the longer-term plan includes things like:

- Linux containers
- Kubernetes-based hosting
- shared builds across macOS, Linux, and Windows developers
- reducing Windows VM footprint in the cloud

then Windows API dependency needs to be made visible early.

### 7.3 `System.Drawing.Common` is a frequent source of misunderstanding

Since .NET 6, `System.Drawing.Common` is effectively **Windows-only**.

So if the codebase uses it for image processing or text rendering, one of the first questions should be:

- are we staying on Windows?
- or do we eventually want Linux or macOS support?

If the answer is Windows-only for the foreseeable future, it may be acceptable for now. If the answer is no, then alternative libraries such as SkiaSharp or ImageSharp need to enter the plan early.

### 7.4 Common signs that the application is tied to Windows

These references or APIs usually mean the first migration estimate should assume a Windows-only landing zone:

- `Microsoft.Win32.Registry`
- `System.Management`
- `System.Diagnostics.EventLog`
- `System.ServiceProcess`
- `System.DirectoryServices`
- `System.Drawing`
- `DllImport` / P/Invoke
- COM references
- `AxInterop.*`
- `Microsoft.Office.Interop.*`

## 8. Shared-library boundaries often decide the whole migration

In larger solutions, migration difficulty is heavily shaped by how shared libraries are cut.

### 8.1 Start with three broad categories

It helps to classify libraries into three types:

1. **pure business or domain logic**
2. **middle layers with some application-model dependency**
3. **layers tightly attached to UI, web, or Windows APIs**

The best candidates to move first are almost always the first category.

- calculations
- rules
- DTOs and contracts
- domain services
- straightforward data transformations

When that part is cleanly extracted, difficulty often drops sharply.

### 8.2 `.NET Standard 2.0` still works as a bridge

Microsoft's guidance still makes `.NET Standard 2.0` the practical answer when a shared library must be used by both the old Framework side and the new .NET side.

Two facts matter:

- **.NET Framework does not support `.NET Standard 2.1`**
- if a library needs to be referenced from both worlds, **2.0 is often the realistic bridge**

### 8.3 Three common library strategies

| Strategy | What changes | Best fit | Main caution |
| --- | --- | --- | --- |
| Move to `netstandard2.0` | Old and new sides can both reference it | business logic, shared contracts, utilities | app-model-specific APIs do not belong there |
| Multi-target, for example `net48;net10.0` | shared code can stay together while environment-specific differences remain | libraries with small but real platform differences | build complexity and conditional branching increase |
| Move directly to `net10.0` only | cleanest future state | new layers that do not need old/new coexistence | .NET Framework can no longer consume it |

### 8.4 Compatibility mode is not a magic trick

`.NET Standard 2.0` compatibility mode can help in some cases, but it is not a transparent answer for everything.  
If a library assumes WPF or another specific application model, it is still not really a shared library in the way migration needs.

### 8.5 ASP.NET libraries live or die on whether `System.Web` can be peeled away

For staged ASP.NET migration, shared libraries that directly depend on `HttpContext.Current` or `System.Web` tend to become painful quickly.

Typical strategies include:

- pushing `System.Web` dependency outside the main contract boundary
- passing request-derived data as DTOs instead
- using adapters during the transition
- using multi-targeting if the dependency cannot be removed immediately

### 8.6 Move libraries leaf-first

Microsoft's incremental ASP.NET guidance describes moving supporting libraries in **postorder depth-first** order, effectively **leaf-first**.

That is valuable outside web projects too:

- lower-level dependencies stabilize first
- compatibility issues stay localized longer
- library-level testing becomes easier

## 9. Inventory NuGet packages, local dependencies, and third-party components

This is where many migrations suffer late if the early pass was too shallow.

### 9.1 Four dependency buckets are more useful than one package list

It helps to separate dependencies into:

1. **public NuGet packages**
2. **internal packages or internal libraries**
3. **local DLL references**
4. **COM, ActiveX, native DLLs, and SDK-style binary integrations**

Looking only at public NuGet packages is not enough.  
The most dangerous items are often categories 3 and 4.

### 9.2 Questions worth asking for every dependency

For each dependency, ask at least:

- does it target modern .NET?
- does it work with `PackageReference`?
- is it compatible with SDK-style projects?
- are there `x86`, `x64`, or `ARM64` restrictions?
- does it rely on design-time tooling or a Visual Studio extension?
- does it assume install scripts or config transforms?
- is the product still supported?

### 9.3 Third-party UI, reporting, and design-time components need separate estimation

This is especially important in WinForms, WPF, and ASP.NET systems.

- grids
- reporting engines
- PDF output libraries
- charting components
- UI libraries with designer integration
- ActiveX wrappers

Those components are not only runtime dependencies. They often involve design-time behavior too, which means "it compiles" is not enough as an estimate.

### 9.4 Native DLLs and bitness always need explicit review

Many older systems looked like they were running as `AnyCPU`, but in reality they depended on things like:

- `x86`-only COM
- 32-bit ActiveX controls
- a specific VC++ runtime version
- signed native DLLs

Modern .NET does not create those constraints. It only makes long-existing constraints visible.

## 10. Treat EF6, serialization, and data concerns as a separate problem track

The runtime move and the redesign of data access or serialization usually go better when they are not forced into the same phase.

### 10.1 EF6 to EF Core is not a direct upgrade

Microsoft's EF guidance is explicit: **EF Core is a total rewrite of EF6 and there is no direct upgrade path**.

That usually makes the practical sequence:

1. move to modern .NET first
2. keep EF6 temporarily if that reduces risk
3. migrate to EF Core later as a separate project

That separation matters a lot.  
Just not combining the runtime migration with the ORM migration often lowers the risk profile significantly.

### 10.2 What changes if EF6 stays for a while

Benefits:

- the data-access layer can change later
- the team can focus on runtime and application-model movement first
- behavior differences from EF Core do not get mixed into the same phase

Cautions:

- EF Core is still the longer-term default for new development
- EF6 Designer and EDMX usage bring their own constraints

### 10.3 EDMX-based EF6 has a design-time story too

The EF6 documentation also notes that the **EF Designer is not directly supported in .NET / .NET Standard projects or in SDK-style .NET Framework projects**.

That means EDMX-based systems need three separate questions:

- does runtime execution still work?
- does the designer workflow still work?
- how will generated code be handled going forward?

If EDMX is used heavily, that belongs in the estimate from day one.

### 10.4 BinaryFormatter and custom serialization are often hidden dependencies

Serialization is easy to underestimate because simple code search may not reveal the whole impact.

Think about:

- persisted data formats
- messaging payloads
- caches
- older WCF or SOAP contracts
- ResX
- clipboard and drag-and-drop behavior

The key point is not only whether the code builds. It is whether **existing data remains readable and compatible**.

## 11. Include configuration, deployment, operations, and CI/CD in the migration boundary

Migration scope is never only source code.

### 11.1 Configuration files

On the Framework side, `app.config` and `web.config` often carry much more than teams remember:

- connection strings
- custom configuration sections
- WCF endpoint settings
- binding redirects
- diagnostics
- ASP.NET-specific settings
- the results of package-install transforms

Modern .NET changes configuration shape and loading paths in many cases.  
So "we will fix config later" is usually a risky idea.

The first step is a **configuration inventory**:

- what exactly exists in config files
- what is required at startup
- what is environment-specific
- what used to be injected by NuGet or installers

### 11.2 Deployment model

Deployment and startup shape matter too:

- IIS?
- Windows Service?
- Scheduled Task?
- ClickOnce, MSI, or a custom installer?
- on-premises server assumptions?
- self-contained or framework-dependent publish?

It is very normal to discover late that the code can run but the deployment path is still tied to an older operating model.

### 11.3 Logging, monitoring, and operational practice

Operations assumptions are easy to miss:

- Windows Event Log
- Performance Counters
- WMI-based monitoring
- fixed service-account and privilege assumptions
- local-file logging assumptions

A migrated application that runs but does not fit the operating model is still not really migrated.

### 11.4 CI/CD and build agents

Before migration, review at least:

- whether build agents can host the required .NET SDKs
- what to do with `nuget.exe` and `msbuild.exe`-centric pipelines
- whether the pipeline should move toward the `dotnet` CLI
- how test execution, coverage, and publish jobs should change
- whether internal pipeline templates still assume older project conventions

"It works locally but CI is dead" is one of the most ordinary migration outcomes when this is skipped.

## 12. A realistic migration sequence

Once the above is clear, the migration path often settles into something like this.

### 12.1 Modernize the current Framework side first

1. move to .NET Framework 4.7.2 or later, ideally 4.8.1
2. update dependencies
3. inspect and reduce `packages.config`
4. move toward `PackageReference` and SDK-style projects where feasible
5. confirm that the current application still builds, starts, and passes tests in that state

This alone often removes a large amount of later noise.

### 12.2 Rescue shared libraries next

Move business logic and shared contracts toward `netstandard2.0` or multi-targeting.  
Use a **leaf-first** order as the default.

### 12.3 Change strategy by application model

- **class libraries, console tools, some services**  
  often the most straightforward path
- **WinForms / WPF**  
  modernize while intentionally staying Windows-only
- **ASP.NET MVC / Web API**  
  one-shot for small systems, staged migration for larger ones
- **Web Forms**  
  assume UI replacement and move shared logic out first
- **WCF server**  
  choose early between compatibility via CoreWCF and redesign via gRPC or HTTP APIs

### 12.4 Do not do everything in one sprint

Combinations worth avoiding include:

- runtime migration plus full ORM replacement
- runtime migration plus auth-platform replacement
- runtime migration plus full cloud move
- runtime migration plus observability-platform replacement
- runtime migration plus UI-framework replacement

Even if all of those changes are eventually necessary, they usually do better as separate phases.

### 12.5 Capture tests and baselines before the risky move

At minimum, it helps to have:

- unit tests
- integration tests for key business flows
- snapshot-style checks for representative screens or APIs
- performance baselines
- a known way to inspect key logs
- rollback procedures

Moving forward without a way to identify what broke after migration is high-risk.

## 13. Premigration checklist

This section is meant to be directly reusable in project planning.

### 13.1 Direction

- [ ] We can explain in one sentence why we are migrating
- [ ] We have decided whether the landing zone is **Windows-only modern .NET** or **future cross-platform**
- [ ] We have chosen the target .NET version
- [ ] We have explicitly listed what is **out of scope** for this phase, such as EF Core migration, auth redesign, or full cloud relocation

### 13.2 Current .NET Framework cleanup

- [ ] We moved the Framework side to 4.7.2 or later, ideally 4.8.1
- [ ] We updated dependencies toward current supported versions
- [ ] We checked where `packages.config` still exists
- [ ] We evaluated `PackageReference` conversion feasibility
- [ ] We evaluated SDK-style conversion feasibility
- [ ] The current application still builds, starts, and passes tests in that cleaned-up state

### 13.3 Application model and technology choices

- [ ] We estimated difficulty separately by class library, desktop, web, WCF, and similar project types
- [ ] We understand that WinForms and WPF remain Windows-only
- [ ] We understand that ASP.NET Framework to ASP.NET Core is an app-model migration
- [ ] We included Web Forms UI replacement in the estimate
- [ ] We evaluated WCF clients separately from WCF servers

### 13.4 Unsupported or high-risk technology

- [ ] We audited AppDomain dependency
- [ ] We audited Remoting, `MarshalByRefObject`, `BeginInvoke`, and `EndInvoke`
- [ ] We audited CAS, Security Transparency, COM+, and Workflow Foundation
- [ ] We audited BinaryFormatter dependency
- [ ] We audited `System.Web` dependency

### 13.5 Windows-only dependency

- [ ] We audited registry, WMI, Event Log, Windows Service, and Directory Services usage
- [ ] We audited `System.Drawing.Common` usage
- [ ] We audited COM, ActiveX, Office Interop, P/Invoke, and native DLL usage
- [ ] We checked `x86`, `x64`, and `ARM64` restrictions

### 13.6 Shared libraries and data access

- [ ] We classified shared libraries into business logic versus app-model-dependent layers
- [ ] We identified libraries that can move to `netstandard2.0`
- [ ] We identified libraries that need multi-targeting
- [ ] We decided whether EF6 can remain while only the runtime moves first
- [ ] We checked EDMX and designer dependency

### 13.7 Operations and build

- [ ] We inventoried configuration files
- [ ] We reviewed deployment shape such as IIS, Service, MSI, and ClickOnce
- [ ] We reviewed logging, monitoring, privilege, and execution-account assumptions
- [ ] We reviewed whether CI/CD and build agents need updates
- [ ] We prepared rollback procedures

## 14. Summary

The important part of a .NET Framework to .NET migration is not only the command sequence.  
It is identifying, before implementation starts, **what can move directly and what is actually a different problem**.

The practical core is:

- clean up the Framework side first
- estimate by application model, not by generic code volume
- find unsupported technologies early
- decide how much Windows-only behavior is acceptable
- decide how shared-library boundaries will be handled
- avoid bundling ORM, auth, cloud, and other major redesigns into the same move

The accuracy of a migration estimate often changes dramatically in the first week.  
If that first week is used to surface assumptions clearly, the rest of the project starts to look much more like normal engineering work.

"Let's just change the target to `net10.0` and see what happens" is not a useless experiment.  
But as a production migration strategy, it starts too late. The real work begins earlier than that.

## 15. References

- [Prerequisites for porting code to .NET](https://learn.microsoft.com/en-us/dotnet/core/porting/premigration-needed-changes)
- [Overview of porting from .NET Framework to .NET](https://learn.microsoft.com/en-us/dotnet/core/porting/framework-overview)
- [Technologies unavailable on .NET](https://learn.microsoft.com/en-us/dotnet/core/porting/net-framework-tech-unavailable)
- [GitHub Copilot app modernization overview](https://learn.microsoft.com/en-us/dotnet/core/porting/github-copilot-app-modernization/overview)
- [GitHub Copilot app modernization installation](https://learn.microsoft.com/en-us/dotnet/core/porting/github-copilot-app-modernization/install)
- [.NET support policy](https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core)
- [.NET Framework support policy](https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-framework)
- [Migrate ASP.NET Framework to ASP.NET Core with tooling](https://learn.microsoft.com/en-us/aspnet/core/migration/fx-to-core/tooling?view=aspnetcore-10.0)
- [Migrate from ASP.NET Framework to ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/migration/fx-to-core/?view=aspnetcore-10.0)
- [Get started with incremental ASP.NET to ASP.NET Core migration](https://learn.microsoft.com/en-us/aspnet/core/migration/fx-to-core/start?view=aspnetcore-10.0)
- [Use the Windows Compatibility Pack to port code to .NET](https://learn.microsoft.com/en-us/dotnet/core/porting/windows-compat-pack)
- [.NET Standard](https://learn.microsoft.com/en-us/dotnet/standard/net-standard)
- [Cross-platform targeting for .NET libraries](https://learn.microsoft.com/en-us/dotnet/standard/library-guidance/cross-platform-targeting)
- [Migrate from packages.config to PackageReference](https://learn.microsoft.com/en-us/nuget/consume-packages/migrate-packages-config-to-package-reference)
- [PackageReference in project files](https://learn.microsoft.com/en-us/nuget/consume-packages/package-references-in-project-files)
- [BinaryFormatter migration guide](https://learn.microsoft.com/en-us/dotnet/standard/serialization/binaryformatter-migration-guide/)
- [BinaryFormatter migration guidance for Windows Forms](https://learn.microsoft.com/en-us/dotnet/standard/serialization/binaryformatter-migration-guide/winforms-applications)
- [WCF Client support policy](https://dotnet.microsoft.com/en-us/platform/support/policy/wcf-client)
- [CoreWCF support policy](https://dotnet.microsoft.com/en-us/platform/support/policy/corewcf)
- [Why migrate WCF to ASP.NET Core gRPC](https://learn.microsoft.com/en-us/aspnet/core/grpc/why-migrate-wcf-to-dotnet-grpc?view=aspnetcore-10.0)
- [Port from EF6 to EF Core](https://learn.microsoft.com/en-us/ef/efcore-and-ef6/porting/)
- [What's new in EF6](https://learn.microsoft.com/en-us/ef/ef6/what-is-new/)
