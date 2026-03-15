---
title: "A Minimum Security Checklist for Windows Application Development"
date: 2026-03-14 15:00
lang: en
translation_key: windows-app-security-minimum-checklist
permalink: /en/blog/2026/03/14/001-windows-app-security-minimum-checklist/
tags:
  - Windows Development
  - Security
  - Architecture
  - C# / .NET
  - Win32
author: Go Komura
description: "A practical minimum security checklist for Windows desktop application development, covering permissions, signing, secrets, transport security, input validation, DLL loading, logging, and dependency hygiene."
consultation_services:
  - id: windows-app-development
    reason: "This topic maps well to Windows application delivery work that needs sane privilege boundaries, signed distribution, safe update paths, and maintainable logging and deployment design."
  - id: technical-consulting
    reason: "If the first need is to review an existing application's security posture, privilege boundaries, or updater design before a rebuild, this fits technical consulting and design review."
---

When people say "Windows application security," the conversation often jumps straight to large themes.  
Zero trust, EDR, SBOM, certificate operations, vulnerability management. All of that matters, but in day-to-day delivery there is a simpler problem first: basic things that should not be left loose.

That is especially true for applications like these:

- WPF, WinForms, or WinUI desktop applications
- C++ or C# Win32 applications
- internal tools that connect to devices, files, or databases
- business applications with auto-update behavior
- solutions that include Windows Services or helper executables

For this kind of software, fixing obvious fundamentals often does more than reaching for advanced defenses too early.  
This article organizes the minimum security baseline in a checklist form that is easier to review across design, implementation, distribution, and operations.

## 1. The short version

- The first things worth protecting are **not asking for unnecessary administrator rights, signing what you ship, keeping secrets out of plaintext, and never disabling certificate validation in production**.
- In Windows software, **the distributable itself** is part of the attack surface. That includes EXEs, DLLs, MSI or MSIX packages, and updater components.
- Patterns like `ServerCertificateValidationCallback => true`, plaintext connection strings, casual `LoadLibrary("foo.dll")`, and SQL built through string concatenation should already be considered below the minimum bar.
- If only part of the system needs elevation, **split that part into a separate process or service** instead of elevating the whole application.
- In Windows distribution, **signing plus timestamping** should be treated as the default, not as polish. It improves trust, tamper detection, and operational clarity.
- For stored secrets, choose something like **DPAPI / ProtectedData** or **Credential Locker** based on the application model. At the very least, move past "leave it in `appsettings.json` as plaintext."
- Logging is not automatically good just because there is more of it. If logs keep tokens, passwords, connection strings, personal data, or full request bodies, the logs themselves can become the incident.

The minimum baseline is less about adding special security features and more about **not shipping dangerous defaults or careless implementation choices**.

## 2. What this article means by "minimum"

### 2.1. In scope

This article is aimed at Windows applications such as:

- WPF, WinForms, or WinUI desktop apps
- Win32 applications written in C++ or C#
- internal distribution tools, monitoring tools, and device integration tools
- products that include helper EXEs, Windows Services, or updaters
- business software distributed as EXE, MSI, or MSIX

Here, "minimum" does **not** mean "enough to satisfy every audit."  
It means the baseline where leaving gaps usually leads to very ordinary, very avoidable incidents.

### 2.2. Out of scope

This is not mainly about:

- organization-wide zero trust design
- full EDR, SIEM, DLP, or MDM operation
- deep kernel driver hardening
- building cryptographic schemes from scratch
- advanced threat hunting or forensic procedure

The focus is narrower: the basic line that Windows application developers should not miss before release.

## 3. The first checklist to look at

Before getting into detail, it helps to look at the whole shape first.

### 3.1. The overview

