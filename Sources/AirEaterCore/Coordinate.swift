import CoreGraphics

/// Cocoa 座標 (NSScreen、左下原点) の矩形を AX 座標 (kAXPositionAttribute、左上原点) に直す。
/// どちらも主ディスプレイが基準なので、ひっくり返す軸は主ディスプレイの高さで決まる。
public func accessibilityFrame(fromCocoa rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
  CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
}
