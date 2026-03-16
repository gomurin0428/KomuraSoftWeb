---
title: "Media Foundation で MP4 動画の各フレームに画像や文字を入れるにはどうするか - Source Reader / Direct2D / Video Processor MFT / Sink Writer の実務的な分解"
date: 2026-03-16 10:00
lang: ja
translation_key: media-foundation-overlay-image-text-on-mp4-frames
tags:
  - Media Foundation
  - C++
  - Windows開発
  - Direct2D
  - DirectWrite
description: "Media Foundation で MP4 の各フレームに画像や文字を焼き込むときの考え方を、Source Reader、Direct2D / DirectWrite、Video Processor MFT、Sink Writer の役割分担で整理します。"
consultation_services:
  - id: windows-app-development
    reason: "Media Foundation、Direct2D、DirectWrite、動画入出力をまたぐ構成整理は Windows アプリ開発そのものに直結するので、Windowsアプリ開発 と相性がよいテーマです。"
  - id: technical-consulting
    reason: "オーバーレイ処理をどこで行うべきか、RGB と YUV の変換をどう分けるか、custom MFT まで含めて設計判断したい場合は技術相談・設計レビューとして進めやすいです。"
---

ロゴ透かし、時刻焼き込み、検査結果、装置番号、作業者名。  
こうした情報を MP4 動画の各フレームに重ねたい、という要件は監視、検査、証跡、分析 UI ではかなり普通にあります。

ただ、Media Foundation を触り始めると、`IMFSourceReader`、`IMFSample`、`IMFMediaBuffer`、`IMFTransform`、`IMFSinkWriter` が並び、「で、結局どこで文字を描けばいいのか」が急に見えにくくなります。

ここで大事なのは、**Media Foundation は主にデコード、エンコード、サンプルの受け渡しを担当し、文字や画像の描画そのものは Direct2D / DirectWrite / WIC 側に任せる**、という役割分担で考えることです。

