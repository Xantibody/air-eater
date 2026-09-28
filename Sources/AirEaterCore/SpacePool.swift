import CoreGraphics

/// 固定した物理 Desktop のプールと、各 Desktop に属するウィンドウ。
/// Hyprland 式の論理番号は保存せず、ここから毎回導出する。
public struct SpacePool: Sendable {
  public let desktops: [Int]
  private var occupied: [Int: Set<CGWindowID>] = [:]

  public init(desktops: some Sequence<Int>) {
    self.desktops = Array(desktops)
  }

  /// ウィンドウがある物理 Desktop。論理番号 N は active[N-1]。
  public var active: [Int] {
    desktops.filter { !(occupied[$0]?.isEmpty ?? true) }
  }

  /// 新しい workspace として使う、番号がいちばん小さい空き Desktop。
  public var firstEmpty: Int? {
    desktops.first { occupied[$0]?.isEmpty ?? true }
  }

  /// 論理番号 workspace (1 始まり) に当たる物理 Desktop。
  /// 今ある workspace の数を超えた番号は、新しい workspace として空き Desktop を返す。
  public func desktop(forWorkspace workspace: Int) -> Int? {
    let active = active
    guard workspace >= 1 else { return nil }
    return workspace <= active.count ? active[workspace - 1] : firstEmpty
  }

  public enum Direction: Sendable {
    case previous, next
  }

  /// current から見て隣の workspace がある物理 Desktop。空き Desktop は飛ばす。
  public func desktop(nextTo current: Int, direction: Direction) -> Int? {
    switch direction {
    case .next: active.first { $0 > current }
    case .previous: active.last { $0 < current }
    }
  }

  /// desktop を表示中に見えたウィンドウで、その Desktop の所属を置き換える。
  /// ユーザーが Mission Control で動かしたウィンドウは、移動先で見えた時点で元の所属から外れる。
  public mutating func observe(desktop: Int, windows: Set<CGWindowID>) {
    for other in occupied.keys where other != desktop {
      occupied[other]?.subtract(windows)
    }
    occupied[desktop] = windows
  }

  /// existing に無いウィンドウ (表示していない Desktop で閉じられたもの) を落とす。
  public mutating func retain(existing: Set<CGWindowID>) {
    for desktop in occupied.keys {
      occupied[desktop]?.formIntersection(existing)
    }
  }
}

extension SpacePool: CustomStringConvertible {
  /// ログ用。観測済みの Desktop だけを "1:{10,11} 2:{}" の形で並べる。
  public var description: String {
    desktops.compactMap { desktop in
      occupied[desktop].map { windows in
        "\(desktop):{\(windows.sorted().map(String.init).joined(separator: ","))}"
      }
    }.joined(separator: " ")
  }
}
