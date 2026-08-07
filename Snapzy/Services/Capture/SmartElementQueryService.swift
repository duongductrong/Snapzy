//
//  SmartElementQueryService.swift
//  Snapzy
//
//  Resolves the AX element under the cursor and publishes its rect in
//  AppKit bottom-left global coordinates for the AreaSelection overlay
//  to render and capture.
//
//  All AX queries run on the main thread per Apple guidance. The input
//  stream is debounced so that a still cursor triggers exactly one query.
//

import AppKit
import ApplicationServices
import Combine
import Foundation

/// Resolves the AX element under the cursor and publishes its rect.
///
/// Threading: all public methods must be called from the main thread.
/// AX APIs are not safe to call off-main (researcher-01 §8), and the
/// internal Combine pipeline uses `DispatchQueue.main` as its scheduler
/// so the query closure also fires on the main thread.
final class SmartElementQueryService {
  static let shared = SmartElementQueryService()

  // MARK: - Public Publisher

  /// Emits the detected element rect in AppKit bottom-left global coordinates.
  /// Emits nil to clear the highlight (no element, permission denied, cancelled).
  var elementDetectedPublisher: AnyPublisher<CGRect?, Never> {
    detectedSubject.eraseToAnyPublisher()
  }

  // MARK: - Dependencies

  private let snapshotProvider: AXSnapshotProviding
  private let permissionChecker: () -> Bool
  private let debounceMilliseconds: Int

  // MARK: - State

  private let inputSubject = PassthroughSubject<(CGPoint, Int32?), Never>()
  private let detectedSubject = PassthroughSubject<CGRect?, Never>()
  private var cancellables = Set<AnyCancellable>()
  private var lastEmittedRect: CGRect?
  private var hasEmittedAtLeastOnce = false
  // Permission-denied warning is intentionally logged once per process lifetime
  // (not per selection session) to avoid flooding diagnostics while the user
  // keeps re-entering smart-element mode without granting access.
  private var hasLoggedPermissionDenied = false
  private(set) var permissionDeniedLogCount = 0

  // MARK: - Init

  init(
    snapshotProvider: AXSnapshotProviding = AXAccessibilitySnapshotProvider(),
    permissionChecker: @escaping () -> Bool = { AXIsProcessTrusted() },
    debounceMilliseconds: Int = 25
  ) {
    self.snapshotProvider = snapshotProvider
    self.permissionChecker = permissionChecker
    self.debounceMilliseconds = debounceMilliseconds
    bindPipeline()
  }

  private func bindPipeline() {
    inputSubject
      .throttle(for: .milliseconds(debounceMilliseconds), scheduler: DispatchQueue.main, latest: true)
      .receive(on: DispatchQueue.global(qos: .userInteractive))
      .sink { [weak self] point, pid in
        self?.queryElement(at: point, pid: pid)
      }
      .store(in: &cancellables)
  }

  // MARK: - Public API

  /// Push the current cursor location (read here so callers never have to fetch it).
  ///
  /// Only safe when nothing else is intercepting mouse-moved events system-wide. Plain area
  /// screenshot's live-passthrough capture installs a `CGEvent` tap that consumes every
  /// mouse-moved event for its own hover tracking — with that tap active, `CGEvent(source:
  /// nil)?.location` stops advancing (it reflects the last event actually delivered through
  /// the normal dispatch path, which the tap intercepts first) and stays frozen at wherever the
  /// cursor was when the tap engaged, even though the pointer keeps moving. Callers in that
  /// situation already have a live, correct point from their own tap callback and should use
  /// `updateLocation(_:pid:)` instead.
  func updateMouseLocation(pid: Int32? = nil) {
    guard let location = CGEvent(source: nil)?.location else { return }
    inputSubject.send((location, pid))
  }

  /// Push an explicit screen point (Quartz global coordinates, top-left origin — the same
  /// space `CGEvent.location` uses) through the debounced input pipeline, for callers that
  /// already have a live, correct cursor position and can't rely on `updateMouseLocation`'s
  /// internal re-read — see its doc comment for why that can go stale.
  func updateLocation(_ point: CGPoint, pid: Int32? = nil) {
    inputSubject.send((point, pid))
  }

