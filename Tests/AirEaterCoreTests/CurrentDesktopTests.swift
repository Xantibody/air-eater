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

extension CurrentDesktopTests {
  // Mission Control のように全 Space を重ねて見せている間は、複数のマーカーが同時に写る。
  // どれが今の Desktop か決められないので、プール外と同じく不明にする (実機で Desktop 2 に着いた
  // 直後に Desktop 1 と判定し、全 Space の窓を Desktop 1 の窓として数えた)
  @Test func severalMarkersOnScreenMeansUnknown() {
    #expect(currentDesktop(markers: Self.markers, onScreen: [901, 902, 100]) == nil)
  }
}
