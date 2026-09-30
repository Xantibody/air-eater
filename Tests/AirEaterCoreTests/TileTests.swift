import CoreGraphics
import Testing

@testable import AirEaterCore

@Suite struct TileTests {
  @Test func leftHalfOfVisibleFrame() {
    let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
    #expect(Tile.left.frame(in: visible) == CGRect(x: 0, y: 0, width: 500, height: 800))
  }
}

extension TileTests {
  // 原点が 0 でない可視領域 (Dock やメニューバーを除いた領域、2 枚目のディスプレイ)
  static let visible = CGRect(x: 100, y: 50, width: 1000, height: 800)

  @Test(arguments: [
    (Tile.left, CGRect(x: 100, y: 50, width: 500, height: 800)),
    (.right, CGRect(x: 600, y: 50, width: 500, height: 800)),
    (.bottom, CGRect(x: 100, y: 50, width: 1000, height: 400)),
    (.top, CGRect(x: 100, y: 450, width: 1000, height: 400)),
  ])
  func tileIsHalfOfVisibleFrameOnItsSide(tile: Tile, expected: CGRect) {
    #expect(tile.frame(in: Self.visible) == expected)
  }
}

extension TileTests {
  // 全画面の代わり。ネイティブの全画面は別の Space を作ってしまうので、可視領域いっぱいに広げるだけにする
  @Test func fillIsTheWholeVisibleFrame() {
    #expect(Tile.fill.frame(in: Self.visible) == Self.visible)
  }
}
