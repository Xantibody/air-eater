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
    print("air-eater: 端末アプリが見つかりません: \(terminalBundleIDs)")
    return
  }
  let configuration = NSWorkspace.OpenConfiguration()
  configuration.createsNewApplicationInstance = true
  do {
    _ = try await workspace.openApplication(at: url, configuration: configuration)
  } catch {
    print("air-eater: \(url.lastPathComponent) を起動できませんでした: \(error)")
  }
}
