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
  private let markers: [Int: CGWindowID]

  init(pool: SpacePool, markers: [Int: CGWindowID]) {
    self.pool = pool
    self.markers = markers
  }

  func refresh() {
    let onScreen = windowList(.optionOnScreenOnly)
    let onScreenIDs = Set(onScreen.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
    current = currentDesktop(markers: markers, onScreen: onScreenIDs)
    if let current {
      pool.observe(
        desktop: current, windows: managedWindows(in: onScreen, excludingProcess: getpid()))
    }
    pool.retain(existing: managedWindows(in: windowList(.optionAll), excludingProcess: getpid()))
  }
}
