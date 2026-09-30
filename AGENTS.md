# AGENTS.md

air-eater で作業する AI エージェントへの案内。人も読む。

## 先に読むもの

1. [docs/design-philosophy.md](docs/design-philosophy.md): 何に賭けているか、何をしないか。機能を足す前に「しないこと」の表と照らす。
2. [docs/concepts.md](docs/concepts.md): コードとログの言葉、流れ、状態の所在。
3. [README.md](README.md): 使い方、キーバインド、前提設定、開発コマンド。
4. `.ai/refs/` (git 管理外): 設計メモと Hyprland の clone。`.ai/research/` に公開 API の調査と実験、`.ai/plans/` に次の設計がある。

## 守ること

- private API (CGS / SkyLight / `_AX…`) を使わない。SIP の変更を前提にしない。候補が private しか無いなら、機能を諦めるか「同等の見え方」の代替を提案する。
- 判断は `Sources/AirEaterCore` に純粋な関数として置き、`Tests/AirEaterCoreTests` で守る。AppKit と AX の呼び出しは `Sources/AirEater` にだけ書く。
- 窓の配置は純正の 4 つの形に限る。独自のレイアウト木や分割比を足さない。
- 時間で待つ処理 (猶予、リトライ) を足すときは、なぜその長さかをコメントに書く。
- ログは判断の理由まで出す。実機の不具合はログだけで追えるようにする。

## 確かめ方

| コマンド | 内容 |
| --- | --- |
| `just check` | 整形の確認、swiftlint (strict)、ビルド、ユニットテスト。コミット前に通す |
| `just e2e` | 実機で air-eater を起動し、標準入力から命令を送って確かめる。Desktop が 2 つ以上あり、Desktop 2 が空で、kitty があり、端末にアクセシビリティ権限があること。CI では回らない |
| `just run` | 起動。`AIR_EATER_LOG_KEYS=1` で全キーをログに出す |

- Desktop 1 と 2 の間に全画面アプリの Space があると、空の Desktop 2 に着いたときに macOS がその全画面アプリを前面にし、Space を勝手に移すことがある。E2E が間欠的に落ちたら、まずこれを疑う。Desktop 1 と 2 を隣り合わせにすると安定する
- 窓の種類ごとの共通シナリオ (自動タイル、フォーカス移動、close) は `Sources/AirEaterE2E/WindowKinds.swift` に種類を足すだけで増やせる
- 振る舞いを変えたら E2E のシナリオを足す (`Sources/AirEaterE2E`)。E2E 自身の窓、Finder の一時フォルダ、E2E が起動した kitty だけを動かし、使う人の窓には触らない。
- swiftlint は strict。ファイルは 400 行まで、識別子は 3 文字以上。`x`、`y` は使えない。
- Swift 6 の並行性検査が有効。通知のクロージャの中で `MainActor.assumeIsolated` を使うときは、Sendable でない値 (Notification、ポインタ) を外で取り出してから持ち込む。

## 書き方

- 言語は日本語。コミットの件名、コメント、ドキュメント、PR と issue の題も日本語。識別子とコードは英語。
- コミットは Conventional Commits。scope は `core`、`app`、`e2e`。構造の変更と振る舞いの変更は別のコミットにする。
- 「なぜそうしないか」は `AIDEV-NOTE:` か `HACK(<issue URL>):` のコメントで、コードのすぐ上に書く。編集する前にそのファイルのアンカーを読む。
- 決めたことと決めていないことは `.ai/plans/` に書く。実装が入ったら `.ai/plans/done/` へ動かし、理由はコミットの本文へ移す。
