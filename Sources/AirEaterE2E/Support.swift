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

/// Finder の窓のうち、タイトルが title のもの。
func finderWindow(titled title: String) -> AXUIElement? {
  guard
    let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
      .first
  else { return nil }
  var windows: CFTypeRef?
  AXUIElementCopyAttributeValue(
    AXUIElementCreateApplication(finder.processIdentifier), kAXWindowsAttribute as CFString,
    &windows)
  return (windows as? [AXUIElement])?.first { window in
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value)
    return value as? String == title
  }
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
