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
    current = currentDesktop(markers: markers.ids, onScreen: onScreenIDs)
    if let current {
      pool.observe(
        desktop: current, windows: managedWindows(in: onScreen, excludingProcess: getpid()))
    }
    pool.retain(existing: managedWindows(in: windowList(.optionAll), excludingProcess: getpid()))
  }
}
