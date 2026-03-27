---
layout: detail-page
lang: ja
translation_key: case-study-long-run-crash-handle-leak
permalink: /case-studies/long-run-crash-handle-leak/
title: "長期稼働後クラッシュをハンドルリークまで追った事例 | 合同会社小村ソフト"
page_name: "長期稼働後クラッシュをハンドルリークまで追った事例"
page_eyebrow: "Case Study"
schema_type: "WebPage"
breadcrumb_parent_label: "技術事例"
breadcrumb_parent_url: "/case-studies/"
description: "一か月単位でしか出ないクラッシュを、観測点の整理とログ増強でハンドルリーク調査へ絞り込んだ技術事例ページです。"
page_keywords:
  - 技術事例
  - 長期稼働
  - クラッシュ
  - ハンドルリーク
  - ログ設計
related_pages:
  - title: "不具合調査・原因解析"
    url: "/services/bug-investigation/"
  - title: "Windowsアプリ開発"
    url: "/services/windows-app-development/"
  - title: "技術事例"
    url: "/case-studies/"
related_articles:
  - title: "産業用カメラ制御アプリが1か月後に突然落ちるとき（前編）"
    url: "/blog/2026/03/11/002-handle-leak-industrial-camera-long-run-crash-part1/"
  - title: "産業用カメラ制御アプリが1か月後に突然落ちるとき（後編）"
    url: "/blog/2026/03/11/003-application-verifier-abnormal-test-foundation-part2/"
---

## 事例概要

約 1 か月の連続運転後にだけ突然落ちる Windows アプリについて、観測点の整理から始めて、最終的にハンドルリークを中心とした調査へ絞り込んだ事例です。
ポイントは、原因そのものだけでなく、**どの観測を先に整えるべきか** を決めたことにありました。

## 症状

- 数日では出ず、長期稼働後にだけクラッシュする
- 例外の出方だけではリークかどうか判断しにくい
- 現場でしか起きず、開発機では再現圧縮が必要

## 制約

- 月単位の再現待ちは現実的ではない
- カメラ再接続や異常経路を含むため、正常系ログだけでは足りない
- どのリソースが増えているかを継続観測できる必要がある

## 何を観測したか

- `Handle Count`、`Private Bytes`、`Thread Count` の heartbeat
- セッション開始・再接続・終了の境界ログ
- `create/open/register` と `close/dispose/unregister` の対になるライフサイクルログ

## どう切り分けたか

まず「長期稼働クラッシュ」をそのまま追わず、再接続や timeout まわりの失敗経路へ再現を圧縮しました。
その結果、メモリリークよりも **ハンドルリーク** を疑う方が筋が良いと判断でき、観測をそこへ集中できました。

## どう改善したか

- 監視項目を増やし、クラッシュ時点だけでなく増加傾向を追えるようにした
- 境界ログを整えて、どの責務が開いてどの責務が閉じたかを追いやすくした
- 後続の異常系テスト基盤へつなげやすい形に調査結果を整理した

## この事例がつながるサービス

この事例は、長期稼働後だけ出る障害を切り分ける **不具合調査・原因解析** と、ログ・再接続・運用観測を実装側から整える **Windowsアプリ開発** の両方へつながります。
