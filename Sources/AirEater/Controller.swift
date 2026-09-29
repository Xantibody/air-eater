import AirEaterCore
import AppKit

/// macOS がショートカットを用意しているのは Desktop 1…9 まで。
/// 実在しない番号は切り替えに失敗するだけなので、プールは常に 1…9 にしておく
private let poolDesktops = 1...9

/// 手で押した Ctrl+数字 と Space の変化を結び付ける猶予。切り替えアニメーションより長く取る
private let manualSwitchWindow: Duration = .milliseconds(1500)

/// Option+キー を受けて、Workspaces を引いて Space を切り替える。
@MainActor
final class Controller {
  private let keyTap = KeyTap()
  private let commandInput = CommandInput()
  private let markers = Markers()
  private let tracker: WindowTracker
  private var refreshTimer: Timer?
  /// 手で押された Ctrl+数字。直後に Space が変われば、そこがその番号の Desktop
  private var pendingSwitch: (desktop: Int, at: ContinuousClock.Instant)?

  init() {
    tracker = WindowTracker(workspaces: Workspaces(desktops: poolDesktops), markers: markers)
  }

  func start() async {
    warnAboutDisabledShortcuts()
    tracker.onWindowCountChanged = { [weak self] desktop, count in
      log("Desktop \(desktop) の窓が \(count) 枚になった")
      self?.arrange(windowCount: count)
    }

    // 現在地はマーカーを置いて初めて分かる。Desktop 1 は必ずあるので、Ctrl+1 を送って
    // 切り替わっても、既に居て切り替わらなくても、その後の Space は Desktop 1 だと決まる
    _ = await switchDesktop(to: 1)
    await markers.placeIfMissing(on: 1)
    tracker.refresh()

    observeWindows()
    commandInput.onCommand = { [weak self] command in
      guard let self else { return }
      Task { await self.perform(command) }
    }
    commandInput.onStatus = { [weak self] in
      guard let self else { return }
      tracker.refresh()
      log("状態 \(tracker.summary)")
    }
    commandInput.start()
    if !startKeyTap() {
      log("キー監視を始められませんでした。アクセシビリティ権限を確認して再起動してください")
    }
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
      MainActor.assumeIsolated { self?.spaceDidChange() }
    }
    // 前面に出たアプリの窓が別の Space にあると、macOS がその Space へ移すことがある。
    // air-eater が送っていない Space の変化の原因を追えるように記録する
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { notification in
      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      log("前面のアプリ → \(app?.localizedName ?? "?")")
    }
    // AIDEV-NOTE: PoC ではウィンドウの生成・破棄を AXObserver で購読せず、1 秒ごとの走査で拾う。
    // 起動直後のウィンドウが workspace に数えられるまで最大 1 秒遅れる
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tracker.refresh() }
    }
  }

  private func spaceDidChange() {
    log("Space が変わった (前面: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"))")
    tracker.noteTransition()
    tracker.refresh()
    guard let pending = pendingSwitch,
      ContinuousClock.now - pending.at < manualSwitchWindow
    else { return }
    pendingSwitch = nil
    // AIDEV-NOTE: 猶予の間に別の理由 (アプリの切り替えなど) で Space が変わると、
    // 違う Space にこの番号のマーカーを置いてしまう。PoC では許容する
    Task {
      await markers.placeIfMissing(on: pending.desktop)
      tracker.refresh()
    }
  }

  // MARK: - 操作

  /// workspace id へ行く。まだ無ければ空き Desktop に作る (Hyprland の `workspace N`)。
  /// 着いたら true。
  @discardableResult
  private func goToWorkspace(_ id: Int) async -> Bool {
    while let target = tracker.workspaces.candidate(for: id) {
      let exists = tracker.workspaces.workspace(on: target) == id
      if exists {
        log("workspace \(id) → Desktop \(target) (\(tracker.workspaces))")
        return await go(to: target)
      }
      log("workspace \(id) を空き候補の Desktop \(target) に作る (\(tracker.workspaces))")
      tracker.assign(id, to: target)
      guard await go(to: target) else {
        tracker.evict(id)
        return false
      }
      // まだ訪れていなかった Desktop には、元から窓があることがある
      guard tracker.workspaces.pool.active.contains(target) else { return true }
      log("Desktop \(target) には元から窓があったので、workspace \(id) は次の候補へ")
      tracker.evict(id)
    }
    log("workspace \(id) を作れる空き Desktop がありません (\(tracker.workspaces))")
    return false
  }

  /// ID 順で隣の workspace へ行く。端では折り返す (Hyprland の `workspace e±1`)。
  private func goToNeighbor(_ direction: SpacePool.Direction) async {
    guard let target = tracker.workspaces.desktop(nextTo: direction) else {
      log("\(direction) → 現在地が workspace でないので移動しない")
      return
    }
    log("\(direction) → Desktop \(target) へ (\(tracker.workspaces))")
    await go(to: target)
  }

  /// 使われていない一番小さい ID の workspace を作り、そこで端末を開く。
  private func openNewWorkspace() async {
    let id = tracker.workspaces.lowestFreeID
    log("新しい workspace \(id) を作る")
    guard await goToWorkspace(id) else { return }
    await launchTerminal()
  }

  /// desktop へ切り替え、初めて来た Desktop ならマーカーを置く。着けなければ false。
  @discardableResult
  private func go(to desktop: Int) async -> Bool {
    let origin = tracker.current
    guard origin != desktop else {
      log("既に Desktop \(desktop) にいる")
      return true
    }
    tracker.noteTransition()
    guard await switchDesktop(to: desktop) else {
      // 今いる Desktop が分からないときは、既に desktop に居て切り替わらなかった可能性もある。
      // そのときはマーカーを置かず、報告もしない
      if origin != nil {
        log("Desktop \(desktop) に切り替えられませんでした。Desktop が無いか Ctrl+\(desktop) が無効です")
      }
      return false
    }
    await markers.placeIfMissing(on: desktop)
    // 着いた Desktop に窓があるかは、移動が落ち着いてからでないと正しく見えない
    await tracker.refreshAfterSettling()
    return true
  }

  // MARK: - キー入力

  private func startKeyTap() -> Bool {
    keyTap.onCommand = { [weak self] command in
      guard let self else { return }
      log("\(command) が押された")
      Task { await self.perform(command) }
    }
    keyTap.onDesktopSwitchKey = { [weak self] desktop in
      log("Ctrl+\(desktop) を検知")
      self?.pendingSwitch = (desktop, .now)
    }
    return keyTap.start()
  }

  private func perform(_ command: Command) async {
    switch command {
    case .workspace(let workspace): await goToWorkspace(workspace)
    case .neighbor(let direction): await goToNeighbor(direction)
    case .openTerminal:
      log("今の workspace に端末を開く")
      await launchTerminal()
    case .newWorkspace: await openNewWorkspace()
    case .tile(let tile): tileFocusedWindow(tile)
    case .arrange: arrangeCurrentWorkspace()
    case .close: closeFocusedWindow()
    }
  }

  // MARK: - 自動タイル

  /// 今の workspace の窓を、数に合った macOS 標準の配置で並べる。
  private func arrangeCurrentWorkspace() {
    tracker.refresh()
    guard let count = tracker.visibleWindowCount else {
      log("arrange → 今の Space の窓の数が分からない")
      return
    }
    arrange(windowCount: count)
  }

  private func arrange(windowCount count: Int) {
    guard let arrangement = Arrangement(windowCount: count) else {
      log("arrange → 窓 \(count) 枚に合う標準の配置が無いので並べない")
      return
    }
    log("arrange → 窓 \(count) 枚なので \(arrangement)")
    arrangeFrontmost(arrangement)
  }
}
