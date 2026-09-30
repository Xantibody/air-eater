import Foundation
import os

private let logger = Logger(subsystem: "dev.xantibody.air-eater", category: "main")

/// 時刻付きで標準エラーに出し、統合ログにも送る。
/// 端末で `just run` を見ていても、`log stream --predicate 'subsystem == "dev.xantibody.air-eater"'`
/// でも同じ内容が追える
func log(_ message: String) {
  let time = Date.now.formatted(
    Date.ISO8601FormatStyle(timeZone: .current).time(includingFractionalSeconds: true))
  FileHandle.standardError.write(Data("\(time) \(message)\n".utf8))
  logger.info("\(message, privacy: .public)")
}
