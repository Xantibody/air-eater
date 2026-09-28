import CoreGraphics
import Testing

@testable import AirEaterCore

@Suite struct DesktopSwitchTests {
  @Test(arguments: [0, 10])
  func desktopOutsideControlDigitsHasNoKeyStroke(desktop: Int) {
    #expect(keyStroke(switchingTo: desktop) == nil)
  }

  // kVK_ANSI_1…9。数字順に並んでいないので実装の定数ではなく生の値で持つ
  @Test(
    arguments: zip(
      1...9,
      [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19] as [CGKeyCode]
    ))
  func desktopNIsControlDigitN(desktop: Int, keyCode: CGKeyCode) {
    #expect(keyStroke(switchingTo: desktop) == KeyStroke(keyCode: keyCode, flags: .maskControl))
  }
}
