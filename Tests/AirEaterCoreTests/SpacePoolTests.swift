import Testing

@testable import AirEaterCore

@Suite struct SpacePoolTests {
  @Test func poolWithoutWindowsHasNoActiveWorkspace() {
    let pool = SpacePool(desktops: 1...9)
    #expect(pool.active == [])
  }

  @Test func observedDesktopBecomesActive() {
    var pool = SpacePool(desktops: 1...9)
    pool.observe(desktop: 3, windows: [10])
    #expect(pool.active == [3])
  }

  @Test func desktopEmptiedByClosingWindowsDropsOut() {
    var pool = SpacePool(desktops: 1...9)
    pool.observe(desktop: 1, windows: [10])
    pool.observe(desktop: 4, windows: [20])
    pool.observe(desktop: 1, windows: [])
    #expect(pool.active == [4])
  }

  @Test func windowSeenOnAnotherDesktopLeavesThePreviousOne() {
    var pool = SpacePool(desktops: 1...9)
    pool.observe(desktop: 1, windows: [10])
    pool.observe(desktop: 5, windows: [10])
    #expect(pool.active == [5])
  }
}

@Suite struct SpacePoolRetainTests {
  @Test func windowClosedOnHiddenDesktopDropsOut() {
    var pool = SpacePool(desktops: 1...9)
    pool.observe(desktop: 1, windows: [10])
    pool.observe(desktop: 2, windows: [20])
    pool.retain(existing: [20])
    #expect(pool.active == [2])
  }
}

@Suite struct SpacePoolFirstEmptyTests {
  @Test func firstDesktopIsEmptyInFreshPool() {
    #expect(SpacePool(desktops: 1...9).firstEmpty == 1)
  }
}

extension SpacePoolFirstEmptyTests {
  @Test func occupiedDesktopIsSkipped() {
    var pool = SpacePool(desktops: 1...9)
    pool.observe(desktop: 1, windows: [10])
    #expect(pool.firstEmpty == 2)
  }

  @Test func gapBetweenOccupiedDesktopsIsReused() {
    var pool = SpacePool(desktops: 1...9)
    pool.observe(desktop: 1, windows: [10])
    pool.observe(desktop: 3, windows: [30])
    #expect(pool.firstEmpty == 2)
  }
}

extension SpacePoolFirstEmptyTests {
  @Test func fullPoolHasNoEmptyDesktop() {
    var pool = SpacePool(desktops: 1...2)
    pool.observe(desktop: 1, windows: [10])
    pool.observe(desktop: 2, windows: [20])
    #expect(pool.firstEmpty == nil)
  }
}

@Suite struct SpacePoolWorkspaceTests {
  @Test func firstWorkspaceOfFreshPoolIsNewOnFirstDesktop() {
    #expect(SpacePool(desktops: 1...9).desktop(forWorkspace: 1) == 1)
  }
}

extension SpacePoolWorkspaceTests {
  @Test func singleWorkspaceMapsToItsDesktop() {
    var pool = SpacePool(desktops: 1...9)
    pool.observe(desktop: 3, windows: [30])
    #expect(pool.desktop(forWorkspace: 1) == 3)
  }
}

extension SpacePoolWorkspaceTests {
  // Desktop 1・4・6 に窓がある。2・3・5 の空きは番号に数えない
  static func poolWithGaps() -> SpacePool {
    var pool = SpacePool(desktops: 1...9)
    pool.observe(desktop: 1, windows: [10])
    pool.observe(desktop: 4, windows: [40])
    pool.observe(desktop: 6, windows: [60])
    return pool
  }

  @Test(arguments: [(1, 1), (2, 4), (3, 6)])
  func workspaceNumbersSkipEmptyDesktops(workspace: Int, desktop: Int) {
    #expect(Self.poolWithGaps().desktop(forWorkspace: workspace) == desktop)
  }

  @Test(arguments: [4, 9])
  func workspaceBeyondActiveOpensFirstEmptyDesktop(workspace: Int) {
    #expect(Self.poolWithGaps().desktop(forWorkspace: workspace) == 2)
  }

  @Test func workspaceZeroHasNoDesktop() {
    #expect(Self.poolWithGaps().desktop(forWorkspace: 0) == nil)
  }
}

@Suite struct SpacePoolNeighborTests {
  @Test func freshPoolHasNoNeighbor() {
    #expect(SpacePool(desktops: 1...9).desktop(nextTo: 1, direction: .next) == nil)
  }
}

extension SpacePoolNeighborTests {
  @Test func nextSkipsEmptyDesktops() {
    var pool = SpacePool(desktops: 1...9)
    pool.observe(desktop: 1, windows: [10])
    pool.observe(desktop: 4, windows: [40])
    #expect(pool.desktop(nextTo: 1, direction: .next) == 4)
  }
}

extension SpacePoolNeighborTests {
  // Desktop 1・4・6 に窓がある。空き Desktop の 2 からも隣へ行ける
  @Test(arguments: [(4, 6), (2, 4), (6, nil)] as [(Int, Int?)])
  func nextIsNearestActiveDesktopAfterCurrent(current: Int, expected: Int?) {
    let pool = SpacePoolWorkspaceTests.poolWithGaps()
    #expect(pool.desktop(nextTo: current, direction: .next) == expected)
  }

  @Test(arguments: [(4, 1), (2, 1), (1, nil)] as [(Int, Int?)])
  func previousIsNearestActiveDesktopBeforeCurrent(current: Int, expected: Int?) {
    let pool = SpacePoolWorkspaceTests.poolWithGaps()
    #expect(pool.desktop(nextTo: current, direction: .previous) == expected)
  }
}
