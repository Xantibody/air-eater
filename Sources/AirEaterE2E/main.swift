import AirEaterCore
import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

// air-eater を実機で起動し、標準入力から操作を送り、ログで結果を確かめる。
// 実際に Desktop を切り替えるので、手元で `just e2e` として回す。CI では回さない。
// 前提: Desktop が 2 個以上あり、Ctrl+1…9 が有効で、実行する端末にアクセシビリティ権限がある

let logLines = LogLines()

/// seconds の間、NSApplication のイベントループを回して待つ。
/// air-eater が E2E の窓を AX で動かすとき、その要求はこのプロセスのメインスレッドが受けるので、
/// 眠って待つと AX の要求が詰まって窓が動かない。RunLoop だけ回すのでは足りず、E2E 自身の窓の
/// 閉じるボタンやドラッグはイベントを sendEvent で流さないと効かない
func pump(_ seconds: Double) {
  let until = Date(timeIntervalSinceNow: seconds)
  // シナリオはメインスレッドで順に回している
  MainActor.assumeIsolated {
    let app = NSApplication.shared
    repeat {
      if let event = app.nextEvent(matching: .any, until: until, inMode: .default, dequeue: true) {
        app.sendEvent(event)
      }
    } while Date() < until
  }
}

// E2E は最初から通常のアプリとして動く (ownAppReady)。後から窓を出すときに購読や AX の準備が
// 遅れないようにするため
_ = ownAppReady

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

// MARK: - 窓の種類ごとの共通シナリオ (自動タイル、フォーカス移動、閉じる)

// Desktop 2 は空なので、そこに workspace 2 を作って窓を 3 枚まで開く。種類は WindowKinds.swift
for kind in windowKinds {
  guard kind.available() else {
    print("… \(kind.name) はこの Mac に無いので飛ばす")
    continue
  }
  let tag = "[\(kind.name)]"
  scenarios += [
    ("\(tag) 空の Desktop 2 に workspace 2 を作る", workspace(2, reaches: 2)),
    ("\(tag) 窓 1 枚目は画面全体に広がる", opensAndArranges(kind, 0)),
    ("\(tag) 窓 2 枚目で左と右に並ぶ (手前の新しい窓が左)", opensAndArranges(kind, 1)),
    ("\(tag) focus right で右の窓 (1 枚目) にフォーカスが移る", focusMoves(kind, "right", to: 0)),
    ("\(tag) focus left で左の窓 (2 枚目) に戻る", focusMoves(kind, "left", to: 1)),
    ("\(tag) 窓 3 枚目で左と 4 分割に並ぶ", opensAndArranges(kind, 2)),
    ("\(tag) close で手前の窓が閉じ、残り 2 枚が左と右に並ぶ", closesFront(kind, leaving: 2)),
    ("\(tag) close でまた手前の窓が閉じ、残りが画面全体に広がる", closesFront(kind, leaving: 1)),
    ("\(tag) E2E が開いた窓を閉じる", { kind.closeAll() }),
    ("\(tag) workspace 1 に戻る", workspace(1, reaches: 1)),
  ]
}

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
