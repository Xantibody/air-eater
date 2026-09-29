import AirEaterCore
import AppKit

/// CGWindowListCopyWindowInfo の結果を辞書の配列で返す。
func windowList(_ option: CGWindowListOption) -> [[String: Any]] {
  CGWindowListCopyWindowInfo(option, kCGNullWindowID) as? [[String: Any]] ?? []
}

/// 今いる Desktop とそこに写っているウィンドウを観測して、SpacePool を最新に保つ。
@MainActor
final class WindowTracker {
  private(set) var pool: SpacePool
  private(set) var current: Int?
  private let markers: Markers

  init(pool: SpacePool, markers: Markers) {
    self.pool = pool
    self.markers = markers
  }

  /// マーカーの無い Space (未訪問の Desktop、フルスクリーン) にいる間は current が nil になり、
  /// そこに写っている窓はどの Desktop にも数えない。
  func refresh() {
    let onScreen = windowList(.optionOnScreenOnly)
    let onScreenIDs = Set(onScreen.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
    let before = (current, pool.description)
    current = currentDesktop(markers: markers.ids, onScreen: onScreenIDs)
    let visible = managedWindows(in: onScreen, excludingProcess: getpid())
    if let current {
      pool.observe(desktop: current, windows: visible)
    }
    pool.retain(existing: managedWindows(in: windowList(.optionAll), excludingProcess: getpid()))

    let place = current.map { "Desktop \($0)" } ?? "不明 (マーカーの無い Space)"
    summary = "現在地 \(place) / プール \(pool.description) / 見えている窓 \(names(of: visible, in: onScreen))"
    // 1 秒ごとに呼ばれるので、変わったときだけ出す
    guard before != (current, pool.description) else { return }
    log(summary)
  }

  /// 最後に refresh したときの現在地・プール・見えている窓。
  private(set) var summary = ""

  private func names(of windows: Set<CGWindowID>, in windowList: [[String: Any]]) -> String {
    let entries = windowList.compactMap { info -> String? in
      guard let id = info[kCGWindowNumber as String] as? CGWindowID, windows.contains(id) else {
        return nil
      }
      return "\(id) \(info[kCGWindowOwnerName as String] as? String ?? "?")"
    }
    return entries.isEmpty ? "なし" : entries.joined(separator: ", ")
  }
}
