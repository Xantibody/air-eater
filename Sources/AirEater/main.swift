import AppKit

let app = NSApplication.shared
// Dock にもアプリ切り替えにも出さない常駐プロセスにする
app.setActivationPolicy(.accessory)

if !requestAccessibilityPermission() {
  log("アクセシビリティ権限がありません。システム設定で許可してから再起動してください")
}
// 「最新の使用状況に基づいて操作スペースを並べ替える」が ON だと物理 Desktop 番号が裏で入れ替わる。
// キーが無いときは既定の ON
let dock = UserDefaults(suiteName: "com.apple.dock")
if dock?.object(forKey: "mru-spaces") as? Bool ?? true {
  log("システム設定 ▸ デスクトップと Dock ▸「最新の使用状況に基づいて操作スペースを並べ替える」を OFF にしてください")
}
// これが ON だと、空の Desktop に着いたとき前面になった別のアプリ (実機では隣の全画面 ChatGPT) の
// Space へ macOS が移してしまう。キーが無いときは既定の ON
if dock?.object(forKey: "workspaces-auto-swoosh") as? Bool ?? true {
  log("システム設定 ▸ デスクトップと Dock ▸「アプリケーションの切り替えで、アプリケーションのウインドウが開いている操作スペースに移動」を OFF にしてください")
}

let controller = Controller()
Task { await controller.start() }
app.run()
