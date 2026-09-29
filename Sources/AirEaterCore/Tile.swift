import CoreGraphics

/// Super+HJKL で寄せる先と、Super+F で広げる先。画面の可視領域を基準にする。
public enum Tile: Sendable, CaseIterable {
  case left, bottom, top, right
  /// 可視領域いっぱい。ネイティブの全画面は別の Space を作って workspace の外に出てしまうので、
  /// Hyprland の fullscreen に当たる操作は窓を同じ大きさに広げるだけにする
  case fill

  /// visible (Cocoa 座標、左下原点) の中での frame。上半分は y が大きい側。
  public func frame(in visible: CGRect) -> CGRect {
    guard let (distance, edge) = halfToKeep(of: visible) else { return visible }
    return visible.divided(atDistance: distance, from: edge).slice
  }

  /// 半分に割るときの、残す側の幅と辺。fill は割らないので nil
  private func halfToKeep(of visible: CGRect) -> (CGFloat, CGRectEdge)? {
    switch self {
    case .left: (visible.width / 2, .minXEdge)
    case .right: (visible.width / 2, .maxXEdge)
    case .bottom: (visible.height / 2, .minYEdge)
    case .top: (visible.height / 2, .maxYEdge)
    case .fill: nil
    }
  }
}
