import AirEaterCore
import AppKit

/// 各 Desktop に 1 つずつ置く、見えない 1×1 のウィンドウ。
/// NSWindow は作られた Space に固定されるので、画面に写っているマーカーで現在地が分かる。
@MainActor
final class Markers {
  private var windows: [Int: NSWindow] = [:]

  var ids: [Int: CGWindowID] {
    windows.mapValues { CGWindowID($0.windowNumber) }
  }

  /// Desktop 1 から順に巡ってマーカーを置き、各 Desktop にあったウィンドウも拾う。
  /// 切り替わらなかった番号をプールの終わりとみなす。
  func install(upTo limit: Int) async -> [Int: Set<CGWindowID>] {
    var seen: [Int: Set<CGWindowID>] = [:]
    for desktop in 1...limit {
      let switched = await switchDesktop(to: desktop)
      // 起動時に Desktop 1 にいれば切り替えは起きない。Desktop 1 は必ずある
      if !switched && desktop > 1 { break }
      // AIDEV-NOTE: 切り替えアニメーションの途中で作ると、マーカーが移動元の Space に
      // 残ることがある。通知の直後ではなく少し待ってから作る
      try? await Task.sleep(for: .milliseconds(300))
      windows[desktop] = Self.makeMarker()
      seen[desktop] = managedWindows(
        in: windowList(.optionOnScreenOnly), excludingProcess: getpid())
    }
    return seen
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
