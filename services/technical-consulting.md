---
layout: service-page
lang: ja
translation_key: service-technical-consulting
permalink: /services/technical-consulting/
title: "技術相談・設計レビュー | 合同会社小村ソフト"
service_name: "技術相談・設計レビュー"
service_type: "Technical consulting and design review"
description: "Windows ソフトの設計や改修方針に迷っている方向けに、技術選定、設計レビュー、既存資産の整理を支援するサービスページです。"
service_keywords:
  - 技術相談
  - 設計レビュー
  - 改修方針
  - Windows設計
  - COM / ActiveX
offer_catalog:
  - name: "技術相談"
    description: "Windows ソフト開発に関する方針整理、制約整理、進め方の相談"
  - name: "設計レビュー"
    description: "アーキテクチャ、責務分割、境界設計、改修方針のレビュー"
  - name: "移行方針整理"
    description: "既存資産の扱い、残す部分と置き換える部分の整理"
faq:
  - q: "実装前の相談だけでも大丈夫ですか？"
    a: "はい。まだコードを書き始めていない段階でも、設計方針や技術選定の相談から対応できます。"
  - q: "COM や ActiveX を含む古い構成でも相談できますか？"
    a: "可能です。Windows の既存資産を前提に、残す・包む・置き換えるの判断を含めて整理します。"
related_articles:
  - title: "ActiveX / OCX を今どう扱うか"
    url: "/blog/2026/03/12/001-activex-ocx-keep-wrap-replace-decision-table/"
  - title: "COM STA/MTA の基礎知識"
    url: "/blog/2026/01/31/000-sta-mta-com-relationship/"
  - title: "C# からネイティブ DLL を使うなら C++/CLI ラッパーが有力な理由"
    url: "/blog/2026/03/07/000-cpp-cli-wrapper-for-native-dlls/"
---

## こういう相談に対応します

- この既存資産は残すべきか、包むべきか、置き換えるべきか
- UI、通信、バックグラウンド処理、ログの責務をどう分けるべきか
- COM / ActiveX / C++/CLI / .NET の境界をどう切るべきか
- 32bit / 64bit 問題をどこで吸収するべきか
- 不具合調査を始める前に、何を観測すべきか

## 向いているフェーズ

- 実装前の方針整理
- 既存システム改修前の設計見直し
- いまの構成がつらいが、全面リプレイスはまだ重い段階
- 障害対応が続いていて、構造から整理し直したい段階

## 相談でよく扱うテーマ

- Windowsアプリのアーキテクチャ整理
- COM / ActiveX / OCX の扱い方
- 32bit / 64bit 相互運用
- スレッドモデルやライフタイム設計
- ログ設計、例外設計、異常系テスト

## 相談の進め方

1. まず、現在の構成・制約・困りごとを整理します。
2. 次に、残すもの、包むもの、置き換えるものを分けます。
3. 必要なら、実装前提のレビューや改修方針の文書化まで進めます。

## 特に相性のよい案件

合同会社小村ソフト は、**Windows の少し古くて少し複雑な案件**との相性がよいです。

- 既存資産がある
- でも今のままでは保守しにくい
- ただし全面作り直しも重い

こういう案件は、設計整理から入るほうが結果的に安く済むことが多いです。