| Area to check | Minimum action | Typical bad pattern |
| --- | --- | --- |
| Execution privileges | Default to `asInvoker` and isolate elevated operations | Setting the entire application to `requireAdministrator` |
| Distribution trust | Sign EXEs, DLLs, MSI, and MSIX packages and attach timestamps | Shipping unsigned binaries |
| Updating | Pin the update source and verify integrity through HTTPS plus signature or hash checks | Downloading over HTTP and overwriting files directly |
| Secrets | Keep secrets out of source code and plaintext settings, and use DPAPI or Credential Locker when needed | Storing API keys or connection strings in config as plaintext |
| Transport security | Use HTTPS and keep certificate validation enabled | Skipping certificate checks with a permanent `return true` |
| External input | Validate SQL input, files, IPC, URIs, CSV, JSON, and similar sources | Trusting input because "it is only an internal tool" |
| DLL loading | Use explicit paths and safe search order such as `SetDefaultDllDirectories` | Relying on current-directory DLL resolution |
| Logging | Mask tokens, passwords, and PII, and separate user-facing errors from internal details | Saving exception details and secrets as-is |
| Dependency hygiene | Keep SDKs, NuGet packages, VC++ runtime pieces, and OSS dependencies updated | Freezing dependencies for years and ignoring advisories |

### 3.2. Keep `asInvoker` as the default

This is often the first place worth reviewing.  
If the whole application runs elevated, then bugs, bad DLL resolution, config mistakes, and untrusted input all run with stronger privileges too.

The baseline pattern is straightforward:

- keep ordinary UI applications at `asInvoker`
- isolate only the operations that truly need administrative rights
- elevate only when that specific operation is required
- validate the input that goes into helper EXEs or services as well

If an application mostly reads and edits data, but only installation or firewall changes need elevation, it is usually safer to keep the UI process unprivileged and move only the privileged operation into a broker process or service.

```xml
<trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
  <security>
    <requestedPrivileges>
      <requestedExecutionLevel level="asInvoker" uiAccess="false" />
    </requestedPrivileges>
  </security>
</trustInfo>
```

"Running as administrator is easier" tends to look convenient only in the beginning.  
Over time, the minimum-privilege design almost always gives a smaller blast radius.

### 3.3. Sign the binaries and the installer

In Windows software, **distribution trust** matters a lot.  
Users interact with EXEs, DLLs, MSI packages, MSIX packages, and updater modules, not with your source repository. If those artifacts are unsigned, both tamper detection and operational confidence become weaker.

The baseline checklist is:

- sign EXEs, DLLs, MSI packages, and MSIX packages
- sign helper binaries used for updating, not just the main installer
- add timestamps
- include certificate renewal procedure in the release workflow

A signature without a timestamp becomes troublesome once the certificate expires.  
It is more stable to treat **signing plus timestamping** as part of the release process.

If you ship MSIX, package signing is already expected.  
Even with MSI or EXE distribution, signing at least the installer and core executables is a reasonable minimum.

### 3.4. Lock down the update path and verify authenticity

In modern Windows applications, the **update path** often lives longer than the initial install path.  
If update handling is weak, the updater can become the weakest part of the product even when the main application is carefully built.

The minimum baseline is:

- fetch update payloads over HTTPS
- verify downloaded content through a signature or hash check
- avoid making the update source URL arbitrarily replaceable
- sign the updater itself
- define rollback or recovery behavior for failures

If MSIX plus App Installer fits your distribution model, it can shift more of the update mechanism toward the OS.  
If you maintain a custom updater, you need to care about both **transport security** and **artifact authenticity**. HTTPS protects the channel, but not by itself the claim that the file truly came from you.

### 3.5. Do not keep secrets in source or plaintext settings

This is one of the most common real-world failure points.  
Because a tool is internal, or because it is "just an EXE," teams often leave connection strings, API keys, shared-folder credentials, or fixed tokens directly in code or config.

Things worth removing first are:

- API keys hard-coded in source
- plaintext passwords in `appsettings.json` or `app.config`
- connection strings committed into the repository
- designs that store ciphertext and the decryption key together
- one shared credential used by every user

For Windows applications, the practical choices usually look like this:

- **You need to store Windows-side credentials**  
  For packaged desktop apps or WinUI, consider Credential Locker.
- **You need encrypted local storage**  
  For Win32 or .NET software, DPAPI / `ProtectedData` is often the practical default.
- **The target system supports Windows integrated authentication**  
  Prefer not storing passwords in the client at all.
- **Secrets can be managed on the server side**  
  Avoid embedding long-lived secrets in the client.

