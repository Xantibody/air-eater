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
        "窓が \(tile) 半分にならなかった: \(tileWindow.frame) (期待 \(expected))")
    }
  }
}
