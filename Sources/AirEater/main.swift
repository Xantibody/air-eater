import AppKit

let app = NSApplication.shared
// Dock にもアプリ切り替えにも出さない常駐プロセスにする
app.setActivationPolicy(.accessory)

if !requestAccessibilityPermission() {
  log("アクセシビリティ権限がありません。システム設定で許可してから再起動してください")
}
// 「最新の使用状況に基づいて操作スペースを並べ替える」が ON だと物理 Desktop 番号が裏で入れ替わる。
// キーが無いときは既定の ON
if UserDefaults(suiteName: "com.apple.dock")?.object(forKey: "mru-spaces") as? Bool ?? true {
  log("システム設定 ▸ デスクトップと Dock ▸「最新の使用状況に基づいて操作スペースを並べ替える」を OFF にしてください")
}

let controller = Controller()
Task { await controller.start() }
app.run()
