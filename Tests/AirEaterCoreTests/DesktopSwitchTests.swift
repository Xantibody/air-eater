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

extension DesktopSwitchTests {
  // 数字キーの down/up に Ctrl のフラグを付けるだけでは、システムが Control を押されたままだと
  // 思い込む (実機で HID の状態に Control が残り、以後のクリックが Ctrl+クリックになった)。
  // 修飾キー自体の押下と解放も送るために、フラグから修飾キーのキーコードを引く
  @Test func controlFlagMapsToTheControlKey() {
    #expect(modifierKeyCodes(for: .maskControl) == [59])
  }

  @Test func eachModifierFlagMapsToItsKeyInAFixedOrder() {
    let flags: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
    #expect(modifierKeyCodes(for: flags) == [59, 58, 56, 55])  // Control, Option, Shift, Command
  }

  @Test func nonModifierFlagsMapToNoKey() {
    #expect(modifierKeyCodes(for: [.maskNonCoalesced, .maskAlphaShift]) == [])
  }
}
