import AirEaterCore
import AppKit

/// 最前面のアプリのフォーカス中ウィンドウを、そのウィンドウがある画面の tile に寄せる。
@MainActor
func tileFocusedWindow(_ tile: Tile) {
  let system = AXUIElementCreateSystemWide()
  guard
    let app = element(system, kAXFocusedApplicationAttribute),
    let window = element(app, kAXFocusedWindowAttribute),
    let primary = NSScreen.screens.first
  else { return }

  let screen = screen(containing: window, primaryHeight: primary.frame.height) ?? primary
  let frame = accessibilityFrame(
    fromCocoa: tile.frame(in: screen.visibleFrame), primaryScreenHeight: primary.frame.height)

  // 最小サイズを持つアプリは 1 回目の size を丸めて返す。position を決めた後に
  // もう一度 size を書くと、1 回目で弾かれた分を吸収できる
  set(window, kAXSizeAttribute, frame.size)
  set(window, kAXPositionAttribute, frame.origin)
  set(window, kAXSizeAttribute, frame.size)
}

private func screen(containing window: AXUIElement, primaryHeight: CGFloat) -> NSScreen? {
  guard
    let origin: CGPoint = value(window, kAXPositionAttribute, .cgPoint, .zero),
    let size: CGSize = value(window, kAXSizeAttribute, .cgSize, .zero)
  else { return nil }
  // AX (左上原点) の中心を Cocoa (左下原点) に直して、それを含む画面を探す
  let center = CGPoint(
    x: origin.x + size.width / 2, y: primaryHeight - (origin.y + size.height / 2))
  return NSScreen.screens.first { $0.frame.contains(center) }
}

private func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
    let value, CFGetTypeID(value) == AXUIElementGetTypeID()
  else { return nil }
  return unsafeDowncast(value, to: AXUIElement.self)
}

private func value<T: BitwiseCopyable>(
  _ element: AXUIElement, _ attribute: String, _ type: AXValueType, _ initial: T
) -> T? {
  var raw: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
    let raw, CFGetTypeID(raw) == AXValueGetTypeID()
  else { return nil }
  var result = initial
  guard AXValueGetValue(unsafeDowncast(raw, to: AXValue.self), type, &result) else { return nil }
  return result
}

private func set(_ element: AXUIElement, _ attribute: String, _ size: CGSize) {
  var size = size
  guard let value = AXValueCreate(.cgSize, &size) else { return }
  AXUIElementSetAttributeValue(element, attribute as CFString, value)
}

private func set(_ element: AXUIElement, _ attribute: String, _ point: CGPoint) {
  var point = point
  guard let value = AXValueCreate(.cgPoint, &point) else { return }
  AXUIElementSetAttributeValue(element, attribute as CFString, value)
}
