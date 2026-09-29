import CoreGraphics
import Testing

@testable import AirEaterCore

/// 自前の frame で並べるには、手前から順に「どのプロセスの窓が今どこにあるか」が要る
@Suite struct WindowEntriesTests {
  static func window(
    _ id: CGWindowID, pid: pid_t, layer: Int = 0, alpha: Double = 1, left: CGFloat = 0
  ) -> [String: Any] {
    [
      kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid,
      kCGWindowLayer as String: layer, kCGWindowAlpha as String: alpha,
      kCGWindowOwnerName as String: "App",
      kCGWindowBounds as String: ["X": left, "Y": 20, "Width": 300, "Height": 200]
        as [String: CGFloat],
    ]
  }

  @Test func keepsFrontToBackOrderAndBounds() {
    let list = [
      Self.window(7, pid: 100, left: 50),
      Self.window(8, pid: 100, layer: 25),  // メニューバーなどの別レイヤー
      Self.window(9, pid: 200, left: 400),
      Self.window(10, pid: 999),  // 自分
    ]
    let entries = managedWindowEntries(in: list, excludingProcess: 999)
    #expect(entries.map(\.id) == [7, 9])
    #expect(entries.map(\.pid) == [100, 200])
    #expect(entries[1].bounds == CGRect(x: 400, y: 20, width: 300, height: 200))
  }
}
