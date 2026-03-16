---
title: "Windowsアプリで「管理者権限が必要な処理だけ」を分離する具体的な書き方"
date: 2026-03-16 10:00
lang: ja
translation_key: windows-admin-broker-deep-dive
tags:
  - Windows開発
  - セキュリティ
  - UAC
  - C# / .NET
  - Win32
description: "Windows アプリで UI を asInvoker のまま保ちつつ、管理者権限が必要な処理だけを helper EXE に分離する設計を、UAC、runas、名前付きパイプ、入力検証まで含めて具体的に整理します。"
consultation_services:
  - id: windows-app-development
    reason: "UAC、helper EXE、サービス化の見極め、machine-wide 設定変更まで含めて Windows アプリ全体の権限設計に関わるので、Windowsアプリ開発 と相性がよいテーマです。"
  - id: technical-consulting
    reason: "既存アプリの `requireAdministrator` 常用を見直し、broker 設計や IPC 境界を再整理したい場合は、技術相談・設計レビューとして進めやすいテーマです。"
---

以前書いた「[Windowsアプリ開発における最低限のセキュリティを守るためのチェックリスト](https://comcomponent.com/blog/2026/03/14/001-windows-app-security-minimum-checklist/)」では、`asInvoker` を基本にし、管理者権限が必要な処理だけを分離する、という線を書きました。

今回はその部分を、**実際にどう書くか**まで踏み込みます。

Windows アプリでは、**同じプロセスの中の一部の処理だけを都合よく「管理者として実行」することはできません**。  
昇格はプロセス境界の話なので、必要なのは「その処理だけを別の実行単位に切り出す設計」です。

ここでは、次の順で整理します。

1. まず前提
2. どの分離モデルを選ぶか
3. いちばん実務で使いやすい `asInvoker` + 管理者 helper EXE の形
4. 実装時に外したくない罠
5. 具体的なコード例

コード例は **.NET 8 / Windows デスクトップアプリ** を前提にしています。  
UI フレームワークは WPF / WinForms / WinUI のどれでもよく、違いが出るのは UI 側のイベントハンドラくらいです。

## 1. まず結論

先に結論だけ並べると、実務ではだいたい次です。

- 通常の UI アプリは `asInvoker` のまま動かす
- 管理者権限が必要な処理は **別 EXE** に切り出す
- その helper EXE は `requireAdministrator` にする
- 起動は `runas` で行う
- helper との通信は、`runas` と相性の悪い標準入出力ではなく、**名前付きパイプ**などの IPC を使う
- helper に渡すのは「生のコマンド文字列」ではなく、**型付きの要求**だけにする
- helper 側では、**要求内容をもう一度検証**する
- IPC の接続元は、**呼び出し元ユーザー SID と想定 PID** で絞る

「管理者で動けば楽」は、最初の 1 回だけです。  
あとで UAC、ドラッグ＆ドロップ、ログ設計、外部入力、サポート運用、DLL 読み込み、設定保存先あたりで、だいたい嫌な顔をされます。

## 2. 前提整理: 同じプロセスの一部だけを管理者化することはできない

Windows の UAC は、「関数単位の昇格」ではなく「**プロセスがどのトークン / 整合性レベルで動いているか**」で制御されます。  
管理者アクセス トークンが必要なアプリは昇格プロンプトの対象になり、親子プロセスは同じ整合性レベルでトークンを継承します。  
つまり、**非昇格の UI プロセスの中で、あるメソッドだけを急に管理者権限で実行する**という設計はできません。  
必要なら、別プロセス・サービス・タスク・昇格 COM など、別の実行単位を使います。

この前提を外して考えると、「このボタンを押した瞬間だけ管理者にしたい」という、少し気の毒な設計相談になります。  
Windows はそこを魔法では埋めてくれません。

## 3. どの分離モデルを選ぶか

Microsoft Learn では、管理者権限が必要なアプリの分離方法として、主に次の 4 つが挙げられています。

| モデル | ざっくりした形 | 向いている場面 |
| --- | --- | --- |
| Administrator Broker Model | 標準ユーザーの UI アプリ + 管理者 helper EXE | 管理者操作が散発的で、必要な瞬間だけ UAC を出せばよい |
| Operating System Service Model | 標準ユーザー UI + 常駐 service | 常時稼働の管理機能、バックグラウンド監視、無人処理 |
| Elevated Task Model | 標準ユーザー UI + 管理者権限のスケジュールタスク | 一回ごとに短く終わる定型処理 |
| Administrator COM Object Model | 標準ユーザー UI + 昇格 COM | 既存 COM 設計があり、機能がかなり限定される場合 |

ざっくりした選び方はこうです。

### 3.1 最初に検討しやすいのは broker EXE

たとえば次のようなケースです。

- Explorer 連携の登録 / 解除
- HKLM 配下の machine-wide 設定変更
- 自アプリの service 登録 / 解除
- ファイアウォール規則の追加 / 削除
- Program Files 配下の管理者操作

これらは、**普段は不要で、設定画面の特定ボタンを押した時だけ必要**になりがちです。  
この場合は、常駐 service まで持ち出すより、**管理者 helper EXE を一回だけ起動して終わる**形のほうが素直です。

### 3.2 service を選ぶのは「常時」「無人」「頻繁」

service は、標準ユーザーアプリから RPC 等で通信するモデルです。  
利点は **昇格プロンプトなし**で管理側処理を受けられることですが、その代わり、**常駐プロセスを運用する責任**が増えます。

たとえば次のようなケースです。

- 常時監視
- ログ収集
- バックグラウンド更新
- 装置やデーモンとの常時連携
- 複数 UI セッションから共有される管理機能

### 3.3 task は「短い定型処理」に向く

Elevated Task Model は、標準ユーザーアプリから管理者権限で動くスケジュールタスクを起動する形です。  
service より軽く、終わったら閉じるので、**1 回ごとの定型ジョブ**には合います。

### 3.4 昇格 COM はかなり限定的

COM elevation moniker は便利そうに見えますが、使いどころは絞られます。  
Microsoft Learn でも、昇格 COM を制御できる UI は COM 側で提示する必要がある、とされていて、**「非昇格 UI から昇格 COM に好き勝手させる」方向には向いていません**。

## 4. 今回のおすすめ: `asInvoker` UI + `requireAdministrator` helper EXE

ここからは、いちばん実務で使いやすい形を具体化します。

```text
[ MyApp.exe ]  asInvoker
      |
      |  ShellExecute / ProcessStartInfo + Verb=runas
      v
[ MyApp.AdminBroker.exe ]  requireAdministrator
      |
      |  named pipe
      v
[ 管理者権限が必要な固定処理だけ実行 ]
```

ポイントは 3 つです。

1. **UI プロセスは最後まで非昇格のまま**
2. **管理者 helper は短命**
3. **helper が受け付ける操作は固定の allowlist のみ**

この 3 つを守るだけで、設計がかなり整理されます。

## 5. 実装で外したくないルール

ここはコードを書く前に決めたほうがよいところです。

### 5.1 helper は「なんでも屋」にしない

ダメな例はこれです。

- UI から helper に `reg add ...` を丸ごと文字列で渡す
- UI から helper に `sc.exe ...` を丸ごと文字列で渡す
- UI から helper に任意のレジストリパスや任意の EXE パスを渡す

これをやると、**UI が壊れたら helper も一緒に壊れます**。  
管理者 helper は、昇格境界の内側です。  
ここに「何でも実行できる口」を作ると、だいぶ危ない。

よい形はこうです。

- `set-explorer-context-menu`
- `install-service`
- `add-firewall-rule`

のように **操作自体を固定**し、必要な引数も **bool / enum / 数値 / 限定された文字列** に寄せます。

### 5.2 helper に渡す path は absolute、しかも UI で決めすぎない

`runas` で起動する helper EXE 自体は、**絶対パスで指定**します。  
PATH 検索や相対パス任せは避けます。

さらに、helper が実行する対象も、できるだけ helper 側で固定解決します。  
今回のサンプルでは、Explorer コンテキストメニューに登録する対象 EXE を **helper と同じフォルダにある `MyApp.exe` に固定**します。

### 5.3 `Verb=\"runas\"` を使うなら `UseShellExecute=true` を明示する

.NET では `ProcessStartInfo.Verb` は `UseShellExecute=true` のときにだけ有効です。  
しかも `UseShellExecute` の既定値は .NET Framework と .NET Core / .NET で違います。  
ここを既定値任せにすると、あとで「動く環境と動かない環境がある」という、地味にむかつく事故が起きます。

なので、ここは**必ず明示**します。

### 5.4 `runas` と標準入出力リダイレクトは相性が悪い

`UseShellExecute=true` にすると、標準入出力のリダイレクト前提の通信は使いにくくなります。  
そのため、helper とのやり取りは **named pipe** など、別の IPC を使ったほうが素直です。

### 5.5 名前付きパイプは既定 ACL に頼らない

名前付きパイプは、既定のセキュリティ記述子だと、Everyone や匿名に読み取り権が入る既定になっています。  
管理者 helper の IPC にそれをそのまま使うのは、かなり雑です。

**必ず明示的な `PipeSecurity` を設定**したほうがよいです。

### 5.6 `PipeOptions.CurrentUserOnly` は今回の用途では使わない

これ、ぱっと見だと便利そうです。  
ただし Windows では、`CurrentUserOnly` は**ユーザーアカウントだけでなく昇格レベルも確認**します。  
つまり、**非昇格 UI と昇格 helper の通信には向きません**。

しかも、標準ユーザー環境では UAC が **credential prompt** になり、helper が別の管理者アカウントで動くことがあります。  
この場合、helper 側で `WindowsIdentity.GetCurrent()` をそのまま使って ACL を作ると、**元の UI ユーザーが繋げなくなる**ことがあります。

なので今回は、

- UI 側で自分の SID を取得して helper に渡す
- helper 側では **UI ユーザー SID にだけ** pipe 接続権を与える
- さらに `GetNamedPipeClientProcessId` で **接続元 PID** も確認する

という形にします。

### 5.7 PID 検証は「雑な横入り」を減らすための追加防御

ランダムな pipe 名だけでもだいぶましですが、同じユーザーで動く別プロセスが先に接続する余地はゼロではありません。  
そこで helper 側で `GetNamedPipeClientProcessId` を使い、**想定した UI プロセス PID と一致するか**を確認します。

もちろん、**PID が合っていれば何でも信用してよい**わけではありません。  
UI が侵害されていれば、helper にも危険な要求が届きます。  
だからこそ、helper 側の operation allowlist と引数検証が必要です。

## 6. サンプルの題材

今回は、**Explorer の右クリックメニューを machine-wide に登録 / 解除する**例にします。

理由は単純で、

- 管理者権限が必要
- 操作の境界がはっきりしている
- helper に任意のコマンド文字列を渡さずに済む
- 実務でも普通にあり得る

からです。

登録先は次のような固定キーです。

- `HKLM\SOFTWARE\Classes\*\shell\MyApp.Open`
- `HKLM\SOFTWARE\Classes\*\shell\MyApp.Open\command`

UI は「Explorer の右クリックメニューに登録する」のチェックボックスだけ持ち、実際のレジストリ操作は helper 側で行います。

## 7. ソリューション構成

```text
MyApp/
  MyApp/                         UI アプリ (asInvoker)
    app.manifest
    ElevationBrokerClient.cs
    SettingsPage.xaml.cs
  MyApp.AdminBroker/             管理者 helper (requireAdministrator)
    app.manifest
    Program.cs
    BrokerLaunchOptions.cs
    ExplorerContextMenuRegistration.cs
  MyApp.BrokerProtocol/          共通契約
    BrokerProtocol.cs
```

共通契約を別プロジェクトにしておくと、

- operation 名
- request / response 型
- パイプのメッセージ形式

を UI と helper で揃えやすくなります。

## 8. マニフェスト

### 8.1 UI 側 (`MyApp/app.manifest`)

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

### 8.2 helper 側 (`MyApp.AdminBroker/app.manifest`)

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

UI はずっと `asInvoker`。  
helper だけ `requireAdministrator`。  
ここを逆にすると、せっかく分けた意味が消えます。

## 9. 共通契約コード

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

ポイントは、**pipe に JSON をそのままだらだら流さず、長さ付きで送る**ことです。  
1 回の要求、1 回の応答、という単純なプロトコルにしておくと事故りにくいです。

## 10. UI 側: helper の起動と通信

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

    private void StartHelper(string pipeName, int clientPid, string clientSid)
    {
        string workingDirectory = Path.GetDirectoryName(_helperExePath)
            ?? throw new InvalidOperationException("Helper executable directory could not be resolved.");

        var startInfo = new ProcessStartInfo
        {
            FileName = _helperExePath,
            Arguments = BuildArguments(pipeName, clientPid, clientSid),
            WorkingDirectory = workingDirectory,
            UseShellExecute = true,
            Verb = "runas"
        };

        try
        {
            Process.Start(startInfo)
                ?? throw new InvalidOperationException("The helper process could not be started.");
        }
        catch (Win32Exception ex) when (ex.NativeErrorCode == 1223)
        {
            throw new OperationCanceledException("管理者権限の承認がキャンセルされました。", ex);
        }
    }
}
```

ここで helper に渡しているのは、pipe 名と接続元確認に必要な最小情報だけです。  
管理者操作そのものは、pipe の中で送る **型付き request** に閉じ込めます。

## 11. helper 側: 起動引数の解析

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

    private static string ReadNextValue(string[] args, ref int index, string optionName)
    {
        if (index + 1 >= args.Length)
        {
            throw new ArgumentException($"A value is required after {optionName}.");
        }

        index++;
        return args[index];
    }
}
```

