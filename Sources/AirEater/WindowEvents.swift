import AppKit
import ApplicationServices

/// 窓の生成・破棄・最小化とアプリの起動・終了を、観測し直す引き金にする。
/// AXObserver の通知は欠けることがある (Electron、起動直後のアプリ) ので、これだけに頼らず、
/// Controller の定期的な走査を保険として残す。通知は「今すぐ走査する理由」でしかない
@MainActor
final class WindowEvents {
  /// 窓の様子が変わったらしい。少し置いて 1 回だけ呼ぶ
  var onChange: () -> Void = {}

  private var observers: [pid_t: AXObserver] = [:]
  private var pending: Task<Void, Never>?

  func start() {
    for app in NSWorkspace.shared.runningApplications { observe(pid: app.processIdentifier) }
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(
      forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
    ) { [weak self] notification in
      // Notification は Sendable でないので、pid だけを MainActor の中へ持ち込む
      let pid = notification.runningApplication?.processIdentifier
      MainActor.assumeIsolated {
        if let pid { self?.observe(pid: pid) }
        self?.changed("アプリの起動")
      }
    }
    center.addObserver(
      forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
    ) { [weak self] notification in
      let pid = notification.runningApplication?.processIdentifier
      MainActor.assumeIsolated {
        if let pid { self?.observers[pid] = nil }
        self?.changed("アプリの終了")
      }
    }
    // 起動時には通常のアプリでなかったプロセス (後から窓を出すコマンドラインのプロセスなど) は、
    // 前面になったときに購読を試みる。前面化そのものも観測し直す理由になる
    center.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] notification in
      let pid = notification.runningApplication?.processIdentifier
      MainActor.assumeIsolated {
        if let pid { self?.observe(pid: pid) }
        self?.changed("アプリの前面化")
      }
    }
    for name in [
      NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
    ] {
      center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.changed("アプリの表示・非表示") }
      }
    }
  }

  /// 通知を受けてから少し置いて onChange を 1 回呼ぶ。窓を作った直後は CGWindowList にまだ載って
  /// いないことがあり、また 1 つの操作で通知が続けて来るので、まとめる
  private func changed(_ reason: String) {
    guard pending == nil else { return }
    pending = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(80))
      guard let self else { return }
      pending = nil
      onChange()
    }
  }

  /// 起動直後のアプリは AX の準備ができておらず、登録が cannotComplete で失敗する。
  /// Amethyst と同じく、間を空けて数回やり直す
  private static let retryDelays: [Duration] = [
    .milliseconds(100), .milliseconds(400), .milliseconds(900), .milliseconds(1600),
    .milliseconds(2500),
  ]

  private func observe(pid: pid_t, attempt: Int = 0) {
    guard pid > 0, pid != getpid(), observers[pid] == nil,
      let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular
    else { return }
    var observer: AXObserver?
    guard AXObserverCreate(pid, windowEventCallback, &observer) == .success, let observer else {
      return
    }
    let element = AXUIElementCreateApplication(pid)
    let context = Unmanaged.passUnretained(self).toOpaque()
    let errors = Self.notifications.map {
      AXObserverAddNotification(observer, element, $0 as CFString, context)
    }
    if errors.contains(.cannotComplete) {
      guard attempt < Self.retryDelays.count else {
        log("\(app.localizedName ?? "?") の窓の通知を購読できなかった。走査だけで追う")
        return
      }
      Task { [weak self] in
        try? await Task.sleep(for: Self.retryDelays[attempt])
        self?.observe(pid: pid, attempt: attempt + 1)
      }
      return
    }
    CFRunLoopAddSource(
      CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), CFRunLoopMode.defaultMode)
    observers[pid] = observer
  }

  private static let notifications = [
    kAXWindowCreatedNotification, kAXUIElementDestroyedNotification,
    kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
  ]

  fileprivate func received(_ notification: String) {
    changed(notification)
  }
}

/// AXObserver の C のコールバック。クロージャは何も捕まえられないので、refcon から WindowEvents を戻す
private let windowEventCallback: AXObserverCallback = { _, _, notification, context in
  guard let context else { return }
  let name = notification as String
  // MainActor に隔離されたクラスは Sendable なので、ポインタでなく参照を閾の中へ渡す
  let events = Unmanaged<WindowEvents>.fromOpaque(context).takeUnretainedValue()
  MainActor.assumeIsolated { events.received(name) }
}

extension Notification {
  fileprivate var runningApplication: NSRunningApplication? {
    userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
  }
}
