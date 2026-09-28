import CoreGraphics

/// Super+HJKL で寄せる先。画面の可視領域を半分に割る。
public enum Tile: Sendable, CaseIterable {
  case left, bottom, top, right

  /// visible (Cocoa 座標、左下原点) の中での frame。上半分は y が大きい側。
  public func frame(in visible: CGRect) -> CGRect {
    let (distance, edge): (CGFloat, CGRectEdge) =
      switch self {
      case .left: (visible.width / 2, .minXEdge)
      case .right: (visible.width / 2, .maxXEdge)
      case .bottom: (visible.height / 2, .minYEdge)
      case .top: (visible.height / 2, .maxYEdge)
      }
    return visible.divided(atDistance: distance, from: edge).slice
  }
}
