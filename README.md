# air-eater

macOS の Space をあらかじめ確保した固定プールとして扱い、Hyprland 式の動的 workspace をネイティブ API だけで再現するウィンドウマネージャ。

- 対象: macOS 26 以降 / Apple Silicon
- 言語: Swift
- private API: 使わない
- SIP: 変更しない

設計思想は [docs/design-philosophy.md](docs/design-philosophy.md)、コードとログの言葉は [docs/concepts.md](docs/concepts.md) にある。

## しくみ

### ウィンドウを Space 間で動かさない

既存ウィンドウを別の Space へ移す公開 API は無い。そこで `movetoworkspace` は v1 の仕様から外し、代わりに「新しい workspace でアプリを開く」を入り口にする。

macOS は新しいウィンドウを必ず今いる Space に開く。先に Space を切り替えてから起動すれば、ウィンドウは最初から目的の workspace に生まれる。

移動が無いので private API も画面外への退避も要らない。Mission Control、ネイティブのフルスクリーン、3本指スワイプはすべて素の挙動のまま使える。

### Space は固定プール

Space は起動前に手で 9 個作っておく。macOS は Space を勝手に削除しないので、固定プールとして安定する。「新規 workspace」は「プール内の空き Space へ行く」操作になる。

### workspace 番号は Hyprland と同じ固定の ID

workspace の番号は固定の ID で、詰めたり振り直したりしない (Hyprland と同じ)。air-eater は workspace ID と物理 Desktop の対応表を持つ。

- まだ無い番号を指すと、空いている Desktop を 1 つ確保してその番号の workspace を作る。1, 2 しか無いときに Option+5 を押すと 1, 2, 5 になる
- 空のまま離れた workspace は消え、Desktop は空きに戻る。他の番号はそのまま
- 窓のある Desktop と表示中の Desktop には番号を自動で付ける。Desktop 番号と同じ番号が空いていればそれを使う

まだ中身を見ていない Desktop も空き候補になるので、着いて窓があれば、その Desktop には自分の番号を付けて次の候補を探す。

### 現在の Space はマーカーウィンドウで観測する

現在の Space を返す公開 API は無い。air-eater が Ctrl+数字 で Desktop に着いたとき、その Space に 1×1 の透明ウィンドウ (マーカー) を置き、`CGWindowListCopyWindowInfo(.optionOnScreenOnly, …)` に写ったマーカーで現在地を決める。`NSWorkspaceActiveSpaceDidChangeNotification` を契機に再評価するので、マーカーを置いた Desktop 同士ならトラックパッドで直接切り替えても状態が追従する。

起動時に全 Desktop を巡回することはしない。起動時は Desktop 1 にだけ行き、他の Desktop は初めて air-eater で移動したときにプールへ入る。Desktop やショートカットを後から足しても、再起動せずにそのまま使える。

### 自動タイルは macOS 標準の配置に任せる

窓の並べ方は自前で計算せず、macOS 15 以降の各アプリにある「ウインドウ ▸ 移動とサイズ変更」の標準の配置を使う。今いる Desktop の窓の数が変わったら、前面のアプリのメニューから数に合った配置を Accessibility API で押す。

| 窓の数 | 標準の配置 |
| --- | --- |
| 1 | 画面全体に表示 |
| 2 | 左と右 |
| 3 | 左と4分割 |
| 4 | 4分割 |
| 5 以上 | 並べない |

- 項目名は言語で変わるので、ショートカットの属性 (キーと修飾キーの組) で項目を探す
- 合成したショートカット (Fn+Ctrl+Shift+← など) は実機で効かなかったので、メニュー項目を直接押す
- 標準のウインドウメニューを持たないアプリ (Electron、Qt など) の窓は、同じ 4 つの形を自前で計算した frame で並べる。形はこの 4 つに限り、独自のレイアウトは持たない
- 初めて見た Desktop の窓は並べ直さない。窓の数が変わったときだけ動く

## キーバインド

Super には Option (⌥) を使う。Cmd+数字 はブラウザのタブ切り替えなど多くのアプリと衝突するため。

| 操作 | キー | 実装 |
| --- | --- | --- |
| workspace N へ移動 | Option+1…9 | N の workspace がある Desktop の Ctrl+数字 を送出。無ければ空き Desktop に作る |
| 隣の workspace へ移動 | Option+[ / ] | 番号順で隣の workspace へ。端では反対の端へ折り返す |
| 今の workspace に端末を開く | Option+Return | kitty (無ければ Ghostty、Terminal) を新しいインスタンスで起動。窓が増えるので自動タイルが並べる |
| 新しい workspace に端末を開く | Option+Shift+Return | 使われていない一番小さい番号の workspace を作り、そこで端末を起動 |
| 左・下・上・右半分に寄せる | Option+H/J/K/L | Accessibility API でフォーカス中のウィンドウの frame を書き込む |
| 画面いっぱいに広げる (fullscreen の代わり) | Option+F | 可視領域いっぱいの frame を書き込む。ネイティブの全画面になっている窓なら、先に全画面を解いて元の Desktop に戻す |
| フォーカス中の窓を閉じる | Option+C | 閉じるボタンを押す (Hyprland の killactive)。アプリは終了しない |
| ウィンドウを別 workspace へ移動 | — | v1 では非対応 |

ネイティブの全画面は使わない。全画面の窓は別の Space に入って workspace の外に出てしまい、戻る先の Space も公開 API では選べないため、Hyprland の fullscreen に当たる操作は「窓を画面いっぱいの大きさにする」に置き換えている。

ホットキーは CGEventTap でプロセス内に持つ。skhd などの外部デーモンは要らない。`RegisterEventHotKey` (Carbon) は Option だけを修飾キーにすると実機で発火しなかったので使っていない。キー監視は手で押した Ctrl+数字 も見ているので、air-eater を通さずに切り替えた Desktop も番号が分かる (トラックパッドのスワイプは分からない)。

## 事前設定

1. Mission Control で Desktop を 9 個作る
2. システム設定 ▸ キーボード ▸ キーボードショートカット ▸ Mission Control で「デスクトップ 1〜9 へ切り替え」(Ctrl+1…9) を有効にする
3. システム設定 ▸ デスクトップと Dock で「最新の使用状況に基づいて操作スペースを並べ替える」を OFF にする
4. 同じ画面で「アプリケーションの切り替えで、アプリケーションのウインドウが開いている操作スペースに移動」を OFF にする。ON だと、空の Desktop に着いたとき前面になった別のアプリ (隣の全画面アプリなど) の Space へ移されてしまう
5. 初回起動時にアクセシビリティ権限を許可する

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

- [x] ホットキーを握って Space を切り替える
- [x] マーカーウィンドウで現在の Space を特定する
- [x] AXObserver でウィンドウの生成・破棄を追跡する (通知は欠けることがあるので 2 秒ごとの走査を保険に残す)
- [x] 論理番号の導出と新規 workspace でのアプリ起動
- [x] 半分割
- [ ] 設定ファイルと永続化