In C#, even a simple DPAPI-based approach is already far better than plain text:

```csharp
using System.Security.Cryptography;
using System.Text;

byte[] plaintext = Encoding.UTF8.GetBytes(secretText);
byte[] ciphertext = ProtectedData.Protect(
    plaintext,
    optionalEntropy: null,
    scope: DataProtectionScope.CurrentUser);
```

The important design question is not only "is it encrypted?" but **who can decrypt it?**  
`CurrentUser` and `LocalMachine` mean very different boundaries.

For SQL Server connections in on-premises environments, Windows authentication can often be the first option to consider.  
If credentials must appear in a connection string, at least avoid leaving them in plaintext config and keep settings such as `Persist Security Info=False` in mind.

### 3.6. Use HTTPS and do not kill certificate validation

One of the oldest patterns in application delivery is that a temporary development shortcut quietly survives into production.  
Transport security code is full of this.

The common dangerous patterns include:

- `ServicePointManager.ServerCertificateValidationCallback += ... => true`
- `HttpClientHandler.DangerousAcceptAnyServerCertificateValidator`
- shipping with revocation checks disabled
- leaving development-only self-signed-certificate assumptions in production code

The baseline rule is simple:

- production traffic uses HTTPS
- certificate validation is not skipped globally
- if an exceptional relaxation is required, scope it tightly to the exact host and certificate you expect
- development bypass code must be excluded reliably by build or configuration
- in .NET, think about revocation checks too

The classic bad example looks like this:

```csharp
ServicePointManager.ServerCertificateValidationCallback +=
    (_, _, _, _) => true;
```

It feels convenient, but it is close to saying, "accept this HTTPS connection no matter who answers."  
Once certificate validation is removed, the value of HTTPS is severely weakened.

### 3.7. Treat all external input as untrusted input

Windows applications are not web applications, so input validation sometimes gets treated more casually.  
In practice, though, Windows software has many input surfaces:

- file paths
- CSV, Excel, JSON, and XML
- command-line arguments
- named pipes, sockets, COM, RPC, and gRPC
- strings sent to the database
- registry values
- clipboard content
- URLs and deep links
- data returned from devices or third-party SDKs

Three baseline rules matter especially often:

1. **Always parameterize SQL**  
   Do not build SQL by string concatenation.
2. **Normalize paths before using them**  
   Do not delete, overwrite, or extract directly from raw user-supplied paths.
3. **Apply size limits and format checks to external files**  
   "It opened successfully" is not the same as "it is safe."

This is the kind of SQL you want to avoid:

```csharp
var sql = "SELECT * FROM Users WHERE Name = '" + userName + "'";
```

Even the minimum safer form should look more like this:

```csharp
using System.Data;
using Microsoft.Data.SqlClient;

using var cmd = connection.CreateCommand();
cmd.CommandText = "SELECT * FROM Users WHERE Name = @name";
cmd.Parameters.Add("@name", SqlDbType.NVarChar, 256).Value = userName;
```

"It is only an internal tool, so the input is trustworthy" is still a risky assumption.  
Broken CSV files, unexpected file names, stale database rows, operator mistakes, and half-written JSON from another tool are all very normal in the field.

### 3.8. Make DLL loading explicit

This is a very Windows-shaped pitfall.  
If you call `LoadLibrary("foo.dll")` with just the file name, search order can cause the process to pick up a DLL from a place you did not intend.

The safer baseline is:

- use an **absolute DLL path** when possible
- call `SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_DEFAULT_DIRS)` early
- add only explicit search directories through `AddDllDirectory`
- avoid designs that feed `SearchPath` results directly into `LoadLibrary`
- do not rely entirely on safe DLL search mode defaults

In native code, a pattern like this early in process initialization is often a strong starting point:

```cpp
SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
```

Then add only the directories you truly need through `AddDllDirectory`.

This area gets ignored easily because "it usually works," but it can fail quietly when the working directory changes or another product drops DLLs into `PATH`.  
It improves not only security but also reliability.

### 3.9. Keep secrets out of logs and exception displays

More logging helps troubleshooting, but logs can also become the place where sensitive data accumulates.