Media Foundation の全体像は以前書いた [Media Foundation とは何か - COM と Windows メディア API の顔が見えてくる理由](https://comcomponent.com/blog/2026/03/09/002-media-foundation-why-it-feels-like-com/) も参考になります。  
また、`IMFSourceReader` で MP4 から 1 枚抜く話は [Media Foundation で MP4 動画の指定時刻から静止画を取り出す方法](https://comcomponent.com/blog/2026/03/15/000-media-foundation-extract-still-image-from-mp4-at-specific-time/) にまとめています。今回はそこからもう一歩進めて、**各フレームにオーバーレイを焼き込んで、もう一度動画として出力する**ところに絞ります。

## 1. まず結論

- `mp4` の各フレームに画像や文字を入れる基本形は、`Source Reader でデコード -> 非圧縮フレームに合成 -> 必要なら色変換 -> Sink Writer で再エンコード` です。
- 画像や文字を置く処理そのものは、Media Foundation より `Direct2D + DirectWrite` か `WIC` で考えるほうが素直です。
- `MP4(H.264)` に戻すなら、描きやすい `RGB32 / ARGB32` と、エンコーダーが受けやすい `NV12 / I420 / YUY2` のあいだをつなぐ変換段が必要になりやすいです。
- 音声を触らないなら、**映像だけ再エンコードして、音声はそのまま remux** する構成が実務ではかなり使いやすいです。
- 初手で custom MFT に飛び込むより、まずは `IMFSourceReader + IMFSinkWriter` の手動パイプラインで全体を掴むほうが事故りにくいです。

## 2. この問題が少しややこしい理由

「動画に文字を入れる」は、実際には次の 4 つの話が混ざっています。

1. **コンテナとコーデックの話**  
   `mp4` はコンテナであって、フレームそのものではありません。中身はたいてい `H.264` や `H.265` の圧縮データです。

2. **デコード / エンコードの話**  
   圧縮済みのままでは、普通の 2D 描画 API で文字や PNG をそのまま載せられません。まず非圧縮フレームに戻す必要があります。

3. **描画の話**  
   文字、ロゴ、PNG の透明合成、アンチエイリアス付きのテキスト描画は、Media Foundation 本体の役割ではありません。ここは Direct2D / DirectWrite / WIC の仕事です。

4. **色空間とピクセル形式の話**  
   描画しやすい形式と、エンコーダーが好む形式は一致しません。ここが地味に嫌な罠です。

雑にまとめると、**「Media Foundation で文字を入れる」ではなく、「Media Foundation でフレームを回し、描画 API で載せ、必要な色変換を入れてからエンコードする」** と考えるのが正解に近いです。

## 3. まず見る整理表

| 方針 | 構成 | 向いている場面 | 気をつける点 |
| --- | --- | --- | --- |
| まず正しく動かす | `Source Reader -> RGB32 / ARGB32 -> 合成 -> Video Processor MFT -> NV12 -> Sink Writer` | バッチ処理、社内ツール、初期実装 | コピー回数が増えやすい |
| 速度を上げる | `D3D11 / DXGI surface -> Direct2D / DirectWrite -> Video Processor MFT -> Sink Writer` | 長尺動画、高解像度、フレーム数が多い処理 | D3D11 と DXGI の管理が増える |
| 再利用できる部品にする | custom `MFT` として実装して topology に差し込む | 複数アプリで使うエフェクト、MF パイプラインへ組み込みたい場合 | 実装、登録、デバッグの難度が上がる |

```mermaid
flowchart LR
    A["MP4 / バイト列"] --> B["IMFSourceReader"]
    B --> C["非圧縮フレーム<br/>ARGB32 / RGB32"]
    C --> D["画像・文字の合成<br/>Direct2D / DirectWrite / WIC"]
    D --> E["RGB -> NV12 変換<br/>Video Processor MFT"]
    E --> F["IMFSinkWriter"]
    F --> G["MP4(H.264)"]

    B --> H["音声サンプル"]
    H --> I["そのままコピー<br/>または再エンコード"]
    I --> F
```

## 4. いちばん実務で扱いやすい構成

### 4.1 入力は `IMFSourceReader` で受ける

入力がファイルパスなら `MFCreateSourceReaderFromURL`、すでにメモリ上の動画データなら `IMFByteStream` を作って `MFCreateSourceReaderFromByteStream` を使う構成が分かりやすいです。

ここで最初に決めるべきなのは、**描画しやすい形式で受けるか、エンコーダー向けの形式で受けるか**です。

- 実装を簡単にしたいなら、まず `RGB32` または `ARGB32`
- エンコード効率を優先するなら `NV12` などの YUV

ただし、**文字や PNG の合成は RGB 系のほうが圧倒的に考えやすい**ので、初手は `RGB32 / ARGB32` を受ける構成が実務ではかなり多いです。

### 4.2 `Source Reader` 側の変換は便利だが、万能ではない

`MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING` を有効にすると、`Source Reader` は `YUV -> RGB32` 変換とインターレース解除をしてくれます。  
これは「まずフレームを取り出して扱いたい」段階ではかなり楽です。

ただし、これは**ソフトウェア処理で、リアルタイム再生向けには最適化されていない**ので、長い動画や高解像度動画では重くなりがちです。

### 4.3 画像や文字の合成は Direct2D / DirectWrite / WIC で考える

ここが本題です。

Media Foundation で受け取った `IMFSample` からバッファーを取り出し、その上にロゴ画像やテキストを載せます。  
このときの考え方は、だいたい次の 2 通りです。

#### A. CPU / システムメモリ寄りの構成

- `IMFSample` から `IMFMediaBuffer` を取得
- 必要なら `ConvertToContiguousBuffer`
- `Lock` あるいは `IMF2DBuffer::Lock2D`
- ピクセルバッファーに対して画像合成
- テキストは Direct2D / DirectWrite でオフスクリーン描画、または自前ブレンド

#### B. GPU / DXGI surface 寄りの構成

- D3D11 でデコード結果を DXGI surface として扱う
- Direct2D でその surface に直接描く
- DirectWrite で文字を描く
- そのまま後段の色変換 / エンコードへ渡す

こちらは速いですが、D3D11 デバイス、DXGI surface、共有サーフェス、同期など、急に部品が増えます。

### 4.4 `ARGB32` のまま `H.264` へ書けるとは限らない

ここが一番ハマりやすいポイントです。

`mp4(H.264)` に戻すとき、**Microsoft の H.264 エンコーダー入力は `I420 / IYUV / NV12 / YUY2 / YV12` などの YUV 系が基本**です。  
つまり、合成しやすい `RGB32 / ARGB32` で描いたあと、そのまま `IMFSinkWriter` に投げれば終わり、にはなりません。

ここで必要になるのが、**RGB 系フレームを YUV 系へ戻す変換段**です。

実務では次のどちらかが多いです。

- `Video Processor MFT` を挟んで `ARGB32 / RGB32 -> NV12`
- 自前の変換処理を入れる

後者はかなり面倒です。  
そのため、まずは `CLSID_VideoProcessorMFT` を使える構成にして、**描画は RGB、エンコーダー入力は NV12**と割り切るほうがかなり楽です。

### 4.5 出力は `IMFSinkWriter` で書く

動画出力は `IMFSinkWriter` が扱いやすいです。

- **出力ストリーム型** … ファイルに書きたい形式  
  例: `MFVideoFormat_H264`
- **入力ストリーム型** … アプリが `Sink Writer` に渡す形式  
  例: `MFVideoFormat_NV12`

つまり `Sink Writer` から見ると、

- あなたのアプリは `NV12` の非圧縮フレームを渡す
- `Sink Writer` はそれを H.264 にエンコードして MP4 に書く

という関係になります。

### 4.6 音声は「触らないならそのまま残す」が実務的

動画にロゴや文字を入れたいだけで、音声そのものは変えたくない、ということはかなり多いです。

この場合、映像 stream だけは

- デコード
- 合成
- 色変換
- 再エンコード

しますが、音声 stream は **圧縮のまま同一形式で書き戻す**構成が取りやすいです。

## 5. 実装の流れ

全体の流れは、だいたい次のようになります。

1. `CoInitializeEx` と `MFStartup`
2. `Source Reader` を作る
3. 映像 stream は `RGB32 / ARGB32` で受ける設定にする
4. 音声 stream は必要なら native compressed のまま読む
5. Direct2D / DirectWrite / WIC の描画リソースを作る
6. `Video Processor MFT` を作って `RGB -> NV12` を構成する
7. `Sink Writer` を作り、映像出力を `H.264`、入力を `NV12` に設定する
8. 必要なら音声 stream も `Sink Writer` に追加する
9. `ReadSample` で 1 フレームずつ読み、合成して、変換して、`WriteSample`
10. `Finalize`
11. `MFShutdown` と `CoUninitialize`

## 6. 先に押さえる落とし穴

### 6.1 `ReadSample` は成功しても `sample == nullptr` がある

`ReadSample` は `S_OK` でも、`ppSample == nullptr` になることがあります。

- end of stream
- stream tick
- そのほかストリームイベント

なので `HRESULT` だけではなく、

- `pdwStreamFlags`
- `ppSample`

の両方を見る必要があります。

### 6.2 タイムスタンプは 100ns 単位で、duration は別に見る

`pllTimestamp` は 100 ナノ秒単位です。  
また、duration は別に `IMFSample` から取得する話になります。

**1 入力フレーム -> 1 出力フレーム** の単純変換なら、入力 sample の timestamp / duration をそのまま引き継ぐほうが安全です。

### 6.3 `IMFSample` から生ポインターを取る前に、まずバッファー構成を見る

`IMFSample` は 1 つとは限らず、複数バッファーを持てます。  
そのため、生メモリに触りたいときは `ConvertToContiguousBuffer` を先に使う構成が安全です。

### 6.4 stride を `width * bytesPerPixel` と決め打ちしない

- 行末にパディングが入る
- pitch が想像より広い
- 2D buffer では負の stride になり得る

ので、`width * 4` のような決め打ちは危険です。  
`IMF2DBuffer::Lock2D` が使えるなら、まずこちらで pitch を受けたほうが安全です。

### 6.5 `ARGB32` で描いたのに `H.264` 側で詰まる

かなり普通に起きます。

原因は単純で、**H.264 エンコーダーの入力が RGB 前提ではない**からです。  
ここで初めて「RGB で描いて、最後に NV12 へ戻す必要があるのか」と分かることが多いです。

## 7. custom MFT はいつ選ぶべきか

Media Foundation ではエフェクトを `IMFTransform` として実装できますし、グレースケール化の SDK サンプルもあります。再利用できる動画エフェクト部品として育てたいなら、custom MFT はきれいです。

ただし、最初の 1 本目としては次の理由で少し重いです。

- `IMFTransform` 契約を満たす必要がある
- 入出力メディアタイプ管理が増える
- MFT の登録や列挙の話が出てくる
- タイムスタンプやストリーム変更まで面倒を見る必要がある

なので、**まずは手動ループで正しさを作り、後で custom MFT に切り出す**ほうが、実務ではだいたい速いです。

## 8. まとめ

Media Foundation で MP4 の各フレームに画像や文字を入れたいときは、発想を次の 4 つに分けると急に見やすくなります。

- `Source Reader` で **圧縮動画を非圧縮フレームにする**
- Direct2D / DirectWrite / WIC で **画像や文字を合成する**
- 必要なら `Video Processor MFT` で **RGB から NV12 などへ戻す**
- `Sink Writer` で **H.264 として MP4 に書く**

つまり、**「Media Foundation で文字を入れる」ではなく、「Media Foundation でフレームを回し、描画 API で載せ、エンコーダー向けの形式に整えて書き戻す」**という分解で考えるのがいちばん実務的です。

## 9. 参考資料

- Microsoft Learn: [Using the Source Reader to Process Media Data](https://learn.microsoft.com/en-us/windows/win32/medfound/processing-media-data-with-the-source-reader)
- Microsoft Learn: [MFCreateSourceReaderFromByteStream](https://learn.microsoft.com/ja-jp/windows/win32/api/mfreadwrite/nf-mfreadwrite-mfcreatesourcereaderfrombytestream)
- Microsoft Learn: [MFCreateMFByteStreamOnStream](https://learn.microsoft.com/ja-jp/windows/win32/api/mfidl/nf-mfidl-mfcreatemfbytestreamonstream)
- Microsoft Learn: [IMFSourceReader::SetCurrentMediaType](https://learn.microsoft.com/ja-jp/windows/win32/api/mfreadwrite/nf-mfreadwrite-imfsourcereader-setcurrentmediatype)
- Microsoft Learn: [MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING](https://learn.microsoft.com/ja-jp/windows/win32/medfound/mf-source-reader-enable-video-processing)
- Microsoft Learn: [MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING](https://learn.microsoft.com/ja-jp/windows/win32/medfound/mf-source-reader-enable-advanced-video-processing)
- Microsoft Learn: [IMFSourceReader::ReadSample](https://learn.microsoft.com/ja-jp/windows/win32/api/mfreadwrite/nf-mfreadwrite-imfsourcereader-readsample)
- Microsoft Learn: [Working with Media Samples](https://learn.microsoft.com/ja-jp/windows/win32/medfound/working-with-media-samples)
- Microsoft Learn: [IMF2DBuffer::Lock2D](https://learn.microsoft.com/ja-jp/windows/win32/api/mfobjects/nf-mfobjects-imf2dbuffer-lock2d)
- Microsoft Learn: [Video Subtype GUIDs](https://learn.microsoft.com/ja-jp/windows/win32/medfound/video-subtype-guids)
- Microsoft Learn: [H.264 Video Encoder](https://learn.microsoft.com/en-us/windows/win32/medfound/h-264-video-encoder)
- Microsoft Learn: [Video Processor MFT](https://learn.microsoft.com/en-us/windows/win32/medfound/video-processor-mft)
- Microsoft Learn: [Using the Sink Writer](https://learn.microsoft.com/en-us/windows/win32/medfound/using-the-sink-writer)
- Microsoft Learn: [Tutorial: Using the Sink Writer to Encode Video](https://learn.microsoft.com/en-us/windows/win32/medfound/tutorial--using-the-sink-writer-to-encode-video)
- Microsoft Learn: [Interoperability Overview (Direct2D)](https://learn.microsoft.com/ja-jp/windows/win32/direct2d/interoperability-overview)
- Microsoft Learn: [Text Rendering with Direct2D and DirectWrite](https://learn.microsoft.com/en-us/windows/win32/direct2d/direct2d-and-directwrite)
- Microsoft Learn: [Writing a Custom MFT](https://learn.microsoft.com/ja-jp/windows/win32/medfound/writing-a-custom-mft)
