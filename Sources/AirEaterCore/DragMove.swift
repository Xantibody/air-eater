import CoreGraphics

/// 窓を掴む場所。frame は AX 座標 (左上原点) で、タイトルバーの中央、上端から 12 pt。
/// 左端の信号機ボタンの上で押すと窓が動かないので、横方向は中央にする。
/// タブをタイトルバーに出すアプリ (Chrome) では、ここがタブに当たることがある
public func dragGrabPoint(in frame: CGRect) -> CGPoint {
  CGPoint(x: frame.midX, y: frame.minY + 12)
}
