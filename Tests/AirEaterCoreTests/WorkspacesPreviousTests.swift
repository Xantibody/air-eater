import Testing

@testable import AirEaterCore

/// 直前にいた workspace (Hyprland の workspace previous)。ID で覚えるので、空になって消えた
/// workspace にも戻れる (戻れば作り直される)
@Suite struct WorkspacesPreviousTests {
  @Test func nothingBeforeTheFirstWorkspace() {
    var workspaces = Workspaces(desktops: 1...9)
    workspaces.enter(1)
    #expect(workspaces.previousID == nil)
  }

  @Test func movingToAnotherWorkspaceRemembersTheOneLeft() {
    var workspaces = Workspaces(desktops: 1...9)
    workspaces.enter(1)
    workspaces.enter(2)
    #expect(workspaces.previousID == 1)
    workspaces.enter(2)  // 同じ Desktop の観測は繰り返される
    #expect(workspaces.previousID == 1)
    workspaces.enter(1)
    #expect(workspaces.previousID == 2)
  }

  @Test func passingThroughAnUnknownSpaceKeepsThePrevious() {
    var workspaces = Workspaces(desktops: 1...9)
    workspaces.enter(1)
    workspaces.enter(2)
    workspaces.enter(nil)  // 全画面など、マーカーの無い Space
    #expect(workspaces.previousID == 1)
  }
}
