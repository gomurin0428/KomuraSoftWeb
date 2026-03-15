---
layout: detail-page
lang: ja
translation_key: case-study-application-verifier-failure-path-testing
permalink: /case-studies/application-verifier-failure-path-testing/
title: "Application Verifier を使った異常系テスト基盤の事例 | KomuraSoft"
page_name: "Application Verifier を使った異常系テスト基盤の事例"
page_eyebrow: "Case Study"
schema_type: "WebPage"
breadcrumb_parent_label: "技術事例"
breadcrumb_parent_url: "/case-studies/"
description: "Application Verifier を使い、異常系テスト基盤を先に整えて再発防止へつなげた技術事例ページです。"
page_keywords:
  - 技術事例
  - Application Verifier
  - 異常系テスト
  - failure path
  - 再発防止
related_pages:
  - title: "不具合調査・原因解析"
    url: "/services/bug-investigation/"
  - title: "技術相談・設計レビュー"
    url: "/services/technical-consulting/"
  - title: "技術事例"
    url: "/case-studies/"
related_articles:
  - title: "Application Verifier を使った異常系テスト基盤の作り方"
    url: "/blog/2026/03/11/003-application-verifier-abnormal-test-foundation-part2/"
  - title: "産業用カメラ制御アプリが1か月後に突然落ちるとき（前編）"
    url: "/blog/2026/03/11/002-handle-leak-industrial-camera-long-run-crash-part1/"
---

## 事例概要

単発の不具合修正で終わらせず、Application Verifier を使って **異常系テスト基盤そのものを整備** した事例です。
目的は「今の障害を見つける」だけでなく、「次に壊れたときも追いやすい状態を先に作る」ことでした。

## 症状

- 通常系試験だけでは、failure path の問題が表に出にくい
- 低リソース時やハンドル異常は、本番に近い条件でだけ見えやすい
- 調査のたびに手順が属人化しやすい

## 制約

- 実機で本当に資源を枯渇させるのはコストもリスクも高い
- ネイティブ境界や Win32 まわりの壊れ方を前倒しで表に出したい
- 次回の障害調査にも流用できる形で整える必要がある

## 何を観測したか

- `Handles`、`Heaps`、`Low Resource Simulation` などの Verifier 設定
- `!htrace` や page heap を含む failure path の痕跡
- 自前の lifecycle log と Verifier stop 情報の対応

## どう切り分けたか

まず通常ログだけで追える範囲と、Verifier を当てないと見えない範囲を分けました。
そのうえで、ハーネス化した実行経路に Verifier を当て、**再現しにくい異常を前倒しで表に出す** 方針へ寄せました。

## どう改善したか

- failure path を意図的に踏ませるテスト基盤を整えた
- ハンドル異常やヒープ異常を、より短いループで観測できるようにした
- 後続の設計レビューや再発防止策へ戻しやすい形で観測点を整理した

## この事例がつながるサービス

この事例は、障害の再現と原因特定を進める **不具合調査・原因解析** に直結します。あわせて、異常系試験や観測点をどこまで設計へ織り込むかを整理する **技術相談・設計レビュー** にもつながります。
