//
//  QuickAccessCountdownTimer.swift
//  Snapzy
//
//  Pausable countdown timer for Quick Access card auto-dismiss
//

import Foundation

@MainActor
protocol QuickAccessCountdownTimerClock: AnyObject {
  var now: TimeInterval { get }
  func sleep(for duration: TimeInterval) async
}

@MainActor
final class ContinuousQuickAccessCountdownTimerClock: QuickAccessCountdownTimerClock {
  private let origin = ContinuousClock.now

  var now: TimeInterval {
    Self.seconds(from: ContinuousClock.now - origin)
  }

  func sleep(for duration: TimeInterval) async {
    guard duration > 0 else { return }
    try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
  }

  private static func seconds(from duration: ContinuousClock.Duration) -> TimeInterval {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
  }
}

/// A pausable countdown timer that tracks remaining time accurately using ContinuousClock.
@MainActor
final class QuickAccessCountdownTimer {

  private var remainingTime: TimeInterval
  private var startedAt: TimeInterval?
  private var task: Task<Void, Never>?
  private var onExpire: (() -> Void)?
  private let clock: QuickAccessCountdownTimerClock

  private(set) var isPaused: Bool = false
  var isRunning: Bool { task != nil && !isPaused }

  init(
    duration: TimeInterval,
    clock: QuickAccessCountdownTimerClock? = nil,
    onExpire: @escaping () -> Void
  ) {
    self.remainingTime = duration
    self.clock = clock ?? ContinuousQuickAccessCountdownTimerClock()
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
      let elapsedSeconds = clock.now - startedAt
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

  /// Restart the countdown from the full duration.
  func restart(duration: TimeInterval) {
    isPaused = false
    remainingTime = duration
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
    startedAt = clock.now
    let clock = clock

    task = Task { @MainActor [weak self, clock] in
      await clock.sleep(for: delay)
      guard !Task.isCancelled else { return }
      self?.onExpire?()
    }
  }
}
