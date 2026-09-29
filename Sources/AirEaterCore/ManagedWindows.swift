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
