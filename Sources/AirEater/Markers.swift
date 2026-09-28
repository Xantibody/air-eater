import AirEaterCore
import AppKit

/// 各 Desktop に 1 つずつ置く、見えない 1×1 のウィンドウ。
/// NSWindow は作られた Space に固定されるので、画面に写っているマーカーで現在地が分かる。
/// 起動時に全 Desktop を巡回せず、air-eater が Desktop に着いたときに置いていく。
@MainActor
final class Markers {
  private var windows: [Int: NSWindow] = [:]

  var ids: [Int: CGWindowID] {
    windows.mapValues { CGWindowID($0.windowNumber) }
  }

  /// 今表示している Space を desktop とみなし、まだマーカーが無ければ置く。
  /// Ctrl+desktop で着いた直後など、現在地が desktop だと分かっているときだけ呼ぶ。
  func placeIfMissing(on desktop: Int) async {
    guard windows[desktop] == nil else { return }
    // AIDEV-NOTE: 切り替えアニメーションの途中で作ると、マーカーが移動元の Space に
    // 残ることがある。通知の直後ではなく少し待ってから作る
    try? await Task.sleep(for: .milliseconds(300))
    let marker = Self.makeMarker()
    windows[desktop] = marker
    log("Desktop \(desktop) にマーカーを置いた (window \(marker.windowNumber))")
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
    window.orderFrontRegardless()
    return window
  }
}
