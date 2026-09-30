import Testing

@testable import AirEaterCore

@Suite struct ArrangementTests {
  @Test func noWindowNeedsNoArrangement() {
    #expect(Arrangement(windowCount: 0) == nil)
  }
}

extension ArrangementTests {
  @Test func singleWindowFillsTheScreen() {
    #expect(Arrangement(windowCount: 1) == .fill)
  }
}

extension ArrangementTests {
  @Test(arguments: [
    (2, Arrangement.leftAndRight),
    (3, .leftAndQuarters),
    (4, .quarters),
  ])
  func windowCountPicksNativeArrangement(count: Int, expected: Arrangement) {
    #expect(Arrangement(windowCount: count) == expected)
  }

  // 標準の配置は 4 枚までしか並べない。それより多いときは触らない
  @Test func fiveOrMoreWindowsAreLeftAlone() {
    #expect(Arrangement(windowCount: 5) == nil)
  }
}