helper 側は **引数が足りない / 余計な引数がある** 時点でエラーにします。  
昇格境界の内側で「とりあえず頑張って解釈する」は、やらないほうがよいです。

## 12. helper 側: pipe 作成・接続元 PID 検証・dispatch

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

ここでの重要点は次です。

- pipe の ACL を **明示的に組み立てる**
- ACL は **helper の現在ユーザー SID ではなく、呼び出し元 UI ユーザー SID にも付与**する
- 接続後に **client PID を検証**する
- request を受けたあとも **operation 名で dispatch**する

`switch (request.Operation)` で固定の操作しか通さない形にしておくと、helper が「昇格した何でも箱」になりにくいです。

## 13. 管理者操作の本体: Explorer 右クリックメニュー登録

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

このコードの意図はかなり重要です。

- UI から **任意のレジストリパス**を受け取っていない
- UI から **任意のコマンド文字列**を受け取っていない
- 登録対象 EXE は helper 側で **固定解決**している
- request の内容は `Enabled` だけ

つまり、helper は「Explorer 右クリックメニューの登録状態を切り替える」という、**一つの意味しか持たない**ようにしてあります。

## 14. UI からの呼び出し例

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

UI 側は普通です。

- チェックボックスの状態を読む
- broker client を呼ぶ
- 失敗したら UI を戻す

