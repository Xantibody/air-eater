/// com.apple.symbolichotkeys の AppleSymbolicHotKeys から、
/// 「デスクトップ N へ切り替え」(Ctrl+N) が有効な N を返す。
public func desktopsWithEnabledShortcut(symbolicHotKeys: [String: Any]) -> Set<Int> {
  Set(
    (1...9).filter { desktop in
      let hotKey = symbolicHotKeys[String(117 + desktop)] as? [String: Any]
      return hotKey?["enabled"] as? Bool == true
    })
}
