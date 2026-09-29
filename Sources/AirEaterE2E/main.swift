import AirEaterCore
import Carbon.HIToolbox
import CoreGraphics
import Foundation

// air-eater を実機で起動し、標準入力から操作を送り、ログで結果を確かめる。
// 実際に Desktop を切り替えるので、手元で `just e2e` として回す。CI では回さない。
// 前提: Desktop が 2 個以上あり、Ctrl+1…9 が有効で、実行する端末にアクセシビリティ権限がある

/// air-eater の標準エラーを行ごとに貯める。
final class LogLines: @unchecked Sendable {
  private let lock = NSLock()
  private var lines: [String] = []
  private var partial = ""

  func append(_ chunk: String) {
    lock.withLock {
      partial += chunk
      while let newline = partial.firstIndex(of: "\n") {
        let line = String(partial[..<newline])
        partial = String(partial[partial.index(after: newline)...])
        print("    | \(line)")
        lines.append(line)
      }
    }
  }

  var count: Int { lock.withLock { lines.count } }

  func lines(from index: Int) -> [String] {
    lock.withLock { Array(lines[min(index, lines.count)...]) }
  }
}

let logLines = LogLines()

/// from 行目以降に contains を含む行が出るまで待つ。
func waitFor(_ contains: String, from index: Int, timeout: Duration = .seconds(3)) -> Bool {
  let deadline = ContinuousClock.now + timeout
  while ContinuousClock.now < deadline {
    if logLines.lines(from: index).contains(where: { $0.contains(contains) }) { return true }
    Thread.sleep(forTimeInterval: 0.05)
  }
  return false
}

/// 実際のキーボードと同じ HID の段にキー入力を送る。
func press(_ keyCode: Int, _ flags: CGEventFlags) {
  let source = CGEventSource(stateID: .hidSystemState)
  for keyDown in [true, false] {
    let event = CGEvent(
      keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: keyDown)
    event?.flags = flags
    event?.post(tap: .cghidEventTap)
  }
}

/// E2E プロセス自身のキー監視に、自分で送ったキーが見えるか。
/// 見えない環境 (このプロセスの起動元によっては見えない) では、キーを使うシナリオを飛ばす
func tapSeesSyntheticKeys() -> Bool {
  final class Seen: @unchecked Sendable { var count = 0 }
  let seen = Seen()
  guard
    let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
      eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
      callback: { _, _, event, userInfo in
        Unmanaged<Seen>.fromOpaque(userInfo!).takeUnretainedValue().count += 1
        return Unmanaged.passUnretained(event)
      },
      userInfo: Unmanaged.passUnretained(seen).toOpaque())
  else { return false }
  let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
  CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
  defer { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode) }
  press(kVK_F19, [])  // どのアプリも使っていないキー
  CFRunLoopRunInMode(.defaultMode, 0.5, false)
  return seen.count > 0
}

let digit = [
  kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8,
  kVK_ANSI_9,
]

// MARK: - air-eater の起動

let binary = CommandLine.arguments.dropFirst().first ?? ".build/out/Products/Debug/air-eater"
let process = Process()
process.executableURL = URL(fileURLWithPath: binary)
let stdin = Pipe()
let stderr = Pipe()
process.standardInput = stdin
process.standardError = stderr
stderr.fileHandleForReading.readabilityHandler = { handle in
  let data = handle.availableData
  guard !data.isEmpty, let text = String(bytes: data, encoding: .utf8) else { return }
  logLines.append(text)
}

/// air-eater の標準入力に命令を 1 行送る。
func send(_ command: String) {
  print("  > \(command)")
  stdin.fileHandleForWriting.write(Data("\(command)\n".utf8))
}

// MARK: - シナリオ

struct Failure: Error, CustomStringConvertible {
  let description: String
}

func expect(_ condition: Bool, _ message: String) throws {
  if !condition { throw Failure(description: message) }
}

