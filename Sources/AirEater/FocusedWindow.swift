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

/// 相手のアプリのフォーカス中の窓を、閉じるボタンを押して閉じる (Hyprland の killactive)。
/// 赤いボタンを押すのと同じなので、未保存の書類があればアプリが確認を出す。アプリは終了しない
@MainActor
func closeFocusedWindow() {
  guard let (window, appName) = focusedWindow(for: "close") else { return }
  guard case .success(let button) = element(window, kAXCloseButtonAttribute) else {
    log("close → \(appName) の窓に閉じるボタンが無い")
    return
  }
  let error = AXUIElementPerformAction(button, kAXPressAction as CFString)
  log("close → \(appName) の窓の閉じるボタンを押した (AXError \(error.rawValue))")
}
