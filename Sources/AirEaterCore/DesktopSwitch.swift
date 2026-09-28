import Carbon.HIToolbox
import CoreGraphics

/// 合成して送出するキー入力 1 回分。
public struct KeyStroke: Equatable, Sendable {
  public let keyCode: CGKeyCode
  public let flags: CGEventFlags
}

/// 数字キー 1…9 の仮想キーコード。添字 0 が 1 キー。
public let digitKeyCodes: [CGKeyCode] = [
  kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
  kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
].map { CGKeyCode($0) }

/// Mission Control の「デスクトップ N へ切り替え」(Ctrl+N) に当たるキー入力。
public func keyStroke(switchingTo desktop: Int) -> KeyStroke? {
  guard digitKeyCodes.indices.contains(desktop - 1) else { return nil }
  return KeyStroke(keyCode: digitKeyCodes[desktop - 1], flags: .maskControl)
}
