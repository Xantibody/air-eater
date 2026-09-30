import ApplicationServices

/// アクセシビリティ権限を確かめ、無ければシステム設定へ誘導するダイアログを出す。
/// キー監視 (CGEventTap)、CGEventPost、AX の読み書きがこの権限に依存する。
@discardableResult
func requestAccessibilityPermission() -> Bool {
  // kAXTrustedCheckOptionPrompt は Swift 6 で可変グローバル扱いになり並行性検査に掛かるので文字列で渡す
  let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
  return AXIsProcessTrustedWithOptions(options)
}

/// 窓がネイティブの全画面かどうか。読み書きできるが、公開ヘッダに定義が無い
let fullscreenAttribute = "AXFullScreen"
