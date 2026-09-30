import AirEaterCore
import AppKit
import ApplicationServices

// E2E が動かす窓の種類と、種類ごとに回す共通のシナリオ

/// air-eater は窓の種類ごとに違う経路を使う (純正の配置か自前の frame、AX で窓を結ぶ手順) ので、
/// 同じシナリオを種類ごとに回す。どの種類も E2E が開いた窓だけを動かし、使う人の窓には触らない。
/// シナリオはメインスレッドで順に回すので、閉包を持っていても並行には触らない
struct WindowKind: @unchecked Sendable {
  let name: String
  /// この Mac で使えるか。無ければその種類のシナリオを飛ばす
  let available: () -> Bool
  /// 純正の「ウインドウ ▸ 移動とサイズ変更」があるか。無ければ自前の frame で並ぶはず
  let hasWindowMenu: Bool
  /// index 番目 (0 始まり) の窓を今の Desktop に開く
  let open: (Int) -> Void
  /// index 番目の窓のタイトル (前方一致で探す。TextEdit は拡張子を隠すことがある)
  let title: (Int) -> String
  /// この種類のアプリの AX 要素
  let application: () -> AXUIElement?
  /// E2E が開いた窓を全部閉じ、後片付けをする
  let closeAll: () -> Void

  func window(_ index: Int) -> AXUIElement? {
    application().flatMap { axWindow(of: $0, titled: title(index)) }
  }

  func focusedTitle() -> String? {
    application().flatMap(focusedWindowTitle(of:))
  }
}

/// 一時フォルダやファイルの URL。名前が窓のタイトルになる
private func temporaryURL(_ suffix: String) -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("air-eater-e2e-\(ProcessInfo.processInfo.processIdentifier)-\(suffix)")
}

// MARK: - Finder (AppKit、純正の配置あり)

private let finderFolders: [URL] = (1...3).map { temporaryURL("finder-\($0)") }

let finderKind = WindowKind(
  name: "Finder",
  available: { true },
  hasWindowMenu: true,
  open: { index in
    try? FileManager.default.createDirectory(
      at: finderFolders[index], withIntermediateDirectories: true)
    NSWorkspace.shared.open(finderFolders[index])
  },
  title: { finderFolders[$0].lastPathComponent },
  application: { axApplication(bundleIdentifier: "com.apple.finder") },
  closeAll: {
    // 窓を閉じてからフォルダを消す。逆だと窓が親フォルダを表示したまま残る
    closeWindows(of: "com.apple.finder", titled: finderFolders.map(\.lastPathComponent))
    for folder in finderFolders { try? FileManager.default.removeItem(at: folder) }
  })

// MARK: - TextEdit (AppKit の書類アプリ、純正の配置あり)

private let textFiles: [URL] = (1...3).map { temporaryURL("textedit-\($0).txt") }
private let textEditURL = URL(fileURLWithPath: "/System/Applications/TextEdit.app")

let textEditKind = WindowKind(
  name: "TextEdit",
  available: { FileManager.default.fileExists(atPath: textEditURL.path) },
  hasWindowMenu: true,
  open: { index in
    try? "air-eater E2E\n".write(to: textFiles[index], atomically: true, encoding: .utf8)
    NSWorkspace.shared.open(
      [textFiles[index]], withApplicationAt: textEditURL,
      configuration: NSWorkspace.OpenConfiguration()
    ) { _, _ in }
  },
  title: { textFiles[$0].deletingPathExtension().lastPathComponent },
  application: { axApplication(bundleIdentifier: "com.apple.TextEdit") },
  closeAll: {
    closeWindows(
      of: "com.apple.TextEdit",
      titled: textFiles.map { $0.deletingPathExtension().lastPathComponent })
    for file in textFiles { try? FileManager.default.removeItem(at: file) }
  })

// MARK: - E2E 自身の窓 (純正の配置なし、イベントループも回さない)

/// E2E を通常のアプリにして AppKit のアクセシビリティを立ち上げる。これを呼ばないと
/// air-eater からの AX の問い合わせに答えられない (kAXErrorCannotComplete になる)
@MainActor let ownAppReady: Bool = {
  NSApplication.shared.setActivationPolicy(.regular)
  NSApplication.shared.finishLaunching()
  return true
}()

@MainActor private var ownWindows: [NSWindow] = []
private func ownTitle(_ index: Int) -> String { "air-eater E2E own \(index + 1)" }

