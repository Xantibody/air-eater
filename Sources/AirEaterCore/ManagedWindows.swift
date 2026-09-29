import CoreGraphics

/// CGWindowListCopyWindowInfo の結果から、workspace の占有に数えるウィンドウを選ぶ。
/// 通常レイヤーにある、自分以外のプロセスの、見えるウィンドウだけを数える。
public func managedWindows(
  in windowList: [[String: Any]], excludingProcess ownPID: pid_t
) -> Set<CGWindowID> {
  Set(
    windowList.compactMap { info in
      isManaged(info, excludingProcess: ownPID)
        ? info[kCGWindowNumber as String] as? CGWindowID : nil
    })
}

/// 一番手前にある通常の窓の持ち主。
public struct WindowOwner: Equatable, Sendable {
  public let pid: pid_t
  public let name: String

  public init(pid: pid_t, name: String) {
    self.pid = pid
    self.name = name
  }
}

/// 画面に写っている窓の一覧 (手前から順) から、一番手前の通常の窓の持ち主を選ぶ。
/// NSWorkspace.frontmostApplication は、起動用のラッパーを挟むアプリ (Nix の kitty) で pid が -1 に
/// なる。窓の持ち主の pid はそういうアプリでも正しいので、AX で操作する相手はこちらで決める
public func frontmostWindowOwner(
  in windowList: [[String: Any]], excludingProcess ownPID: pid_t
) -> WindowOwner? {
  windowList.lazy
    .filter { isManaged($0, excludingProcess: ownPID) }
    .compactMap { info -> WindowOwner? in
      guard let pid = info[kCGWindowOwnerPID as String] as? pid_t else { return nil }
      return WindowOwner(pid: pid, name: info[kCGWindowOwnerName as String] as? String ?? "?")
    }
    .first
}

/// 通常レイヤーに窓を出すが、ユーザーの窓ではない macOS のプロセス。
/// WindowManager はタイル表示などの間、一番手前に窓を出す
private let systemOverlayOwners: Set<String> = ["WindowManager"]

private func isManaged(_ info: [String: Any], excludingProcess ownPID: pid_t) -> Bool {
  guard info[kCGWindowNumber as String] is CGWindowID,
    let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
    !systemOverlayOwners.contains(info[kCGWindowOwnerName as String] as? String ?? "")
  else { return false }
  return info[kCGWindowLayer as String] as? Int == 0
    && (info[kCGWindowAlpha as String] as? Double ?? 0) > 0
}

/// 画面に写っている通常の窓 1 つ分。bounds は CGWindowList の座標 (左上原点、AX と同じ)
public struct WindowEntry: Equatable, Sendable {
  public let id: CGWindowID
  public let pid: pid_t
  public let bounds: CGRect
}

/// 画面に写っている窓の一覧 (手前から順) から、占有に数える窓を順番を保って選ぶ。
/// 自前の frame で並べるときに、手前の窓から順に置き場所を割り当てるのに使う
public func managedWindowEntries(
  in windowList: [[String: Any]], excludingProcess ownPID: pid_t
) -> [WindowEntry] {
  windowList.compactMap { info in
    guard isManaged(info, excludingProcess: ownPID),
      let id = info[kCGWindowNumber as String] as? CGWindowID,
      let pid = info[kCGWindowOwnerPID as String] as? pid_t,
      let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
      let left = bounds["X"], let top = bounds["Y"], let width = bounds["Width"],
      let height = bounds["Height"]
    else { return nil }
    return WindowEntry(
      id: id, pid: pid, bounds: CGRect(x: left, y: top, width: width, height: height))
  }
}
