import CoreGraphics
import Testing

@testable import AirEaterCore

@Suite struct KeyCommandTests {
  @Test func keyWithoutModifierIsNotACommand() {
    #expect(command(keyCode: 0x12, flags: []) == nil)
  }
}

extension KeyCommandTests {
  @Test func optionOneGoesToWorkspaceOne() {
    #expect(command(keyCode: 0x12, flags: .maskAlternate) == .workspace(1))
  }
}

extension KeyCommandTests {
  @Test(
    arguments: [
      (CGKeyCode(0x19), Command.workspace(9)),
      (0x21, .neighbor(.previous)),  // [
      (0x1E, .neighbor(.next)),  // ]
      (0x24, .openTerminal),  // Return
      (0x04, .tile(.left)),  // H
      (0x26, .tile(.bottom)),  // J
      (0x28, .tile(.top)),  // K
      (0x25, .tile(.right)),  // L
      (0x08, .close),  // C
      (0x03, .tile(.fill)),  // F
    ] as [(CGKeyCode, Command)])
  func optionKeyMapsToCommand(keyCode: CGKeyCode, expected: Command) {
    #expect(command(keyCode: keyCode, flags: .maskAlternate) == expected)
  }

  @Test func unboundKeyWithOptionIsNotACommand() {
    #expect(command(keyCode: 0x00, flags: .maskAlternate) == nil)  // A
  }
}

extension KeyCommandTests {
  // Option+Cmd+1 などはアプリのショートカットなので横取りしない
  @Test(arguments: [CGEventFlags.maskCommand, .maskControl, .maskShift])
  func optionCombinedWithAnotherModifierIsNotACommand(extra: CGEventFlags) {
    #expect(command(keyCode: 0x12, flags: [.maskAlternate, extra]) == nil)
  }

  // 実際のキーイベントには修飾キー以外のフラグも付いてくる
  @Test func nonModifierFlagsAreIgnored() {
    let flags: CGEventFlags = [.maskAlternate, .maskNonCoalesced, .maskAlphaShift]
    #expect(command(keyCode: 0x12, flags: flags) == .workspace(1))
  }
}

extension KeyCommandTests {
  // Option+Shift+Return だけは Shift 付きで、新しい workspace に端末を開く
  @Test func optionShiftReturnOpensTerminalInNewWorkspace() {
    #expect(command(keyCode: 0x24, flags: [.maskAlternate, .maskShift]) == .newWorkspace)
  }

  @Test func optionShiftWithOtherKeysIsNotACommand() {
    #expect(command(keyCode: 0x12, flags: [.maskAlternate, .maskShift]) == nil)
  }
}
