---
layout: detail-page
lang: ja
translation_key: case-studies-hub
permalink: /case-studies/
title: "技術事例 | KomuraSoft"
page_name: "技術事例"
page_eyebrow: "Case Studies"
schema_type: "CollectionPage"
description: "KomuraSoft が対応してきた不具合調査、通信異常の切り分け、長期稼働障害の解析、異常系テスト基盤整備の技術事例をまとめたページです。"
page_keywords:
  - 技術事例
  - 不具合調査
  - 長期稼働障害
  - 通信異常
related_pages:
  - title: "会社情報"
    url: "/company/"
  - title: "代表略歴"
    url: "/profile/go-komura/"
  - title: "技術トピック"
    url: "/topics/"
related_articles:
  - title: "産業用カメラ通信の数秒停止を切り分けた事例"
    url: "/blog/2026/03/11/001-tcp-retransmission-rfc1323-industrial-camera/"
  - title: "長期稼働後クラッシュをハンドルリークまで追った事例"
    url: "/blog/2026/03/11/002-handle-leak-industrial-camera-long-run-crash-part1/"
  - title: "Application Verifier を使った異常系テスト基盤の事例"
    url: "/blog/2026/03/11/003-application-verifier-abnormal-test-foundation-part2/"
---

## 扱っている事例の傾向

KomuraSoft の技術事例は、単純なバグ修正よりも、現場で見えにくい障害の切り分けや、再発防止のための基盤整備に寄っています。

たとえば、次のような種類の案件です。

- 数秒だけ止まる通信異常の原因切り分け
- 一か月単位の長期稼働後にだけ出るクラッシュ調査
- メモリリークやハンドルリークを追いやすくする異常系テスト基盤の整備

## 事例 1: 通信停止の待ち時間を要因分解して短縮

産業用カメラ制御で、まれに数秒単位の停止が出る問題に対して、再送待ち時間と OS の通信条件を切り分けました。
結果として、RFC1323 タイムスタンプ設定がボトルネックに効く構造だと判断できました。

## 事例 2: 長期稼働後クラッシュをリークに結び付けた調査

一か月程度の連続運転後にだけ落ちる障害について、再現条件の整理と観測ログの増強を進め、ハンドルリークを中心とした調査に絞り込みました。
「見えにくい障害でも、どの観測が有効か」を整える仕事に近い事例です。

## 事例 3: 異常系テスト基盤を先に作って再発防止へつなげた例

Application Verifier を使って、unexpected な失敗経路でも痕跡を追いやすい基盤を整えました。
単発の修正だけでなく、次回の障害で調べやすくするための仕込みまで含めて扱っています。
