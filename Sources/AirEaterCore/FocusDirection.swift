import CoreGraphics

/// フォーカスを移す向き (Hyprland の movefocus)。Option+Shift+H/J/K/L で vim と同じ向き
public enum FocusDirection: Sendable, CaseIterable {
  case left, down, up, right

  /// focused から見てこの向きにある窓のうち、中心が一番近いものの添字。無ければ nil。
  /// frame は AX 座標 (左上原点) で、上は y が小さい側。Hyprland と同じく端で折り返さない
  public func neighbor(of focused: CGRect, among others: [CGRect]) -> Int? {
    let origin = CGPoint(x: focused.midX, y: focused.midY)
    return others.indices
      .filter { isAhead(CGPoint(x: others[$0].midX, y: others[$0].midY), from: origin) }
      .min { distance(others[$0], from: origin) < distance(others[$1], from: origin) }
  }

  private func isAhead(_ point: CGPoint, from origin: CGPoint) -> Bool {
    switch self {
    case .left: point.x < origin.x
    case .right: point.x > origin.x
    case .up: point.y < origin.y
    case .down: point.y > origin.y
    }
  }

  private func distance(_ frame: CGRect, from origin: CGPoint) -> CGFloat {
    hypot(frame.midX - origin.x, frame.midY - origin.y)
  }
}
