# air-eater

macOS の Space をあらかじめ確保した固定プールとして扱い、Hyprland 式の動的 workspace をネイティブ API だけで再現するウィンドウマネージャ。

- 対象: macOS 26 以降 / Apple Silicon
- 言語: Swift
- private API: 使わない
- SIP: 変更しない

## しくみ

### ウィンドウを Space 間で動かさない

既存ウィンドウを別の Space へ移す公開 API は無い。そこで `movetoworkspace` は v1 の仕様から外し、代わりに「新しい workspace でアプリを開く」を入り口にする。

macOS は新しいウィンドウを必ず今いる Space に開く。先に Space を切り替えてから起動すれば、ウィンドウは最初から目的の workspace に生まれる。

移動が無いので private API も画面外への退避も要らない。Mission Control、ネイティブのフルスクリーン、3本指スワイプはすべて素の挙動のまま使える。

### Space は固定プール

Space は起動前に手で 9 個作っておく。macOS は Space を勝手に削除しないので、固定プールとして安定する。「新規 workspace」は「プール内の空き Space へ行く」操作になる。

### 論理番号は保存せず導出する

物理 Desktop 1–9 は固定のまま。ウィンドウがある Desktop だけを並べたものを Hyprland 式の論理番号とし、毎回そこから計算する。

```swift
let pool: [Int]                      // [1,2,...,9] 物理 Desktop 番号
var occupied: [Int: Set<WindowID>]   // 物理番号 → そこに属するウィンドウ
var active: [Int] { pool.filter { !(occupied[$0]?.isEmpty ?? true) } }
// 論理 N → 物理 = active[N-1]
```

Desktop が空になれば `active` から落ち、後ろの番号が自然に繰り上がる。

### 現在の Space はマーカーウィンドウで観測する

現在の Space を返す公開 API は無い。起動時に各 Space へ 1×1 の透明ウィンドウを置き、`CGWindowListCopyWindowInfo(.optionOnScreenOnly, …)` に写ったマーカーで現在地を決める。`NSWorkspaceActiveSpaceDidChangeNotification` を契機に再評価するので、トラックパッドで直接切り替えても状態が追従する。

## キーバインド

| 操作 | キー | 実装 |
| --- | --- | --- |
| workspace N へ移動 | Super+1…9 | `active[N-1]` の物理番号に対応する Ctrl+数字 を送出 |
| 隣の workspace へ移動 | Super+← → | Ctrl+矢印 を送出 |
| 新しい workspace でアプリ起動 | Super+Return | 最小の空き Desktop へ切り替えてから起動 |
| 四分割 | Super+H/J/K/L | Accessibility API でウィンドウの frame を書き込む |
| ウィンドウを別 workspace へ移動 | — | v1 では非対応 |

ホットキーは `RegisterEventHotKey` (Carbon) でプロセス内に持つ。skhd などの外部デーモンは要らない。

## 事前設定

1. Mission Control で Desktop を 9 個作る
2. システム設定 ▸ キーボード ▸ キーボードショートカット ▸ Mission Control で「デスクトップ 1〜9 へ切り替え」(Ctrl+1…9) を有効にする
3. システム設定 ▸ デスクトップと Dock で「最新の使用状況に基づいて操作スペースを並べ替える」を OFF にする
4. 初回起動時にアクセシビリティ権限を許可する

## 開発

### 必要なもの

- Nix (flakes 有効)
- direnv (任意)
- Xcode または Command Line Tools (Swift 6.2 以降)

Swift コンパイラと macOS SDK は Nix ではなくシステムのものを使う。nixpkgs の Swift は macOS 26 の SDK に追従していないため。Nix の devShell は swiftlint、treefmt、just を用意する。

### セットアップ

```sh
cp .envrc.example .envrc
direnv allow
```

direnv を使わない場合は `nix develop` でシェルに入る。

### コマンド

| コマンド | 内容 |
| --- | --- |
| `just build` | ビルド |
| `just test` | テスト (Swift Testing) |
| `just run` | 起動 |
| `just lint` | swiftlint |
| `just fmt` | 整形 (`swift format` と nixfmt) |
| `just check` | 整形確認・lint・ビルド・テストをまとめて実行 |

## ロードマップ

1. ホットキーを握って Space を切り替える
2. マーカーウィンドウで現在の Space を特定する
3. AXObserver でウィンドウの生成・破棄を追跡する
4. 論理番号の導出と新規 workspace でのアプリ起動
5. 四分割
6. 設定ファイルと永続化
