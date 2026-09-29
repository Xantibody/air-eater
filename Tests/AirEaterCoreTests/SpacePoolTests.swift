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
