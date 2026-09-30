import CoreGraphics
import Testing

@testable import AirEaterCore

/// 実機で一度、全 Space の窓が一斉に「画面に写っている」と報告される瞬間を観測した。
/// そのまま数えると、他の Desktop の窓が全部この Desktop に移ったように見える。
/// 既に別の Desktop の窓だと分かっている窓が混ざった観測は捨てる
@Suite struct SuspectObservationTests {
  static func pool() -> SpacePool {
    var pool = SpacePool(desktops: 1...9)
    pool.observe(desktop: 1, windows: [10, 11])
    pool.observe(desktop: 3, windows: [30])
    return pool
  }

  @Test func windowsNeverSeenElsewhereAreTrusted() {
    #expect(!Self.pool().isSuspect(desktop: 2, windows: [20, 21]))
  }

  @Test func theDesktopsOwnWindowsAreTrusted() {
    #expect(!Self.pool().isSuspect(desktop: 1, windows: [10, 11, 12]))
  }

  // Mission Control で窓を 1 枚動かした直後は、移動先で 1 枚だけ別の Desktop の窓が見える。これは信じる
  @Test func oneWindowMovedFromAnotherDesktopIsTrusted() {
    #expect(!Self.pool().isSuspect(desktop: 2, windows: [20, 30]))
  }

  // 実機で見た形: Desktop 1 の窓が全部、別の Desktop の観測に混ざる
  @Test func manyWindowsFromOtherDesktopsMakeTheObservationSuspect() {
    #expect(Self.pool().isSuspect(desktop: 2, windows: [10, 11, 30, 99]))
  }

  // 別の Desktop の窓が 2 枚あっても、この Desktop の窓の方が多ければ信じる
  @Test func aFewForeignWindowsAmongManyOwnAreTrusted() {
    #expect(!Self.pool().isSuspect(desktop: 2, windows: [10, 30, 20, 21, 22]))
  }

  @Test func emptyObservationIsTrusted() {
    #expect(!Self.pool().isSuspect(desktop: 2, windows: []))
  }
}
