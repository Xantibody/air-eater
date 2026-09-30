import AirEaterCore
import CoreGraphics
import Foundation

/// キー入力を HID の段で横から見る。
/// Option だけを修飾キーにした RegisterEventHotKey は、登録に成功しても実機 (Darwin 27) で
/// 一度も発火しなかった (macOS 15 で入ったキーロガー対策の制限とみられる)。
/// CGEventTap で自分で読み分ける。
/// 手で押した Ctrl+数字 も見えるので、air-eater を通さない切り替えの行き先も分かる。
@MainActor
final class KeyTap {
  var onCommand: (Command) -> Void = { _ in }
  var onDesktopSwitchKey: (Int) -> Void = { _ in }
  private var tap: CFMachPort?

  /// アクセシビリティ権限が無いと作れず false を返す。
  func start() -> Bool {
    guard
      let tap = CGEvent.tapCreate(
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
        callback: { _, type, event, userInfo in
          guard let userInfo else { return Unmanaged.passUnretained(event) }
          let keyTap = Unmanaged<KeyTap>.fromOpaque(userInfo).takeUnretainedValue()
          // CGEvent は Sendable でないので、メインアクターへは値だけを渡す
          let key = Key(
            keyCode: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)),
            flags: event.flags,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
          )
          // メインのランループに載せているので、コールバックはメインスレッドで呼ばれる
          let passThrough = MainActor.assumeIsolated { keyTap.handle(type: type, key: key) }
          return passThrough ? Unmanaged.passUnretained(event) : nil
        },
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else { return false }
    self.tap = tap
    CFRunLoopAddSource(
      CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    return true
  }

  /// キー入力をアプリに渡すなら true。
  private func handle(type: CGEventType, key: Key) -> Bool {
    switch type {
    case .keyDown:
      break
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      // コールバックが遅いとシステムがタップを止める。止まったままだと全ホットキーが死ぬ
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      log("キー監視が止められたので再開した")
      return true
    default:
      return true
    }

    // 入力内容がすべて出るので、キー監視そのものを疑うときだけ有効にする
    if logsEveryKey {
      log(
        "キー keyCode=\(key.keyCode) flags=0x\(String(key.flags.rawValue, radix: 16)) repeat=\(key.isRepeat)"
      )
    }
    if let action = command(keyCode: key.keyCode, flags: key.flags) {
      // 押しっぱなしの自動リピートでは操作を繰り返さない。どちらもアプリには渡さない
      if !key.isRepeat { onCommand(action) }
      return false
    }
    if !key.isRepeat, let desktop = desktopSwitched(keyCode: key.keyCode, flags: key.flags) {
      onDesktopSwitchKey(desktop)
    }
    return true
  }
}

private let logsEveryKey = ProcessInfo.processInfo.environment["AIR_EATER_LOG_KEYS"] == "1"

private struct Key: Sendable {
  let keyCode: CGKeyCode
  let flags: CGEventFlags
  let isRepeat: Bool
}
