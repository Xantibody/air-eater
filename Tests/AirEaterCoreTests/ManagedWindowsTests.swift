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
