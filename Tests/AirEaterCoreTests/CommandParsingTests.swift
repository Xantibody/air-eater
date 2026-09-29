import Testing

@testable import AirEaterCore

@Suite struct CommandParsingTests {
  @Test func emptyLineIsNotACommand() {
    #expect(Command(parsing: "") == nil)
  }
}

extension CommandParsingTests {
  @Test func workspaceLineParsesItsNumber() {
    #expect(Command(parsing: "workspace 2") == .workspace(2))
  }
}

extension CommandParsingTests {
  @Test(
    arguments: [
      ("workspace 9", Command.workspace(9)),
      ("neighbor previous", .neighbor(.previous)),
      ("neighbor next", .neighbor(.next)),
      ("new", .newWorkspace), ("terminal", .openTerminal), ("close", .close),
      ("tile left", .tile(.left)),
      ("tile bottom", .tile(.bottom)),
      ("tile top", .tile(.top)),
      ("tile right", .tile(.right)),
      ("  workspace 3  ", .workspace(3)), ("arrange", .arrange),
    ] as [(String, Command)])
  func lineParsesToCommand(line: String, expected: Command) {
    #expect(Command(parsing: line) == expected)
  }

  @Test(arguments: ["workspace", "workspace x", "workspace 0", "neighbor up", "tile middle", "fly"])
  func malformedLineIsNotACommand(line: String) {
    #expect(Command(parsing: line) == nil)
  }
}
