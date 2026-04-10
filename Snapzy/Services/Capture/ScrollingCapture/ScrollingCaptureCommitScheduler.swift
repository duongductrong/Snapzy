//
//  ScrollingCaptureCommitScheduler.swift
//  Snapzy
//
//  Coalesces stitch-lane refresh work so only the latest pending request is committed.
//

import Foundation

@MainActor
final class ScrollingCaptureCommitScheduler {
  struct Request {
    let sequenceNumber: Int
    let reason: String
    let expectedSignedDeltaPixels: Int?
    let requestedAt: TimeInterval
  }

  private let onRequestCoalesced: () -> Void
  private let operation: (Request) async -> Void

  private var runnerTask: Task<Void, Never>?
  private var currentRequest: Request?
  private var pendingRequest: Request?
  private var nextSequenceNumber = 0

  init(
    onRequestCoalesced: @escaping () -> Void = {},
    operation: @escaping (Request) async -> Void
  ) {
    self.onRequestCoalesced = onRequestCoalesced
    self.operation = operation
  }

  var isRunning: Bool {
    currentRequest != nil
  }

  var hasPendingWork: Bool {
    currentRequest != nil || pendingRequest != nil || runnerTask != nil
  }

  var activeRequestCount: Int {
    var count = 0
    if currentRequest != nil {
      count += 1
    }
    if pendingRequest != nil {
      count += 1
    }
    return count
  }

  @discardableResult
  func schedule(reason: String, expectedSignedDeltaPixels: Int?) -> Request {
    nextSequenceNumber += 1
    let request = Request(
      sequenceNumber: nextSequenceNumber,
      reason: reason,
      expectedSignedDeltaPixels: expectedSignedDeltaPixels,
      requestedAt: ProcessInfo.processInfo.systemUptime
    )

    if pendingRequest != nil {
      onRequestCoalesced()
    }
    pendingRequest = request
    startRunnerIfNeeded()
    return request
  }

  func discardPendingRequest() {
    pendingRequest = nil
  }

  func cancel() {
    runnerTask?.cancel()
    runnerTask = nil
    currentRequest = nil
    pendingRequest = nil
  }

  func waitForIdle() async {
    while hasPendingWork {
      try? await Task.sleep(nanoseconds: 20_000_000)
    }
  }

  private func startRunnerIfNeeded() {
    guard runnerTask == nil else { return }

    runnerTask = Task { @MainActor [weak self] in
      await self?.runLoop()
    }
  }

  private func runLoop() async {
    defer {
      runnerTask = nil
      currentRequest = nil
      if Task.isCancelled {
        pendingRequest = nil
      }
    }

    while !Task.isCancelled {
      guard let request = pendingRequest else { return }
      pendingRequest = nil
      currentRequest = request
      await operation(request)
      currentRequest = nil
    }
  }
}
