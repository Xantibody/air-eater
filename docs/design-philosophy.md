# 設計思想

air-eater は、macOS の Space をそのまま workspace として使い、Hyprland 式の操作を公開 API だけで載せるウィンドウマネージャである。この文書は「なぜそうするか」と「何をしないか」を書く。仕組みは README、中心の抽象は [concepts.md](concepts.md) にある。

## 1 つの賭け

**窓を Space 間で動かさなければ、macOS の Space は workspace として使える。**

既存の窓を別の Space へ移す公開 API は無い。他のツールはここで private API (yabai、Amethyst、WhichSpace) か、Space を捨てて窓を画面外に隠す方式 (AeroSpace) を選んだ。air-eater は移動そのものを入り口から外し、「新しい作業は新しい workspace で始める」を入り口にする。macOS は新しい窓を必ず今いる Space に開くので、先に Space を切り替えてから起動すれば、窓は最初から目的の workspace に生まれる。

この割り切りのおかげで、次が成り立つ。

- private API を 1 つも使わない。SIP も変更しない。macOS の版が上がっても壊れにくい部品 (`CGEvent`、`CGWindowList`、AX の position/size、`isOnActiveSpace`) だけに依存する。
- Mission Control、トラックパッドのスワイプ、Cmd+Tab は素のまま使える。air-eater は macOS の隣で動くだけで、macOS と喧嘩しない。
- air-eater が落ちても、窓はそれぞれの Desktop に残る。後始末が要らない。

## 守ること

1. **private API を使わない。SIP を変更しない。** 便利でも、版ごとに壊れる経路は取らない。
2. **macOS が並べられるときは macOS に任せる。** 窓の配置は macOS 15 以降の純正の配置 (画面全体、左と右、左と 4 分割、4 分割) をメニューから押す。純正が無いアプリにだけ、同じ 4 つの形を自前の frame で作る。形はこの 4 つに限り、独自のレイアウト木や分割比は持たない。
3. **Hyprland の意味論に合わせる。** workspace の番号は固定の ID で、詰めたり振り直したりしない。空のまま離れた workspace は消える。隣への移動は ID 順で端を折り返す。本家のソースを読んで合わせた (`.ai/research/hyprland-workspaces.md`)。
4. **判断は副作用と切り離す。** どの Desktop へ行くか、どの窓を数えるか、どの配置を使うかは `AirEaterCore` の純粋な関数で決め、ユニットテストで守る。`AirEater` は決めたことを実行するだけにする。
5. **時間のヒューリスティックは最後の手段。** 切り替えのアニメーション中に窓を数えない猶予のように、どうしても要るものだけ残し、理由をコメントに書く。イベント (通知) で拾えるものは通知で拾い、走査は保険にする。

## しないこと

| しないこと | 理由 |
| --- | --- |
| 窓を画面外に隠して workspace を偽装する (AeroSpace 式) | Mission Control に隠した窓が見え、落ちたときに窓が角に残る。macOS と喧嘩する |
| 独自のレイアウトエンジン (木構造、分割比、5 枚以上の配置) | AeroSpace の焼き直しになる。純正の 4 つの形で足りる範囲に絞る |
| ネイティブの全画面を workspace として扱う | 全画面は別の Space に入り、マーカーが無いので追えない。戻る先も選べない。代わりに「窓を可視領域いっぱいにする」(Option+F) を全画面の同等品にする |
| Desktop の自動作成・削除 | Mission Control を開いて AX で押す方法しか無く、画面が切り替わり、階層が版ごとに変わる。Desktop は使う人が先に作る |
| 合成スワイプでアニメーション無しに切り替える | CGEvent の非公開フィールドに依存し、macOS 27 で塞がれた |
| 窓の移動を自動で走らせる | 公開 API の経路 (掴んだまま Ctrl+N) はカーソルを乗っ取り、約 1.5 秒かかる。入れるなら使う人が押したときだけ |

## 判断の基準

- ネイティブの機能を忠実に再現できないときは、公開 API で確実に動く「同等の見え方」を採る。忠実さの不足は README に 1 行書く。
- 新しい機能は、まず「macOS の素の機能で済むか」を探し、次に「AX で frame を書くだけで済むか」を探す。それでも無理なら、思想の表に照らして諦める。
- 前提設定 (Ctrl+1…9 の有効化、Space の並べ替え OFF など) を使う人に求めるのはよいが、黙って動かなくなってはいけない。起動時に検知して案内する。

## 公開 API の限界 (2026-09 時点、macOS 27)

| やりたいこと | 判定 | 使う手段 |
| --- | --- | --- |
| Space の切り替え | 可能 | Ctrl+数字 を `CGEvent` で送る |
| 現在地の判定 | 可能 | 自前のマーカー窓の `isOnActiveSpace` |
| 今の Space の窓の列挙 | 可能 | `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` |
| 別 Space にある窓の所在 | 不可能 | 自己追跡しかない |
| 窓の生成・破棄の通知 | 脆いが可能 | `AXObserver` を引き金にし、走査を保険に残す |
| 純正の配置 | 脆いが可能 | 「ウインドウ」メニューを AX で押す。無いアプリは自前の frame |
| 窓を別 Desktop へ移す | 脆いが可能 | ドラッグ状態で Ctrl+N (Option+Shift+数字)。使う人が押したときだけ |
| 全画面の出入り | 可能 (未文書化) | `AXFullScreen` の読み書き。戻る先は選べない |
| Desktop の作成・削除 | 脆いが可能 | 採らない |

根拠と実験の記録は `.ai/research/` にある (git 管理外)。

## 先行例との違い

| | air-eater | AeroSpace | yabai |
| --- | --- | --- | --- |
| workspace の実体 | macOS の Space | 画面外への退避 | macOS の Space |
| private API | 使わない | ほぼ使わない | 使う (SIP 無効化) |
| 窓の移動 | 入り口から外す | AX の position | private |
| レイアウト | 純正の 4 つの形 | 独自の木 | 独自の BSP |
| Mission Control | 素のまま | 隠した窓が見える | 素のまま |

AeroSpace は「Space は使い物にならない」という前提から始まり、air-eater は「窓を動かさなければ Space で足りる」という前提から始まる。前提が逆なので、同じ部品 (AXObserver、AX の frame) を使っても設計は重ならない。
