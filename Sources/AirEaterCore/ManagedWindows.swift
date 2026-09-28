import CoreGraphics

/// CGWindowListCopyWindowInfo の結果から、workspace の占有に数えるウィンドウを選ぶ。
/// 通常レイヤーにある、自分以外のプロセスの、見えるウィンドウだけを数える。
public func managedWindows(
  in windowList: [[String: Any]], excludingProcess ownPID: pid_t
) -> Set<CGWindowID> {
  Set(
    windowList.compactMap { info -> CGWindowID? in
      guard
        let id = info[kCGWindowNumber as String] as? CGWindowID,
        let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
        info[kCGWindowLayer as String] as? Int == 0,
        (info[kCGWindowAlpha as String] as? Double ?? 0) > 0
      else { return nil }
      return id
    })
}
