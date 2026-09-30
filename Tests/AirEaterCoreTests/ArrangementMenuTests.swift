import Testing

@testable import AirEaterCore

/// Finder (macOS 26、日本語) の「ウインドウ ▸ 移動とサイズ変更」を AX で読んだ並び。
/// 項目名は言語で変わるので、ショートカットだけを持つ
let moveAndResizeMenu: [MenuShortcut?] = [
  nil,  // 2分割 (見出し)
  MenuShortcut(virtualKey: 123, modifiers: 28),  // 左
  MenuShortcut(virtualKey: 124, modifiers: 28),  // 右
  MenuShortcut(virtualKey: 126, modifiers: 28),  // 上
  MenuShortcut(virtualKey: 125, modifiers: 28),  // 下
  nil,  // 区切り
  nil,  // 4分割 (見出し)
  nil, nil, nil, nil,  // 左上・右上・左下・右下
  nil,  // 区切り
  nil,  // 配置 (見出し)
  MenuShortcut(virtualKey: 123, modifiers: 29),  // 左と右
  MenuShortcut(virtualKey: 123, modifiers: 31),  // 左と4分割
  MenuShortcut(virtualKey: 124, modifiers: 29),  // 右と左
  MenuShortcut(virtualKey: 124, modifiers: 31),  // 右と4分割
  MenuShortcut(virtualKey: 126, modifiers: 29),  // 上と下
  MenuShortcut(virtualKey: 126, modifiers: 31),  // 上と4分割
  MenuShortcut(virtualKey: 125, modifiers: 29),  // 下と上
  MenuShortcut(virtualKey: 125, modifiers: 31),  // 下と4分割
  nil,  // 4分割 (配置)
  nil,  // 区切り
  MenuShortcut(character: "R", modifiers: 28),  // 前のサイズに戻す
]

@Suite struct ArrangementMenuTests {
  @Test func emptyMenuHasNoArrangement() {
    #expect(Arrangement.leftAndRight.index(in: []) == nil)
  }
}

extension ArrangementMenuTests {
  @Test func leftAndRightIsFoundByItsShortcut() {
    #expect(Arrangement.leftAndRight.index(in: moveAndResizeMenu) == 13)
  }
}

/// 同じく Finder の「ウインドウ」メニューの先頭。画面全体に表示は Fn+Ctrl+F
let windowMenu: [MenuShortcut?] = [
  MenuShortcut(character: "M", modifiers: 0),  // しまう
  MenuShortcut(character: "M", modifiers: 2),  // すべてをしまう
  nil,  // 拡大/縮小
  nil,  // すべてを拡大/縮小
  MenuShortcut(character: "F", modifiers: 28),  // 画面全体に表示
  MenuShortcut(character: "C", modifiers: 28),  // 中央に配置
  nil,  // 移動とサイズ変更
]

extension ArrangementMenuTests {
  @Test(
    arguments: [
      (Arrangement.leftAndQuarters, 14),
      // 4分割 (配置) にはショートカットが無い。下と4分割のすぐ後ろにある
      (.quarters, 21),
    ])
  func arrangementIsFoundInMoveAndResizeMenu(arrangement: Arrangement, expected: Int) {
    #expect(arrangement.index(in: moveAndResizeMenu) == expected)
  }

  @Test func fillIsFoundInWindowMenu() {
    #expect(Arrangement.fill.index(in: windowMenu) == 4)
  }

  // 配置の項目が無い別のメニューでは見つからない
  @Test(arguments: [Arrangement.leftAndRight, .leftAndQuarters, .quarters])
  func arrangementIsNotInWindowMenuTop(arrangement: Arrangement) {
    #expect(arrangement.index(in: windowMenu) == nil)
  }
}
