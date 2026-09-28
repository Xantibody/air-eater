import CoreGraphics
import Testing

@testable import AirEaterCore

@Suite struct CoordinateTests {
  @Test func bottomLeftCornerMovesToTopOfFlippedSpace() {
    let cocoa = CGRect(x: 0, y: 0, width: 100, height: 100)
    #expect(
      accessibilityFrame(fromCocoa: cocoa, primaryScreenHeight: 1000)
        == CGRect(x: 0, y: 900, width: 100, height: 100))
  }
}

extension CoordinateTests {
  @Test(arguments: [
    // 主ディスプレイの上端に接する窓
    (CGRect(x: 0, y: 900, width: 100, height: 100), CGRect(x: 0, y: 0, width: 100, height: 100)),
    // 主ディスプレイの上に置いた 2 枚目のディスプレイ。AX では y が負になる
    (
      CGRect(x: 200, y: 1200, width: 300, height: 300),
      CGRect(x: 200, y: -500, width: 300, height: 300)
    ),
  ])
  func flipIsMeasuredFromPrimaryScreen(cocoa: CGRect, expected: CGRect) {
    #expect(accessibilityFrame(fromCocoa: cocoa, primaryScreenHeight: 1000) == expected)
  }
}
