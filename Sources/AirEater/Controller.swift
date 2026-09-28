import AirEaterCore
import AppKit
import Carbon.HIToolbox

/// Hyprland の Super に当たる修飾キー。
/// Cmd+数字 はブラウザのタブ切り替えなど多くのアプリと衝突するので Option にしている
private let superModifier = UInt32(optionKey)

/// macOS がショートカットを用意しているのは Desktop 1…9 まで。
/// 実在しない番号は切り替えに失敗するだけなので、プールは常に 1…9 にしておく
private let poolDesktops = 1...9

/// ホットキーを受けて、SpacePool を引いて Space を切り替える。
@MainActor
final class Controller {
  private let hotKeys = HotKeyCenter()
  private let markers = Markers()
  private let tracker: WindowTracker
  private var refreshTimer: Timer?

  init() {
    tracker = WindowTracker(pool: SpacePool(desktops: poolDesktops), markers: markers)
  }

  func start() async {
    warnAboutDisabledShortcuts()

    // 現在地はマーカーを置いて初めて分かる。Desktop 1 は必ずあるので、Ctrl+1 を送って
    // 切り替わっても、既に居て切り替わらなくても、その後の Space は Desktop 1 だと決まる
    _ = await switchDesktop(to: 1)
    await markers.placeIfMissing(on: 1)
    tracker.refresh()

    observeWindows()
    registerHotKeys()
    log("準備できました")
  }

  private func warnAboutDisabledShortcuts() {
    let symbolicHotKeys =
      UserDefaults(suiteName: "com.apple.symbolichotkeys")?
      .dictionary(forKey: "AppleSymbolicHotKeys") ?? [:]
    let enabled = desktopsWithEnabledShortcut(symbolicHotKeys: symbolicHotKeys)
    let disabled = poolDesktops.filter { !enabled.contains($0) }
    guard !disabled.isEmpty else { return }
    log(
      "Ctrl+\(disabled.map(String.init).joined(separator: ",")) が無効です。"
        + "システム設定 ▸ キーボード ▸ キーボードショートカット ▸ Mission Control で有効にしてください"
        + " (Desktop が足りないと項目自体が出ません)")
  }

  // MARK: - 観測

  private func observeWindows() {
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        log("Space が変わった")
        self?.tracker.refresh()
      }
    }
    // AIDEV-NOTE: PoC ではウィンドウの生成・破棄を AXObserver で購読せず、1 秒ごとの走査で拾う。
    // 起動直後のウィンドウが workspace に数えられるまで最大 1 秒遅れる
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tracker.refresh() }
    }
  }

  // MARK: - 操作

  private func goToWorkspace(_ workspace: Int) async {
    let active = tracker.pool.active
    guard let target = tracker.pool.desktop(forWorkspace: workspace) else {
      log("workspace \(workspace) → 行き先なし (active=\(active))")
      return
    }
    let kind = workspace <= active.count ? "" : " (workspace 数を超えたので空き候補)"
    log("workspace \(workspace) → Desktop \(target)\(kind) (active=\(active))")
    await go(to: target)
  }

  private func goToNeighbor(_ direction: SpacePool.Direction) async {
    guard let current = tracker.current else {
      log("\(direction) → 現在地が不明なので移動しない")
      return
    }
    guard let target = tracker.pool.desktop(nextTo: current, direction: direction) else {
      log("\(direction) → Desktop \(current) の先に workspace なし (active=\(tracker.pool.active))")
      return
    }
    log("\(direction) → Desktop \(current) から Desktop \(target) へ")
    await go(to: target)
  }

  /// 空き候補の Desktop へ行き、空だったら端末を開く。
  /// まだ訪れていない Desktop も空き候補に入るので、着いて窓があれば次の候補へ進む
  private func openNewWorkspace() async {
    tracker.refresh()
    while let target = tracker.pool.firstEmpty {
      log("新しい workspace → 空き候補 Desktop \(target)")
      guard await go(to: target) else { return }
      if !tracker.pool.active.contains(target) {
        await launchTerminal()
        return
      }
      log("Desktop \(target) には窓があったので次の候補へ")
    }
    log("空いている Desktop がありません")
  }

  /// desktop へ切り替え、初めて来た Desktop ならマーカーを置く。着けなければ false。
  @discardableResult
  private func go(to desktop: Int) async -> Bool {
    let origin = tracker.current
    guard origin != desktop else {
      log("既に Desktop \(desktop) にいる")
      return true
    }
    guard await switchDesktop(to: desktop) else {
      // 今いる Desktop が分からないときは、既に desktop に居て切り替わらなかった可能性もある。
      // そのときはマーカーを置かず、報告もしない
      if origin != nil {
        log("Desktop \(desktop) に切り替えられませんでした。Desktop が無いか Ctrl+\(desktop) が無効です")
      }
      return false
    }
    await markers.placeIfMissing(on: desktop)
    tracker.refresh()
    return true
  }

  // MARK: - ホットキー

  private func registerHotKeys() {
    for workspace in 1...digitKeyCodes.count {
      bind(digitKeyCodes[workspace - 1], "\(workspace)") { await $0.goToWorkspace(workspace) }
    }
    bind(CGKeyCode(kVK_ANSI_LeftBracket), "[") { await $0.goToNeighbor(.previous) }
    bind(CGKeyCode(kVK_ANSI_RightBracket), "]") { await $0.goToNeighbor(.next) }
    bind(CGKeyCode(kVK_Return), "Return") { await $0.openNewWorkspace() }
    // vim の hjkl と同じ向き
    let tiles: [(Int, Tile)] = [
      (kVK_ANSI_H, .left), (kVK_ANSI_J, .bottom), (kVK_ANSI_K, .top), (kVK_ANSI_L, .right),
    ]
    let letters: [Tile: String] = [.left: "H", .bottom: "J", .top: "K", .right: "L"]
    for (keyCode, tile) in tiles {
      bind(CGKeyCode(keyCode), letters[tile] ?? "\(tile)") { _ in tileFocusedWindow(tile) }
    }
  }

  private func bind(
    _ keyCode: CGKeyCode, _ name: String, _ action: @escaping @MainActor (Controller) async -> Void
  ) {
    do {
      try hotKeys.register(keyCode: UInt32(keyCode), modifiers: superModifier) { [weak self] in
        guard let self else { return }
        log("Option+\(name) が押された")
        Task { await action(self) }
      }
    } catch {
      log("Option+\(name) を登録できませんでした: \(error)")
    }
  }
}
