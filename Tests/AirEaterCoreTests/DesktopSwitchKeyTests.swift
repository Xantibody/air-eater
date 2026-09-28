import CoreGraphics
import Testing

@testable import AirEaterCore

@Suite struct DesktopSwitchKeyTests {
  @Test func digitWithoutControlSwitchesNothing() {
    #expect(desktopSwitched(keyCode: 0x12, flags: []) == nil)
  }
}

extension DesktopSwitchKeyTests {
  @Test func controlOneSwitchesToDesktopOne() {
    #expect(desktopSwitched(keyCode: 0x12, flags: .maskControl) == 1)
  }
}

extension DesktopSwitchKeyTests {
  @Test func controlNineSwitchesToDesktopNine() {
    #expect(desktopSwitched(keyCode: 0x19, flags: [.maskControl, .maskNonCoalesced]) == 9)
  }

  @Test func controlWithAnotherModifierSwitchesNothing() {
    #expect(desktopSwitched(keyCode: 0x12, flags: [.maskControl, .maskAlternate]) == nil)
  }

  @Test func controlWithNonDigitSwitchesNothing() {
    #expect(desktopSwitched(keyCode: 0x00, flags: .maskControl) == nil)  // Ctrl+A
  }
}
