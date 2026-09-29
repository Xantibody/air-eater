import AirEaterCore
import AppKit

/// 相手のアプリ (targetApplication) のフォーカス中の窓。
/// 取れなければ、何のための操作だったか (purpose) と理由をログに出して nil
@MainActor
func focusedWindow(for purpose: String) -> (window: AXUIElement, appName: String)? {
  guard let owner = targetApplication() else {
    log("\(purpose) → 相手のアプリが無い")
    return nil
  }
  switch element(AXUIElementCreateApplication(owner.pid), kAXFocusedWindowAttribute) {
  case .success(let window): return (window, owner.name)
  case .failure(let error):
    log("\(purpose) → \(owner.name) のフォーカス中の窓が取れない (AXError \(error.code.rawValue))")
    return nil
  }
}
