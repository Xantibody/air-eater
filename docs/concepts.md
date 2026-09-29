# 中心の抽象

コードとログに出てくる言葉と、それぞれがどこに住んでいるかを書く。思想は [design-philosophy.md](design-philosophy.md)、使い方は README にある。

## 言葉

| 言葉 | 意味 | 住む場所 |
| --- | --- | --- |
| Desktop | macOS の通常の Space。番号は Mission Control の並び順で、Ctrl+数字 の数字と同じ。全画面の Space は Desktop ではない | `SpacePool` |
| プール (pool) | air-eater が使ってよい Desktop の範囲 (1…9)。実在する Desktop の数はシステムの設定から読み、それを超える番号は候補にしない | `SpacePool`、`DesktopCount` |
| workspace | Hyprland と同じ固定の ID。1 つの Desktop に 1 対 1 で割り当てる。ID の値は 9 を超えてもよいが、同時に存在できるのはプールの数まで | `Workspaces` |
| 割り当て (assigned) | workspace ID → Desktop の対応表。窓のある Desktop と表示中の Desktop には自動で ID を付ける。Desktop 番号と同じ ID が空いていればそれを使う | `Workspaces` |
| 確保 (reserved) | 行くと決めたが、まだ着いていない Desktop。着くまでは「空のまま離れた」として外さない | `Workspaces` |
| マーカー | Desktop ごとに 1 つ置く 1×1 の透明な窓。デスクトップのすぐ上の階層に置き、フォーカスを奪わない。画面に写っているマーカーで現在地が分かる | `Markers` |
| 現在地 (current) | 今表示している Desktop。マーカーの無い Space (未訪問の Desktop、全画面) にいる間は nil で、そこの窓はどこにも数えない | `Workspaces.current`、`CurrentDesktop` |
| 数える窓 (managed) | 通常レイヤーにあり、alpha が 0 でなく、自分と macOS のオーバーレイ (WindowManager) 以外の窓 | `ManagedWindows` |
| 移動中 (settling) | Ctrl+N を送った、通知を受けた、手の Ctrl+N を見た、のいずれかから 600 ms。この間は移動元と移動先の窓が同時に写るので数えない | `WindowTracker` |
| 命令 (Command) | Option+キー か標準入力の 1 行から読む操作。`workspace N`、`move N`、`neighbor`、`terminal`、`new`、`tile <side>`、`focus <direction>`、`arrange`、`close`、`previous` | `KeyCommand` |
| 配置 (Arrangement) | 窓の数に合った純正の形。1 枚は全体、2 枚は左と右、3 枚は左と 4 分割、4 枚は 4 分割。5 枚以上は並べない | `Arrangement` |
| Tile | Option+H/J/K/L/F で書く 1 枚の窓の frame。左右上下の半分と、可視領域いっぱい (fill) | `Tile` |
| 向き (FocusDirection) | Option+Shift+H/J/K/L でフォーカスを移す向き。中心がその向きにあり一番近い窓を選ぶ | `FocusDirection` |

## 流れ

### Option+N で workspace N へ行く

1. 実在する Desktop の数を読み直す。
2. `Workspaces.candidate(for: N)` が Desktop を返す。既に N がある Desktop か、どの ID にも割り当てておらず窓も見ていない Desktop。
3. まだ無い N なら、その Desktop を確保して Ctrl+数字 を送り、切り替わるのを待つ (上限 1.5 秒)。
4. 着いたらマーカーを置き、移動が落ち着いてから窓を数える。元から窓があった Desktop なら、その Desktop に自分の番号を付け、N は次の候補へ。
5. 表示中の Desktop は空でも workspace として残る。離れた時点で空だと確かめた workspace は割り当てを外す。

### 窓の数が変わったとき

1. AXObserver かアプリの通知が来たら 80 ms 置いて観測し直す。通知が欠けても 2 秒ごとの走査が拾う。
2. 現在地の窓の数が前に見たときから変わっていたら、数に合った配置を選ぶ。初めて見た Desktop では動かない (使う人が並べた窓を勝手に並べ直さない)。
3. 前面のアプリの「ウインドウ」メニューから純正の配置を AX で押す。メニューが無いアプリなら、写っている窓を手前から順に取り、同じ形の frame を AX で書く。

### Option+Shift+N で窓を workspace N へ移す

1. 行き先の Desktop は Option+N と同じ手順で決める (無ければ確保する)。
2. フォーカス中の窓のタイトルバーの中央を掴み、数 px ドラッグしてから Ctrl+数字 を送る。切り替わってから 0.9 秒掴んだまま待ち、離す。カーソルは元の位置へ戻す。
3. 全画面と最小化の窓は掴めないので断る。移動中は「移動中」の猶予がそのまま効く。

### 端末を開く

- Option+Return は今の workspace に。Option+Shift+Return は使われていない一番小さい ID の workspace を作ってから。
- 端末は新しいインスタンスで起動する (kitty、無ければ Ghostty、Terminal)。窓が増えるので自動タイルが並べる。

## 状態の所在

```text
AirEaterCore (純粋、ユニットテスト)        AirEater (副作用、E2E)
  Workspaces / SpacePool                    Controller   命令を 1 つずつ順に実行する
  KeyCommand / Command(parsing:)            WindowTracker  CGWindowList を観測して Workspaces を更新
  Arrangement / Tile / Coordinate           Markers / SpaceSwitching / KeyTap / CommandInput
  ManagedWindows / CurrentDesktop           Arranger (純正) / FrameArranger (自前) / WindowTiling / WindowMover / FocusMover
  DesktopCount / DesktopShortcuts           WindowEvents (AXObserver) / Launcher / FocusedWindow
```

- Core は CoreGraphics の型しか知らない。AppKit と AX の呼び出しは App にだけある。
- 判断を増やすときは Core に純粋な関数として足し、App から呼ぶ。App に `if` を増やす前に、Core に置けないかを考える。
- Controller の状態遷移は今は E2E だけが守っている。Core の状態機械に出す構造変更が次の候補 (`.ai/plans/`)。

## 前提としている macOS の挙動

- 新しい窓は今いる Space に開く。
- NSWindow は作られた Space に留まる (canJoinAllSpaces を付けない限り)。
- Ctrl+数字 は Mission Control の並び順の Desktop へ切り替える。「最新の使用状況に基づいて並べ替える」が ON だと並びが変わるので OFF を求める。
- 「アプリの切り替えで窓のある Space へ移動」が ON だと、空の Desktop に着いた直後に別の Space へ移されることがあるので OFF を求める。
- 全画面の出入りの遷移中は `AXFullScreen` を書いても無視される。落ち着くまで待つ。
