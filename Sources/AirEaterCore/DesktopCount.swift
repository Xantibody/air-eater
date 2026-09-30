/// com.apple.spaces の SpacesDisplayConfiguration から、主画面にある通常の Desktop の数を読む。
/// 全画面アプリの Space (type 4) は数えない。読めなければ nil
public func desktopCount(inSpacesConfiguration configuration: [String: Any]) -> Int? {
  let display = configuration["SpacesDisplayConfiguration"] as? [String: Any]
  let management = display?["Management Data"] as? [String: Any]
  let monitors = management?["Monitors"] as? [[String: Any]] ?? []
  // 表示装置ごとの項目のうち、主画面は "Main"。Spaces を持たない項目も混ざる
  guard
    let main = monitors.first(where: { $0["Display Identifier"] as? String == "Main" }),
    let spaces = main["Spaces"] as? [[String: Any]]
  else { return nil }
  return spaces.filter { $0["type"] as? Int == ordinaryDesktopType }.count
}

/// 通常の Desktop の type。全画面アプリの Space は 4
private let ordinaryDesktopType = 0
