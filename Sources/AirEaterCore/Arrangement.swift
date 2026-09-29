/// 窓の数に合わせて使う、macOS 標準の配置 (ウインドウ ▸ 移動とサイズ変更)。
/// 自前で frame を計算せず、各アプリのメニューにある標準の機能を押す。
public enum Arrangement: Equatable, Sendable {
  /// 画面全体に表示
  case fill
  /// 配置 ▸ 左と右
  case leftAndRight
  /// 配置 ▸ 左と4分割
  case leftAndQuarters
  /// 配置 ▸ 4分割
  case quarters

  public init?(windowCount: Int) {
    switch windowCount {
    case 1: self = .fill
    case 2: self = .leftAndRight
    case 3: self = .leftAndQuarters
    case 4: self = .quarters
    default: return nil
    }
  }
}

/// メニュー項目のショートカット (AXMenuItemCmdChar / CmdVirtualKey / CmdModifiers)。
/// AXMenuItemCmdModifiers は 1 = Shift、2 = Option、4 = Control、8 = Cmd なし、16 = fn を足した値
public struct MenuShortcut: Equatable, Sendable {
  public let character: String?
  public let virtualKey: Int?
  public let modifiers: Int

  public init(character: String? = nil, virtualKey: Int? = nil, modifiers: Int) {
    self.character = character
    self.virtualKey = virtualKey
    self.modifiers = modifiers
  }
}

extension Arrangement {
  /// 1 つのメニューの項目の並び (ショートカットの無い項目は nil) から、押す項目の位置を探す。
  public func index(in menu: [MenuShortcut?]) -> Int? {
    switch self {
    case .fill: menu.firstIndex(of: Self.fillShortcut)
    case .leftAndRight: menu.firstIndex(of: MenuShortcut(virtualKey: kLeftArrow, modifiers: 29))
    case .leftAndQuarters:
      menu.firstIndex(of: MenuShortcut(virtualKey: kLeftArrow, modifiers: 31))
    case .quarters:
      // ショートカットが無いので、直前の「下と4分割」(Fn+Ctrl+Shift+Option+↓) を目印にする
      menu.firstIndex(of: MenuShortcut(virtualKey: kDownArrow, modifiers: 31))
        .map { $0 + 1 }
        .flatMap { menu.indices.contains($0) ? $0 : nil }
    }
  }

  /// 画面全体に表示 (Fn+Ctrl+F)
  private static let fillShortcut = MenuShortcut(character: "F", modifiers: 28)
}

private let kLeftArrow = 123
private let kDownArrow = 125
