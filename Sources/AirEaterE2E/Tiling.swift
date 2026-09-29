import AirEaterCore
import AppKit
import Foundation

// タイルのシナリオで動かされる側の窓と、その確認

/// 動かされる側の窓。ユーザーの窓には触らないよう、E2E 自身が開く
@MainActor let tileWindow: NSWindow = {
  NSApplication.shared.setActivationPolicy(.regular)
  // これを呼ばないと AppKit のアクセシビリティが立ち上がらず、air-eater からの AX の問い合わせに
  // 答えられない (kAXErrorCannotComplete になる)
  NSApplication.shared.finishLaunching()
  let window = NSWindow(
    contentRect: NSRect(x: 200, y: 200, width: 400, height: 300),
    styleMask: [.titled, .resizable], backing: .buffered, defer: false)
  window.title = "air-eater E2E"
  window.isReleasedWhenClosed = false
  return window
}()

/// E2E の窓を開いて前面に出す。air-eater はフォーカス中の窓を動かすので、これが前提になる
func showTileWindow() throws {
  let start = logLines.count
  // シナリオはメインスレッドで順に回している
  MainActor.assumeIsolated {
    tileWindow.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
  try expect(waitFor("前面のアプリ → AirEaterE2E", from: start), "E2E の窓が前面にならなかった")
}

/// tile を送ると、E2E の窓がその画面の可視領域の半分に収まること。
func tiles(_ tile: Tile) -> () throws -> Void {
  {
    try MainActor.assumeIsolated {
      guard let screen = tileWindow.screen ?? NSScreen.main else {
        throw Failure(description: "画面が取れない")
      }
      let expected = tile.frame(in: screen.visibleFrame)
      send("tile \(tile)")
      let deadline = Date(timeIntervalSinceNow: 2)
      while Date() < deadline, !nearlyEqual(tileWindow.frame, expected) { pump(0.05) }
      try expect(
        nearlyEqual(tileWindow.frame, expected),
        "窓が \(tile) の大きさにならなかった: \(tileWindow.frame) (期待 \(expected))")
    }
  }
}

/// ネイティブの全画面にした E2E の窓に tile fill を送ると、全画面が解けて可視領域いっぱいになること。
/// 全画面は別の Space に移るので、戻って落ち着くまで含めて待つ
func fillsFromFullscreen() throws {
  try MainActor.assumeIsolated {
    tileWindow.collectionBehavior = .fullScreenPrimary
    tileWindow.toggleFullScreen(nil)
    var deadline = Date(timeIntervalSinceNow: 4)
    while Date() < deadline, !tileWindow.styleMask.contains(.fullScreen) { pump(0.05) }
    try expect(tileWindow.styleMask.contains(.fullScreen), "E2E の窓が全画面にならなかった")
    // styleMask は遷移の始まりで変わる。遷移中に AXFullScreen を書いても無視されるので、
    // 窓が画面全体に広がって落ち着くまで待つ
    while Date() < deadline, tileWindow.frame != tileWindow.screen?.frame { pump(0.05) }
    pump(1.5)

    send("tile fill")
    deadline = Date(timeIntervalSinceNow: 6)
    while Date() < deadline, tileWindow.styleMask.contains(.fullScreen) { pump(0.05) }
    try expect(!tileWindow.styleMask.contains(.fullScreen), "全画面が解けなかった")
    guard let screen = tileWindow.screen ?? NSScreen.main else {
      throw Failure(description: "画面が取れない")
    }
    let expected = screen.visibleFrame
    while Date() < deadline, !nearlyEqual(tileWindow.frame, expected) { pump(0.05) }
    try expect(
      nearlyEqual(tileWindow.frame, expected),
      "全画面を解いた窓が可視領域いっぱいにならなかった: \(tileWindow.frame) (期待 \(expected))")
  }
}
