import AirEaterCore
import AppKit
import Carbon.HIToolbox

/// Hyprland の Super に当たる修飾キー。
/// Cmd+数字 はブラウザのタブ切り替えなど多くのアプリと衝突するので Option にしている
private let superModifier = UInt32(optionKey)

/// macOS がショートカットを用意しているのは Desktop 1…9 まで
private let poolLimit = 9

/// ホットキーを受けて、SpacePool を引いて Space を切り替える。
@MainActor
final class Controller {
  private let hotKeys = HotKeyCenter()
  private let markers = Markers()
  private var tracker: WindowTracker?
  private var refreshTimer: Timer?

  func start() async {
    let seen = await markers.install(upTo: poolLimit)
    var pool = SpacePool(desktops: seen.keys.sorted())
    for (desktop, windows) in seen {
      pool.observe(desktop: desktop, windows: windows)
    }
    let tracker = WindowTracker(pool: pool, markers: markers.ids)
    self.tracker = tracker
    print("air-eater: Desktop \(pool.desktops) をプールにしました。workspace は \(pool.active)")
    if pool.desktops.count < poolLimit {
      print("air-eater: Desktop が \(poolLimit) 個ありません。Desktop を増やすか Ctrl+数字 のショートカットを有効にしてください")
    }

    // 起動前にいた Desktop は分からない (現在地はマーカーを置いて初めて分かる) ので、最初の workspace に戻る
    _ = await switchDesktop(to: pool.active.first ?? 1)

    observeWindows()
    registerHotKeys()
    print("air-eater: 準備できました")
  }

  // MARK: - 観測

  private func observeWindows() {
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.tracker?.refresh() }
    }
    // AIDEV-NOTE: PoC ではウィンドウの生成・破棄を AXObserver で購読せず、1 秒ごとの走査で拾う。
    // 起動直後のウィンドウが workspace に数えられるまで最大 1 秒遅れる
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tracker?.refresh() }
    }
  }

  // MARK: - 操作

  private func goToWorkspace(_ workspace: Int) async {
    guard let tracker, let target = tracker.pool.desktop(forWorkspace: workspace) else { return }
    await go(to: target)
  }

  private func goToNeighbor(_ direction: SpacePool.Direction) async {
    guard let tracker, let current = tracker.current,
      let target = tracker.pool.desktop(nextTo: current, direction: direction)
    else { return }
    await go(to: target)
  }

  private func openNewWorkspace() async {
    guard let tracker else { return }
    tracker.refresh()
    guard let target = tracker.pool.firstEmpty else {
      print("air-eater: 空いている Desktop がありません")
      return
    }
    await go(to: target)
    await launchTerminal()
  }

  private func go(to desktop: Int) async {
    guard tracker?.current != desktop else { return }
    _ = await switchDesktop(to: desktop)
    tracker?.refresh()
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
    for (keyCode, tile) in tiles {
      bind(CGKeyCode(keyCode), "\(tile)") { _ in tileFocusedWindow(tile) }
    }
  }

  private func bind(
    _ keyCode: CGKeyCode, _ name: String, _ action: @escaping @MainActor (Controller) async -> Void
  ) {
    do {
      try hotKeys.register(keyCode: UInt32(keyCode), modifiers: superModifier) { [weak self] in
        guard let self else { return }
        Task { await action(self) }
      }
    } catch {
      print("air-eater: Option+\(name) を登録できませんでした: \(error)")
    }
  }
}