だけです。  
レジストリを直接触りません。  
それが分離です。

## 15. この実装で押さえていること

このサンプルで実際に守っている線を整理すると、こうです。

### 15.1 UI と helper の責務分離

- UI は、利用者の操作を受けるだけ
- helper は、固定の管理者操作だけを実行する

### 15.2 helper に「任意実行口」を作っていない

- 任意レジストリパスを受けていない
- 任意コマンドラインを受けていない
- 任意 EXE パスを受けていない

### 15.3 起動経路が固定

- helper EXE は absolute path
- `runas` を明示
- `UseShellExecute = true` を明示

### 15.4 IPC 接続元を絞っている

- pipe ACL を UI ユーザー SID に限定
- 接続後に client PID を確認

### 15.5 管理者操作の対象も固定

- レジストリの hive / path が固定
- 登録対象 EXE も固定解決

これくらいまでやると、「UI が壊れたら helper で何でもできる」状態からはかなり離れます。

## 16. よくある NG

### 16.1 UI 全体を `requireAdministrator` にする

設定画面の 1 ボタンだけ管理者権限が必要なのに、全部昇格で起動する。  
これは、権限境界を雑に潰す方向です。

### 16.2 helper に生の文字列コマンドを渡す

たとえばこういう設計です。

```text
UI -> helper に "reg add HKLM\\.... /v ... /d ..."
```

