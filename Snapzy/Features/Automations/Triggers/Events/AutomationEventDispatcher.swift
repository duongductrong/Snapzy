//
//  AutomationEventDispatcher.swift
//  Snapzy
//
//  Turns events into launches without letting them pile up: one run at a
//  time per automation (later files wait, at most
//  `AutomationEventLimits.maxPendingPerAutomation`), a small global cap on
//  event runs in flight, and a circuit breaker that pauses an automation's
//  events when it fires faster than any person would (a loop, a sync client
//  dumping a folder). Every launch goes through `AutomationLauncher`, so all
//  of its gates apply.
//

import Foundation

@MainActor
final class AutomationEventDispatcher {
  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}

  typealias Launch = @MainActor (UUID, AutomationInvocation, AutomationInput) async -> AutomationLaunchOutcome

  struct Job: Equatable {
    let automationID: UUID
    let invocation: AutomationInvocation
    let file: URL
    let isAlreadyInHistory: Bool
  }

  private let launch: Launch
  private let now: () -> Date
  private let maxConcurrent: Int
  private let maxPending: Int
  private let burstLimit: Int
  private let burstWindow: TimeInterval
  /// Called once when an automation's events get paused by the breaker.
  var onBurstPaused: ((UUID) -> Void)?

  private var queues: [UUID: [Job]] = [:]
  /// Automations with queued jobs, in the order they first queued (fair rotation).
  private var order: [UUID] = []
  private var running = Set<UUID>()
  private var recentStarts: [UUID: [Date]] = [:]
  private(set) var pausedAutomationIDs = Set<UUID>()
  private var droppedLogged = Set<UUID>()

  init(
    launch: @escaping Launch = { id, invocation, input in
      await AutomationLauncher.shared.launch(.id(id), invocation: invocation, input: input)
    },
    now: @escaping () -> Date = { Date() },
    maxConcurrent: Int = AutomationEventLimits.maxConcurrentRuns,
    maxPending: Int = AutomationEventLimits.maxPendingPerAutomation,
    burstLimit: Int = AutomationEventLimits.burstLimit,
    burstWindow: TimeInterval = AutomationEventLimits.burstWindow
  ) {
    self.launch = launch
    self.now = now
    self.maxConcurrent = maxConcurrent
    self.maxPending = maxPending
    self.burstLimit = burstLimit
    self.burstWindow = burstWindow
  }

  var runningCount: Int { running.count }

  func pendingCount(for automationID: UUID) -> Int {
    queues[automationID]?.count ?? 0
  }

  var isIdle: Bool { running.isEmpty && queues.isEmpty }

  /// Queues one run per file. Files beyond the per-automation cap are dropped.
  func enqueue(
    _ automationID: UUID,
    invocation: AutomationInvocation,
    files: [URL],
    isAlreadyInHistory: Bool
  ) {
    guard !files.isEmpty, !pausedAutomationIDs.contains(automationID) else { return }
    var queue = queues[automationID] ?? []
    var dropped = 0
    for file in files {
      guard queue.count < maxPending else {
        dropped += 1
        continue
      }
      // The same file queued twice (two events for one write) runs once.
      let job = Job(automationID: automationID, invocation: invocation, file: file, isAlreadyInHistory: isAlreadyInHistory)
      if !queue.contains(job) { queue.append(job) }
    }
    if dropped > 0, droppedLogged.insert(automationID).inserted {
      DiagnosticLogger.shared.log(
        .warning,
        .action,
        "Automation event files dropped; queue full",
        context: ["automation": automationID.uuidString, "dropped": "\(dropped)", "invocation": invocation.rawValue]
      )
    }
    guard !queue.isEmpty else { return }
    queues[automationID] = queue
    if !order.contains(automationID) { order.append(automationID) }
    pump()
  }

  /// Lifts the breaker (the automation was edited, or events were turned back on).
  func resume(_ automationID: UUID) {
    pausedAutomationIDs.remove(automationID)
    recentStarts[automationID] = nil
    droppedLogged.remove(automationID)
  }

  /// Drops everything queued (events paused, or the automation lost its trigger).
  func cancelPending(_ automationID: UUID? = nil) {
    if let automationID {
      queues[automationID] = nil
      order.removeAll { $0 == automationID }
    } else {
      queues.removeAll()
      order.removeAll()
    }
  }

  private func pump() {
    while running.count < maxConcurrent,
          let index = order.firstIndex(where: { !running.contains($0) })
    {
      let automationID = order.remove(at: index)
      guard var queue = queues[automationID], !queue.isEmpty else {
        queues[automationID] = nil
        continue
      }
      let job = queue.removeFirst()
      queues[automationID] = queue.isEmpty ? nil : queue
      if !queue.isEmpty { order.append(automationID) }

      guard admitStart(automationID) else { continue }
      running.insert(automationID)
      Task { @MainActor [weak self] in
        guard let self else { return }
        let input = AutomationInput(files: [job.file], isAlreadyInHistory: job.isAlreadyInHistory)
        let outcome = await self.launch(job.automationID, job.invocation, input)
        if case .rejected(let rejection) = outcome {
          // The launcher logged it; drop the rest of the queue when nothing can run.
          if rejection.stopsFurtherEventRuns { self.cancelPending(job.automationID) }
        }
        self.running.remove(job.automationID)
        self.pump()
      }
    }
  }

  /// Records a start; trips the breaker when the automation fires too fast.
  private func admitStart(_ automationID: UUID) -> Bool {
    let date = now()
    var starts = (recentStarts[automationID] ?? []).filter { date.timeIntervalSince($0) < burstWindow }
    guard starts.count < burstLimit else {
      pausedAutomationIDs.insert(automationID)
      cancelPending(automationID)
      recentStarts[automationID] = nil
      DiagnosticLogger.shared.log(
        .warning,
        .action,
        "Automation events paused; firing too fast",
        context: ["automation": automationID.uuidString, "limit": "\(burstLimit)/\(Int(burstWindow))s"]
      )
      onBurstPaused?(automationID)
      return false
    }
    starts.append(date)
    recentStarts[automationID] = starts
    return true
  }
}

extension AutomationLaunchRejection {
  /// The automation itself can't run (not per file): skip what is still queued.
  var stopsFurtherEventRuns: Bool {
    switch self {
    case .notFound, .disabled, .needsReview, .invalidChain, .codeStepsDisabled, .eventCodeNotAllowed, .unsupportedSource:
      true
    default:
      false
    }
  }
}
