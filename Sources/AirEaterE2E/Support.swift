import AirEaterCore
import AppKit
import ApplicationServices
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
