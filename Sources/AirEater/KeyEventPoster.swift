import AirEaterCore
import CoreGraphics

/// キー入力を HID 層に合成して送る。システムのホットキー (Mission Control) は
/// session tap に送っても反応しないので cghidEventTap に流す。
/// アクセシビリティ権限が無いと黙って捨てられる。
func post(_ stroke: KeyStroke) {
  let source = CGEventSource(stateID: .hidSystemState)
  let modifiers = modifierKeyCodes(for: stroke.flags)
  // AIDEV-NOTE: 修飾キーの押下と解放 (flagsChanged) も送る。数字キーの down / up に Ctrl の
  // フラグを付けるだけだと、システムの HID の状態に Control が残り、以後のマウスダウンが
  // Ctrl+クリックになって窓を掴めなくなった (実機で movetoworkspace が動かなくなった原因)
  for keyCode in modifiers {
    postFlagsChanged(source, keyCode, flags: stroke.flags)
  }
  for keyDown in [true, false] {
    let event = CGEvent(keyboardEventSource: source, virtualKey: stroke.keyCode, keyDown: keyDown)
    event?.flags = stroke.flags
    event?.post(tap: .cghidEventTap)
  }
  for keyCode in modifiers.reversed() {
    postFlagsChanged(source, keyCode, flags: [])
  }
}

private func postFlagsChanged(_ source: CGEventSource?, _ keyCode: CGKeyCode, flags: CGEventFlags) {
  let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: !flags.isEmpty)
  event?.type = .flagsChanged
  event?.flags = flags
  event?.post(tap: .cghidEventTap)
}
