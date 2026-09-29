import AirEaterCore
import AppKit

/// 前面のアプリの「ウインドウ」メニューにある macOS 標準の配置を AX で押す。
/// 合成したショートカット (Fn+Ctrl+Shift+← など) は実機で効かなかったので、メニュー項目を直接押す。
/// 標準のウインドウメニューを持たないアプリでは何もできない
@MainActor
@discardableResult
func arrangeFrontmost(_ arrangement: Arrangement) -> Bool {
  guard let frontmost = NSWorkspace.shared.frontmostApplication else {
    log("\(arrangement) → 前面のアプリが無い")
    return false
  }
  let appName = frontmost.localizedName ?? "?"
  let app = AXUIElementCreateApplication(frontmost.processIdentifier)
  guard case .success(let menuBar) = element(app, kAXMenuBarAttribute) else {
    log("\(arrangement) → \(appName) のメニューバーが読めない")
    return false
  }
  // 項目の多いメニュー (履歴、ブックマーク) の奥まで探さないよう、まず「画面全体に表示」を
  // 持つメニュー (= ウインドウメニュー) を見つけ、その中と 1 段下のサブメニューだけを探す
  let menus = children(of: menuBar).flatMap { children(of: $0) }
  guard
    let windowMenu = menus.first(where: { Arrangement.fill.index(in: shortcuts(in: $0)) != nil })
  else {
    log("\(arrangement) → \(appName) に標準のウインドウメニューが無い")
    return false
  }
  let candidates = [windowMenu] + children(of: windowMenu).flatMap { children(of: $0) }
  for menu in candidates {
    let items = children(of: menu)
    guard let index = arrangement.index(in: items.map(shortcut(of:))) else { continue }
    let error = AXUIElementPerformAction(items[index], kAXPressAction as CFString)
    log("\(arrangement) → \(appName) のメニューを押した (AXError \(error.rawValue))")
    return error == .success
  }
  log("\(arrangement) → \(appName) のウインドウメニューに該当する配置が無い")
  return false
}

private func shortcuts(in menu: AXUIElement) -> [MenuShortcut?] {
  children(of: menu).map(shortcut(of:))
}

private func shortcut(of item: AXUIElement) -> MenuShortcut? {
  let character = attribute(item, kAXMenuItemCmdCharAttribute, as: String.self)
  let virtualKey = attribute(item, kAXMenuItemCmdVirtualKeyAttribute, as: Int.self)
  guard character != nil || virtualKey != nil else { return nil }
  let modifiers = attribute(item, kAXMenuItemCmdModifiersAttribute, as: Int.self) ?? 0
  return MenuShortcut(character: character, virtualKey: virtualKey, modifiers: modifiers)
}
