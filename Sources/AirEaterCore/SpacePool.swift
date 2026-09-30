import CoreGraphics

/// 固定した物理 Desktop のプールと、各 Desktop に属するウィンドウ。
/// workspace の番号付けは Workspaces が持ち、ここは窓の所属だけを追う。
public struct SpacePool: Sendable {
  public let desktops: [Int]
  private var occupied: [Int: Set<CGWindowID>] = [:]

  public init(desktops: some Sequence<Int>) {
    self.desktops = Array(desktops)
  }

  /// ウィンドウがある物理 Desktop。
  public var active: [Int] {
    desktops.filter { !(occupied[$0]?.isEmpty ?? true) }
  }

  /// desktop を表示して、窓が無いと確かめたか。まだ見ていない Desktop は false。
  public func isObservedEmpty(_ desktop: Int) -> Bool {
    occupied[desktop]?.isEmpty ?? false
  }

  public enum Direction: Sendable {
    case previous, next
  }

  /// desktop を表示中に見えたウィンドウで、その Desktop の所属を置き換える。
  /// ユーザーが Mission Control で動かしたウィンドウは、移動先で見えた時点で元の所属から外れる。
  public mutating func observe(desktop: Int, windows: Set<CGWindowID>) {
    for other in occupied.keys where other != desktop {
      occupied[other]?.subtract(windows)
    }
    occupied[desktop] = windows
  }

  /// desktop で見えたと報告された窓に、既に別の Desktop の窓だと分かっている窓が混ざっているか。
  /// 実機で一度、全 Space の窓が一斉に「画面に写っている」と報告される瞬間があり、それを数えると
  /// 他の Desktop の窓が全部ここへ移ったように見えた。混ざっていれば、その観測は捨てる。
  /// Mission Control で窓を 1 枚動かした直後も別の Desktop の窓が見えるので、2 枚以上で、かつ
  /// 観測の半分以上を占めるときだけ疑う
  public func isSuspect(desktop: Int, windows: Set<CGWindowID>) -> Bool {
    let foreign = occupied.filter { $0.key != desktop }.values
      .reduce(into: Set<CGWindowID>()) { $0.formUnion($1) }
      .intersection(windows).count
    return foreign >= 2 && foreign * 2 >= windows.count
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
