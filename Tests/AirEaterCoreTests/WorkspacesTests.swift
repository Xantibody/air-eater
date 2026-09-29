import CoreGraphics
import Testing

@testable import AirEaterCore

@Suite struct WorkspacesCandidateTests {
  @Test func freshPoolOffersFirstDesktopForAnyWorkspace() {
    #expect(Workspaces(desktops: 1...9).candidate(for: 5) == 1)
  }
}

extension WorkspacesCandidateTests {
  @Test func assignedWorkspaceGoesToItsDesktop() {
    var workspaces = Workspaces(desktops: 1...9)
    workspaces.assign(5, to: 3)
    #expect(workspaces.candidate(for: 5) == 3)
  }
}

extension WorkspacesCandidateTests {
  // Desktop 1 は workspace 1 に割り当て済み、Desktop 2 は窓があると分かっている
  @Test func newWorkspaceSkipsAssignedAndOccupiedDesktops() {
    var workspaces = Workspaces(desktops: 1...9)
    workspaces.assign(1, to: 1)
    workspaces.observe(desktop: 2, windows: [20])
    #expect(workspaces.candidate(for: 5) == 3)
  }

  @Test func fullPoolHasNoCandidateForNewWorkspace() {
    var workspaces = Workspaces(desktops: 1...2)
    workspaces.assign(1, to: 1)
    workspaces.assign(2, to: 2)
    #expect(workspaces.candidate(for: 3) == nil)
  }
}

@Suite struct WorkspacesAdoptionTests {
  @Test func desktopWithWindowsBecomesWorkspaceOfSameNumber() {
    var workspaces = Workspaces(desktops: 1...9)
    workspaces.observe(desktop: 3, windows: [30])
    #expect(workspaces.workspace(on: 3) == 3)
  }
}

extension WorkspacesAdoptionTests {
  // Desktop 2 が workspace 1 を使っているので、Desktop 1 には空いている一番小さい 2 を付ける
  @Test func adoptedDesktopTakesLowestFreeIDWhenItsNumberIsUsed() {
    var workspaces = Workspaces(desktops: 1...9)
    workspaces.assign(1, to: 2)
    workspaces.observe(desktop: 1, windows: [10])
    #expect(workspaces.workspace(on: 1) == 2)
  }
}

@Suite struct WorkspacesLifecycleTests {
  // Hyprland でも表示中の workspace は空でも存在する
  @Test func enteredEmptyDesktopBecomesWorkspace() {
    var workspaces = Workspaces(desktops: 1...9)
    workspaces.enter(4)
    #expect(workspaces.workspace(on: 4) == 4)
  }

  @Test func emptyWorkspaceIsReleasedWhenLeft() {
    var workspaces = Workspaces(desktops: 1...9)
    workspaces.enter(1)
    workspaces.assign(5, to: 2)
    workspaces.observe(desktop: 2, windows: [])
    workspaces.enter(2)
    workspaces.enter(1)
    #expect(workspaces.workspace(on: 2) == nil)
  }
}

extension WorkspacesLifecycleTests {
  @Test func workspaceWithWindowsSurvivesBeingLeft() {
    var workspaces = Workspaces(desktops: 1...9)
    workspaces.observe(desktop: 2, windows: [20])
    workspaces.enter(2)
    workspaces.enter(1)
    #expect(workspaces.workspace(on: 2) == 2)
  }

  // 全画面アプリの Space に移っても、表示していた空の workspace は消える
  @Test func leavingForSpaceOutsidePoolReleasesEmptyWorkspace() {
    var workspaces = Workspaces(desktops: 1...9)
    workspaces.enter(3)
    workspaces.enter(nil)
    #expect(workspaces.workspace(on: 3) == nil)
  }

  // 空になって離れた ID は、次に同じ番号を指したとき空き Desktop に作り直される
  @Test func releasedIDCanBeCreatedAgain() {
    var workspaces = Workspaces(desktops: 1...9)
    workspaces.observe(desktop: 1, windows: [10])
    workspaces.enter(1)
    workspaces.assign(5, to: 2)
    workspaces.enter(2)
    workspaces.enter(1)
    #expect(workspaces.candidate(for: 5) == 2)
    #expect(workspaces.lowestFreeID == 2)
  }
}

@Suite struct WorkspacesNeighborTests {
  @Test func outsidePoolHasNoNeighbor() {
    #expect(Workspaces(desktops: 1...9).desktop(nextTo: .next) == nil)
  }
}

extension WorkspacesNeighborTests {
  // workspace 1 → Desktop 1、3 → Desktop 2、5 → Desktop 4
  static func threeWorkspaces(currentlyOn desktop: Int) -> Workspaces {
    var workspaces = Workspaces(desktops: 1...9)
    workspaces.assign(1, to: 1)
    workspaces.assign(3, to: 2)
    workspaces.assign(5, to: 4)
    for occupied in [1, 2, 4] {
      workspaces.observe(desktop: occupied, windows: [CGWindowID(occupied)])
    }
    workspaces.enter(desktop)
    return workspaces
  }
}

extension WorkspacesNeighborTests {
  // Hyprland の e+1 / e-1 と同じく、端では反対の端へ折り返す
  @Test(arguments: [(2, 4), (4, 1)])
  func nextWrapsAroundWorkspaceIDs(from desktop: Int, expected: Int) {
    #expect(Self.threeWorkspaces(currentlyOn: desktop).desktop(nextTo: .next) == expected)
  }

  @Test(arguments: [(2, 1), (4, 2), (1, 4)])
  func previousWrapsAroundWorkspaceIDs(from desktop: Int, expected: Int) {
    #expect(Self.threeWorkspaces(currentlyOn: desktop).desktop(nextTo: .previous) == expected)
  }

  @Test func singleWorkspaceIsItsOwnNeighbor() {
    var workspaces = Workspaces(desktops: 1...9)
    workspaces.enter(1)
    #expect(workspaces.desktop(nextTo: .next) == 1)
  }
}
