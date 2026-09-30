import AirEaterCore
import AppKit

/// 標準のウインドウメニューを持たないアプリの窓を、純正の配置と同じ形の自前の frame で並べる。
/// 今の Desktop に写っている窓を手前から順に取り、CGWindowList の位置と一致する AX の窓に書き込む。
/// 純正の配置が押せたときは使わない (Controller が先に arrangeFrontmost を試す)
@MainActor
func arrangeByFrames(_ arrangement: Arrangement) {
  let entries = managedWindowEntries(
    in: windowList(.optionOnScreenOnly), excludingProcess: getpid())
  guard let primary = NSScreen.screens.first else { return }
  let screen =
    entries.first.flatMap {
      screen(containingAXFrame: $0.bounds, primaryHeight: primary.frame.height)
    } ?? primary
  let frames = arrangement.frames(in: screen.visibleFrame).map {
    accessibilityFrame(fromCocoa: $0, primaryScreenHeight: primary.frame.height)
  }
  guard entries.count == frames.count else {
    log("\(arrangement) → 窓が \(entries.count) 枚で配置の \(frames.count) 枚と合わないので自前では並べない")
    return
  }

  var used: [AXUIElement] = []
  for (entry, frame) in zip(entries, frames) {
    let others = entries.filter { $0.pid == entry.pid && $0.id != entry.id }
    guard let window = axWindow(matching: entry, among: others, excluding: used) else {
      log("\(arrangement) → 窓 \(entry.id) に当たる AX の窓が見つからない")
      continue
    }
    used.append(window)
    // 最小サイズを持つアプリのために、半分割と同じ size → position → size の順で書く
    let results = [
      set(window, kAXSizeAttribute, frame.size),
      set(window, kAXPositionAttribute, frame.origin),
      set(window, kAXSizeAttribute, frame.size),
    ]
    if let failure = results.first(where: { $0 != .success }) {
      log("\(arrangement) → 窓 \(entry.id) の frame を書けなかった (AXError \(failure.rawValue))")
    }
  }
  log("\(arrangement) → 自前の frame で \(entries.count) 枚を並べた")
}

/// entry に当たる、そのプロセスの AX の窓。
/// AX の窓と CGWindowList の窓を結ぶ公開 API は無いので、frame の一致で結ぶ。
/// 同じ frame の窓が 2 つあるときのために、既に使った窓は除く。
/// 作られた直後の窓は CGWindowList の位置がまだ古いことがあり一致しないので、そのときは
/// 同じプロセスの他の窓 (others) に当たらない候補が 1 つだけならそれにする
func axWindow(
  matching entry: WindowEntry, among others: [WindowEntry], excluding used: [AXUIElement]
) -> AXUIElement? {
  let app = AXUIElementCreateApplication(entry.pid)
  guard let windows = attribute(app, kAXWindowsAttribute, as: [AXUIElement].self) else {
    return nil
  }
  let candidates = windows.filter { window in !used.contains { CFEqual($0, window) } }
    .compactMap { window in axFrame(of: window).map { (window: window, frame: $0) } }
  if let exact = candidates.first(where: { nearlyEqual($0.frame, entry.bounds) }) {
    return exact.window
  }
  let unclaimed = candidates.filter { candidate in
    !others.contains { nearlyEqual(candidate.frame, $0.bounds) }
  }
  return unclaimed.count == 1 ? unclaimed[0].window : nil
}

private func axFrame(of window: AXUIElement) -> CGRect? {
  guard let origin: CGPoint = value(window, kAXPositionAttribute, .cgPoint, .zero),
    let size: CGSize = value(window, kAXSizeAttribute, .cgSize, .zero)
  else { return nil }
  return CGRect(origin: origin, size: size)
}

/// 座標の丸めで 1〜2 pt ずれることがあるので、それは同じとみなす
private func nearlyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
  abs(lhs.minX - rhs.minX) <= 2 && abs(lhs.minY - rhs.minY) <= 2
    && abs(lhs.width - rhs.width) <= 2 && abs(lhs.height - rhs.height) <= 2
}
