import AirEaterCore
import Foundation

/// 標準入力から 1 行 1 命令で操作を受け取る (`workspace 2`、`new` など)。
/// キー監視を通さずに操作できるので、E2E テストはこちらから操作を送る。端末から手で打ってもよい
@MainActor
final class CommandInput {
  var onCommand: (Command) -> Void = { _ in }
  var onStatus: () -> Void = {}

  func start() {
    let lines = LineBuffer()
    FileHandle.standardInput.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      // 入力が閉じられたら止める。止めないと空読みを繰り返す
      guard !data.isEmpty else {
        handle.readabilityHandler = nil
        return
      }
      for line in lines.append(data) {
        Task { @MainActor in self?.receive(line) }
      }
    }
  }

  private func receive(_ line: String) {
    // 操作ではなく、今の状態をログに出させる問い合わせ。E2E が現在地を確かめるのに使う
    if line.trimmingCharacters(in: .whitespaces) == "status" {
      onStatus()
      return
    }
    guard let command = Command(parsing: line) else {
      log("命令を読めませんでした: \(line)")
      return
    }
    log("\(command) を標準入力から受けた")
    onCommand(command)
  }
}

/// 読み取りの途中で切れた行をつなぐ。readabilityHandler は同時に 1 つしか走らない
private final class LineBuffer: @unchecked Sendable {
  private var partial = Data()

  func append(_ data: Data) -> [String] {
    partial.append(data)
    var lines: [String] = []
    while let newline = partial.firstIndex(of: UInt8(ascii: "\n")) {
      lines.append(String(bytes: partial[..<newline], encoding: .utf8) ?? "")
      partial.removeSubrange(...newline)
    }
    return lines
  }
}
