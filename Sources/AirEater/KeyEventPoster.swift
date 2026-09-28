import AirEaterCore
import CoreGraphics

/// キー入力を HID 層に合成して送る。システムのホットキー (Mission Control) は
/// session tap に送っても反応しないので cghidEventTap に流す。
/// アクセシビリティ権限が無いと黙って捨てられる。
func post(_ stroke: KeyStroke) {
  let source = CGEventSource(stateID: .hidSystemState)
  for keyDown in [true, false] {
    let event = CGEvent(keyboardEventSource: source, virtualKey: stroke.keyCode, keyDown: keyDown)
    event?.flags = stroke.flags
    event?.post(tap: .cghidEventTap)
  }
}
