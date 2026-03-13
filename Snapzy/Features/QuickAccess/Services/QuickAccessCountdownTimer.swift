//
//  QuickAccessCountdownTimer.swift
//  Snapzy
//
//  Pausable countdown timer for Quick Access card auto-dismiss
//

import Foundation

/// A pausable countdown timer that tracks remaining time accurately using ContinuousClock.
@MainActor
final class QuickAccessCountdownTimer {

  private var remainingTime: TimeInterval
  private var startedAt: ContinuousClock.Instant?
  private var task: Task<Void, Never>?
  private var onExpire: (() -> Void)?

  private(set) var isPaused: Bool = false
  var isRunning: Bool { task != nil && !isPaused }

  init(duration: TimeInterval, onExpire: @escaping () -> Void) {
    self.remainingTime = duration
    self.onExpire = onExpire
  }

  // MARK: - Public API

  /// Start the countdown from the initial duration
  func start() {
    isPaused = false
    scheduleTask()
  }

  /// Pause the countdown, preserving remaining time
  func pause() {
    guard !isPaused, task != nil else { return }
    isPaused = true

    // Calculate elapsed time and update remaining
    if let startedAt {
      let elapsed = ContinuousClock.now - startedAt
      let elapsedSeconds = Double(elapsed.components.seconds)
        + Double(elapsed.components.attoseconds) / 1e18
      remainingTime = max(0, remainingTime - elapsedSeconds)
    }

    task?.cancel()
    task = nil
    startedAt = nil
  }

  /// Resume the countdown from where it was paused
  func resume() {
    guard isPaused else { return }
    isPaused = false

    guard remainingTime > 0 else {
      // Already expired while paused
      onExpire?()
      return
    }

    scheduleTask()
  }

  /// Cancel the countdown entirely
  func cancel() {
    isPaused = false
    task?.cancel()
    task = nil
    startedAt = nil
    onExpire = nil
  }

  // MARK: - Private

  private func scheduleTask() {
    task?.cancel()
    let delay = remainingTime
    startedAt = ContinuousClock.now

    task = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      guard !Task.isCancelled else { return }
      await MainActor.run {
        self?.onExpire?()
      }
    }
  }
}
