import CoreGraphics
import Testing

@testable import AirEaterCore

@Suite struct ManagedWindowsTests {
  @Test func emptyWindowListHasNoManagedWindow() {
    #expect(managedWindows(in: [], excludingProcess: 1) == [])
  }
}

extension ManagedWindowsTests {
  static func window(
    _ id: CGWindowID, pid: pid_t = 500, layer: Int = 0, alpha: Double = 1
  ) -> [String: Any] {
    [
      kCGWindowNumber as String: id,
      kCGWindowOwnerPID as String: pid,
      kCGWindowLayer as String: layer,
      kCGWindowAlpha as String: alpha,
    ]
  }

  @Test func ordinaryAppWindowIsManaged() {
    #expect(managedWindows(in: [Self.window(10)], excludingProcess: 1) == [10])
  }
}

extension ManagedWindowsTests {
  @Test func onlyOrdinaryWindowsOfOtherAppsAreManaged() {
    let windowList = [
      Self.window(10),
      Self.window(11, pid: 1),  // 自分のマーカー
      Self.window(12, layer: 25),  // メニューバーやステータス項目
      Self.window(13, alpha: 0),  // 見えないウィンドウ
      Self.window(14, pid: 600),
    ]
    #expect(managedWindows(in: windowList, excludingProcess: 1) == [10, 14])
  }
}

@Suite struct FrontmostWindowOwnerTests {
  @Test func emptyWindowListHasNoOwner() {
    #expect(frontmostWindowOwner(in: [], excludingProcess: 1) == nil)
  }
}

extension FrontmostWindowOwnerTests {
  static func window(
    _ id: CGWindowID, pid: pid_t, name: String, layer: Int = 0
  ) -> [String: Any] {
    var info = ManagedWindowsTests.window(id, pid: pid, layer: layer)
    info[kCGWindowOwnerName as String] = name
    return info
  }

  // NSWorkspace では Nix の kitty の pid が -1 になるが、窓の持ち主の pid は正しい
  @Test func frontmostOrdinaryWindowDecidesTheOwner() {
    let windowList = [
      Self.window(1, pid: 800, name: "Window Server", layer: 25),  // メニューバー
      Self.window(2, pid: 1, name: "air-eater"),  // 自分のマーカー
      Self.window(3, pid: 19176, name: "kitty"),
      Self.window(4, pid: 600, name: "Finder"),
    ]
    #expect(
      frontmostWindowOwner(in: windowList, excludingProcess: 1)
        == WindowOwner(pid: 19176, name: "kitty"))
  }
}

extension FrontmostWindowOwnerTests {
  // タイル表示などの間、macOS の WindowManager が通常レイヤーの一番手前に窓を出すことがある。
  // 実機で、E2E の窓より手前にいて、タイルの相手を取り違えた
  @Test func windowManagerOverlayIsNeitherCountedNorTheOwner() {
    let windowList = [
      Self.window(1, pid: 700, name: "WindowManager"),
      Self.window(2, pid: 500, name: "AirEaterE2E"),
    ]
    #expect(
      frontmostWindowOwner(in: windowList, excludingProcess: 1)
        == WindowOwner(pid: 500, name: "AirEaterE2E"))
    #expect(managedWindows(in: windowList, excludingProcess: 1) == [2])
  }
}
