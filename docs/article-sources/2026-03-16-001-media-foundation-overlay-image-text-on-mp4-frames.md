# Media Foundation で MP4 動画の各フレームに画像や文字を入れるにはどうするか - Source Reader / Direct2D / Video Processor MFT / Sink Writer の実務的な分解

2026年03月16日 10:00 · 小村 豪 · Media Foundation, C++, Windows開発, Direct2D, DirectWrite

ロゴ透かし、時刻焼き込み、検査結果、装置番号、作業者名。  
こうした情報を MP4 動画の各フレームに重ねたい、という要件は監視、検査、証跡、分析 UI ではかなり普通にあります。

ただ、Media Foundation を触り始めると、`IMFSourceReader`、`IMFSample`、`IMFMediaBuffer`、`IMFTransform`、`IMFSinkWriter` が並び、「で、結局どこで文字を描けばいいのか」が急に見えにくくなります。

ここで大事なのは、**Media Foundation は主にデコード、エンコード、サンプルの受け渡しを担当し、文字や画像の描画そのものは Direct2D / DirectWrite / WIC 側に任せる**、という役割分担で考えることです。

Media Foundation の全体像は以前書いた [Media Foundation とは何か - COM と Windows メディア API の顔が見えてくる理由](https://comcomponent.com/blog/2026/03/09/002-media-foundation-why-it-feels-like-com/) も参考になります。  
また、`IMFSourceReader` で MP4 から 1 枚抜く話は [Media Foundation で MP4 動画の指定時刻から静止画を取り出す方法 - .cpp にそのまま貼れる 1 ファイル完結版](https://comcomponent.com/blog/2026/03/15/000-media-foundation-extract-still-image-from-mp4-at-specific-time/) にまとめています。今回はそこからもう一歩進めて、**各フレームにオーバーレイを焼き込んで、もう一度動画として出力する**ところに絞ります。

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

雑にまとめると、**「Media Foundation で文字を入れる」ではなく、「Media Foundation でフレームを回し、描画 API で載せ、必要な色変換を入れてからエンコードする」**と考えるのが正解に近いです。

## 3. まず見る整理表

| 方針 | 構成 | 向いている場面 | 気をつける点 |
|---|---|---|---|
| まず正しく動かす | `Source Reader -> RGB32/ARGB32 -> 合成 -> Video Processor MFT -> NV12 -> Sink Writer` | バッチ処理、社内ツール、初期実装 | コピー回数が増えやすい |
| 速度を上げる | `D3D11 / DXGI surface -> Direct2D/DirectWrite -> Video Processor MFT -> Sink Writer` | 長尺動画、高解像度、フレーム数が多い処理 | D3D11 と DXGI の管理が増える |
| 再利用できる部品にする | custom `MFT` として実装して topology に差し込む | 複数アプリで使うエフェクト、MF パイプラインへ組み込みたい場合 | 実装、登録、デバッグの難度が上がる |

### 3.1 処理イメージ

```mermaid
flowchart LR
    A[MP4 / バイト列] --> B[IMFSourceReader]
    B --> C[非圧縮フレーム<br/>ARGB32 / RGB32]
    C --> D[画像・文字の合成<br/>Direct2D / DirectWrite / WIC]
    D --> E[RGB -> NV12 変換<br/>Video Processor MFT]
    E --> F[IMFSinkWriter]
    F --> G[MP4(H.264)]

    B --> H[音声サンプル]
    H --> I[そのままコピー<br/>または再エンコード]
    I --> F
```

この形にしておくと、どこが Media Foundation で、どこが描画 API で、どこが色変換なのかが見えます。

## 4. いちばん実務で扱いやすい構成

### 4.1 入力は `IMFSourceReader` で受ける

入力がファイルパスなら `MFCreateSourceReaderFromURL`、すでにメモリ上の動画データなら `IMFByteStream` を作って `MFCreateSourceReaderFromByteStream` を使う構成が分かりやすいです。

「与えられた動画データ」がファイルではなく生バイト列や独自ストリームなら、`IStream` を `MFCreateMFByteStreamOnStream` で `IMFByteStream` に包んでから `Source Reader` に渡す形が素直です。

ここで最初に決めるべきなのは、**描画しやすい形式で受けるか、エンコーダー向けの形式で受けるか**です。

- 実装を簡単にしたいなら、まず `RGB32` または `ARGB32`
- エンコード効率を優先するなら `NV12` などの YUV

ただし、**文字や PNG の合成は RGB 系のほうが圧倒的に考えやすい**ので、初手は `RGB32 / ARGB32` を受ける構成が実務ではかなり多いです。

### 4.2 `Source Reader` 側の変換は便利だが、万能ではない

`MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING` を有効にすると、`Source Reader` は `YUV -> RGB32` 変換とインターレース解除をしてくれます。  
これは「まずフレームを取り出して扱いたい」段階ではかなり楽です。

ただし、これは**ソフトウェア処理で、リアルタイム再生向けには最適化されていない**ので、長い動画や高解像度動画では重くなりがちです。

Windows 8 以降なら `MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING` も使えます。こちらは、

- より広い形式変換
- サイズ変更
- フレームレート変換
- 一部 GPU 利用

まで見込めるので、少し本気の実装ではこちらも選択肢に入ります。

ただし、どちらにしても **「描画」そのものは別の層** です。`Source Reader` は「描きやすい形まで持ってくる」担当だと思っておくのが安全です。

なお、D3D11 ベースで surface を扱う設計に寄せるなら、`MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING` に頼りすぎず、明示的な D3D 管理や `MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING` / `Video Processor MFT` 側に責務を寄せたほうが整理しやすいです。

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

この構成は分かりやすいです。  
特に、ロゴの重ね合わせ、四角形の描画、簡単な字幕、タイムスタンプなどはこれで十分なことが多いです。

#### B. GPU / DXGI surface 寄りの構成

- D3D11 でデコード結果を DXGI surface として扱う
- Direct2D でその surface に直接描く
- DirectWrite で文字を描く
- そのまま後段の色変換 / エンコードへ渡す

こちらは速いですが、D3D11 デバイス、DXGI surface、共有サーフェス、同期など、急に部品が増えます。  
長尺の 1080p / 4K 処理や、1 本ではなく大量本数を回す場合に効いてきます。

### 4.4 `ARGB32` のまま `H.264` へ書けるとは限らない

ここが一番ハマりやすいポイントです。

`mp4(H.264)` に戻すとき、**Microsoft の H.264 エンコーダー入力は `I420 / IYUV / NV12 / YUY2 / YV12` などの YUV 系が基本**です。  
つまり、合成しやすい `RGB32 / ARGB32` で描いたあと、そのまま `IMFSinkWriter` に投げれば終わり、にはなりません。

ここで必要になるのが、**RGB 系フレームを YUV 系へ戻す変換段**です。

実務では次のどちらかが多いです。

- `Video Processor MFT` を挟んで `ARGB32/RGB32 -> NV12`
- 自前の変換処理を入れる

後者はかなり面倒です。  
そのため、まずは `CLSID_VideoProcessorMFT` を使える構成にして、**描画は RGB、エンコーダー入力は NV12** と割り切るほうがかなり楽です。

しかも `Video Processor MFT` は、

- 色空間変換
- サイズ変更
- インターレース解除
- フレームレート変換

まで担当できます。  
「最終出力のサイズを少し変えたい」「入力がインターレースかもしれない」といった話も、この段に寄せやすくなります。

透過 PNG をロゴに使う場合も、最終的な MP4 は通常は**不透明な動画フレームへ焼き込まれる**と考えておくと整理しやすいです。透過は合成時点で使い切る、というイメージです。

### 4.5 出力は `IMFSinkWriter` で書く

動画出力は `IMFSinkWriter` が扱いやすいです。

考え方は単純で、

- **出力ストリーム型** … ファイルに書きたい形式  
  例: `MFVideoFormat_H264`
- **入力ストリーム型** … アプリが `Sink Writer` に渡す形式  
  例: `MFVideoFormat_NV12`

を分けて設定します。

つまり `Sink Writer` から見ると、

- あなたのアプリは `NV12` の非圧縮フレームを渡す
- `Sink Writer` はそれを H.264 にエンコードして MP4 に書く

という関係になります。

ここで大事なのは、**`Sink Writer` 自体は勝手に何でも変換してくれる魔法の箱ではない**ことです。  
サイズ変更、フレームレート変換、音声リサンプリングなどは、必要なら前段で済ませておく前提で考えたほうが安全です。

### 4.6 音声は「触らないならそのまま残す」が実務的

動画にロゴや文字を入れたいだけで、音声そのものは変えたくない、ということはかなり多いです。

この場合、映像 stream だけは

- デコード
- 合成
- 色変換
- 再エンコード

しますが、音声 stream は **圧縮のまま同一形式で書き戻す** 構成が取りやすいです。

`Sink Writer` は **compressed input with identical output** をサポートしているので、音声がそのまま出せる条件なら、**音声だけ remux** できます。  
実務でかなり助かるやつです。

もちろん、入力音声の形式が出力コンテナにそのまま合わない場合や、音声も加工したい場合は別途オーディオ側の再エンコードが必要です。  
ただ、最初の実装では **「映像だけ再エンコード、音声はそのまま」** を目標にすると、全体がかなり見えやすくなります。

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

擬似コードにすると、イメージはこんな感じです。

```text
初期化
  COM と Media Foundation を初期化
  Source Reader を作成
  Video stream は RGB32 / ARGB32 で受ける
  Audio stream は native compressed のままにする
  Video Processor MFT を RGB -> NV12 で構成
  Sink Writer を MP4(H.264) 出力で構成
  Sink Writer の video input は NV12 にする
  必要なら audio stream も追加

ループ
  video sample を ReadSample で取得
  flags を見て end-of-stream / stream tick を処理
  sample があれば timestamp と duration を取得
  sample buffer を取り出す
  logo と text を合成する
  RGB sample を NV12 sample に変換する
  output sample に timestamp / duration を設定する
  Sink Writer へ WriteSample する

  音声を残すなら audio sample も順次 WriteSample する

終了
  Sink Writer::Finalize
  shutdown
```

この時点で見えてくるはずのことは、**「描画」と「エンコード前の色変換」は別工程**だという点です。  
ここを 1 つにまとめて考えると急に混乱します。

## 6. 先に押さえる落とし穴

### 6.1 `ReadSample` は成功しても `sample == nullptr` がある

`ReadSample` は `S_OK` でも、`ppSample == nullptr` になることがあります。  
典型例は、

- end of stream
- stream tick
- そのほかストリームイベント

です。

なので `HRESULT` だけではなく、

- `pdwStreamFlags`
- `ppSample`

の両方を見る必要があります。

### 6.2 タイムスタンプは 100ns 単位で、duration は別に見る

`pllTimestamp` は 100 ナノ秒単位です。  
また、duration は別に `IMFSample` から取得する話になります。

ここで雑に「30fps だから毎回 333333 を足せばよい」とすると、可変フレームレートや編集済み素材で地味に破綻します。  
**1 入力フレーム -> 1 出力フレーム** の単純変換なら、入力 sample の timestamp / duration をそのまま引き継ぐほうが安全です。

### 6.3 `IMFSample` から生ポインターを取る前に、まずバッファー構成を見る

`IMFSample` は 1 つとは限らず、複数バッファーを持てます。  
そのため、生メモリに触りたいときは `ConvertToContiguousBuffer` を先に使う構成が安全です。

### 6.4 stride を `width * bytesPerPixel` と決め打ちしない

これはとても大事です。

- 行末にパディングが入る
- pitch が想像より広い
- 2D buffer では負の stride になり得る

ので、`width * 4` のような決め打ちは危険です。  
`IMF2DBuffer::Lock2D` が使えるなら、まずこちらで pitch を受けたほうが安全です。

### 6.5 `ARGB32` で描いたのに `H.264` 側で詰まる

かなり普通に起きます。

原因は単純で、**H.264 エンコーダーの入力が RGB 前提ではない**からです。  
ここで初めて「RGB で描いて、最後に NV12 へ戻す必要があるのか」と分かることが多いです。地味ですが本丸です。

### 6.6 `MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING` は楽だが、重いことがある

この属性は入口として便利ですが、ソフトウェア処理です。  
少数フレームの抽出や、重くてもいいオフライン処理ならかなり助かりますが、長尺・高解像度・大量本数の処理ではボトルネックになりやすいです。

最初の 1 本を通したあとで重いと分かったら、

- `D3D11 + DXGI surface`
- `Direct2D/DirectWrite`
- `Video Processor MFT`

寄りに持っていくと改善しやすいです。

### 6.7 `Sink Writer` はサイズ変更やフレームレート変換の魔法箱ではない

出力側でサイズや fps を変えたいなら、前段で揃える意識が必要です。  
この意味でも `Video Processor MFT` を 1 段持っておくと整理しやすくなります。

## 7. custom MFT はいつ選ぶべきか

ここまで読むと、「最初から custom MFT のほうが Media Foundation らしいのでは」と思うかもしれません。  
それは半分正しいです。

実際、Media Foundation ではエフェクトを `IMFTransform` として実装できますし、グレースケール化の SDK サンプルもあります。  
再利用できる動画エフェクト部品として育てたいなら、custom MFT はきれいです。

ただし、最初の 1 本目としては次の理由で少し重いです。

- `IMFTransform` 契約を満たす必要がある
- 入出力メディアタイプ管理が増える
- MFT の登録や列挙の話が出てくる
- タイムスタンプやストリーム変更まで面倒を見る必要がある

なので、**まずは手動ループで正しさを作り、後で custom MFT に切り出す**ほうが、実務ではだいたい速いです。

整理すると、次のようになります。

- **1 アプリ内で完結するツール**  
  `Source Reader + Direct2D/DirectWrite + Video Processor MFT + Sink Writer`
- **複数アプリや pipeline で使い回したいエフェクト**  
  custom MFT
- **再生パイプラインやトポロジへ自然に差し込みたい**  
  custom MFT / topology 寄りの設計

## 8. まとめ

Media Foundation で MP4 の各フレームに画像や文字を入れたいときは、発想を次の 4 つに分けると急に見やすくなります。

- `Source Reader` で **圧縮動画を非圧縮フレームにする**
- Direct2D / DirectWrite / WIC で **画像や文字を合成する**
- 必要なら `Video Processor MFT` で **RGB から NV12 などへ戻す**
- `Sink Writer` で **H.264 として MP4 に書く**

つまり、**「Media Foundation で文字を入れる」ではなく、「Media Foundation でフレームを回し、描画 API で載せ、エンコーダー向けの形式に整えて書き戻す」** という分解で考えるのがいちばん実務的です。

特に MP4/H.264 では、

- 画像や文字は RGB 系で描きたい
- でもエンコーダーは YUV 系を好む

というズレが本質です。  
ここを先に知っているかどうかで、実装の迷い方がかなり変わります。

## 9. 関連記事

- [Media Foundation とは何か - COM と Windows メディア API の顔が見えてくる理由](https://comcomponent.com/blog/2026/03/09/002-media-foundation-why-it-feels-like-com/)
- [Media Foundation で MP4 動画の指定時刻から静止画を取り出す方法 - .cpp にそのまま貼れる 1 ファイル完結版](https://comcomponent.com/blog/2026/03/15/000-media-foundation-extract-still-image-from-mp4-at-specific-time/)

## 10. 参考資料

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
