import CoreGraphics

/// 画面に写っているウィンドウからマーカーを探し、今表示している物理 Desktop を返す。
/// マーカーの居ない Space (ネイティブのフルスクリーンなど) はプール外なので nil。
/// マーカーが 2 つ以上写っているとき (Mission Control のように全 Space を重ねて見せている間) も、
/// どれが今の Desktop か決められないので nil
public func currentDesktop(markers: [Int: CGWindowID], onScreen: Set<CGWindowID>) -> Int? {
  let visible = markers.filter { onScreen.contains($0.value) }
  return visible.count == 1 ? visible.first?.key : nil
}
