import AirEaterCore
import AppKit

/// 最前面のアプリのフォーカス中ウィンドウを、そのウィンドウがある画面の tile に寄せる。
@MainActor
func tileFocusedWindow(_ tile: Tile) {
  guard let (window, appName) = focusedWindow(for: "\(tile)") else { return }
  guard let primary = NSScreen.screens.first else { return }

  let screen = screen(containing: window, primaryHeight: primary.frame.height) ?? primary
  let frame = accessibilityFrame(
    fromCocoa: tile.frame(in: screen.visibleFrame), primaryScreenHeight: primary.frame.height)
  log("\(tile) → \(appName) の窓を \(screen.localizedName) の \(frame) (AX 座標) に寄せる")

  // 最小サイズを持つアプリは 1 回目の size を丸めて返す。position を決めた後に
  // もう一度 size を書くと、1 回目で弾かれた分を吸収できる
  let results = [
    set(window, kAXSizeAttribute, frame.size),
    set(window, kAXPositionAttribute, frame.origin),
    set(window, kAXSizeAttribute, frame.size),
  ]
  if let failure = results.first(where: { $0 != .success }) {
    log("\(tile) → \(appName) の窓の frame を書けなかった (AXError \(failure.rawValue))")
  }
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
