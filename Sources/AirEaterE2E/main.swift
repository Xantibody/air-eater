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

/// previous を送ると Desktop desktop に着いて留まること。
func previous(reaches desktop: Int) -> () throws -> Void {
  { try arrivesAndStays(at: desktop) { send("previous") } }
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
  // 直前の workspace は ID で覚えているので、消えた 5 にも戻れる (空き Desktop 2 に作り直す)
  ("previous で直前の workspace 5 に戻る (消えていたので作り直す)", previous(reaches: 2)),
  ("previous でまた workspace 1 に戻る", previous(reaches: 1)),
  ("workspace 1 のまま留まる", workspace(1, reaches: 1)),
]

// MARK: - タイル

scenarios += [
  ("E2E の窓を開いて前面に出す", showTileWindow),
  ("tile left で窓が左半分になる", tiles(.left)),
  ("tile bottom で窓が下半分になる", tiles(.bottom)),
  ("tile top で窓が上半分になる", tiles(.top)),
  ("tile right で窓が右半分になる", tiles(.right)),
  ("tile fill で窓が可視領域いっぱいになる", tiles(.fill)),
  ("全画面の窓に tile fill を送ると、全画面を解いて可視領域いっぱいになる", fillsFromFullscreen),
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

/// close を送ると、手前にある 2 枚目の Finder の窓が閉じ、残った 1 枚目が画面全体に広がること。
func closesFrontFinderWindow() throws {
  let start = logLines.count
  send("close")
  try expect(waitFor("close → Finder の窓の閉じるボタンを押した", from: start), "close が Finder の窓を閉じなかった")
  try expect(
    waitFor("窓が 1 枚になった", from: start, timeout: .seconds(4)),
    "閉じた後に窓が 1 枚になったと air-eater が気づかなかった")
  let deadline = Date(timeIntervalSinceNow: 3)
  var frame: CGRect?
  repeat {
    pump(0.1)
    frame = finderWindow(titled: finderFolders[0].lastPathComponent).flatMap(axFrame(of:))
  } while !(frame.map { nearlyEqual($0, expectedAXFrame(nil)) } ?? false) && Date() < deadline
  try expect(
    finderWindow(titled: finderFolders[1].lastPathComponent) == nil, "2 枚目の窓が閉じていない")
  try expect(
    frame.map { nearlyEqual($0, expectedAXFrame(nil)) } == true,
    "残った窓が画面全体に広がらなかった: \(frame.map { "\($0)" } ?? "窓が無い")")
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
  // 1 枚なら 画面全体に表示、2 枚なら 左と右 (前面の新しい窓が左)。
  // close (Option+C) で手前の 2 枚目を閉じると 1 枚に戻り、自動タイルが画面全体に広げる
  ("Finder の窓 1 枚目は画面全体に広がる", opensAndArranges(folder: 0, expected: [(0, nil)])),
  (
    "Finder の窓 2 枚目で左と右に並ぶ",
    opensAndArranges(folder: 1, expected: [(1, .left), (0, .right)])
  ),
  // 方向でフォーカスを移す (Option+Shift+H/J/K/L)。左が手前 (2 枚目) の状態から右へ、そして左へ戻る
  ("focus right で右の Finder の窓 (1 枚目) にフォーカスが移る", focusMoves("right", toFolder: 0)),
  ("focus left で左の Finder の窓 (2 枚目) に戻る", focusMoves("left", toFolder: 1)),
  ("close で手前の Finder の窓が閉じ、残りが画面全体に広がる", closesFrontFinderWindow),
  ("E2E が開いた Finder の窓を閉じる", { closeFinderWindows() }),
  // 純正の配置が無いアプリ (E2E 自身) の窓は、同じ形を自前の frame で作る
  ("純正の配置が無い窓 1 枚目は通知で 1 秒以内に気づき、自前の frame で画面全体に広がる", opensAndArrangesByFrames),
  ("純正の配置が無い窓 2 枚目で自前の frame で左と右に並ぶ", opensAndArrangesByFrames),
  ("純正の配置が無い窓 3 枚目で自前の frame で左と 4 分割に並ぶ", opensAndArrangesByFrames),
  ("自前の frame で並べた E2E の窓を閉じる", { closeFallbackWindows() }),
  ("workspace 1 に戻る", workspace(1, reaches: 1)),
]

// MARK: - 端末を開く (Option+Return / Option+Shift+Return)

/// E2E を始める前から窓を持っている端末のプロセス。これ以外を E2E が起動したものとみなし、
/// 最後に終了させる。Nix の kitty は NSRunningApplication では pid が -1 になって当てにならない
/// ので、窓の持ち主 (CGWindowList) で見分ける
let terminalName = "kitty"
let terminalsBeforeE2E = processes(owningWindowsNamed: terminalName)

/// E2E が起動した端末の pid を、起動した順 (pid の昇順) に。
func launchedTerminals() -> [pid_t] {
  processes(owningWindowsNamed: terminalName).subtracting(terminalsBeforeE2E).sorted()
}

/// command を送って端末が 1 つ起動し、Desktop の窓が count 枚になり、
/// expected の各端末 (起動した順の番号) がその位置 (nil なら画面全体) に並ぶこと。
func launchesTerminal(
  _ command: String, count: Int, expected: [(Int, Tile?)]
) -> () throws -> Void {
  {
    let start = logLines.count
    send(command)
    try expect(
      waitFor("新しいインスタンスで起動した", from: start, timeout: .seconds(5)), "端末が起動しなかった")
    try expect(
      waitFor("窓が \(count) 枚になった", from: start, timeout: .seconds(5)),
      "窓が \(count) 枚になったと air-eater が気づかなかった")
    let deadline = Date(timeIntervalSinceNow: 4)
    var mismatches: [String] = []
    repeat {
      pump(0.1)
      let terminals = launchedTerminals()
      mismatches = expected.compactMap { index, tile in
        let frame =
          terminals.indices.contains(index)
          ? firstWindow(ofProcess: terminals[index]).flatMap(axFrame(of:)) : nil
        let want = expectedAXFrame(tile)
        return frame.map { nearlyEqual($0, want) } == true
          ? nil : "端末 \(index + 1): \(frame.map { "\($0)" } ?? "窓が無い") (期待 \(want))"
      }
    } while !mismatches.isEmpty && Date() < deadline
    try expect(mismatches.isEmpty, "標準の配置で並ばなかった: \(mismatches)")
  }
}

/// E2E が起動した端末を終わらせる。ユーザーが使っている端末には触らない
func quitLaunchedTerminals() {
  for pid in launchedTerminals() { kill(pid, SIGTERM) }
  pump(1.5)
}

scenarios += [
  ("端末を試すため空の Desktop 2 に workspace 2 を作る", workspace(2, reaches: 2)),
  (
    "terminal で今の workspace に端末が開き、画面全体に広がる",
    launchesTerminal("terminal", count: 1, expected: [(0, nil)])
  ),
  (
    "もう一度 terminal で 2 つ目が開き、左と右に並ぶ",
    launchesTerminal("terminal", count: 2, expected: [(1, .left), (0, .right)])
  ),
  ("E2E が起動した端末を終わらせる", { quitLaunchedTerminals() }),
  ("workspace 1 に戻る", workspace(1, reaches: 1)),
  ("new で新しい workspace に端末が開き、画面全体に広がる", launchesTerminal("new", count: 1, expected: [(0, nil)])),
  ("E2E が起動した端末を終わらせる", { quitLaunchedTerminals() }),
  // 窓の移動 (Option+Shift+数字)。Finder の窓を Desktop 1 で開き、workspace 2 へ移す
  ("workspace 1 に戻る", workspace(1, reaches: 1)),
  (
    "move 2 で Finder の窓が workspace 2 へ移り、一緒に Desktop 2 に着く",
    movesFinderWindow(toWorkspace: 2, reaches: 2)
  ),
  ("移した Finder の窓を閉じる", { closeMovedFinderWindow() }),
  ("workspace 1 に戻って終わる", workspace(1, reaches: 1)),
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
