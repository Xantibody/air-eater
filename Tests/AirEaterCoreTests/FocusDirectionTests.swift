import CoreGraphics
import Testing

@testable import AirEaterCore

/// 方向でフォーカスを移す (Hyprland の movefocus)。frame は AX 座標 (左上原点、上は y が小さい)
@Suite struct FocusDirectionTests {
  // 左と右に並んだ 2 枚。手前 (フォーカス中) が左
  static let left = CGRect(x: 0, y: 0, width: 500, height: 800)
  static let right = CGRect(x: 500, y: 0, width: 500, height: 800)

  @Test func rightPicksTheWindowWhoseCenterIsToTheRight() {
    #expect(FocusDirection.right.neighbor(of: Self.left, among: [Self.right]) == 0)
  }

  @Test func noWindowInThatDirectionPicksNothing() {
    #expect(FocusDirection.left.neighbor(of: Self.left, among: [Self.right]) == nil)
  }

  // 左と 4 分割: 左の窓から右へ行くと、右上と右下のうち中心が近い右上
  @Test func nearestCenterWinsAmongSeveral() {
    let topRight = CGRect(x: 500, y: 0, width: 500, height: 400)
    let bottomRight = CGRect(x: 500, y: 400, width: 500, height: 400)
    let focused = CGRect(x: 0, y: 0, width: 500, height: 400)  // 左上の 4 分割
    #expect(FocusDirection.right.neighbor(of: focused, among: [bottomRight, topRight]) == 1)
    #expect(FocusDirection.down.neighbor(of: topRight, among: [focused, bottomRight]) == 1)
    #expect(FocusDirection.up.neighbor(of: bottomRight, among: [focused, topRight]) == 1)
  }
}