これは helper が command executor になります。  
やめたほうがよいです。

### 16.3 名前付きパイプの既定 ACL をそのまま使う

「ローカル IPC だから大丈夫だろう」は、少し危ない。  
パイプは Windows セキュリティの対象なので、**ちゃんと ACL を作る**ほうがよいです。

### 16.4 `CurrentUserOnly` に飛びつく

便利そうですが、今回の **medium integrity の UI ↔ high integrity の helper** には向きません。  
ここは explicit ACL のほうが扱いやすいです。

### 16.5 helper が任意 path を受け取って操作する

たとえば次のようなものです。

- 任意ファイルを Program Files にコピー
- 任意キーを HKLM に書く
- 任意 service 名を削除
- 任意コマンドで firewall rule を追加

helper がそれを受けると、helper 自体が管理者権限の汎用実行口になります。  
操作は必ず **固定化**したほうがよいです。

## 17. まとめ

Windows アプリで「一部の処理だけ管理者権限が必要」というのは、珍しい話ではありません。  
ただし、その解き方は「全部 `requireAdministrator` にする」ではなく、**実行境界を切る**ことです。

最初に取りやすい形は、次です。

- UI は `asInvoker`
- 管理者処理は helper EXE に分離
- helper は `requireAdministrator`
- 起動は `runas`
- 通信は named pipe
- helper は固定 operation しか受けない
- pipe ACL と client PID で接続元を絞る
- helper 側で引数を再検証する

