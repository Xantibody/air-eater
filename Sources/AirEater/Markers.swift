import AirEaterCore
import AppKit

/// 各 Desktop に 1 つずつ置く、見えない 1×1 のウィンドウ。
/// NSWindow は作られた Space に固定されるので、画面に写っているマーカーで現在地が分かる。
/// 起動時に全 Desktop を巡回せず、air-eater が Desktop に着いたときに置いていく。
@MainActor
final class Markers {
  private var windows: [Int: NSWindow] = [:]
  private var placing: [Int: Task<Void, Never>] = [:]

  var ids: [Int: CGWindowID] {
    windows.mapValues { CGWindowID($0.windowNumber) }
  }

  /// 今表示している Space を desktop とみなし、まだマーカーが無ければ置く。
  /// Ctrl+desktop で着いた直後など、現在地が desktop だと分かっているときだけ呼ぶ。
  /// 戻った時点で、マーカーは画面に写っているウィンドウの一覧に載っている。
  func placeIfMissing(on desktop: Int) async {
    guard windows[desktop] == nil else { return }
    // air-eater が送った Ctrl+N はキー監視にも見えるので、同じ Desktop に対して
    // 2 経路から呼ばれることがある。2 回目は新しく置かず、1 回目が置き終わるのを待つ
    if let inFlight = placing[desktop] {
      await inFlight.value
      return
    }
    let task = Task { await place(on: desktop) }
    placing[desktop] = task
    await task.value
    placing[desktop] = nil
  }

  private func place(on desktop: Int) async {
    // AIDEV-NOTE: 切り替えアニメーションの途中で作ると、マーカーが移動元の Space に
    // 残ることがある。通知の直後ではなく少し待ってから作る
    try? await Task.sleep(for: .milliseconds(300))
    let marker = Self.makeMarker()
    windows[desktop] = marker
    let visibleAfter = await Self.waitUntilOnScreen(CGWindowID(marker.windowNumber))
    log("Desktop \(desktop) にマーカーを置いた (window \(marker.windowNumber)、一覧に載るまで \(visibleAfter))")
  }

  /// 作った直後のウィンドウは、CGWindowList の一覧にすぐには載らない。
  /// 載る前に現在地を読むと「マーカーの無い Space」に見えるので、載るまで待つ。
  private static func waitUntilOnScreen(_ id: CGWindowID) async -> String {
    let clock = ContinuousClock()
    let start = clock.now
    while clock.now - start < .seconds(1) {
      let onScreen = windowList(.optionOnScreenOnly).compactMap {
        $0[kCGWindowNumber as String] as? CGWindowID
      }
      if onScreen.contains(id) {
        return (clock.now - start).formatted(.units(allowed: [.milliseconds]))
      }
      try? await Task.sleep(for: .milliseconds(20))
    }
    return "1 秒以上 (載らなかった)"
  }

  private static func makeMarker() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.ignoresMouseEvents = true
    // Cmd+` のウィンドウ巡回に出さない。全 Space への表示 (canJoinAllSpaces) は付けてはいけない
    window.collectionBehavior = [.ignoresCycle, .fullScreenNone]
    // 通常レベルで最前面に置くと、その Desktop に着くたびに macOS が air-eater を前面にして
    // 他のアプリからキーボードのフォーカスを奪う。デスクトップのすぐ上に沈めておく
    window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
    window.orderFrontRegardless()
    return window
  }
}
