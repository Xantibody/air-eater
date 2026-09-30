import AirEaterCore
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

// E2E の部品のうち、main.swift のグローバル (起動した air-eater やシナリオの状態) に頼らないもの

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

struct Failure: Error, CustomStringConvertible {
  let description: String
}

func expect(_ condition: Bool, _ message: String) throws {
  if !condition { throw Failure(description: message) }
}

/// 座標の丸めで 1〜2 pt ずれることがあるので、それは同じとみなす
func nearlyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
  abs(lhs.minX - rhs.minX) <= 2 && abs(lhs.minY - rhs.minY) <= 2
    && abs(lhs.width - rhs.width) <= 2 && abs(lhs.height - rhs.height) <= 2
}

/// bundle ID のアプリの AX 要素。走っていなければ nil
func axApplication(bundleIdentifier: String) -> AXUIElement? {
  NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
    .map { AXUIElementCreateApplication($0.processIdentifier) }
}

func axWindows(of app: AXUIElement) -> [AXUIElement] {
  var windows: CFTypeRef?
  AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)
  return (windows as? [AXUIElement]) ?? []
}

func axTitle(of window: AXUIElement) -> String? {
  var value: CFTypeRef?
  AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value)
  return value as? String
}

/// app の窓のうち、タイトルが title で始まるもの。TextEdit は拡張子を隠すことがあるので前方一致
func axWindow(of app: AXUIElement, titled title: String) -> AXUIElement? {
  axWindows(of: app).first { axTitle(of: $0)?.hasPrefix(title) == true }
}

/// app でフォーカス中の窓のタイトル。
func focusedWindowTitle(of app: AXUIElement) -> String? {
  var window: CFTypeRef?
  AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window)
  guard let window else { return nil }
  return axTitle(of: unsafeDowncast(window, to: AXUIElement.self))
}

/// bundle ID のアプリの、タイトルが titles のどれかで始まる窓を閉じるボタンで閉じる。
func closeWindows(of bundleIdentifier: String, titled titles: [String]) {
  guard let app = axApplication(bundleIdentifier: bundleIdentifier) else { return }
  for title in titles {
    guard let window = axWindow(of: app, titled: title) else { continue }
    var button: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &button)
    if let button {
      AXUIElementPerformAction(
        unsafeDowncast(button, to: AXUIElement.self), kAXPressAction as CFString)
    }
  }
  pump(1)
}

/// Finder の窓のうち、タイトルが title のもの。
func finderWindow(titled title: String) -> AXUIElement? {
  axApplication(bundleIdentifier: "com.apple.finder").flatMap { axWindow(of: $0, titled: title) }
}

/// AX 座標 (左上原点) の frame。
func axFrame(of window: AXUIElement) -> CGRect? {
  var position: CFTypeRef?
  var size: CFTypeRef?
  guard
    AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
    AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
    let position, let size
  else { return nil }
  var origin = CGPoint.zero
  var extent = CGSize.zero
  AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin)
  AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &extent)
  return CGRect(origin: origin, size: extent)
}

/// 主画面の可視領域の中の tile (nil なら全体) を、AX 座標で。
func expectedAXFrame(_ tile: Tile?) -> CGRect {
  MainActor.assumeIsolated {
    let screen = NSScreen.screens[0]
    let cocoa = tile?.frame(in: screen.visibleFrame) ?? screen.visibleFrame
    return accessibilityFrame(fromCocoa: cocoa, primaryScreenHeight: screen.frame.height)
  }
}

/// 主画面の可視領域を arrangement で割った場所を、手前の窓から順に AX 座標で。
func expectedAXFrames(_ arrangement: Arrangement) -> [CGRect] {
  MainActor.assumeIsolated {
    let screen = NSScreen.screens[0]
    return arrangement.frames(in: screen.visibleFrame).map {
      accessibilityFrame(fromCocoa: $0, primaryScreenHeight: screen.frame.height)
    }
  }
}

/// プロセス pid の最初の窓。
func firstWindow(ofProcess pid: pid_t) -> AXUIElement? {
  var windows: CFTypeRef?
  AXUIElementCopyAttributeValue(
    AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &windows)
  return (windows as? [AXUIElement])?.first
}

/// 名前が name のアプリで、窓を持っているプロセス。
func processes(owningWindowsNamed name: String) -> Set<pid_t> {
  let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
  return Set(
    windows.compactMap { info in
      info[kCGWindowOwnerName as String] as? String == name
        ? info[kCGWindowOwnerPID as String] as? pid_t : nil
    })
}

/// 実際のキーボードと同じ HID の段にキー入力を送る。
func press(_ keyCode: Int, _ flags: CGEventFlags) {
  let source = CGEventSource(stateID: .hidSystemState)
  // 修飾キーの押下と解放も送る。送らないと HID の状態に Control が残り、次の E2E やユーザーの
  // クリックが Ctrl+クリックになる (air-eater の post と同じ)
  let modifiers = modifierKeyCodes(for: flags)
  func flagsChanged(_ code: CGKeyCode, _ flags: CGEventFlags) {
    let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: !flags.isEmpty)
    event?.type = .flagsChanged
    event?.flags = flags
    event?.post(tap: .cghidEventTap)
  }
  for code in modifiers { flagsChanged(code, flags) }
  for keyDown in [true, false] {
    let event = CGEvent(
      keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: keyDown)
    event?.flags = flags
    event?.post(tap: .cghidEventTap)
  }
  for code in modifiers.reversed() { flagsChanged(code, []) }
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
