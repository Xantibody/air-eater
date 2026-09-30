import Testing

@testable import AirEaterCore

@Suite struct DesktopShortcutsTests {
  @Test func noSymbolicHotKeysMeansNoDesktopShortcut() {
    #expect(desktopsWithEnabledShortcut(symbolicHotKeys: [:]) == [])
  }
}

extension DesktopShortcutsTests {
  static func hotKey(enabled: Bool) -> [String: Any] {
    ["enabled": enabled, "value": ["type": "standard"]]
  }

  // 「デスクトップ N へ切り替え」の ID は 117+N
  @Test func enabledShortcutForDesktopOne() {
    #expect(
      desktopsWithEnabledShortcut(symbolicHotKeys: ["118": Self.hotKey(enabled: true)]) == [1])
  }
}

extension DesktopShortcutsTests {
  // 手元の Mac で実際に見た形: 1〜4 は項目があって無効、5〜9 は Desktop が無いので項目ごと無い
  @Test func disabledAndMissingShortcutsAreNotEnabled() {
    let symbolicHotKeys: [String: Any] = [
      "118": Self.hotKey(enabled: true),
      "119": Self.hotKey(enabled: false),
      "120": Self.hotKey(enabled: true),
      "126": Self.hotKey(enabled: true),
      "32": Self.hotKey(enabled: true),  // Mission Control 自体など、Desktop 以外のショートカット
    ]
    #expect(desktopsWithEnabledShortcut(symbolicHotKeys: symbolicHotKeys) == [1, 3, 9])
  }
}
