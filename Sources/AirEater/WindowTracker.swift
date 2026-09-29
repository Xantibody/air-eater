import AirEaterCore
import AppKit

/// CGWindowListCopyWindowInfo の結果を辞書の配列で返す。
func windowList(_ option: CGWindowListOption) -> [[String: Any]] {
  CGWindowListCopyWindowInfo(option, kCGNullWindowID) as? [[String: Any]] ?? []
}

/// 今いる Desktop とそこに写っているウィンドウを観測して、Workspaces を最新に保つ。
@MainActor
final class WindowTracker {
  private(set) var workspaces: Workspaces
  private let markers: Markers

  init(workspaces: Workspaces, markers: Markers) {
    self.workspaces = workspaces
    self.markers = markers
  }

  var current: Int? { workspaces.current }

  /// マーカーの無い Space (未訪問の Desktop、フルスクリーン) にいる間は current が nil になり、
  /// そこに写っている窓はどの Desktop にも数えない。
  func refresh() {
    let onScreen = windowList(.optionOnScreenOnly)
    let onScreenIDs = Set(onScreen.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
    let before = state
    let desktop = currentDesktop(markers: markers.ids, onScreen: onScreenIDs)
    let visible = managedWindows(in: onScreen, excludingProcess: getpid())
    let settling = isSettling
    if let desktop, !settling {
      workspaces.observe(desktop: desktop, windows: visible)
    }
    workspaces.retain(
      existing: managedWindows(in: windowList(.optionAll), excludingProcess: getpid()))
    workspaces.enter(desktop)

    let place = desktop.map { "Desktop \($0)" } ?? "不明 (マーカーの無い Space)"
    summary =
      "現在地 \(place)\(settling ? " (移動中なので窓は数えない)" : "")"
      + " / workspace \(workspaces) / 窓 \(workspaces.pool)"
      + " / 見えている窓 \(names(of: visible, in: onScreen))"
    // 1 秒ごとに呼ばれるので、変わったときだけ出す
    guard before != state else { return }
    log(summary)
  }

  /// 最後に refresh したときの現在地・workspace・見えている窓。
  private(set) var summary = ""

  private var state: String {
    "\(current.map(String.init) ?? "-") \(workspaces) \(workspaces.pool)"
  }

  /// desktop を workspace id として確保する。
  func assign(_ id: Int, to desktop: Int) {
    workspaces.assign(id, to: desktop)
  }

  /// 確保した Desktop に元から窓があったので、id をそこから外す。
  func evict(_ id: Int) {
    workspaces.evict(id)
  }

  // MARK: - 移動中の扱い

  /// 切り替えのアニメーション中は、移動元と移動先 (と、途中で割り込んだ Space) の窓が
  /// 同時に画面に写る。そのまま数えると、よその窓をこの Desktop の窓として数えてしまう。
  /// 実機では、Ctrl+N を送ってから約 0.3 秒で通知が来て、その後 0.4 秒ほど別の Space の窓が写った
  private let settleDuration: Duration = .milliseconds(600)
  private var lastTransition: ContinuousClock.Instant?

  private var isSettling: Bool {
    lastTransition.map { ContinuousClock.now - $0 < settleDuration } ?? false
  }

  /// Space の移動が始まった (Ctrl+N を送った、通知を受けた) ことを記録する。
  func noteTransition() {
    lastTransition = .now
  }

  /// 移動が落ち着くまで待ってから観測する。着いた Desktop に窓があるかを見るときに使う。
  func refreshAfterSettling() async {
    if let lastTransition {
      let remaining = settleDuration - (ContinuousClock.now - lastTransition)
      if remaining > .zero { try? await Task.sleep(for: remaining) }
    }
    refresh()
  }

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
