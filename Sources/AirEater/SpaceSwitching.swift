import AirEaterCore
import AppKit

/// Space 切り替えの完了を待つ上限。アニメーションは 1 秒弱かかる
private let switchTimeout: Duration = .milliseconds(1500)

/// Ctrl+数字 を送って desktop へ切り替え、切り替わるまで待つ。
/// 切り替わらなかった (既にそこにいる、その Desktop が無い、ショートカットが無効) なら false。
@MainActor
func switchDesktop(to desktop: Int) async -> Bool {
  guard let stroke = keyStroke(switchingTo: desktop) else { return false }
  let clock = ContinuousClock()
  let start = clock.now
  let switched = await waitForSpaceChange(timeout: switchTimeout) { post(stroke) }
  let elapsed = (clock.now - start).formatted(.units(allowed: [.milliseconds]))
  log("Ctrl+\(desktop) → \(switched ? "切り替わった" : "切り替わらず") (\(elapsed))")
  return switched
}

/// 通知の購読を始めてから trigger を呼び、次の activeSpaceDidChange を待つ。
/// 先に購読しておかないと、切り替えが速いときに通知を取りこぼす。
@MainActor
func waitForSpaceChange(timeout: Duration, trigger: () -> Void) async -> Bool {
  let center = NSWorkspace.shared.notificationCenter
  return await withCheckedContinuation { continuation in
    let gate = ResumeOnce(continuation)
    let token = center.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
    ) { _ in
      MainActor.assumeIsolated { gate.resume(true) }
    }
    gate.cleanup = { center.removeObserver(token) }
    trigger()
    Task {
      try? await Task.sleep(for: timeout)
      gate.resume(false)
    }
  }
}

/// 通知とタイムアウトのうち先に来た方だけで continuation を再開する。
@MainActor
private final class ResumeOnce {
  private var continuation: CheckedContinuation<Bool, Never>?
  var cleanup: () -> Void = {}

  init(_ continuation: CheckedContinuation<Bool, Never>) {
    self.continuation = continuation
  }

  func resume(_ value: Bool) {
    guard let continuation else { return }
    self.continuation = nil
    cleanup()
    continuation.resume(returning: value)
  }
}
