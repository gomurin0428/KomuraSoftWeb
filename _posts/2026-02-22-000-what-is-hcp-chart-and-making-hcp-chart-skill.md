---
title: "HCPチャートとは何か - HCP-DSL を決定的 SVG に変換する MakingHCPChartSkill の使い方"
date: 2026-02-22 10:00
lang: ja
translation_key: what-is-hcp-chart-and-making-hcp-chart-skill
tags: [HCP, Codex, SVG, Python, 設計]
author: Go Komura
description: "HCPチャートとは何かを説明しつつ、MakingHCPChartSkill で HCP-DSL を決定的 SVG に変換する流れ、読み方、使い方をまとめます。"
consultation_services:
  - id: technical-consulting
    reason: "設計や処理の流れを見える形で整理したいテーマなので、技術相談・設計レビューの文脈で活きやすい記事です。"
---

# HCPチャートとは何か - HCP-DSL を決定的 SVG に変換する MakingHCPChartSkill の使い方

## 目次

1. [HCPチャートとは何か](#1-hcpチャートとは何か)
2. [このリポジトリが解決する課題](#2-このリポジトリが解決する課題)
3. [リポジトリ構成を最短で把握する](#3-リポジトリ構成を最短で把握する)
4. [10分ハンズオン（GCDサンプル）](#4-10分ハンズオンgcdサンプル)
5. [サンプル2例の読み方](#5-サンプル2例の読み方)
6. [中で何をしているか（HCPチャート）](#6-中で何をしているかhcpチャート)
7. [まとめ](#7-まとめ)

---

HCPチャートを「仕様として読める図」にしたいとき、手書きの図だけでは運用が難しくなります。  
`MakingHCPChartSkill` は、**HCP-DSL（テキスト）を仕様に沿って解釈し、決定的なSVGを返す**ためのスキルリポジトリです。

この記事では、HCPチャートの基本から始めて、実際に動かすところまでを一気に確認します。

## 1. HCPチャートとは何か

HCPチャートは、処理を階層的に記述するための表現です。  
このリポジトリでは、次の書き方が必須ルールとして扱われています。

- 左側は「何を達成するか（目的）」
- 右側（深いインデント）は「どう達成するか（手段・詳細）」
- 最上位（レベル0）には目的ラベルを書く

このルールに沿ってテキストを書くことで、設計意図と実装詳細の対応が読み取りやすくなります。

## 2. このリポジトリが解決する課題

図だけを人手で管理すると、次の問題が起きがちです。

- 図と仕様テキストがズレる
- 分岐や階層の制約が曖昧になる
- 差分レビューしづらい

`MakingHCPChartSkill` では、HCP-DSLをJSONリクエストとして渡し、`hcp_render_svg.py` が検証と描画を行います。  
同じ入力なら同じ出力になるため、図をCIやレビューに組み込みやすい構成です。

## 3. リポジトリ構成を最短で把握する

対象リポジトリ: `https://github.com/gomurin0428/MakingHCPChartSkill`

- `hcp-chart-svg-v2/SKILL.md`  
  スキルの使い方と制約（`renderAllModules` と `module` の同時指定禁止など）。
- `hcp-chart-svg-v2/scripts/hcp_render_svg.py`  
  JSON入力を検証し、HCP-DSLを解釈してSVGレスポンスを返す本体。
- `hcp-chart-svg-v2/references/`  
  仕様リファレンス、サンプルrequest/response、サンプルSVG。
- `hcp-chart-svg-v2/scripts/hcp_xml_to_svg.py`  
  deprecated。現在は `hcp_render_svg.py` を使う。

## 4. 10分ハンズオン（GCDサンプル）

### 4.1. リポジトリを取得する

```powershell
git clone https://github.com/gomurin0428/MakingHCPChartSkill.git
cd .\MakingHCPChartSkill
```

### 4.2. スキルをローカル Codex に配置する

```powershell
Copy-Item -Recurse -Force .\hcp-chart-svg-v2 "$HOME\.codex\skills\hcp-chart-svg-v2"
```

### 4.3. サンプル入力からSVGレスポンスを生成する

```powershell
python .\hcp-chart-svg-v2\scripts\hcp_render_svg.py `
  --input .\hcp-chart-svg-v2\references\example-gcd-request.json `
  --output .\hcp-chart-svg-v2\references\example-gcd-response.json `
  --pretty
```

### 4.4. レスポンスJSONからSVGを取り出す

```powershell
$r = Get-Content -Raw .\hcp-chart-svg-v2\references\example-gcd-response.json | ConvertFrom-Json
$r.svg | Set-Content -NoNewline -Encoding utf8 .\hcp-chart-svg-v2\references\example-gcd.svg
```

### 4.5. 補足（入力制約）

- `renderAllModules=true` のときは `module` を指定できません。
- `diagnostics` に `error` がある場合、`svg` または `svgs` は空になります。

## 5. サンプル2例の読み方

### 5.1. ユークリッドの互除法（GCD）

- 入力例: `example-gcd-request.json`
- 出力例: `example-gcd-response.json`

![GCDサンプルのHCPチャート](/assets/images/hcp-chart-skill/example-gcd.svg)

「入力の受け取り」「繰り返し」「返却」が階層で分離されていて、処理の目的と手段が追いやすい構成です。

### 5.2. 受注承認フロー

- 入力例: `example-order-approval-request.json`
- 出力例: `example-order-approval-response.json`

![受注承認サンプルのHCPチャート](/assets/images/hcp-chart-skill/example-order-approval.svg)

業務フローでも、`fork` と `true/false` を使って分岐の意図を明確に記述できます。

## 6. 中で何をしているか（HCPチャート）

`execute_request` の処理フローを、HCP-DSLで表現すると次のようになります。

```text
\module main
リクエストを受け取り前提を確認する
    入力JSONの必須項目を検証する
DSLを解析して構造化する
    モジュールと階層を解釈する
    diagnostics を収集する
診断結果に応じて応答経路を選ぶ
    \fork error が存在するか
        \true はい
            空の SVG 系ペイロードを返す
        \false いいえ
            描画対象モジュールを決定する
            \fork renderAllModules が true か
                \true はい
                    全モジュールの SVG を生成する
                    svgs を含む応答JSONを組み立てる
                \false いいえ
                    単一モジュールの SVG を生成する
                    svg を含む応答JSONを組み立てる
結果を呼び出し元へ返す
```

上のDSLを実際にレンダリングした図がこちらです。

![MakingHCPChartSkill内部処理フローのHCPチャート](/assets/images/hcp-chart-skill/skill-internal-flow.svg)

## 7. まとめ

HCPチャートは、図として見やすいだけでなく、**仕様として扱える形で管理できる**のが強みです。  
`MakingHCPChartSkill` を使うと、HCP-DSLを検証しながらSVGまで一貫して生成できます。

次に試すなら、普段の処理仕様を1つHCP-DSLで書き、`diagnostics` を見ながら整形していくと導入効果が実感しやすいです。

## 参考資料

- [MakingHCPChartSkill](https://github.com/gomurin0428/MakingHCPChartSkill)
- [hcp-chart-svg-v2/SKILL.md](https://github.com/gomurin0428/MakingHCPChartSkill/blob/main/hcp-chart-svg-v2/SKILL.md)
- [hcp-chart-svg-v2/scripts/hcp_render_svg.py](https://github.com/gomurin0428/MakingHCPChartSkill/blob/main/hcp-chart-svg-v2/scripts/hcp_render_svg.py)