/// trigger の後に Desktop desktop に着き、その後 settle の間は他の Space へ動かないこと。
func arrivesAndStays(
  at desktop: Int, settle: Duration = .seconds(2), trigger: () -> Void
) throws {
  let start = logLines.count
  trigger()
  try expect(isAt(desktop, within: .seconds(3)), "Desktop \(desktop) にいると分からなかった")
  let arrived = logLines.count
  Thread.sleep(forTimeInterval: Double(settle.components.seconds))
  let after = logLines.lines(from: arrived)
  let moved = after.filter { $0.contains("現在地 ") && !$0.contains("現在地 Desktop \(desktop) ") }
  try expect(moved.isEmpty, "Desktop \(desktop) に着いた後に移動した: \(moved)")
  try expect(isAt(desktop, within: .seconds(1)), "留まっているはずの Desktop \(desktop) から離れていた")
  // マーカーは見えない窓なので、air-eater が前面に出るとキーボードの入力先が消える
  let stolen = logLines.lines(from: start).filter { $0.contains("前面のアプリ → air-eater") }
  try expect(stolen.isEmpty, "air-eater がフォーカスを奪った: \(stolen)")
}

/// status を送り、air-eater が今 Desktop desktop にいると答えるまで待つ。
func isAt(_ desktop: Int, within timeout: Duration) -> Bool {
  let deadline = ContinuousClock.now + timeout
  while ContinuousClock.now < deadline {
    let start = logLines.count
    send("status")
    if waitFor("状態 現在地 Desktop \(desktop) ", from: start, timeout: .milliseconds(300)) {
      return true
    }
  }
  return false
}

/// workspace N を送ると Desktop desktop に着いて留まること。
func workspace(_ number: Int, reaches desktop: Int) -> () throws -> Void {
  { try arrivesAndStays(at: desktop) { send("workspace \(number)") } }
}

/// 手で Ctrl+N を押したのと同じキーを送り、air-eater がその Desktop を N 番だと分かること。
func manualSwitch(to desktop: Int) -> () throws -> Void {
  { try arrivesAndStays(at: desktop) { press(digit[desktop - 1], .maskControl) } }
}

let tapWorks = tapSeesSyntheticKeys()

// 使うのは Desktop 1 と 2 だけ。間に全画面アプリの Space が挟まっていてもよい
var scenarios: [(String, () throws -> Void)] = [
  ("workspace 1 で Desktop 1 に留まる", workspace(1, reaches: 1))
]
// air-eater がまだ行っていない Desktop 2 を、手の Ctrl+2 で覚えられるか。
// Desktop 2 に一度でも air-eater で行くとマーカーが付くので、それより前に回す
if tapWorks {
  scenarios += [
    ("手の Ctrl+2 で着いた Desktop 2 を 2 番だと分かる", manualSwitch(to: 2)),
    ("手の Ctrl+1 で Desktop 1 に戻る", manualSwitch(to: 1)),
  ]
} else {
  print("… 送ったキーがキー監視に見えない環境なので、手の Ctrl+数字 のシナリオは飛ばす")
}
scenarios += [
  ("空きを指す workspace 2 で Desktop 2 に着いて留まる", workspace(2, reaches: 2)),
  ("workspace 1 で Desktop 1 に戻って留まる", workspace(1, reaches: 1)),
  ("もう一度 workspace 2 で Desktop 2 に留まる", workspace(2, reaches: 2)),
  ("workspace 1 で Desktop 1 に戻る", workspace(1, reaches: 1)),
]

// MARK: - 実行

try process.run()
defer { process.terminate() }

guard waitFor("準備できました", from: 0, timeout: .seconds(10)) else {
  print("✘ air-eater が起動しなかった")
  process.terminate()
  exit(1)
}

var failures = 0
for (name, scenario) in scenarios {
  print("▶ \(name)")
  do {
    try scenario()
    print("✔ \(name)")
  } catch {
    failures += 1
    print("✘ \(name): \(error)")
  }
}
process.terminate()
print(failures == 0 ? "✔ 全 \(scenarios.count) 件通過" : "✘ \(failures) / \(scenarios.count) 件失敗")
exit(failures == 0 ? 0 : 1)
