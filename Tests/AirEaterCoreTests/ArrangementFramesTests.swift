import CoreGraphics
import Testing

@testable import AirEaterCore

/// 純正の配置が無いアプリのために、同じ 4 つの配置を自前の frame で再現する。
/// 並びは手前の窓から順で、Cocoa 座標 (左下原点)
@Suite struct ArrangementFramesTests {
  static let visible = CGRect(x: 100, y: 50, width: 1000, height: 800)

  @Test func fillIsTheWholeVisibleFrame() {
    #expect(Arrangement.fill.frames(in: Self.visible) == [Self.visible])
  }

  @Test func leftAndRightPutsTheFrontWindowOnTheLeft() {
    #expect(
      Arrangement.leftAndRight.frames(in: Self.visible) == [
        CGRect(x: 100, y: 50, width: 500, height: 800),
        CGRect(x: 600, y: 50, width: 500, height: 800),
      ])
  }

  @Test func leftAndQuartersSplitsTheRightHalfTopAndBottom() {
    #expect(
      Arrangement.leftAndQuarters.frames(in: Self.visible) == [
        CGRect(x: 100, y: 50, width: 500, height: 800),
        CGRect(x: 600, y: 450, width: 500, height: 400),
        CGRect(x: 600, y: 50, width: 500, height: 400),
      ])
  }

  @Test func quartersGoTopLeftTopRightBottomLeftBottomRight() {
    #expect(
      Arrangement.quarters.frames(in: Self.visible) == [
        CGRect(x: 100, y: 450, width: 500, height: 400),
        CGRect(x: 600, y: 450, width: 500, height: 400),
        CGRect(x: 100, y: 50, width: 500, height: 400),
        CGRect(x: 600, y: 50, width: 500, height: 400),
      ])
  }
}
