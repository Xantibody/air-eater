import CoreGraphics
import Testing

@testable import AirEaterCore

@Suite struct CurrentDesktopTests {
  @Test func withoutMarkersCurrentDesktopIsUnknown() {
    #expect(currentDesktop(markers: [:], onScreen: [100]) == nil)
  }
}

extension CurrentDesktopTests {
  @Test func desktopWhoseMarkerIsOnScreenIsCurrent() {
    #expect(currentDesktop(markers: [2: 902], onScreen: [100, 902]) == 2)
  }
}

extension CurrentDesktopTests {
  static let markers: [Int: CGWindowID] = [1: 901, 2: 902, 3: 903]

  @Test func onlyTheMarkerOnScreenDecidesAmongMany() {
    #expect(currentDesktop(markers: Self.markers, onScreen: [100, 903, 200]) == 3)
  }

  @Test func spaceWithoutMarkerIsOutsideThePool() {
    #expect(currentDesktop(markers: Self.markers, onScreen: [100, 200]) == nil)
  }
}
