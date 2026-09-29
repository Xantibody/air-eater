import CoreGraphics

/// Hyprland 式の workspace。番号は固定の ID で、詰めたり振り直したりしない。
/// 各 workspace は物理 Desktop に 1 対 1 で割り当て、空になって離れたら割り当てを外す。
public struct Workspaces: Sendable {
  public private(set) var pool: SpacePool
  /// workspace ID → 物理 Desktop
  private var assigned: [Int: Int] = [:]
  /// 確保したが、まだ着いていない Desktop。向かう途中で「離れた空の workspace」として外さない
  private var reserved: Set<Int> = []

  public init(desktops: some Sequence<Int>) {
    pool = SpacePool(desktops: desktops)
  }

  /// workspace id を表示するために行く Desktop。
  /// まだ無い workspace には、どの workspace にも割り当てておらず窓も見ていない Desktop を選ぶ。
  /// まだ訪れていない Desktop も候補に入るので、着いて窓があれば observe の後にもう一度引く
  public func candidate(for id: Int) -> Int? {
    if let desktop = assigned[id] { return desktop }
    let taken = Set(assigned.values)
    return pool.desktops.first { desktop in
      desktop <= (existingDesktops ?? .max) && !taken.contains(desktop)
        && !pool.active.contains(desktop)
    }
  }

  /// 実在する Desktop の数。分からなければ nil で、プールの全部を候補にする
  private var existingDesktops: Int?

  /// 実在する Desktop が count 個だと分かった。それより大きい番号は候補にしない
  public mutating func limitToExistingDesktops(_ count: Int?) {
    existingDesktops = count
  }

  /// desktop を workspace id にする。着くまでは外さない。
  public mutating func assign(_ id: Int, to desktop: Int) {
    assigned[id] = desktop
    reserved.insert(desktop)
  }

  /// id のために確保した Desktop に元から窓があったとき、id をそこから外す。
  /// その Desktop には自分の ID を付け直し、id は candidate で次の Desktop を引き直す
  public mutating func evict(_ id: Int) {
    guard let desktop = assigned.removeValue(forKey: id) else { return }
    reserved.remove(desktop)
    if pool.active.contains(desktop) { adopt(desktop) }
  }

  /// desktop を表示中に見えたウィンドウで、その Desktop の中身を置き換える。
  public mutating func observe(desktop: Int, windows: Set<CGWindowID>) {
    pool.observe(desktop: desktop, windows: windows)
    if !windows.isEmpty { adopt(desktop) }
  }

  /// 表示していない Desktop で閉じられた窓を落とす。
  public mutating func retain(existing: Set<CGWindowID>) {
    pool.retain(existing: existing)
  }

  /// 今表示している Desktop。マーカーの無い Space (全画面アプリなど) にいる間は nil
  public private(set) var current: Int?

  /// desktop (nil ならプール外の Space) を表示し始めた。
  /// 表示中の Desktop は空でも workspace にし、離れた空の workspace は割り当てを外す。
  /// 外すのは空だと見て確かめた Desktop だけで、まだ中身を見ていない Desktop と
  /// 向かっている途中の Desktop は残す
  public mutating func enter(_ desktop: Int?) {
    current = desktop
    if let desktop {
      reserved.remove(desktop)
      adopt(desktop)
    }
    for (id, other) in assigned
    where other != desktop && !reserved.contains(other) && pool.isObservedEmpty(other) {
      assigned[id] = nil
    }
  }

  /// desktop に割り当てている workspace ID。
  public func workspace(on desktop: Int) -> Int? {
    assigned.first { $0.value == desktop }?.key
  }

  /// まだ使われていない一番小さい workspace ID。
  public var lowestFreeID: Int {
    (1...).first { assigned[$0] == nil }!
  }

  /// まだ workspace でない desktop に ID を付ける。
  /// Desktop 番号と同じ ID が空いていればそれを使い、指が覚えている番号とずれないようにする
  private mutating func adopt(_ desktop: Int) {
    guard workspace(on: desktop) == nil else { return }
    assigned[assigned[desktop] == nil ? desktop : lowestFreeID] = desktop
  }

  /// 今の workspace から ID 順で隣にある workspace の Desktop。
  public func desktop(nextTo direction: SpacePool.Direction) -> Int? {
    guard let current, let id = workspace(on: current) else { return nil }
    let ids = assigned.keys.sorted()
    guard let index = ids.firstIndex(of: id) else { return nil }
    let step = direction == .next ? 1 : ids.count - 1
    return assigned[ids[(index + step) % ids.count]]
  }
}

extension Workspaces: CustomStringConvertible {
  /// ログ用。"1→D1 5→D2" の形で ID 順に並べる。
  public var description: String {
    assigned.sorted { $0.key < $1.key }.map { "\($0.key)→D\($0.value)" }.joined(separator: " ")
  }
}