  /// Push an explicit point through the debounced input pipeline.
  /// Internal so tests can exercise the debounce/dedup without depending on
  /// the real cursor position. Not part of the production call surface.
  internal func pushInputForTesting(point: CGPoint, pid: Int32?) {
    inputSubject.send((point, pid))
  }

  /// Clear the current highlight and forget the last emission so the next query
  /// will always emit (even if it matches the previous rect).
  func cancelPendingQueries() {
    lastEmittedRect = nil
    hasEmittedAtLeastOnce = false
    detectedSubject.send(nil)
  }

  /// Prompt the user for Accessibility permission if not already granted.
  /// Returns `true` if permission is already granted at call time.
  ///
  /// Deliberately calls `AXIsProcessTrusted()` directly (not the injected
  /// `permissionChecker`) — the system prompt must reflect real TCC trust,
  /// not a test fake. Tests that need to assert prompt behavior should
  /// instead exercise the `queryElement` path, which uses the injectable
  /// checker.
  @discardableResult
  func ensureAccessibilityPermission() -> Bool {
    if AXIsProcessTrusted() { return true }
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    DiagnosticLogger.shared.log(
      .warning,
      .capture,
      "Smart element capture: accessibility prompt shown"
    )
    return false
  }

  // MARK: - Query

  /// Direct query entry point. Public to the test target via `@testable import`;
  /// production callers go through `updateMouseLocation(pid:)` so the input is
  /// debounced. Tests may call this directly to bypass timing.
  internal func queryElement(at point: CGPoint, pid: Int32?) {
    guard permissionChecker() else {
      logPermissionDeniedOnce()
      emit(nil)
      return
    }

    DiagnosticLogger.shared.log(.debug, .capture, "queryElement(at: \(point), pid: \(pid ?? -1))")

    guard let raw = snapshotProvider.snapshot(at: point, pid: pid) else {
      DiagnosticLogger.shared.log(.debug, .capture, "snapshotProvider.snapshot returned nil")
      emit(nil)
      return
    }

    DiagnosticLogger.shared.log(.debug, .capture, "snapshot returned element: role=\(raw.role ?? "nil") size=\(raw.size)")

    guard let meaningful = AXElementInspector.findMeaningful(raw) else {
      DiagnosticLogger.shared.log(
        .debug,
        .capture,
        "Smart element capture: no meaningful element after walk",
        context: ["rawRole": raw.role ?? "nil", "rawSize": "\(raw.size)"]
      )
      emit(nil)
      return
    }

    guard let flippedRect = AXElementInspector.screenRect(forTopLeftRect: meaningful.rect) else {
      DiagnosticLogger.shared.log(
        .warning,
        .capture,
        "Smart element capture: no screen contains AX rect",
        context: ["axRect": "\(meaningful.rect)"]
      )
      emit(nil)
      return
    }

    DiagnosticLogger.shared.log(
      .debug,
      .capture,
      "Smart element capture: emit",
      context: [
        "role": meaningful.role ?? "nil",
        "axRect": "\(meaningful.rect)",
        "flippedRect": "\(flippedRect)",
      ]
    )
    emit(flippedRect)
  }

  private func emit(_ rect: CGRect?) {
    let block = { [weak self] in
      guard let self = self else { return }
      if self.hasEmittedAtLeastOnce && rect == self.lastEmittedRect { return }
      self.hasEmittedAtLeastOnce = true
      self.lastEmittedRect = rect
      self.detectedSubject.send(rect)
    }
    if Thread.isMainThread {
      block()
    } else {
      DispatchQueue.main.async(execute: block)
    }
  }

  private func logPermissionDeniedOnce() {
    guard !hasLoggedPermissionDenied else { return }
    hasLoggedPermissionDenied = true
    permissionDeniedLogCount += 1
    DiagnosticLogger.shared.log(
      .warning,
      .capture,
      "Smart element capture: accessibility not trusted; emitting nil"
    )
  }
}
