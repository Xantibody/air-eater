import CoreGraphics

/// 画面に写っているウィンドウからマーカーを探し、今表示している物理 Desktop を返す。
/// マーカーの居ない Space (ネイティブのフルスクリーンなど) はプール外なので nil。
public func currentDesktop(markers: [Int: CGWindowID], onScreen: Set<CGWindowID>) -> Int? {
  markers.first { onScreen.contains($0.value) }?.key
}
