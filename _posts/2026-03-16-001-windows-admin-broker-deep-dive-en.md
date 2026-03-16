---
title: "How to Isolate Only Administrator-Required Work in Windows Apps"
date: 2026-03-16 10:00
lang: en
translation_key: windows-admin-broker-deep-dive
permalink: /en/blog/2026/03/16/001-windows-admin-broker-deep-dive/
tags:
  - Windows Development
  - Security
  - UAC
  - C# / .NET
  - Win32
author: Go Komura
description: "A practical deep dive into keeping a Windows UI app at asInvoker while isolating administrator-only operations into a helper EXE, covering UAC, runas, named pipes, request validation, and common pitfalls."
consultation_services:
  - id: windows-app-development
    reason: "This topic maps well to Windows application work that needs clean UAC boundaries, helper executables, and machine-wide configuration changes without turning the whole UI into an elevated process."
  - id: technical-consulting
    reason: "If the first need is to review an existing application's overuse of `requireAdministrator`, redesign the broker boundary, or tighten IPC and privilege separation before a larger rewrite, this fits technical consulting and design review well."
---

In the earlier article, ["A Minimum Security Checklist for Windows Application Development"](https://comcomponent.com/en/blog/2026/03/14/001-windows-app-security-minimum-checklist/), I touched on a practical rule: keep the UI at `asInvoker`, and isolate only the work that truly needs administrator rights.

This article takes that rule further and turns it into code.

On Windows, you cannot conveniently make only one method inside a process "run as administrator."  
Elevation is a process-boundary question. If one operation needs a different token, the usual answer is to move that operation into a different execution unit.

Here I want to walk through:

1. the basic constraint
2. how to choose a separation model
3. the most practical shape for many desktop apps: `asInvoker` UI plus an elevated helper EXE
4. the mistakes worth avoiding during implementation
5. concrete code examples

The examples assume **.NET 8 on Windows desktop**.  
Whether the UI is WPF, WinForms, or WinUI does not change the core design very much.

## 1. The short version

In practice, the baseline usually looks like this:

- keep the normal UI process at `asInvoker`
- move administrator-only work into a **separate EXE**
- mark that helper EXE as `requireAdministrator`
- start it with `runas`
- use **named pipes** or another real IPC mechanism instead of standard input/output
- send **typed requests**, not raw command strings
- validate the request again on the helper side
- lock down the IPC connection by **caller user SID** and **expected PID**

"Just run the whole app as administrator" only feels easy at the beginning.  
Later it usually becomes painful around UAC behavior, drag and drop, logging, support workflows, DLL loading, and where settings are stored.

## 2. The basic constraint: you cannot elevate only part of one process

UAC is not a "function-level elevation" system.  
It is about **which token and integrity level the process itself is running under**.

That means a non-elevated UI process cannot suddenly decide that one method call should execute with administrative rights.  
If administrative rights are required, you need another execution boundary: another process, a service, a task, or a limited elevated COM design.

If that constraint is ignored, the design discussion usually turns into a sad variation of:

"Can this one button run as admin while the rest of the app stays normal?"

Windows does not provide magic for that.

## 3. Picking a separation model

Microsoft documents several common patterns for applications that need administrator privileges:

| Model | Rough shape | Best fit |
| --- | --- | --- |
| Administrator Broker Model | standard-user UI + elevated helper EXE | occasional administrative operations that can trigger UAC only when needed |
| Operating System Service Model | standard-user UI + service | always-on management features, background monitoring, unattended work |
| Elevated Task Model | standard-user UI + elevated scheduled task | short, repeatable operations that start and finish cleanly |
| Administrator COM Object Model | standard-user UI + elevated COM object | existing COM-heavy designs with a narrow feature boundary |

The practical selection usually looks like this.

### 3.1 The broker EXE is often the easiest first step

Typical examples are:

- registering or removing Explorer integration
- changing machine-wide settings under HKLM
- installing or removing the app's service
- adding or deleting firewall rules
- writing something under Program Files

These are often things the user does only occasionally from a settings page.  
For that kind of workload, a short-lived elevated helper EXE is often cleaner than introducing a permanent service.

### 3.2 A service makes sense when the work is constant or unattended

A service model gives you a management process that stays up and can be called without showing UAC every time.  
That is useful, but it also means you now own a long-running privileged process operationally.

That trade-off is more reasonable for cases like:

- continuous monitoring
- log collection
- background updating
- always-on device communication
- shared administrative features across multiple UI sessions

### 3.3 Tasks are good for short, fixed jobs

The elevated task model is lighter than a service and naturally fits one-off jobs that start, do the work, and end.

### 3.4 Elevated COM is narrower than it first looks

The COM elevation moniker can sound attractive, but it is usually more specialized than it appears.  
If the application is an ordinary desktop app without a strong COM-centered design already in place, it is rarely the easiest place to start.

## 4. Recommended shape here: `asInvoker` UI plus `requireAdministrator` helper EXE

For many desktop applications, the following structure is a good default:

```text
[ MyApp.exe ]  asInvoker
      |
      |  ShellExecute / ProcessStartInfo + Verb=runas
      v
[ MyApp.AdminBroker.exe ]  requireAdministrator
      |
      |  named pipe
      v
[ fixed administrator-only operation ]
```

Three points matter most:

1. **The UI stays non-elevated from start to finish**
2. **The elevated helper is short-lived**
3. **The helper accepts only a fixed allowlist of operations**

That alone removes a lot of confusion from the design.

## 5. Rules worth deciding before implementation

These are easier to get right before the code spreads.

### 5.1 Do not make the helper a generic command runner

Bad patterns look like this:

- the UI sends `reg add ...` as a full raw string
- the UI sends `sc.exe ...` as a full raw string
- the UI sends arbitrary registry paths or arbitrary executable paths

Once that happens, the helper becomes a privileged "do anything" box.

A better pattern is to make the operation itself fixed:

- `set-explorer-context-menu`
- `install-service`
- `add-firewall-rule`

and keep the parameters limited to things like booleans, enums, numbers, or tightly constrained strings.

### 5.2 Use absolute paths, and avoid letting the UI over-decide them

The helper EXE started through `runas` should be referenced by an **absolute path**.  
Do not lean on PATH lookup or relative paths.

It is also better if the helper resolves its real target locally instead of trusting the UI too much.  
In the sample below, the EXE registered for the Explorer context menu is resolved by the helper as `MyApp.exe` in the same folder.

### 5.3 If you use `Verb="runas"`, explicitly set `UseShellExecute=true`

In .NET, `ProcessStartInfo.Verb` works only when `UseShellExecute=true`.  
The default also differs between .NET Framework and newer .NET runtimes.

Leaving that to defaults is a good way to get a version-dependent failure later.

### 5.4 `runas` and redirected standard I/O do not fit well together

Once `UseShellExecute=true` is required, standard I/O redirection stops being a good transport choice.  
That is one reason named pipes are a much more natural fit for this design.

### 5.5 Do not trust the default ACLs on named pipes

Named pipes are real Windows security objects.  
If the elevated helper is exposing an IPC endpoint, relying on default ACLs is too loose for comfort.

Build the pipe security explicitly.

### 5.6 `PipeOptions.CurrentUserOnly` is not the answer here

This option looks promising at first glance, but on Windows it is not only about the account identity. It also cares about elevation context.

That makes it a poor fit for **medium-integrity UI <-> high-integrity helper** communication.

There is also another practical wrinkle: in a standard-user environment, UAC may become a **credential prompt**, and the helper can end up running as a different administrative account. If the helper builds its ACL from `WindowsIdentity.GetCurrent()` alone, the original UI user may no longer be able to connect.

So for this design, the cleaner approach is:

- the UI sends its own SID to the helper
- the helper grants pipe access specifically to that UI user SID
- the helper also verifies the client PID after the pipe connects

### 5.7 PID verification is a useful extra boundary

Even with a random pipe name, it is still better not to assume that any process under the same user should be able to race in and talk first.

That is why `GetNamedPipeClientProcessId` is helpful here.  
The helper can confirm that the connected client is the specific UI process that launched it.

This does **not** mean matching the PID is enough to trust everything.  
If the UI process itself is already compromised, the helper can still receive dangerous requests. That is exactly why the helper must keep a fixed operation allowlist and validate the arguments again.

## 6. The sample scenario

For the concrete example, I will use **registering or removing a machine-wide Explorer context menu entry**.

It is a good sample because:

- it needs administrator rights
- the boundary of the operation is clear
- there is no need to pass arbitrary command strings into the helper
- it is also a very believable real-world requirement

The fixed registry targets are:

- `HKLM\SOFTWARE\Classes\*\shell\MyApp.Open`
- `HKLM\SOFTWARE\Classes\*\shell\MyApp.Open\command`

The UI just exposes a checkbox like "Register Explorer context menu."  
The elevated helper does the registry write.

## 7. Suggested solution structure

```text
MyApp/
  MyApp/                         UI app (asInvoker)
    app.manifest
    ElevationBrokerClient.cs
    SettingsPage.xaml.cs
  MyApp.AdminBroker/             elevated helper (requireAdministrator)
    app.manifest
    Program.cs
    BrokerLaunchOptions.cs
    ExplorerContextMenuRegistration.cs
  MyApp.BrokerProtocol/          shared contract
    BrokerProtocol.cs
```

Keeping the shared contract in its own project makes it easier to keep these aligned:

- operation names
- request and response types
- the pipe message format

## 8. Manifests

### 8.1 UI-side manifest

```xml
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="1.0.0.0" name="MyApp.app" />
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="asInvoker" uiAccess="false" />
      </requestedPrivileges>
    </security>
  </trustInfo>
</assembly>
```

### 8.2 Helper-side manifest

```xml
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="1.0.0.0" name="MyApp.AdminBroker.app" />
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="requireAdministrator" uiAccess="false" />
      </requestedPrivileges>
    </security>
  </trustInfo>
</assembly>
```

The UI stays at `asInvoker`.  
Only the helper asks for elevation.  
If that is reversed, the separation loses much of its value.

## 9. Shared contract code

### 9.1 `MyApp.BrokerProtocol/BrokerProtocol.cs`

```csharp
using System.Buffers.Binary;
using System.Text.Json;

namespace MyApp.BrokerProtocol;

public static class BrokerJson
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };
}

public static class BrokerOperations
{
    public const string SetExplorerContextMenu = "set-explorer-context-menu";
}

public sealed record BrokerRequest(string Operation, JsonElement Payload);

public sealed record BrokerResponse(bool Success, string? ErrorCode, string? Message)
{
    public static BrokerResponse Ok(string? message = null) => new(true, null, message);

    public static BrokerResponse Fail(string errorCode, string message) =>
        new(false, errorCode, message);
}

public sealed record SetExplorerContextMenuRequest(bool Enabled);

public static class PipeMessageSerializer
{
    private const int MaxPayloadBytes = 256 * 1024;

    public static async Task WriteAsync<T>(Stream stream, T value, CancellationToken cancellationToken)
    {
        byte[] payload = JsonSerializer.SerializeToUtf8Bytes(value, BrokerJson.Options);
        if (payload.Length > MaxPayloadBytes)
        {
            throw new InvalidDataException($"Payload is too large: {payload.Length} bytes.");
        }

        byte[] header = new byte[sizeof(int)];
        BinaryPrimitives.WriteInt32LittleEndian(header, payload.Length);

        await stream.WriteAsync(header.AsMemory(0, header.Length), cancellationToken);
        await stream.WriteAsync(payload.AsMemory(0, payload.Length), cancellationToken);
        await stream.FlushAsync(cancellationToken);
    }

    public static async Task<T> ReadAsync<T>(Stream stream, CancellationToken cancellationToken)
    {
        byte[] header = await ReadExactAsync(stream, sizeof(int), cancellationToken);
        int payloadLength = BinaryPrimitives.ReadInt32LittleEndian(header);

        if (payloadLength <= 0 || payloadLength > MaxPayloadBytes)
        {
            throw new InvalidDataException($"Invalid payload length: {payloadLength}");
        }

        byte[] payload = await ReadExactAsync(stream, payloadLength, cancellationToken);

        return JsonSerializer.Deserialize<T>(payload, BrokerJson.Options)
            ?? throw new InvalidDataException($"Failed to deserialize {typeof(T).FullName}.");
    }

    private static async Task<byte[]> ReadExactAsync(Stream stream, int length, CancellationToken cancellationToken)
    {
        byte[] buffer = new byte[length];
        int offset = 0;

        while (offset < length)
        {
            int read = await stream.ReadAsync(buffer.AsMemory(offset, length - offset), cancellationToken);
            if (read == 0)
            {
                throw new EndOfStreamException("Pipe was closed before the expected number of bytes was read.");
            }

            offset += read;
        }

        return buffer;
    }
}
```

The main point is to avoid streaming arbitrary JSON forever over the pipe.  
A simple length-prefixed request / response shape is much harder to mis-handle.

## 10. UI side: launching the helper and talking to it

### 10.1 `MyApp/ElevationBrokerClient.cs`

```csharp
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO.Pipes;
using System.Security.Principal;
using System.Text.Json;
using MyApp.BrokerProtocol;

namespace MyApp;

public sealed class ElevationBrokerClient
{
    private readonly string _helperExePath;

    public ElevationBrokerClient(string helperExePath)
    {
        _helperExePath = Path.GetFullPath(helperExePath);

        if (!Path.IsPathRooted(_helperExePath))
        {
            throw new ArgumentException("Helper executable path must be absolute.", nameof(helperExePath));
        }

        if (!File.Exists(_helperExePath))
        {
            throw new FileNotFoundException("Helper executable was not found.", _helperExePath);
        }
    }

    public async Task SetExplorerContextMenuEnabledAsync(bool enabled, CancellationToken cancellationToken = default)
    {
        string pipeName = $"myapp-broker-{Guid.NewGuid():N}";
        int clientPid = Environment.ProcessId;
        string clientSid = GetCurrentUserSid();

        StartHelper(pipeName, clientPid, clientSid);

        using var pipe = new NamedPipeClientStream(
            serverName: ".",
            pipeName: pipeName,
            direction: PipeDirection.InOut,
            options: PipeOptions.Asynchronous);

        using var connectCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        connectCts.CancelAfter(TimeSpan.FromSeconds(30));

        await pipe.ConnectAsync(connectCts.Token);

        BrokerRequest request = new(
            BrokerOperations.SetExplorerContextMenu,
            JsonSerializer.SerializeToElement(
                new SetExplorerContextMenuRequest(enabled),
                BrokerJson.Options));

        await PipeMessageSerializer.WriteAsync(pipe, request, cancellationToken);

        BrokerResponse response = await PipeMessageSerializer.ReadAsync<BrokerResponse>(pipe, cancellationToken);

        if (!response.Success)
        {
            throw new InvalidOperationException(
                $"Admin broker returned an error. Code={response.ErrorCode}, Message={response.Message}");
        }
    }
}
```

The UI is not sending raw administrative commands.  
It launches the helper, opens the pipe, and sends a typed request. That boundary matters.

## 11. Helper side: parsing launch arguments

### 11.1 `MyApp.AdminBroker/BrokerLaunchOptions.cs`

```csharp
namespace MyApp.AdminBroker;

internal sealed class BrokerLaunchOptions
{
    public required string PipeName { get; init; }
    public required int ExpectedClientProcessId { get; init; }
    public required string ClientUserSid { get; init; }

    public static BrokerLaunchOptions Parse(string[] args)
    {
        string? pipeName = null;
        int? clientPid = null;
        string? clientSid = null;

        for (int i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--pipe":
                    pipeName = ReadNextValue(args, ref i, "--pipe");
                    break;
                case "--client-pid":
                    string pidText = ReadNextValue(args, ref i, "--client-pid");
                    if (!int.TryParse(pidText, out int pid) || pid <= 0)
                    {
                        throw new ArgumentException($"Invalid client PID: {pidText}");
                    }

                    clientPid = pid;
                    break;
                case "--client-sid":
                    clientSid = ReadNextValue(args, ref i, "--client-sid");
                    break;
                default:
                    throw new ArgumentException($"Unknown argument: {args[i]}");
            }
        }

        if (string.IsNullOrWhiteSpace(pipeName))
        {
            throw new ArgumentException("--pipe is required.");
        }

        if (clientPid is null)
        {
            throw new ArgumentException("--client-pid is required.");
        }

        if (string.IsNullOrWhiteSpace(clientSid))
        {
            throw new ArgumentException("--client-sid is required.");
        }

        return new BrokerLaunchOptions
        {
            PipeName = pipeName,
            ExpectedClientProcessId = clientPid.Value,
            ClientUserSid = clientSid
        };
    }
}
```

The helper should fail early if:

- an argument is missing
- an argument is malformed
- an argument is unexpected

Guessing what the caller meant is the wrong instinct inside an elevated boundary.

## 12. Helper side: pipe creation, PID verification, and dispatch

### 12.1 `MyApp.AdminBroker/Program.cs`

```csharp
using System.ComponentModel;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.Json;
using MyApp.BrokerProtocol;

namespace MyApp.AdminBroker;

internal static class Program
{
    public static async Task<int> Main(string[] args)
    {
        BrokerLaunchOptions options = BrokerLaunchOptions.Parse(args);

        using var brokerCts = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        using NamedPipeServerStream pipe = CreatePipeServer(options);

        await pipe.WaitForConnectionAsync(brokerCts.Token);

        VerifyClientProcessId(pipe, options.ExpectedClientProcessId);

        BrokerRequest request = await PipeMessageSerializer.ReadAsync<BrokerRequest>(pipe, brokerCts.Token);
        BrokerResponse response = await DispatchAsync(request);

        await PipeMessageSerializer.WriteAsync(pipe, response, brokerCts.Token);

        return response.Success ? 0 : 2;
    }

    private static Task<BrokerResponse> DispatchAsync(BrokerRequest request)
    {
        try
        {
            return request.Operation switch
            {
                BrokerOperations.SetExplorerContextMenu => HandleSetExplorerContextMenuAsync(request.Payload),
                _ => Task.FromResult(
                    BrokerResponse.Fail(
                        "unsupported_operation",
                        $"Unsupported operation: {request.Operation}"))
            };
        }
        catch (JsonException ex)
        {
            return Task.FromResult(BrokerResponse.Fail("invalid_payload", ex.Message));
        }
        catch (Exception ex)
        {
            return Task.FromResult(BrokerResponse.Fail("broker_failure", ex.Message));
        }
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetNamedPipeClientProcessId(
        IntPtr pipe,
        out uint clientProcessId);
}
```

The important ideas are:

- build the pipe ACL **explicitly**
- grant access not only to the helper identity but to the **original UI user SID**
- verify the **client PID** after the connection is established
- dispatch only through a fixed operation switch

That keeps the helper from drifting into a general elevated command box.

## 13. The administrative operation itself: Explorer context-menu registration

### 13.1 `MyApp.AdminBroker/ExplorerContextMenuRegistration.cs`

```csharp
using Microsoft.Win32;

namespace MyApp.AdminBroker;

internal static class ExplorerContextMenuRegistration
{
    private const string MenuKeyPath = @"SOFTWARE\Classes\*\shell\MyApp.Open";
    private const string CommandKeyPath = @"SOFTWARE\Classes\*\shell\MyApp.Open\command";
    private const string MenuText = "Open with MyApp";
    private const string ClientExecutableName = "MyApp.exe";

    public static void Apply(bool enabled)
    {
        string clientExePath = ResolveClientExecutablePath();

        using RegistryKey hklm = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, GetRegistryView());

        if (enabled)
        {
            using RegistryKey menuKey = hklm.CreateSubKey(MenuKeyPath)
                ?? throw new InvalidOperationException($"Failed to create registry key: {MenuKeyPath}");

            menuKey.SetValue(null, MenuText, RegistryValueKind.String);
            menuKey.SetValue("Icon", $"\"{clientExePath}\",0", RegistryValueKind.String);

            using RegistryKey commandKey = hklm.CreateSubKey(CommandKeyPath)
                ?? throw new InvalidOperationException($"Failed to create registry key: {CommandKeyPath}");

            commandKey.SetValue(null, $"\"{clientExePath}\" \"%1\"", RegistryValueKind.String);
        }
        else
        {
            hklm.DeleteSubKeyTree(@"SOFTWARE\Classes\*\shell\MyApp.Open", throwOnMissingSubKey: false);
        }
    }
}
```

The intent here matters more than the registry API calls themselves:

- the UI does **not** send an arbitrary registry path
- the UI does **not** send an arbitrary command string
- the helper resolves the target EXE in a fixed way
- the request contains only `Enabled`

That makes the helper mean one thing only: toggle this one Explorer integration feature.

## 14. Example UI call site

### 14.1 `MyApp/SettingsPage.xaml.cs`

```csharp
using System.Windows;

namespace MyApp;

public partial class SettingsPage
{
    private readonly ElevationBrokerClient _broker = new(
        Path.Combine(AppContext.BaseDirectory, "MyApp.AdminBroker.exe"));

    private async void ExplorerMenuCheckBox_Click(object sender, RoutedEventArgs e)
    {
        bool enabled = ExplorerMenuCheckBox.IsChecked == true;

        try
        {
            await _broker.SetExplorerContextMenuEnabledAsync(enabled);
            MessageBox.Show("Setting has been updated.", "MyApp");
        }
        catch (OperationCanceledException)
        {
            MessageBox.Show("The administrator approval prompt was canceled.", "MyApp");
            ExplorerMenuCheckBox.IsChecked = !enabled;
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "Failed to update the setting.");
            ExplorerMenuCheckBox.IsChecked = !enabled;
        }
    }
}
```

The UI-side job is intentionally small:

- read the checkbox state
- call the broker client
- restore the UI if the operation fails

The registry stays out of the UI process.

## 15. What this design is really enforcing

The useful boundaries here are:

- **clear responsibility split** between UI and helper
- **no generic execution channel** inside the elevated process
- **fixed launch path** for the helper
- **restricted IPC origin** through SID and PID checks
- **fixed administrator target surface** rather than arbitrary registry or file operations

That is what moves the helper away from "elevated utility box" and closer to "one narrow administrator boundary."

## 16. Common mistakes

### 16.1 Marking the whole UI as `requireAdministrator`

If only one settings-page button needs elevation, making the entire UI elevated is just flattening the privilege boundary.

### 16.2 Passing raw command strings into the helper

Patterns like this are the wrong direction:

```text
UI -> helper sends "reg add HKLM\\.... /v ... /d ..."
```

That makes the helper a privileged command executor.

### 16.3 Using default named-pipe ACLs

"It is only local IPC" is not enough.  
Named pipes are part of the Windows security model, so the ACL deserves deliberate design.

### 16.4 Reaching for `CurrentUserOnly` too quickly

It sounds convenient, but it is not a good fit for this medium-integrity UI to high-integrity helper path.

### 16.5 Letting the helper act on arbitrary paths or names

For example:

- copy any file into Program Files
- write any HKLM key
- delete any service name
- add a firewall rule from any incoming command string

That is how the helper turns into a general privileged execution surface.

## 17. Wrap-up

Needing administrator rights for only part of a Windows application is not unusual.  
The mistake is thinking the answer must be "make the whole application elevated."

The more sustainable answer is usually:

- keep the UI at `asInvoker`
- move administrator work into a helper EXE
- mark only that helper as `requireAdministrator`
- launch it with `runas`
- communicate through named pipes
- accept only fixed operations
- restrict the pipe client by SID and PID
- validate the request again inside the helper

That shape also ages well.  
If the design later wants to move toward a service model, the operation contract and the boundary already exist. That boundary itself becomes reusable design work.

Most security improvements are not about adding something flashy.  
They are about refusing to leave a sloppy boundary in place.  
Administrator rights are no different.

## 18. References

- Previous article: A Minimum Security Checklist for Windows Application Development  
  https://comcomponent.com/en/blog/2026/03/14/001-windows-app-security-minimum-checklist/
- Administrator Broker Model - Win32 apps  
  https://learn.microsoft.com/en-us/windows/win32/secauthz/administrator-broker-model
- Developing Applications that Require Administrator Privilege  
  https://learn.microsoft.com/en-us/windows/win32/secauthz/developing-applications-that-require-administrator-privilege
- Operating System Service Model - Win32 apps  
  https://learn.microsoft.com/en-us/windows/win32/secauthz/operating-system-service-model
- Elevated Task Model - Win32 apps  
  https://learn.microsoft.com/en-us/windows/win32/secauthz/elevated-task-model
- Administrator COM Object Model - Win32 apps  
  https://learn.microsoft.com/en-us/windows/win32/secauthz/administrator-com-object-model
- The COM Elevation Moniker  
  https://learn.microsoft.com/en-us/windows/win32/com/the-com-elevation-moniker
- How User Account Control works  
  https://learn.microsoft.com/en-us/windows/security/application-security/application-control/user-account-control/how-it-works
- ProcessStartInfo.UseShellExecute  
  https://learn.microsoft.com/en-us/dotnet/fundamentals/runtime-libraries/system-diagnostics-processstartinfo-useshellexecute
- Named Pipe Security and Access Rights  
  https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipe-security-and-access-rights
- PipeOptions Enum  
  https://learn.microsoft.com/en-us/dotnet/api/system.io.pipes.pipeoptions?view=net-10.0
- NamedPipeServerStreamAcl.Create  
  https://learn.microsoft.com/en-us/dotnet/api/system.io.pipes.namedpipeserverstreamacl.create?view=net-10.0
- GetNamedPipeClientProcessId  
  https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getnamedpipeclientprocessid
- RegistryView Enum  
  https://learn.microsoft.com/en-us/dotnet/api/microsoft.win32.registryview?view=net-8.0