この形にしておくと、あとから service 化したくなったときも移行しやすいです。  
operation 契約をきちんと分けておけば、**UI と管理者処理の境界がそのまま設計資産**になります。

セキュリティの話は、派手な機能を足すことより、**雑な境界を残さない**ことのほうが効きます。  
管理者権限も同じです。  
全部まとめて持たせるのではなく、必要なところだけ、できるだけ狭く渡す。  
そのくらいの地味さが、あとで効いてきます。

## 18. 参考資料

- 元記事: Windowsアプリ開発における最低限のセキュリティを守るためのチェックリスト  
  https://comcomponent.com/blog/2026/03/14/001-windows-app-security-minimum-checklist/
- Administrator Broker Model - Win32 apps  
  https://learn.microsoft.com/ja-jp/windows/win32/secauthz/administrator-broker-model
- Developing Applications that Require Administrator Privilege  
  https://learn.microsoft.com/en-us/windows/win32/secauthz/developing-applications-that-require-administrator-privilege
- Operating System Service Model - Win32 apps  
  https://learn.microsoft.com/ja-jp/windows/win32/secauthz/operating-system-service-model
- Elevated Task Model - Win32 apps  
  https://learn.microsoft.com/en-us/windows/win32/secauthz/elevated-task-model
- Administrator COM Object Model - Win32 apps  
  https://learn.microsoft.com/ja-jp/windows/win32/secauthz/administrator-com-object-model
- The COM Elevation Moniker  
  https://learn.microsoft.com/en-us/windows/win32/com/the-com-elevation-moniker
- How User Account Control works  
  https://learn.microsoft.com/en-us/windows/security/application-security/application-control/user-account-control/how-it-works
- ProcessStartInfo.UseShellExecute  
  https://learn.microsoft.com/ja-jp/dotnet/fundamentals/runtime-libraries/system-diagnostics-processstartinfo-useshellexecute
- Named Pipe Security and Access Rights  
  https://learn.microsoft.com/ja-jp/windows/win32/ipc/named-pipe-security-and-access-rights
- PipeOptions Enum  
  https://learn.microsoft.com/en-us/dotnet/api/system.io.pipes.pipeoptions?view=net-10.0
- NamedPipeServerStreamAcl.Create  
  https://learn.microsoft.com/en-us/dotnet/api/system.io.pipes.namedpipeserverstreamacl.create?view=net-10.0
- GetNamedPipeClientProcessId  
  https://learn.microsoft.com/ja-jp/windows/win32/api/winbase/nf-winbase-getnamedpipeclientprocessid
- RegistryView Enum  
  https://learn.microsoft.com/ja-jp/dotnet/api/microsoft.win32.registryview?view=net-8.0
