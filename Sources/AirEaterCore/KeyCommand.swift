import Carbon.HIToolbox
import CoreGraphics

/// Super+キー で呼び出す操作。
public enum Command: Equatable, Sendable {
  case workspace(Int)
  case neighbor(SpacePool.Direction)
  /// 今の workspace に端末を開く。窓が増えるので自動タイルが並べる
  case openTerminal
  /// 新しい workspace を作り、そこに端末を開く
  case newWorkspace
  case tile(Tile)
  /// 今の workspace の窓を、数に合った macOS 標準の配置で並べ直す
  case arrange
  /// フォーカス中の窓を閉じる (Hyprland の killactive)。アプリは終了しない
  case close
  /// フォーカス中の窓を workspace N へ移し、一緒に移る (Hyprland の movetoworkspace)
  case moveToWorkspace(Int)
}

/// 数字以外の Super+キー。hjkl は vim と同じ向き
private let namedCommands: [Int: Command] = [
  kVK_ANSI_LeftBracket: .neighbor(.previous),
  kVK_ANSI_RightBracket: .neighbor(.next),
  kVK_Return: .openTerminal,
  kVK_ANSI_H: .tile(.left),
  kVK_ANSI_J: .tile(.bottom),
  kVK_ANSI_K: .tile(.top),
  kVK_ANSI_L: .tile(.right),
  kVK_ANSI_F: .tile(.fill),
  kVK_ANSI_C: .close,
]

/// Super+Shift+キー。Hyprland でも Shift 付きは「別の場所へ」の操作に当てることが多い
private let shiftedCommands: [Int: Command] = [
  kVK_Return: .newWorkspace
]

/// 押し分けに使う修飾キー。Caps Lock や fn など他のフラグは見ない
private let modifiers: CGEventFlags = [.maskAlternate, .maskCommand, .maskControl, .maskShift]

/// キー入力が air-eater の操作に当たるなら、その操作を返す。
public func command(keyCode: CGKeyCode, flags: CGEventFlags) -> Command? {
  switch flags.intersection(modifiers) {
  case .maskAlternate:
    if let index = digitKeyCodes.firstIndex(of: keyCode) {
      return .workspace(index + 1)
    }
    return namedCommands[Int(keyCode)]
  case [.maskAlternate, .maskShift]:
    if let index = digitKeyCodes.firstIndex(of: keyCode) {
      return .moveToWorkspace(index + 1)
    }
    return shiftedCommands[Int(keyCode)]
  default:
    return nil
  }
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
  /// 形は `workspace <N>` / `move <N>` / `neighbor previous|next` / `terminal` / `new` /
  /// `tile <side>` / `arrange` / `close`
  public init?(parsing line: String) {
    let words = line.split(separator: " ").map(String.init)
    if words.count == 1, let command = singleWordCommands[words[0]] {
      self = command
      return
    }
    switch (words.first, words.dropFirst().first, words.count) {
    case ("workspace", let number?, 2):
      guard let number = Int(number), number >= 1 else { return nil }
      self = .workspace(number)
    case ("move", let number?, 2):
      guard let number = Int(number), number >= 1 else { return nil }
      self = .moveToWorkspace(number)
    case ("neighbor", "previous", 2): self = .neighbor(.previous)
    case ("neighbor", "next", 2): self = .neighbor(.next)
    case ("tile", let side?, 2):
      guard let tile = Tile.allCases.first(where: { "\($0)" == side }) else { return nil }
      self = .tile(tile)
    default: return nil
    }
  }
}

/// 引数を取らない命令。
private let singleWordCommands: [String: Command] = [
  "terminal": .openTerminal,
  "new": .newWorkspace,
  "arrange": .arrange,
  "close": .close,
]