The minimum review points are:

- do not log passwords, bearer tokens, or API keys
- do not dump full connection strings
- mask personal or business data bodies
- separate internal diagnostics from user-facing error messages
- do not leave debug-only PII logging enabled in production
- review access rights on dump, trace, and log storage

Recent .NET tooling also makes structured redaction easier, but even without that, the minimum change is to stop turning every object into a string and logging it raw.

Common bad patterns include:

- storing full HTTP request or response bodies
- dumping full headers or tokens on authentication failure
- showing raw exception messages in a `MessageBox`
- packing every sensitive log into a maintenance ZIP

A better split looks like this:

- **User-facing**: "Failed to connect to the server. Check the network settings and URL."
- **Internal log**: target host, TLS error category, correlation ID, stack trace, retry count

That separation alone improves both confidentiality and diagnosability.

### 3.10. Do not neglect dependencies and tools

This is not flashy, but it matters.  
Even if the application code is careful, an outdated runtime or a dependency with known vulnerabilities can still become the weak point.

The minimum baseline is:

- keep .NET SDK and runtime versions within supported ranges
- check NuGet and OSS dependencies regularly
- for C++, manage runtime redistributables and external DLL versions explicitly
- include vulnerability review in the release checklist
- keep a smoke test so dependency updates do not become impossible to ship

The most dangerous pattern here is "we will update everything later."  
After half a year or a year, the dependency gap can become large enough that even basic security maintenance turns into major work.

## 4. A release checklist you can actually use

Below is a simple pre-release checklist that works as a yes-or-no review sheet.

### 4.1. Privileges and execution model

- [ ] Normal startup runs as `asInvoker`
- [ ] Operations that require administrator rights are isolated into a separate EXE, service, or similar component
- [ ] If a service is used, it is not running under a stronger account than necessary
- [ ] Responsibilities are clearly split between `%ProgramFiles%` and user-data locations

### 4.2. Distribution and signing

- [ ] EXEs, DLLs, MSI / MSIX packages, and updater binaries are signed
- [ ] Timestamps are attached to signatures
- [ ] Certificate expiry and renewal steps are included in the release flow
- [ ] There is a defined integrity or tamper-detection method for distributed artifacts

### 4.3. Updating

- [ ] Update retrieval uses HTTPS
- [ ] Downloaded updates are verified by signature or hash
- [ ] The update source URL is not trivially replaceable
- [ ] There is a rollback or retry policy for update failures

### 4.4. Secrets

- [ ] Passwords, API keys, and connection strings are not hard-coded in source
- [ ] Secrets are not stored in plaintext config files
- [ ] Secrets that must be stored locally are protected with DPAPI, Credential Locker, or an equivalent Windows mechanism
- [ ] Where possible, the design leans on Windows authentication or user-provided credentials

### 4.5. Transport security

- [ ] Production traffic uses HTTPS
- [ ] `DangerousAcceptAnyServerCertificateValidator` or `=> true` certificate bypasses are not present in release artifacts
- [ ] Host-name validation and revocation checks are being considered
- [ ] Development-only certificate assumptions are not leaking into production code or config

### 4.6. Input and data access

- [ ] SQL uses parameters
- [ ] Command-line input, files, IPC, and URIs have limits and format validation
- [ ] Path handling normalizes input and prevents root escape
- [ ] Raw exception messages are not shown directly to end users

### 4.7. DLLs and runtime environment

- [ ] DLL load sources are explicit
- [ ] Search order is controlled with `SetDefaultDllDirectories`, `AddDllDirectory`, or equivalent measures
- [ ] DLL resolution does not depend on the current directory or `PATH`
- [ ] The files required for dynamic loading at the destination environment are understood

### 4.8. Logging and operations

- [ ] Tokens, passwords, and PII are not written to logs
- [ ] Internal diagnostics and user-facing messages are separated
- [ ] Storage permissions for dumps, traces, and logs have been reviewed
- [ ] SDK and dependency update status is checked as part of release preparation

## 5. Common false comforts

### 5.1. "It is only an internal tool"

