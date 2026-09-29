import AirEaterCore
import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

// air-eater を実機で起動し、標準入力から操作を送り、ログで結果を確かめる。
// 実際に Desktop を切り替えるので、手元で `just e2e` として回す。CI では回さない。
// 前提: Desktop が 2 個以上あり、Ctrl+1…9 が有効で、実行する端末にアクセシビリティ権限がある

let logLines = LogLines()

/// seconds の間、メインのランループを回して待つ。
/// air-eater が E2E の窓を AX で動かすとき、その要求はこのプロセスのメインスレッドが受けるので、
/// 眠って待つと AX の要求が詰まって窓が動かない
func pump(_ seconds: Double) {
  RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
}

/// from 行目以降に contains を含む行が出るまで待つ。
func waitFor(_ contains: String, from index: Int, timeout: Duration = .seconds(3)) -> Bool {
  let deadline = ContinuousClock.now + timeout
  while ContinuousClock.now < deadline {
    if logLines.lines(from: index).contains(where: { $0.contains(contains) }) { return true }
    pump(0.05)
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

/// trigger の後に Desktop desktop に着き、その後 settle の間は他の Space へ動かないこと。
func arrivesAndStays(
  at desktop: Int, settle: Duration = .seconds(2), trigger: () -> Void
) throws {
  let start = logLines.count
  trigger()
  try expect(isAt(desktop, within: .seconds(3)), "Desktop \(desktop) にいると分からなかった")
  let arrived = logLines.count
  pump(Double(settle.components.seconds))
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

/// status を送り、workspace の割り当てに expected (例 "5→D2") が含まれるか (included が false なら含まれないか)。
func workspaces(include expected: String, _ included: Bool = true) -> () throws -> Void {
  {
    let start = logLines.count
    send("status")
    try expect(waitFor("状態 現在地", from: start, timeout: .seconds(1)), "status に答えなかった")
    let line = logLines.lines(from: start).first { $0.contains("状態 現在地") } ?? ""
    let workspaces = line.components(separatedBy: " / ").first { $0.hasPrefix("workspace ") } ?? ""
    try expect(
      workspaces.contains(expected) == included,
      "workspace の割り当てが想定と違う (\(included ? "" : "not ")\(expected)): \(workspaces)")
  }
}

/// neighbor を送ると Desktop desktop に着いて留まること。
func neighbor(_ direction: String, reaches desktop: Int) -> () throws -> Void {
  { try arrivesAndStays(at: desktop) { send("neighbor \(direction)") } }
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
// Desktop 1 には窓があり workspace 1。Desktop 2 は空
scenarios += [
  ("まだ無い workspace 2 を空の Desktop 2 に作って留まる", workspace(2, reaches: 2)),
  ("workspace 2 は Desktop 2 にある", workspaces(include: "2→D2")),
  ("workspace 1 で Desktop 1 に戻って留まる", workspace(1, reaches: 1)),
  ("空のまま離れた workspace 2 は消える", workspaces(include: "2→D2", false)),
  // Hyprland と同じく番号は詰めない。workspace 5 は 5 のまま空き Desktop 2 に作る
  ("workspace 5 を空の Desktop 2 に作って留まる", workspace(5, reaches: 2)),
  ("workspace 5 は Desktop 2 にある", workspaces(include: "5→D2")),
  ("workspace 5 から隣 (ID 順で折り返して workspace 1) へ行く", neighbor("next", reaches: 1)),
  ("空のまま離れた workspace 5 は消える", workspaces(include: "5→D2", false)),
  ("workspace 1 のまま留まる", workspace(1, reaches: 1)),
]

// MARK: - タイル

/// 動かされる側の窓。ユーザーの窓には触らないよう、E2E 自身が開く
let tileWindow: NSWindow = {
  NSApplication.shared.setActivationPolicy(.regular)
  // これを呼ばないと AppKit のアクセシビリティが立ち上がらず、air-eater からの AX の問い合わせに
  // 答えられない (kAXErrorCannotComplete になる)
  NSApplication.shared.finishLaunching()
  let window = NSWindow(
    contentRect: NSRect(x: 200, y: 200, width: 400, height: 300),
    styleMask: [.titled, .resizable], backing: .buffered, defer: false)
  window.title = "air-eater E2E"
  window.isReleasedWhenClosed = false
  return window
}()

/// E2E の窓を開いて前面に出す。air-eater はフォーカス中の窓を動かすので、これが前提になる
func showTileWindow() throws {
  let start = logLines.count
  // シナリオはメインスレッドで順に回している
  MainActor.assumeIsolated {
    tileWindow.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
  try expect(waitFor("前面のアプリ → AirEaterE2E", from: start), "E2E の窓が前面にならなかった")
}

/// tile を送ると、E2E の窓がその画面の可視領域の半分に収まること。
func tiles(_ tile: Tile) -> () throws -> Void {
  {
    try MainActor.assumeIsolated {
      guard let screen = tileWindow.screen ?? NSScreen.main else {
        throw Failure(description: "画面が取れない")
      }
      let expected = tile.frame(in: screen.visibleFrame)
      send("tile \(tile)")
      let deadline = Date(timeIntervalSinceNow: 2)
      while Date() < deadline, !nearlyEqual(tileWindow.frame, expected) { pump(0.05) }
      try expect(
        nearlyEqual(tileWindow.frame, expected),
        "窓が \(tile) 半分にならなかった: \(tileWindow.frame) (期待 \(expected))")
    }
  }
}

scenarios += [
  ("E2E の窓を開いて前面に出す", showTileWindow),
  ("tile left で窓が左半分になる", tiles(.left)),
  ("tile bottom で窓が下半分になる", tiles(.bottom)),
  ("tile top で窓が上半分になる", tiles(.top)),
  ("tile right で窓が右半分になる", tiles(.right)),
  ("E2E の窓を閉じる", { MainActor.assumeIsolated { tileWindow.close() } }),
]

// MARK: - 自動タイル (macOS 標準の配置)

// 標準の配置は各アプリの「ウインドウ」メニューにあり、E2E のようなコマンドラインのプロセスには
// AppKit が項目を足さない。Finder の窓で確かめる。開くのは E2E が作った一時フォルダだけ

/// Finder で開く一時フォルダ。名前が窓のタイトルになる
let finderFolders: [URL] = (1...2).map { index in
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("air-eater-e2e-\(ProcessInfo.processInfo.processIdentifier)-\(index)")
  try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

/// index 番目の一時フォルダを Finder で開き、expected の各窓がその位置に並ぶこと。
/// expected は (何番目のフォルダの窓か, 期待する位置 (nil なら画面全体)) の並び
func opensAndArranges(folder index: Int, expected: [(Int, Tile?)]) -> () throws -> Void {
  {
    let start = logLines.count
    NSWorkspace.shared.open(finderFolders[index])
    try expect(
      waitFor("窓が \(index + 1) 枚になった", from: start, timeout: .seconds(4)),
      "Finder の窓が \(index + 1) 枚になったと air-eater が気づかなかった")
    let deadline = Date(timeIntervalSinceNow: 3)
    var mismatches: [String] = []
    repeat {
      pump(0.1)
      mismatches = expected.compactMap { folder, tile in
        let title = finderFolders[folder].lastPathComponent
        let frame = finderWindow(titled: title).flatMap(axFrame(of:))
        let want = expectedAXFrame(tile)
        return frame.map { nearlyEqual($0, want) } == true
          ? nil : "\(title): \(frame.map { "\($0)" } ?? "窓が無い") (期待 \(want))"
      }
    } while !mismatches.isEmpty && Date() < deadline
    try expect(mismatches.isEmpty, "標準の配置で並ばなかった: \(mismatches)")
  }
}

/// E2E が開いた Finder の窓を閉じる。
func closeFinderWindows() {
  for folder in finderFolders {
    guard let window = finderWindow(titled: folder.lastPathComponent) else { continue }
    var button: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &button)
    if let button {
      AXUIElementPerformAction(
        unsafeDowncast(button, to: AXUIElement.self), kAXPressAction as CFString)
    }
  }
  pump(1)
  for folder in finderFolders { try? FileManager.default.removeItem(at: folder) }
}

scenarios += [
  ("自動タイルを試すため空の Desktop 2 に workspace 2 を作る", workspace(2, reaches: 2)),
  // 1 枚なら 画面全体に表示、2 枚なら 左と右 (前面の新しい窓が左)
  ("Finder の窓 1 枚目は画面全体に広がる", opensAndArranges(folder: 0, expected: [(0, nil)])),
  (
    "Finder の窓 2 枚目で左と右に並ぶ",
    opensAndArranges(folder: 1, expected: [(1, .left), (0, .right)])
  ),
  ("E2E が開いた Finder の窓を閉じる", { closeFinderWindows() }),
  ("workspace 1 に戻る", workspace(1, reaches: 1)),
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