let ownKind = WindowKind(
  name: "E2E 自身 (メニュー無し)",
  available: { true },
  hasWindowMenu: false,
  open: { index in
    MainActor.assumeIsolated {
      _ = ownAppReady
      // 並べる側は CGWindowList の位置で AX の窓を探すので、窓ごとに違う場所に開く
      let window = NSWindow(
        contentRect: NSRect(x: 100 + 150 * index, y: 100, width: 400, height: 300),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
      window.title = ownTitle(index)
      window.isReleasedWhenClosed = false
      ownWindows.append(window)
      window.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
    }
  },
  title: ownTitle,
  application: { AXUIElementCreateApplication(getpid()) },
  closeAll: {
    MainActor.assumeIsolated {
      ownWindows.forEach { $0.close() }
      ownWindows.removeAll()
    }
  })

/// 共通のシナリオを回す種類。足すときはここに並べる
let windowKinds = [finderKind, textEditKind, ownKind]

// MARK: - 種類ごとに回すシナリオ

/// kind の窓を 1 枚開くと、air-eater が窓の数に合った配置に並べること。
/// 期待した経路 (純正のメニューか自前の frame) を通ったかもログで見る
func opensAndArranges(_ kind: WindowKind, _ index: Int) -> () throws -> Void {
  {
    let start = logLines.count
    let shown = Date()
    kind.open(index)
    let count = index + 1
    try expect(
      waitFor("窓が \(count) 枚になった", from: start, timeout: .seconds(5)),
      "\(kind.name) の窓が \(count) 枚になったと気づかなかった")
    // 窓の生成は AXObserver で拾うので、定期的な走査 (2 秒) を待たずに気づくはず
    let latency = Date().timeIntervalSince(shown)
    try expect(latency < 1.5, "窓が増えたと気づくのに \(latency) 秒かかった (通知でなく走査で拾った)")
    let route = kind.hasWindowMenu ? "のメニューを押した" : "自前の frame で"
    try expect(
      waitFor(route, from: start, timeout: .seconds(3)),
      "\(kind.name) を期待した経路 (\(route)) で並べなかった")
    try expectArranged(kind, count: count)
  }
}

/// close を送ると kind の手前の窓 (一番新しい) が閉じ、残り leaving 枚が数に合った配置に並び直すこと。
func closesFront(_ kind: WindowKind, leaving: Int) -> () throws -> Void {
  {
    let start = logLines.count
    send("close")
    try expect(waitFor("閉じるボタンを押した", from: start), "close が窓を閉じなかった")
    try expect(
      waitFor("窓が \(leaving) 枚になった", from: start, timeout: .seconds(5)),
      "閉じた後に窓が \(leaving) 枚になったと気づかなかった")
    let deadline = Date(timeIntervalSinceNow: 2)
    while Date() < deadline, kind.window(leaving) != nil { pump(0.1) }
    try expect(kind.window(leaving) == nil, "手前の窓 (\(kind.title(leaving))) が閉じていない")
    try expectArranged(kind, count: leaving)
  }
}

/// focus を送ると、kind のアプリでフォーカス中の窓が index 番目の窓に変わること。
func focusMoves(_ kind: WindowKind, _ direction: String, to index: Int) -> () throws -> Void {
  {
    let start = logLines.count
    send("focus \(direction)")
    try expect(waitFor("focus → \(direction) の窓", from: start), "focus が窓を選ばなかった")
    let title = kind.title(index)
    let deadline = Date(timeIntervalSinceNow: 2)
    var focused: String?
    repeat {
      pump(0.1)
      focused = kind.focusedTitle()
    } while focused?.hasPrefix(title) != true && Date() < deadline
    try expect(
      focused?.hasPrefix(title) == true, "フォーカスが \(title) に移らなかった: \(focused ?? "なし")")
  }
}

/// kind の窓 count 枚が、数に合った配置になっていること。
/// 手前 (一番新しい) の窓は配置の先頭の場所にあり、残りの窓は残りの場所を集合として埋める。
/// 純正の配置は残りの窓をどの順で置くか決まっていないので、順は問わない
func expectArranged(_ kind: WindowKind, count: Int) throws {
  guard let arrangement = Arrangement(windowCount: count) else { return }
  let expected = expectedAXFrames(arrangement)
  let deadline = Date(timeIntervalSinceNow: 3)
  var problem: String?
  repeat {
    pump(0.1)
    problem = arrangementProblem(kind, count: count, expected: expected)
  } while problem != nil && Date() < deadline
  try expect(problem == nil, "\(kind.name) の窓が並ばなかった: \(problem ?? "")")
}

private func arrangementProblem(_ kind: WindowKind, count: Int, expected: [CGRect]) -> String? {
  // 添字の大きい窓ほど新しく、手前にある
  let frames = (0..<count).reversed().map { index in
    (kind.title(index), kind.window(index).flatMap(axFrame(of:)))
  }
  guard let front = frames.first?.1 else { return "手前の窓が無い" }
  guard nearlyEqual(front, expected[0]) else {
    return "手前の窓 \(frames[0].0) が \(front) (期待 \(expected[0]))"
  }
  var remaining = Array(expected.dropFirst())
  for (title, frame) in frames.dropFirst() {
    guard let frame else { return "\(title) の窓が無い" }
    guard let match = remaining.firstIndex(where: { nearlyEqual(frame, $0) }) else {
      return "\(title) が \(frame) (期待のどれでもない: \(remaining))"
    }
    remaining.remove(at: match)
  }
  return nil
}