Internal tools still encounter broken files, operator mistakes, shared folders, unmanaged endpoints, old DLLs, and loose permissions.  
Not being internet-facing does not erase the attack surface.

### 5.2. "It uses HTTPS, so it is safe"

HTTPS matters, but disabling certificate validation removes much of the point.  
For update distribution, HTTPS also is not enough by itself. Artifact authenticity still needs to be verified.

### 5.3. "It is encrypted, so it is safe"

Encryption alone is not the full answer if key placement, decryption rights, user boundaries, and machine boundaries are not thought through.  
Values protected with `LocalMachine`, for example, should not be casually treated as if they were per-user secrets.

### 5.4. "If we log more, we can always investigate later"

If the logs themselves spray tokens or personal data, the logging strategy becomes part of the incident.  
What to preserve and what to redact should be decided before increasing volume.

### 5.5. "Running as administrator solves it"

It may feel easier at first, but later it usually makes UAC behavior, distribution, support, privilege boundaries, DLL loading, and file placement harder.  
Minimum privilege is more stable over time.

## 6. A practical priority order

If everything cannot be fixed at once, a reasonable order is:

1. **Review elevation first**  
   Stop using `requireAdministrator` as the default.
2. **Add signing and timestamping**  
   Establish trust in what you ship.
3. **Move secrets out of source and plaintext config**  
   Reduce the easiest leakage path.
4. **Fix HTTPS and certificate validation shortcuts**  
   Remove `=> true` style bypasses from release builds.
5. **Review SQL, file, and IPC input handling**  
   Reduce concatenation and unchecked input.
6. **Make DLL loading deterministic**  
   Stop loading by bare name or through `PATH` assumptions.
7. **Mask logs**  
   Prevent incident response from turning into a second incident.
8. **Make dependency review routine**  
   Turn it into a release habit rather than a future project.

That order tends to work well when the goal is simply to close the most obvious holes first.

## 7. Summary

Before adding large security systems, Windows application security improves a lot just by tightening the basics around  
**privileges, signing, secrets, transport, input, DLL loading, and logging**.

The minimum line to keep in view is:

- do not run the whole application as administrator
- sign distributed and updated binaries and attach timestamps
- keep secrets out of source code and plaintext configuration
- do not disable certificate validation even when using HTTPS
- do not trust external input from SQL, files, IPC, or similar sources
- make DLL load paths explicit
- keep sensitive data out of logs
- do not leave dependencies unmanaged

Security is broad, and there is no need to finish every topic at once.  
But there is a great deal of value in making sure **obviously dangerous defaults are not what you ship**.

## 8. References

- [Administrator Broker Model - Win32 apps](https://learn.microsoft.com/en-us/windows/win32/secauthz/administrator-broker-model)
- [How User Account Control works](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/user-account-control/how-it-works)
- [Authenticode Digital Signatures](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/authenticode)
- [Time Stamping Authenticode Signatures](https://learn.microsoft.com/en-us/windows/win32/seccrypto/time-stamping-authenticode-signatures)
- [Sign a Windows app package](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview)
- [Credential Locker for Windows apps](https://learn.microsoft.com/en-us/windows/apps/develop/security/credential-locker)
- [CryptProtectData function (dpapi.h)](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata)
- [CA5359: Do not disable certificate validation](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca5359)
- [CA5399: Enable HttpClient certificate revocation list check](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca5399)
- [Configuring parameters - ADO.NET Provider for SQL Server](https://learn.microsoft.com/en-us/sql/connect/ado-net/configure-parameters?view=sql-server-ver17)
- [Connection String Syntax - ADO.NET](https://learn.microsoft.com/en-us/dotnet/framework/data/adonet/connection-string-syntax)
- [Dynamic-Link Library Security - Win32 apps](https://learn.microsoft.com/en-us/windows/win32/dlls/dynamic-link-library-security)
- [SetDefaultDllDirectories function (libloaderapi.h)](https://learn.microsoft.com/en-us/windows/win32/api/libloaderapi/nf-libloaderapi-setdefaultdlldirectories)
- [Data redaction in .NET](https://learn.microsoft.com/en-us/dotnet/core/extensions/data-redaction)
