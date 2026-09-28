import AppKit

/// 新しい workspace で開くアプリ。先に見つかったものを使う
private let terminalBundleIDs = ["com.mitchellh.ghostty", "com.apple.Terminal"]

/// 端末を新しいインスタンスとして起動する。
/// 起動済みのアプリを openApplication すると既存ウィンドウのある Space へ飛ばされるので、
/// 新しいインスタンスにして今いる Space にウィンドウを作らせる
@MainActor
func launchTerminal() async {
  let workspace = NSWorkspace.shared
  guard
    let url = terminalBundleIDs.lazy.compactMap(workspace.urlForApplication(withBundleIdentifier:))
      .first
  else {
    log("端末アプリが見つかりません: \(terminalBundleIDs)")
    return
  }
  let configuration = NSWorkspace.OpenConfiguration()
  configuration.createsNewApplicationInstance = true
  do {
    let app = try await workspace.openApplication(at: url, configuration: configuration)
    log("\(url.lastPathComponent) を新しいインスタンスで起動した (pid \(app.processIdentifier))")
  } catch {
    log("\(url.lastPathComponent) を起動できませんでした: \(error)")
  }
}
