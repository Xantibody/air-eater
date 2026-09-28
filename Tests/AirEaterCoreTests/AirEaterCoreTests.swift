import Testing

@testable import AirEaterCore

@Test func defaultPoolHasNineDesktops() {
  #expect(defaultPool == Array(1...9))
}
