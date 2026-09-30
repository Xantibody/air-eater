import AirEaterCore
import AppKit

/// 今の Desktop で、direction の向きにある窓にフォーカスを移す (Hyprland の movefocus)。
/// 窓の位置は CGWindowList から取る (一番手前の窓がフォーカス中)。選んだ窓を AX で手前に出し、
/// そのアプリを前面にする。別のアプリの窓でも構わない
@MainActor
func moveFocus(_ direction: FocusDirection) {
  let entries = managedWindowEntries(
    in: windowList(.optionOnScreenOnly), excludingProcess: getpid())
  guard let focused = entries.first else {
    log("focus → 今の Desktop に窓が無い")
    return
  }
  let others = Array(entries.dropFirst())
  guard let index = direction.neighbor(of: focused.bounds, among: others.map(\.bounds)) else {
    log("focus → \(direction) に窓が無い")
    return
  }
  let target = others[index]
  let sameApp = entries.filter { $0.pid == target.pid && $0.id != target.id }
  guard let window = axWindow(matching: target, among: sameApp, excluding: []) else {
    log("focus → 窓 \(target.id) に当たる AX の窓が見つからない")
    return
  }
  let raised = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
  // macOS 14 以降、前面化は「要求」で断られることがある。断られたらログに残す
  let activated = NSRunningApplication(processIdentifier: target.pid)?.activate() ?? false
  log(
    "focus → \(direction) の窓 \(target.id) を手前に出した"
      + " (AXRaise \(raised.rawValue)、activate \(activated))")
}
