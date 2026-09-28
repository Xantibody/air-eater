import Testing

@testable import AirEaterCore

@Suite struct SpacePoolDescriptionTests {
  @Test func freshPoolDescribesNothing() {
    #expect(SpacePool(desktops: 1...9).description == "")
  }
}

extension SpacePoolDescriptionTests {
  @Test func observedDesktopListsItsWindows() {
    var pool = SpacePool(desktops: 1...9)
    pool.observe(desktop: 3, windows: [30])
    #expect(pool.description == "3:{30}")
  }
}

extension SpacePoolDescriptionTests {
  // 空と確かめた Desktop は {} で残し、まだ見ていない Desktop は出さない
  @Test func describesObservedDesktopsInOrderWithSortedWindows() {
    var pool = SpacePool(desktops: 1...9)
    pool.observe(desktop: 5, windows: [52, 51])
    pool.observe(desktop: 2, windows: [])
    pool.observe(desktop: 1, windows: [10])
    #expect(pool.description == "1:{10} 2:{} 5:{51,52}")
  }
}
