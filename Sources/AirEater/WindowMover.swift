import AirEaterCore
import AppKit

/// フォーカス中の窓を desktop へ移す。窓を別の Space へ移す公開 API は無いので、タイトルバーを掴んで
/// 数 px ドラッグした状態で Ctrl+desktop を送り、切り替わってから離す (Amethyst と同じ手法)。
/// カーソルを実際に動かすので、終わったら元の位置へ戻す。切り替わったら true。
/// mouseDown だけでは窓は付いて来ない。ドラッグ状態に入ってから切り替えるのが要点 (実機で確認)
@MainActor
func dragFocusedWindow(to desktop: Int) async -> Bool {
  guard let (window, appName) = focusedWindow(for: "move") else { return false }
  guard attribute(window, fullscreenAttribute, as: Bool.self) != true else {
    log("move → \(appName) の窓は全画面なので移せない。先に Option+F で全画面を解く")
    return false
  }
  guard attribute(window, kAXMinimizedAttribute, as: Bool.self) != true else {
    log("move → \(appName) の窓は最小化されているので移せない")
    return false
  }
  guard let origin: CGPoint = value(window, kAXPositionAttribute, .cgPoint, .zero),
    let size: CGSize = value(window, kAXSizeAttribute, .cgSize, .zero)
  else {
    log("move → \(appName) の窓の位置が取れない")
    return false
  }
  let grab = dragGrabPoint(in: CGRect(origin: origin, size: size))
  let cursor = CGEvent(source: nil)?.location
  log("move → \(appName) の窓を \(grab) で掴んで Desktop \(desktop) へ")

  await mouse(.mouseMoved, at: grab)
  await mouse(.leftMouseDown, at: grab)
  await mouse(.leftMouseDragged, at: grab.offsetBy(5))
  await mouse(.leftMouseDragged, at: grab.offsetBy(10))
  try? await Task.sleep(for: .milliseconds(200))
  let switched = await switchDesktop(to: desktop)
  // 切り替えの通知が来た直後は、まだアニメーションの途中。窓が移動先に落ち着くまで掴んでおく。
  // 実機では通知の後 0.3 秒で離すと窓が元の Desktop に残り、1 秒弱掴んでいれば付いて来た
  try? await Task.sleep(for: .milliseconds(900))
  await mouse(.leftMouseDragged, at: grab.offsetBy(12))
  await mouse(.leftMouseUp, at: grab.offsetBy(12))
  if let cursor { CGWarpMouseCursorPosition(cursor) }
  if !switched { log("move → 切り替わらなかったので、窓は元の Desktop に残る") }
  return switched
}

/// マウスのイベントを実際のマウスと同じ HID 層に送り、次のイベントまで少し置く。
private func mouse(_ type: CGEventType, at point: CGPoint) async {
  let event = CGEvent(
    mouseEventSource: nil, mouseType: type,
    mouseCursorPosition: point, mouseButton: .left)
  event?.post(tap: .cghidEventTap)
  try? await Task.sleep(for: .milliseconds(60))
}

extension CGPoint {
  fileprivate func offsetBy(_ delta: CGFloat) -> CGPoint {
    CGPoint(x: x + delta, y: y + delta)
  }
}
