import CoreGraphics
import Testing

@testable import AirEaterCore

/// 窓を別の Desktop へ移すには、タイトルバーを掴んだまま Ctrl+N を送る。掴む場所の計算
@Suite struct DragMoveTests {
  // 窓の frame は AX 座標 (左上原点)。タイトルバーは上端にある
  @Test func grabsTheMiddleOfTheTitleBar() {
    let frame = CGRect(x: 100, y: 200, width: 600, height: 400)
    #expect(dragGrabPoint(in: frame) == CGPoint(x: 400, y: 212))
  }
}
