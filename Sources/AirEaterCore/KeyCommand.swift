import Carbon.HIToolbox
import CoreGraphics

/// Super+キー で呼び出す操作。
public enum Command: Equatable, Sendable {
  case workspace(Int)
  case neighbor(SpacePool.Direction)
  case newWorkspace
  case tile(Tile)
}

/// 数字以外の Super+キー。hjkl は vim と同じ向き
private let namedCommands: [Int: Command] = [
  kVK_ANSI_LeftBracket: .neighbor(.previous),
  kVK_ANSI_RightBracket: .neighbor(.next),
  kVK_Return: .newWorkspace,
  kVK_ANSI_H: .tile(.left),
  kVK_ANSI_J: .tile(.bottom),
  kVK_ANSI_K: .tile(.top),
  kVK_ANSI_L: .tile(.right),
]

/// 押し分けに使う修飾キー。Caps Lock や fn など他のフラグは見ない
private let modifiers: CGEventFlags = [.maskAlternate, .maskCommand, .maskControl, .maskShift]

/// キー入力が air-eater の操作に当たるなら、その操作を返す。
public func command(keyCode: CGKeyCode, flags: CGEventFlags) -> Command? {
  guard flags.intersection(modifiers) == .maskAlternate else { return nil }
  if let index = digitKeyCodes.firstIndex(of: keyCode) {
    return .workspace(index + 1)
  }
  return namedCommands[Int(keyCode)]
}

/// キー入力が Mission Control の「デスクトップ N へ切り替え」(Ctrl+N) なら N を返す。
/// air-eater を通さずに手で切り替えたときも、行き先の番号をここから知る。
public func desktopSwitched(keyCode: CGKeyCode, flags: CGEventFlags) -> Int? {
  guard flags.intersection(modifiers) == .maskControl,
    let index = digitKeyCodes.firstIndex(of: keyCode)
  else { return nil }
  return index + 1
}

extension Command {
  /// テストや外部からの操作用に、1 行の文字列から操作を読む。
  /// 形は `workspace <N>` / `neighbor previous|next` / `new` / `tile left|bottom|top|right`
  public init?(parsing line: String) {
    let words = line.split(separator: " ").map(String.init)
    switch (words.first, words.dropFirst().first, words.count) {
    case ("workspace", let number?, 2):
      guard let number = Int(number), number >= 1 else { return nil }
      self = .workspace(number)
    case ("neighbor", "previous", 2): self = .neighbor(.previous)
    case ("neighbor", "next", 2): self = .neighbor(.next)
    case ("new", nil, 1): self = .newWorkspace
    case ("tile", let side?, 2):
      guard let tile = Tile.allCases.first(where: { "\($0)" == side }) else { return nil }
      self = .tile(tile)
    default: return nil
    }
  }
}
