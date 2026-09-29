import Testing

@testable import AirEaterCore

@Suite struct DesktopCountTests {
  @Test func missingConfigurationHasNoCount() {
    #expect(desktopCount(inSpacesConfiguration: [:]) == nil)
  }
}

extension DesktopCountTests {
  static func configuration(monitors: [[String: Any]]) -> [String: Any] {
    ["SpacesDisplayConfiguration": ["Management Data": ["Monitors": monitors]]]
  }

  static var desktop: [String: Any] { ["type": 0] }
  static var fullScreen: [String: Any] { ["type": 4, "TileLayoutManager": [:] as [String: Any]] }

  @Test func singleDesktopOnMainDisplay() {
    let configuration = Self.configuration(monitors: [
      ["Display Identifier": "Main", "Spaces": [Self.desktop]]
    ])
    #expect(desktopCount(inSpacesConfiguration: configuration) == 1)
  }
}

extension DesktopCountTests {
  // 実機 (2026-09-29) の並び: Desktop | ChatGPT | Desktop | Magical Merchant | Desktop | Slack。
  // Spaces を持たない表示装置の項目も混ざっていた
  @Test func onlyOrdinaryDesktopsOnMainDisplayAreCounted() {
    let configuration = Self.configuration(monitors: [
      ["Display Identifier": "4F2A-EXTERNAL"],
      [
        "Display Identifier": "Main",
        "Spaces": [
          Self.desktop, Self.fullScreen, Self.desktop, Self.fullScreen, Self.desktop,
          Self.fullScreen,
        ],
      ],
    ])
    #expect(desktopCount(inSpacesConfiguration: configuration) == 3)
  }
}
