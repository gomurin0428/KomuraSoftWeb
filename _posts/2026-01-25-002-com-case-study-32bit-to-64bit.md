---
title: "COMが役立つケーススタディ-32bitアプリから64bit DLLを呼び出したいとき"
date: 2026-01-25 11:00
tags: [COM, Windows開発, 32bit, 64bit]
author: Go Komura
---

# COMが役立つケーススタディ-32bitアプリから64bit DLLを呼び出したいとき

## 想定状況

32bitの既存アプリを保ったまま、**64bit DLLの処理を使いたい**というケースです。  
しかし、32bitプロセスは64bit DLLを読み込めません。これはOSレベルでの制約です。

よくある状況は次のようなものです。

- 既存の32bitアプリは資産として大きく、すぐには移行できない
- 64bit DLL側に新機能がある、または依存ライブラリが64bitのみ
- 32bit側から「型付きで」呼び出したい

このとき、**「同一プロセス内で呼び出す」ことは不可能**です。

## 解決方法

解決の基本は、**Out-of-proc COM（EXEサーバー）で分離する**ことです。  
64bit DLLは64bitのCOMサーバー（EXE）から呼び出し、32bitアプリはCOM経由で使います。

流れは次の通りです。

1. 64bitのCOM LocalServer（EXE）を用意し、内部で64bit DLLを呼び出す
2. COMインターフェース（IDL/TypeLib）を共有し、型を公開する
3. 32bitアプリはCOMを「型付き」で呼び出す（Proxy/Marshalでやり取り）

注意点としては以下があります。

- **32bit/64bitの登録は別**（WOW6432Node含む）
- **独自構造体はマーシャリング設計が必要**
- **IPCのオーバーヘッド**があるため、高頻度呼び出しは注意

つまり、**「64bitの処理を別プロセスに逃がして、COMで橋渡しする」**のが王道です。

## 処理の流れ（シーケンス図）

以下は、32bitアプリが64bit DLLの処理を呼び出すときの流れです。

<pre class="mermaid">
sequenceDiagram
    participant App as 32bit クライアントアプリ
    box rgba(100,100,255,0.1) COMが自動で処理（開発者は意識不要）
        participant Proxy as COM Proxy<br/>(32bit側)
        participant RPC as RPC/IPC<br/>(プロセス間通信)
        participant Stub as COM Stub<br/>(64bit側)
    end
    participant Server as 64bit COM Server<br/>(EXE)
    participant DLL as 64bit DLL

    App->>Proxy: ICalcService.Add(1, 2)
    rect rgba(100,100,255,0.1)
        Note over Proxy: パラメータをマーシャリング
        Proxy->>RPC: シリアライズされたデータ
        RPC->>Stub: プロセス境界を越えて転送
        Note over Stub: パラメータをアンマーシャリング
    end
    Stub->>Server: Add(1, 2)
    Server->>DLL: ネイティブ関数呼び出し
    DLL-->>Server: 結果: 3
    Server-->>Stub: 結果: 3
    rect rgba(100,100,255,0.1)
        Note over Stub: 戻り値をマーシャリング
        Stub-->>RPC: シリアライズされた結果
        RPC-->>Proxy: プロセス境界を越えて転送
        Note over Proxy: 戻り値をアンマーシャリング
    end
    Proxy-->>App: 結果: 3
</pre>

**ポイント:**
- 32bitアプリは `ICalcService` インターフェースを通じて型安全に呼び出せる
- COMランタイムが自動的にProxy/Stubを生成・管理
- プロセス間通信のオーバーヘッドがあるため、細かい呼び出しより一括処理が望ましい

## サンプルコード(イメージ。全てCSharp)

以下は**概念のイメージ**です。実際には登録やTypeLibの生成などが必要です。

```csharp
// 共有インターフェース（IDL相当）
[ComVisible(true)]
[Guid("7A4B5B23-0A2F-4D2B-9D4D-8A2A92B8B001")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ICalcService
{
    int Add(int a, int b);
}

// 64bit COM LocalServer（EXE側）
[ComVisible(true)]
[Guid("1C9B6F4D-1E9A-4E61-9A4F-6A0F1D2D9A11")]
[ClassInterface(ClassInterfaceType.None)]
public class CalcService : ICalcService
{
    public int Add(int a, int b)
    {
        // ここで64bit DLLを呼び出す
        return a + b;
    }
}

// 32bitアプリ側（クライアント）
Type t = Type.GetTypeFromProgID("KomuraSoft.CalcService");
var calc = (ICalcService)Activator.CreateInstance(t);
int result = calc.Add(1, 2);
```

この形にすると、32bit側は**「型付きで」**扱えます。  
COMが内部でプロキシ/スタブを使い、IPC経由で呼び出してくれます。

## 完全なサンプルコード

上記の概念を実際に動作する形で実装したサンプルを GitHub で公開しています。

**[Call64bitDLLFrom32bitProc - GitHub](https://github.com/gomurin0428/Call64bitDLLFrom32bitProc)**

このリポジトリには以下が含まれています：

- **Call64bitDLLFrom32bitProc/** - 64bit COM LocalServer (EXE)
- **X64DLL/** - 64bit DLL（実処理）
- **X86App/** - 32bit クライアント (WinForms)
- **scripts/** - COM サーバー登録・解除スクリプト

README に記載の手順に従ってビルド・登録すれば、実際に 32bit プロセスから 64bit DLL を呼び出す動作を確認できます。

## 参考資料

- Component Object Model (COM) の概要  
  https://learn.microsoft.com/en-us/windows/win32/com/component-object-model--com--portal
- COM LocalServer32 の登録  
  https://learn.microsoft.com/en-us/windows/win32/com/localserver32
- COM インターフェースの基本  
  https://learn.microsoft.com/en-us/windows/win32/com/the-component-object-model
- COM Interop（.NETからの利用）  
  https://learn.microsoft.com/en-us/dotnet/standard/native-interop/cominterop
