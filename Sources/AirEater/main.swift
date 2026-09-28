import AirEaterCore
import AppKit
import Carbon.HIToolbox

/// Hyprland の Super に当たる修飾キー。
/// Cmd+数字 はブラウザのタブ切り替えなど多くのアプリと衝突するので Option にしている
let superModifier = UInt32(optionKey)

let app = NSApplication.shared
// Dock にもアプリ切り替えにも出さない常駐プロセスにする
app.setActivationPolicy(.accessory)

if !requestAccessibilityPermission() {
  print("air-eater: アクセシビリティ権限がありません。システム設定で許可してから再起動してください")
}

let hotKeys = HotKeyCenter()
for desktop in 1...digitKeyCodes.count {
  guard let stroke = keyStroke(switchingTo: desktop) else { continue }
  do {
    try hotKeys.register(keyCode: UInt32(stroke.keyCode), modifiers: superModifier) {
      post(stroke)
    }
  } catch {
    print("air-eater: Super+\(desktop) を登録できませんでした: \(error)")
  }
}

print("air-eater: 起動しました (Option+1…9 で Desktop 切り替え)")
app.run()
