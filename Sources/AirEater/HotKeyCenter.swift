import Carbon.HIToolbox

/// RegisterEventHotKey で握ったホットキーと、押されたときの処理の対応表。
/// Carbon のホットキーはアクセシビリティ権限なしで使える。
@MainActor
final class HotKeyCenter {
  private var actions: [UInt32: () -> Void] = [:]
  private var refs: [EventHotKeyRef] = []

  init() {
    var pressed = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyID
        )
        guard status == noErr else { return status }
        let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
        // Carbon のイベントはメインスレッドのランループで配送される
        MainActor.assumeIsolated { center.actions[hotKeyID.id]?() }
        return noErr
      },
      1,
      &pressed,
      Unmanaged.passUnretained(self).toOpaque(),
      nil
    )
  }

  /// - Parameters:
  ///   - keyCode: 仮想キーコード (kVK_*)
  ///   - modifiers: Carbon の修飾キー (cmdKey, optionKey など)
  func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) throws {
    let id = EventHotKeyID(signature: Self.signature, id: UInt32(actions.count + 1))
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    guard status == noErr, let ref else {
      throw HotKeyError.registrationFailed(keyCode: keyCode, status: status)
    }
    refs.append(ref)
    actions[id.id] = action
  }

  /// "AirE"
  private static let signature: OSType = 0x4169_7245
}

enum HotKeyError: Error {
  case registrationFailed(keyCode: UInt32, status: OSStatus)
}
