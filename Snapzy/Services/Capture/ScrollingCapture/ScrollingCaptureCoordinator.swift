//
//  ScrollingCaptureCoordinator.swift
//  Snapzy
//
//  Phase-01 coordinator for guided scrolling capture sessions.
//

import AppKit
import Combine
import Foundation

@MainActor
final class ScrollingCaptureCoordinator {
  static let shared = ScrollingCaptureCoordinator()

  private let captureManager = ScreenCaptureManager.shared
  private let maxOutputHeight = ScrollingCaptureFeature.maxOutputHeight
  private let liveRefreshIntervalNanoseconds: UInt64 = 50_000_000
  private let defaultMinimumRefreshSpacing: TimeInterval = 0.09
  private let fastMinimumRefreshSpacing: TimeInterval = 0.06
  private let defaultScrollSettleDelay: TimeInterval = 0.05
  private let fastScrollSettleDelay: TimeInterval = 0.03
  private let scrollIdleTimeout: TimeInterval = 0.28
  private let defaultMinimumPendingScrollPoints: CGFloat = 10
  private let fastMinimumPendingScrollPoints: CGFloat = 8
  private let defaultForcedRefreshScrollPoints: CGFloat = 42
  private let fastForcedRefreshScrollPoints: CGFloat = 28
  private let autoScrollFrameWaitTimeoutNanoseconds: UInt64 = 220_000_000
  private let autoScrollFallbackCaptureDelayNanoseconds: UInt64 = 85_000_000
  private let livePreviewFramePollIntervalNanoseconds: UInt64 = 8_000_000
  private let previewTruthLagToleranceMs = 90
  private let scrollHitSlop: CGFloat = 32
  private let processingQueue = DispatchQueue(
    label: "com.snapzy.scrolling-capture.processing",
    qos: .userInitiated
  )

  private var sessionModel: ScrollingCaptureSessionModel?
  private var hudWindow: ScrollingCaptureHUDWindow?
  private var previewWindow: ScrollingCapturePreviewWindow?
  private var regionOverlayWindows: [RecordingRegionOverlayWindow] = []
  private var sessionModelObservation: AnyCancellable?
  private var latestImage: CGImage?
  private var stitcher: ScrollingCaptureStitcher?
  private var autoScrollEngine: ScrollingCaptureAutoScrollEngine?
  private var liveFrameSource: ScrollingCaptureFrameSource?
  private var commitScheduler: ScrollingCaptureCommitScheduler?
  private var sessionMetrics = ScrollingCaptureSessionMetrics()
  private var didFlushSessionMetrics = false
  private var selectedRect: CGRect?
  private var saveDirectory: URL?
  private var format: ImageFormat = .png
  private var prefetchedContentTask: ShareableContentPrefetchTask?
  private var scrollMonitor: Any?
  private var localSessionKeyMonitor: Any?
  private var globalSessionKeyMonitor: Any?
  private var pendingRefreshTask: Task<Void, Never>?
  private var autoScrollTask: Task<Void, Never>?
  private var prepareCaptureContextTask: Task<Void, Never>?
  private var preparedCaptureContext: ScreenCaptureManager.PreparedAreaCaptureContext?
  private var captureScaleFactor: CGFloat = 2
  private var pendingScrollDistancePoints: CGFloat = 0
  private var pendingScrollDirection: Int?
  private var pendingMixedDirections = false
  private var lockedScrollDirection: Int?
  private var lastScrollEventTime: TimeInterval?
  private var lastRefreshTime: TimeInterval?
  private var lastAcceptedDeltaPixels: Int?
  private var isRefreshingPreview = false
  private var sessionGeneration = 0
  private var autoScrollStepPoints: CGFloat = 0
  private var autoScrollConsecutiveFailures = 0
  private var autoScrollConsecutiveNoMovement = 0
  private var livePreviewFrameSequence = 0
  private var lastScheduledCommitSequenceNumber = 0
  private var lastScheduledCommitUpdate: ScrollingCaptureStitchUpdate?
  private var lastLivePreviewPublishedAt: TimeInterval?
  private var lastCommittedObservationAt: TimeInterval?

  private enum AutoScrollFrameObservation {
    case frameArrived(waitDurationMs: Int)
    case timedOut(waitDurationMs: Int)
    case fallbackDelay(waitDurationMs: Int)
  }

  var isActive: Bool {
    sessionModel != nil
  }

  func beginSession(
    rect: CGRect,
    saveDirectory: URL,
    format: ImageFormat,
    prefetchedContentTask: ShareableContentPrefetchTask?
  ) {
    cancel()
    sessionGeneration += 1

    let model = ScrollingCaptureSessionModel(selectedRect: rect)
    self.sessionModel = model
    self.selectedRect = rect
    self.saveDirectory = saveDirectory
    self.format = format
    self.prefetchedContentTask = prefetchedContentTask
    self.captureScaleFactor = scaleFactor(for: rect)
    self.sessionModelObservation?.cancel()
    self.sessionModelObservation = nil
    self.pendingScrollDistancePoints = 0
    self.pendingScrollDirection = nil
    self.pendingMixedDirections = false
    self.lockedScrollDirection = nil
    self.lastScrollEventTime = nil
    self.lastRefreshTime = nil
    self.lastAcceptedDeltaPixels = nil
    self.isRefreshingPreview = false
    self.preparedCaptureContext = nil
    self.prepareCaptureContextTask = nil
    self.autoScrollEngine = nil
    self.liveFrameSource = nil
    self.commitScheduler = makeCommitScheduler()
    self.autoScrollTask = nil
    self.autoScrollStepPoints = 0
    self.autoScrollConsecutiveFailures = 0
    self.autoScrollConsecutiveNoMovement = 0
    self.livePreviewFrameSequence = 0
    self.lastScheduledCommitSequenceNumber = 0
    self.lastScheduledCommitUpdate = nil
    self.lastLivePreviewPublishedAt = nil
    self.lastCommittedObservationAt = nil
    self.sessionMetrics = ScrollingCaptureSessionMetrics()
    self.didFlushSessionMetrics = false

    showRegionOverlay(for: rect)
    bindRegionOverlayGuidance(to: model)
    hudWindow = ScrollingCaptureHUDWindow(
      anchorRect: rect,
      model: model,
      onStart: { [weak self] in self?.startCapture() },
      onDone: { [weak self] in self?.finish() },
      onCancel: { [weak self] in self?.cancel() }
    )
    previewWindow = ScrollingCapturePreviewWindow(anchorRect: rect, model: model)

    hudWindow?.orderFrontRegardless()
    previewWindow?.orderFrontRegardless()
    installSessionKeyMonitorsIfNeeded()
    prewarmCaptureContext(for: rect)
    prepareAutoScrollEngineIfNeeded(for: rect, model: model)
    updatePreviewTruthState()

    if ScrollingCaptureFeature.showHints {
      AppToastManager.shared.show(
        message: "Select only the moving content, press Start Capture, then let Snapzy auto-scroll when possible or keep scrolling naturally.",
        style: .info,
        position: .topCenter
      )
    }

    DiagnosticLogger.shared.log(
      .info,
      .capture,
      "Scrolling capture session ready",
      context: ["rect": "\(Int(rect.width))x\(Int(rect.height))"]
    )
  }

  func cancel() {
    flushSessionMetricsIfNeeded(reason: "cancelled")
    sessionGeneration += 1
    pendingRefreshTask?.cancel()
    pendingRefreshTask = nil
    autoScrollTask?.cancel()
    autoScrollTask = nil
    prepareCaptureContextTask?.cancel()
    prepareCaptureContextTask = nil
    commitScheduler?.cancel()
    commitScheduler = nil
    stopLivePreviewIfNeeded()
    removeSessionKeyMonitors()
    sessionModelObservation?.cancel()
    sessionModelObservation = nil

    if let scrollMonitor {
      NSEvent.removeMonitor(scrollMonitor)
      self.scrollMonitor = nil
    }

    for overlay in regionOverlayWindows {
      overlay.close()
    }
    regionOverlayWindows.removeAll()
    hudWindow?.orderOut(nil)
    previewWindow?.orderOut(nil)
    hudWindow = nil
    previewWindow = nil
    sessionModel = nil
    latestImage = nil
    stitcher = nil
    selectedRect = nil
    saveDirectory = nil
    prefetchedContentTask = nil
    preparedCaptureContext = nil
    pendingScrollDistancePoints = 0
    pendingScrollDirection = nil
    pendingMixedDirections = false
    lockedScrollDirection = nil
    lastScrollEventTime = nil
    lastRefreshTime = nil
    lastAcceptedDeltaPixels = nil
    isRefreshingPreview = false
    autoScrollEngine?.invalidate()
    autoScrollEngine = nil
    commitScheduler = nil
    autoScrollStepPoints = 0
    autoScrollConsecutiveFailures = 0
    autoScrollConsecutiveNoMovement = 0
    livePreviewFrameSequence = 0
    lastScheduledCommitSequenceNumber = 0
    lastScheduledCommitUpdate = nil
    lastLivePreviewPublishedAt = nil
    lastCommittedObservationAt = nil
    sessionMetrics = ScrollingCaptureSessionMetrics()
    didFlushSessionMetrics = false
  }

  private func startCapture() {
    guard let sessionModel else { return }
    guard sessionModel.phase == .ready else { return }

    if let selectedRect {
      prepareAutoScrollEngineIfNeeded(for: selectedRect, model: sessionModel)
    }

    setRegionOverlayInteractionEnabled(false)
    sessionModel.phase = .capturing
    sessionModel.runtimeState = .streaming
    sessionModel.statusText = sessionModel.autoScrollEnabled && autoScrollEngine != nil
      ? "Capturing the first frame. After that, Snapzy will auto-scroll the target surface."
      : "Capturing the first frame. After that, keep scrolling downward at a steady pace."
    updatePreviewTruthState()
    installScrollMonitorIfNeeded()

    Task { @MainActor in
      await startLivePreviewIfPossible()
      let initialUpdate = await refreshPreview(reason: "Initial frame captured")
      if case .initialized? = initialUpdate?.outcome {
        startAutoScrollIfNeeded()
      }
    }
  }

  private func finish() {
    guard let sessionModel else { return }
    guard sessionModel.phase == .capturing else {
      if sessionModel.isInteractionLocked {
        sessionMetrics.recordFinalizingBlockedInput()
      }
      return
    }

    beginFinalizing()

    Task { @MainActor in
      await waitForPendingPreviewRefresh()

      if abs(pendingScrollDistancePoints) > 2 {
        _ = await refreshPreview(reason: "Final visible frame captured before save")
      }

      if latestImage == nil {
        _ = await refreshPreview(reason: "Current frame captured before save")
      }

      stopLivePreviewIfNeeded()

      if let mergedImage = stitcher?.mergedImage() {
        latestImage = mergedImage
        sessionModel.previewImage = mergedImage
      }

      guard let latestImage, let saveDirectory else {
        sessionMetrics.recordFinalizingCompleted(at: ProcessInfo.processInfo.systemUptime)
        sessionModel.phase = .capturing
        sessionModel.runtimeState = .paused
        sessionModel.statusText =
          "Snapzy couldn't lock a savable stitched image yet. You can keep capturing, try Done again, or Cancel."
        sessionModel.previewCaption = "No savable stitched result is ready yet"
        updatePreviewTruthState()
        AppToastManager.shared.show(message: "No stitched frame is ready yet.", style: .warning)
        return
      }

      sessionMetrics.recordFinalizingCompleted(at: ProcessInfo.processInfo.systemUptime)
      sessionModel.phase = .saving
      sessionModel.runtimeState = .saving
      sessionModel.statusText = "Saving the stitched long image."
      sessionModel.previewCaption = "Saving stitched result..."
      updatePreviewTruthState()

      let result = await captureManager.saveProcessedImage(
        latestImage,
        to: saveDirectory,
        format: format
      )

      switch result {
      case .success:
        flushSessionMetricsIfNeeded(reason: "saved")
        SoundManager.playScreenshotCapture()
        AppToastManager.shared.show(
          message: "Scrolling Capture experimental: saved the stitched image.",
          style: .info
        )
        cancel()
      case .failure(let error):
        sessionModel.phase = .capturing
        sessionModel.runtimeState = .paused
        sessionModel.statusText =
          "Save failed. The stitched result is frozen, so you can try Done again or Cancel."
        sessionModel.previewCaption = "Save failed • stitched result is still ready"
        updatePreviewTruthState()
        AppToastManager.shared.show(message: error.localizedDescription, style: .error)
      }
    }
  }

  private func installScrollMonitorIfNeeded() {
    guard scrollMonitor == nil else { return }

    scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      DispatchQueue.main.async {
        self?.handleScrollEvent(event)
      }
    }
  }

  private func handleScrollEvent(_ event: NSEvent) {
    guard let selectedRect, let sessionModel else { return }
    guard sessionModel.phase == .capturing else { return }
    guard autoScrollTask == nil else { return }
    guard abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) else { return }
    guard selectedRect.insetBy(dx: -scrollHitSlop, dy: -scrollHitSlop).contains(NSEvent.mouseLocation) else {
      return
    }

    let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 18
    let deltaY = CGFloat(event.scrollingDeltaY) * multiplier
    guard abs(deltaY) > 0.5 else { return }
    sessionMetrics.recordScrollEvent(deltaY: deltaY)

    let direction = deltaY > 0 ? 1 : -1
    if let lockedScrollDirection, direction != lockedScrollDirection {
      sessionModel.statusText = "Direction changed. Keep scrolling the same way or restart the session."
      pendingRefreshTask?.cancel()
      pendingRefreshTask = nil
      commitScheduler?.discardPendingRequest()
      pendingScrollDistancePoints = 0
      pendingScrollDirection = nil
      pendingMixedDirections = false
      updatePreviewTruthState()
      return
    }

    if let pendingScrollDirection, pendingScrollDirection != direction {
      pendingMixedDirections = true
    } else {
      pendingScrollDirection = direction
    }

    pendingScrollDistancePoints += deltaY
    lastScrollEventTime = ProcessInfo.processInfo.systemUptime

    sessionModel.statusText = "Capturing and aligning the latest visible content..."
    startLiveRefreshLoopIfNeeded()
    updatePreviewTruthState()
  }

  private func refreshPreview(
    reason: String,
    expectedSignedDeltaPixelsOverride: Int? = nil
  ) async -> ScrollingCaptureStitchUpdate? {
    let generation = sessionGeneration
    guard let sessionModel else { return nil }
    guard sessionModel.phase == .capturing || sessionModel.phase == .finalizing else { return nil }
    guard !isRefreshingPreview else { return nil }
    let isFinalizingRefresh = sessionModel.phase == .finalizing

    sessionModel.runtimeState = isFinalizingRefresh ? .finalizing : .committing
    updatePreviewTruthState()
    let refreshStartedAt = CFAbsoluteTimeGetCurrent()
    isRefreshingPreview = true
    defer {
      isRefreshingPreview = false
      if generation == sessionGeneration {
        lastRefreshTime = ProcessInfo.processInfo.systemUptime
        updatePreviewTruthState()
      }
    }

    do {
      let expectedSignedDeltaPixels: Int?
      let batchScrollDirection = pendingScrollDirection
      let hadMixedDirections = pendingMixedDirections
      if let expectedSignedDeltaPixelsOverride {
        expectedSignedDeltaPixels = expectedSignedDeltaPixelsOverride
      } else if abs(pendingScrollDistancePoints) > 2 {
        expectedSignedDeltaPixels = normalizedExpectedDeltaPixels(
          from: Int(round(pendingScrollDistancePoints * captureScaleFactor))
        )
      } else {
        expectedSignedDeltaPixels = nil
      }
      pendingScrollDistancePoints = 0
      pendingScrollDirection = nil
      pendingMixedDirections = false

      if hadMixedDirections {
        sessionModel.runtimeState = isFinalizingRefresh ? .finalizing : .paused
        sessionModel.statusText = isFinalizingRefresh
          ? "Finalizing the current stitched result after mixed scroll directions."
          : "Mixed scroll directions detected. Keep one direction so Snapzy can align."
        let totalDurationMs = Self.elapsedMilliseconds(since: refreshStartedAt)
        sessionMetrics.recordRefreshFailure(
          reason: reason,
          captureDurationMs: 0,
          stitchDurationMs: 0,
          totalDurationMs: totalDurationMs
        )
        updatePreviewTruthState()
        return nil
      }

      let captureStartedAt = CFAbsoluteTimeGetCurrent()
      guard let capturedImage = try await capturePreparedAreaForSession() else {
        sessionModel.runtimeState = isFinalizingRefresh ? .finalizing : .paused
        sessionModel.statusText = isFinalizingRefresh
          ? "Couldn't capture the last frame. Snapzy will save the current stitched result."
          : "Unable to capture the selected area."
        let totalDurationMs = Self.elapsedMilliseconds(since: refreshStartedAt)
        sessionMetrics.recordRefreshFailure(
          reason: reason,
          captureDurationMs: Self.elapsedMilliseconds(since: captureStartedAt),
          stitchDurationMs: 0,
          totalDurationMs: totalDurationMs
        )
        updatePreviewTruthState()
        return nil
      }
      let captureDurationMs = Self.elapsedMilliseconds(since: captureStartedAt)
      guard generation == sessionGeneration, self.sessionModel != nil else { return nil }

      let stitchStartedAt = CFAbsoluteTimeGetCurrent()
      let (update, processedStitcher) = await stitchCapturedImage(
        capturedImage,
        expectedSignedDeltaPixels: expectedSignedDeltaPixels,
        renderMergedImage: !(sessionModel.isUsingLivePreview && sessionModel.livePreviewImage != nil)
      )
      let stitchDurationMs = Self.elapsedMilliseconds(since: stitchStartedAt)
      guard generation == sessionGeneration, let sessionModel = self.sessionModel else { return nil }
      if let processedStitcher {
        self.stitcher = processedStitcher
      }

      guard let update else {
        sessionModel.runtimeState = isFinalizingRefresh ? .finalizing : .paused
        sessionModel.statusText = isFinalizingRefresh
          ? "Couldn't refresh the last frame. Snapzy will save the current stitched result."
          : "Unable to render the stitched preview."
        let totalDurationMs = Self.elapsedMilliseconds(since: refreshStartedAt)
        sessionMetrics.recordRefreshFailure(
          reason: reason,
          captureDurationMs: captureDurationMs,
          stitchDurationMs: stitchDurationMs,
          totalDurationMs: totalDurationMs
        )
        updatePreviewTruthState()
        return nil
      }

      let previewPublishStartedAt = CFAbsoluteTimeGetCurrent()
      if let mergedImage = update.mergedImage {
        latestImage = mergedImage
        sessionModel.previewImage = mergedImage
      }
      if
        case .appended = update.outcome,
        lockedScrollDirection == nil,
        update.mergeDirection != .unresolved,
        let batchScrollDirection
      {
        lockedScrollDirection = batchScrollDirection
      }
      recordCommittedObservation(for: update.outcome)
      sessionModel.acceptedFrameCount = update.acceptedFrameCount
      sessionModel.stitchedPixelHeight = update.outputHeight
      let previewPublishDurationMs = Self.elapsedMilliseconds(since: previewPublishStartedAt)
      let totalDurationMs = Self.elapsedMilliseconds(since: refreshStartedAt)
      sessionMetrics.recordRefreshSuccess(
        reason: reason,
        captureDurationMs: captureDurationMs,
        stitchDurationMs: stitchDurationMs,
        previewPublishDurationMs: previewPublishDurationMs,
        totalDurationMs: totalDurationMs,
        outcome: update.outcome,
        alignmentDebug: update.alignmentDebug
      )

      if isFinalizingRefresh {
        sessionModel.runtimeState = .finalizing
        sessionModel.previewCaption = finalizingPreviewCaption(for: update)
        sessionModel.statusText = finalizingStatusText(for: update)
        updatePreviewTruthState()
        return update
      }

      switch update.outcome {
      case .initialized:
        lastAcceptedDeltaPixels = nil
        sessionModel.runtimeState = previewRuntimeState()
        sessionModel.previewCaption = reason
        sessionModel.statusText =
          "First frame locked. Keep the pointer over the highlighted region and scroll downward steadily."
      case .appended(let deltaY):
        lastAcceptedDeltaPixels = deltaY
        sessionModel.runtimeState = previewRuntimeState()
        sessionModel.previewCaption =
          "\(update.acceptedFrameCount) frames stitched • +\(deltaY) px"
        sessionModel.statusText =
          "Session active. \(update.acceptedFrameCount) frames stitched into \(update.outputHeight) px."
      case .ignoredNoMovement:
        sessionModel.runtimeState = previewRuntimeState()
        if update.likelyReachedBoundary {
          sessionModel.previewCaption = "\(update.acceptedFrameCount) frames stitched • no new content"
          sessionModel.statusText =
            "No new content detected. You're probably at the end of the scrollable content. Press Done to save."
        } else {
          sessionModel.statusText = "Waiting for new content. Keep the scroll moving in one direction."
        }
      case .ignoredAlignmentFailed:
        sessionModel.runtimeState = update.matchFailureCount >= 2 ? .paused : previewRuntimeState()
        if update.matchFailureCount >= 2 {
          sessionModel.statusText = "Alignment paused. Slow down and keep one direction so Snapzy can recover."
        } else {
          sessionModel.statusText = "Couldn't align that frame. Keep the same direction and a steadier pace."
        }
      case .reachedHeightLimit:
        sessionModel.runtimeState = .paused
        sessionModel.previewCaption = "\(update.acceptedFrameCount) frames stitched • height limit reached"
        sessionModel.statusText =
          "Reached the \(maxOutputHeight) px output limit. Press Done to save the current result."
      }
      updatePreviewTruthState()
      return update
    } catch {
      let totalDurationMs = Self.elapsedMilliseconds(since: refreshStartedAt)
      sessionMetrics.recordRefreshFailure(
        reason: reason,
        captureDurationMs: 0,
        stitchDurationMs: 0,
        totalDurationMs: totalDurationMs
      )
      sessionModel.runtimeState = isFinalizingRefresh ? .finalizing : .paused
      DiagnosticLogger.shared.log(
        .error,
        .capture,
        "Scrolling capture preview refresh failed",
        context: ["error": error.localizedDescription]
      )
      sessionModel.statusText = isFinalizingRefresh
        ? "Finalizing the current stitched result after the last refresh failed."
        : "Preview refresh failed. You can Cancel and try again."
      updatePreviewTruthState()
      return nil
    }
  }

  private func showRegionOverlay(for rect: CGRect) {
    for overlay in regionOverlayWindows {
      overlay.close()
    }
    regionOverlayWindows.removeAll()

    for screen in NSScreen.screens {
      let overlay = RecordingRegionOverlayWindow(screen: screen, highlightRect: rect)
      overlay.interactionDelegate = self
      overlay.setInteractionEnabled(true)
      overlay.updateGuidance(currentRegionOverlayGuidance())
      overlay.orderFrontRegardless()
      regionOverlayWindows.append(overlay)
    }
  }

  private func bindRegionOverlayGuidance(to model: ScrollingCaptureSessionModel) {
    sessionModelObservation?.cancel()
    sessionModelObservation = model.objectWillChange.sink { [weak self] _ in
      DispatchQueue.main.async {
        self?.syncRegionOverlayGuidance()
      }
    }
    syncRegionOverlayGuidance()
  }

  private func syncRegionOverlayGuidance() {
    let guidance = currentRegionOverlayGuidance()
    for overlay in regionOverlayWindows {
      overlay.updateGuidance(guidance)
    }
  }

  private func currentRegionOverlayGuidance() -> RecordingRegionOverlayGuidance? {
    guard let guidance = sessionModel?.selectionGuidance else { return nil }
    let tone: RecordingRegionOverlayGuidanceTone

    switch guidance.tone {
    case .neutral:
      tone = .neutral
    case .active:
      tone = .active
    case .warning:
      tone = .warning
    case .progress:
      tone = .progress
    }

    return RecordingRegionOverlayGuidance(
      title: guidance.title,
      detail: guidance.detail,
      tone: tone
    )
  }

  private func setRegionOverlayInteractionEnabled(_ enabled: Bool) {
    for overlay in regionOverlayWindows {
      overlay.setInteractionEnabled(enabled)
    }
  }

  private func updateSelectedRect(_ rect: CGRect, reprepareSession: Bool) {
    let normalizedRect = rect.standardized
    selectedRect = normalizedRect
    sessionModel?.selectedRect = normalizedRect
    captureScaleFactor = scaleFactor(for: normalizedRect)

    for overlay in regionOverlayWindows {
      overlay.updateHighlightRect(normalizedRect)
    }
    hudWindow?.updateAnchorRect(normalizedRect)
    previewWindow?.updateAnchorRect(normalizedRect)

    if reprepareSession {
      refreshSelectionPreparation()
    }
  }

  private func refreshSelectionPreparation() {
    guard let selectedRect, let sessionModel, sessionModel.phase == .ready else { return }

    preparedCaptureContext = nil
    prepareCaptureContextTask?.cancel()
    prepareCaptureContextTask = nil
    latestImage = nil
    stitcher = nil
    lastAcceptedDeltaPixels = nil
    autoScrollStepPoints = 0
    autoScrollConsecutiveFailures = 0
    autoScrollConsecutiveNoMovement = 0
    livePreviewFrameSequence = 0
    lastScheduledCommitSequenceNumber = 0
    lastScheduledCommitUpdate = nil
    lastLivePreviewPublishedAt = nil
    lastCommittedObservationAt = nil
    sessionModel.previewImage = nil
    sessionModel.livePreviewImage = nil
    sessionModel.isUsingLivePreview = false
    sessionModel.previewCaption = "Start Capture to lock the first frame"
    sessionModel.acceptedFrameCount = 0
    sessionModel.stitchedPixelHeight = 0
    sessionModel.runtimeState = .ready
    sessionModel.statusText =
      "Adjust the region so only the moving content stays inside, then press Start Capture. Press Esc to cancel."

    prewarmCaptureContext(for: selectedRect)
    prepareAutoScrollEngineIfNeeded(for: selectedRect, model: sessionModel)
    updatePreviewTruthState()
  }

  private func prewarmCaptureContext(for rect: CGRect) {
    prepareCaptureContextTask?.cancel()
    prepareCaptureContextTask = Task { @MainActor [weak self] in
      guard let self else { return }

      do {
        let context = try await self.captureManager.prepareAreaCapture(
          rect: rect,
          excludeDesktopIcons: DesktopIconManager.shared.isIconHidingEnabled,
          excludeDesktopWidgets: DesktopIconManager.shared.isWidgetHidingEnabled,
          excludeOwnApplication: true,
          prefetchedContentTask: self.prefetchedContentTask
        )

        guard !Task.isCancelled else { return }
        self.preparedCaptureContext = context
        self.captureScaleFactor = context.scaleFactor
      } catch {
        if error is CancellationError { return }
        DiagnosticLogger.shared.log(
          .warning,
          .capture,
          "Scrolling capture prewarm failed",
          context: ["error": error.localizedDescription]
        )
      }
    }
  }

  private func ensurePreparedCaptureContext() async throws -> ScreenCaptureManager.PreparedAreaCaptureContext {
    if let preparedCaptureContext {
      return preparedCaptureContext
    }

    if let prepareCaptureContextTask {
      await prepareCaptureContextTask.value
      self.prepareCaptureContextTask = nil
      if let preparedCaptureContext {
        return preparedCaptureContext
      }
    }

    guard let selectedRect else {
      throw CaptureError.cancelled
    }

    let context = try await captureManager.prepareAreaCapture(
      rect: selectedRect,
      excludeDesktopIcons: DesktopIconManager.shared.isIconHidingEnabled,
      excludeDesktopWidgets: DesktopIconManager.shared.isWidgetHidingEnabled,
      excludeOwnApplication: true,
      prefetchedContentTask: prefetchedContentTask
    )
    preparedCaptureContext = context
    captureScaleFactor = context.scaleFactor
    return context
  }

  private func capturePreparedAreaForSession() async throws -> CGImage? {
    do {
      let context = try await ensurePreparedCaptureContext()
      return try await captureManager.capturePreparedArea(context)
    } catch {
      preparedCaptureContext = nil
      prepareCaptureContextTask?.cancel()
      prepareCaptureContextTask = nil
      throw error
    }
  }

  private func startLiveRefreshLoopIfNeeded() {
    guard pendingRefreshTask == nil else { return }

    pendingRefreshTask = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { self.pendingRefreshTask = nil }

      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: self.liveRefreshIntervalNanoseconds)
        if Task.isCancelled { return }
        guard let sessionModel = self.sessionModel, sessionModel.phase == .capturing else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let idleDuration = self.lastScrollEventTime.map { now - $0 } ?? .greatestFiniteMagnitude
        let pendingDistance = abs(self.pendingScrollDistancePoints)
        let hasPendingMotion = pendingDistance > 2
        let hasEnoughSettledMotion = pendingDistance >= self.minimumPendingScrollPoints()
          && idleDuration >= self.scrollSettleDelay()
        let shouldRefresh = hasPendingMotion
          && (hasEnoughSettledMotion || pendingDistance >= self.forcedRefreshScrollPoints())
          && self.canStartRefresh(at: now)

        if shouldRefresh {
          self.scheduleCommitRefresh(reason: "Live stitched preview")
          return
        }

        if idleDuration >= self.scrollIdleTimeout {
          if hasPendingMotion && self.canStartRefresh(at: now) {
            self.scheduleCommitRefresh(reason: "Latest visible frame")
          }
          return
        }
      }
    }
  }

  private func canStartRefresh(at now: TimeInterval) -> Bool {
    guard !isRefreshingPreview else { return false }
    guard let lastRefreshTime else { return true }
    return now - lastRefreshTime >= minimumRefreshSpacing()
  }

  private func prepareAutoScrollEngineIfNeeded(
    for rect: CGRect,
    model: ScrollingCaptureSessionModel
  ) {
    model.autoScrollAvailable = AXIsProcessTrusted()

    guard model.autoScrollEnabled else {
      autoScrollEngine?.invalidate()
      autoScrollEngine = nil
      model.autoScrollStatusText = model.autoScrollAvailable
        ? "Auto-scroll is off for this session."
        : "Auto-scroll needs Accessibility permission."
      return
    }

    guard model.autoScrollAvailable else {
      autoScrollEngine?.invalidate()
      autoScrollEngine = nil
      model.autoScrollStatusText = "Auto-scroll needs Accessibility permission."
      return
    }

    let engine = ScrollingCaptureAutoScrollEngine(selectionRect: rect)
    switch engine.prepare() {
    case .ready(let description):
      model.autoScrollAvailable = true
      autoScrollEngine = engine
      autoScrollStepPoints = initialAutoScrollStepPoints()
      autoScrollConsecutiveFailures = 0
      autoScrollConsecutiveNoMovement = 0
      model.autoScrollStatusText = description
    case .unavailablePermission(let description), .noScrollableTarget(let description):
      model.autoScrollAvailable = AXIsProcessTrusted()
      autoScrollEngine = nil
      model.autoScrollStatusText = description
    }
  }

  private func startAutoScrollIfNeeded() {
    guard autoScrollTask == nil else { return }
    guard let autoScrollEngine, let sessionModel else { return }
    guard sessionModel.phase == .capturing, sessionModel.autoScrollEnabled else { return }

    autoScrollStepPoints = max(autoScrollStepPoints, initialAutoScrollStepPoints())
    autoScrollConsecutiveFailures = 0
    autoScrollConsecutiveNoMovement = 0
    sessionModel.isAutoScrolling = true
    sessionModel.autoScrollStatusText = "Auto-scroll running with \(autoScrollEngine.targetDescription.lowercased())."

    autoScrollTask = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.runAutoScrollLoop()
    }
  }

  private func stopAutoScrollLoop() {
    autoScrollTask?.cancel()
    autoScrollTask = nil
    sessionModel?.isAutoScrolling = false
  }

  private func runAutoScrollLoop() async {
    defer {
      autoScrollTask = nil
      if let sessionModel, sessionModel.phase == .capturing {
        sessionModel.isAutoScrolling = false
        if sessionModel.autoScrollEnabled {
          sessionModel.autoScrollStatusText = autoScrollEngine?.targetDescription
            ?? "Auto-scroll is ready when a supported target is found."
        }
      }
    }

    guard let autoScrollEngine else { return }

    while !Task.isCancelled {
      guard let sessionModel = self.sessionModel, sessionModel.phase == .capturing else { return }

      let requestedStepPoints = min(max(autoScrollStepPoints, 28), maxAutoScrollStepPoints())
      let frameSequenceBeforeStep = livePreviewFrameSequence
      let stepOutcome = await autoScrollEngine.performStep(points: requestedStepPoints)
      sessionMetrics.recordAutoScrollStep(requestedPoints: requestedStepPoints, outcome: stepOutcome)
      if Task.isCancelled { return }

      switch stepOutcome {
      case .failed(let description):
        sessionModel.statusText = "\(description) Continue scrolling manually or press Done."
        return
      case .blocked(let description):
        autoScrollConsecutiveNoMovement += 1
        if autoScrollConsecutiveNoMovement == 1 {
          autoScrollEngine.flipWheelDirectionHint()
        }
        autoScrollStepPoints = min(maxAutoScrollStepPoints(), requestedStepPoints * 1.18)
        if autoScrollConsecutiveNoMovement >= 3 {
          sessionModel.statusText = "\(description) You can continue scrolling manually."
          return
        }
        try? await Task.sleep(nanoseconds: 80_000_000)
        continue
      case .reachedBoundary(let description):
        _ = await scheduleCommitRefreshAndWait(
          reason: "Final auto-scroll frame",
          expectedSignedDeltaPixelsOverride: Int(round(requestedStepPoints * captureScaleFactor))
        )
        sessionModel.statusText = "\(description) Press Done to save the current result."
        sessionModel.autoScrollStatusText = "Reached the end of the scrollable content."
        return
      case .scrolled(let estimatedPoints, let boundaryReached):
        sessionModel.statusText = "Auto-scrolling and stitching the latest visible content..."
        let frameObservation = await waitForAutoScrollFrameObservation(after: frameSequenceBeforeStep)
        let observedFrame: Bool
        switch frameObservation {
        case .frameArrived:
          observedFrame = true
        case .timedOut:
          observedFrame = false
          sessionModel.autoScrollStatusText = "Auto-scroll waiting for frame sync."
        case .fallbackDelay:
          observedFrame = false
        }

        let update = await scheduleCommitRefreshAndWait(
          reason: "Auto-scroll preview",
          expectedSignedDeltaPixelsOverride: Int(round(estimatedPoints * captureScaleFactor))
        )

        guard let update else {
          sessionModel.statusText = "Auto-scroll paused because Snapzy couldn't refresh the preview."
          return
        }

        switch update.outcome {
        case .initialized:
          continue
        case .appended(let deltaY):
          autoScrollConsecutiveFailures = 0
          autoScrollConsecutiveNoMovement = 0
          sessionMetrics.recordAutoScrollCommitAccepted()
          let acceptedPoints = CGFloat(deltaY) / max(captureScaleFactor, 1)
          let blendedStep = acceptedPoints * 0.82 + requestedStepPoints * 0.18
          autoScrollStepPoints = min(maxAutoScrollStepPoints(), max(24, blendedStep))
          sessionModel.autoScrollStatusText =
            observedFrame
            ? "Auto-scroll frame-synced • step \(Int(round(autoScrollStepPoints))) pt"
            : "Auto-scroll running • step \(Int(round(autoScrollStepPoints))) pt"

          if boundaryReached {
            sessionModel.statusText = "Auto-scroll reached the end. Press Done to save the current result."
            sessionModel.autoScrollStatusText = "Reached the end of the scrollable content."
            return
          }
        case .ignoredNoMovement:
          if update.likelyReachedBoundary {
            sessionModel.statusText =
              "No new content detected. Auto-scroll reached the end. Press Done to save the current result."
            sessionModel.autoScrollStatusText = "Reached the end of the scrollable content."
            return
          }
          autoScrollConsecutiveNoMovement += 1
          autoScrollStepPoints = min(maxAutoScrollStepPoints(), requestedStepPoints * 1.22)
          if autoScrollConsecutiveNoMovement >= 3 {
            sessionModel.statusText = observedFrame
              ? "Auto-scroll no longer sees new content. You can press Done or continue manually."
              : "Auto-scroll paused after repeated frame stalls. You can continue manually or press Done."
            return
          }
        case .ignoredAlignmentFailed:
          autoScrollConsecutiveFailures += 1
          autoScrollStepPoints = max(20, requestedStepPoints * 0.72)
          if autoScrollConsecutiveFailures >= 3 {
            sessionModel.statusText =
              "Auto-scroll paused after repeated alignment misses. You can continue manually or press Done."
            return
          }
        case .reachedHeightLimit:
          sessionModel.autoScrollStatusText = "Height limit reached."
          return
        }
      }
    }
  }

  private func waitForPendingPreviewRefresh() async {
    await commitScheduler?.waitForIdle()
    while isRefreshingPreview {
      try? await Task.sleep(nanoseconds: 20_000_000)
    }
  }

  private func startLivePreviewIfPossible() async {
    guard let sessionModel else { return }
    guard sessionModel.phase == .capturing else { return }

    do {
      let context = try await ensurePreparedCaptureContext()
      let frameSource = liveFrameSource ?? ScrollingCaptureFrameSource()
      liveFrameSource = frameSource

      try await frameSource.start(
        with: context,
        frameHandler: { [weak self] cgImage in
          self?.publishLivePreviewFrame(cgImage)
        },
        failureHandler: { [weak self] errorDescription in
          self?.handleLivePreviewFailure(errorDescription)
        }
      )
      sessionMetrics.recordLivePreviewStart(success: true)
      sessionModel.livePreviewImage = nil
      sessionModel.isUsingLivePreview = true
      sessionModel.runtimeState = .streaming
      sessionModel.previewCaption = "Live preview running while Snapzy locks the stitched frame."
      updatePreviewTruthState()
    } catch {
      sessionMetrics.recordLivePreviewStart(success: false)
      sessionMetrics.recordLivePreviewFallbackActivation()
      sessionModel.isUsingLivePreview = false
      updatePreviewTruthState()
      DiagnosticLogger.shared.log(
        .warning,
        .capture,
        "Scrolling capture live preview fallback to stitched preview",
        context: ["error": error.localizedDescription]
      )
    }
  }

  private func stopLivePreviewIfNeeded(clearImage: Bool = true) {
    liveFrameSource?.stop()
    liveFrameSource = nil
    if clearImage {
      sessionModel?.livePreviewImage = nil
    }
    sessionModel?.isUsingLivePreview = false
    updatePreviewTruthState()
  }

  private func publishLivePreviewFrame(_ cgImage: CGImage) {
    guard let sessionModel, sessionModel.phase == .capturing else { return }

    let publishStartedAt = CFAbsoluteTimeGetCurrent()
    let publishedAt = ProcessInfo.processInfo.systemUptime
    livePreviewFrameSequence += 1
    sessionModel.livePreviewImage = cgImage
    sessionModel.isUsingLivePreview = true
    if !(commitScheduler?.isRunning ?? false), sessionModel.runtimeState != .paused {
      sessionModel.runtimeState = .previewing
    }
    lastLivePreviewPublishedAt = publishedAt
    let publishDurationMs = Self.elapsedMilliseconds(since: publishStartedAt)
    sessionMetrics.recordLivePreviewFramePublished(
      at: publishedAt,
      publishDurationMs: publishDurationMs
    )
    updatePreviewTruthState()
  }

  private func handleLivePreviewFailure(_ errorDescription: String) {
    sessionMetrics.recordLivePreviewFailure()
    DiagnosticLogger.shared.log(
      .warning,
      .capture,
      "Scrolling capture live preview stream stopped",
      context: ["error": errorDescription]
    )
    stopLivePreviewIfNeeded(clearImage: false)
    sessionModel?.runtimeState = .paused
    updatePreviewTruthState()
  }

  private func normalizedExpectedDeltaPixels(from rawValue: Int) -> Int {
    guard rawValue != 0 else { return 0 }

    let sign = rawValue > 0 ? 1 : -1
    let magnitude = abs(rawValue)
    guard let lastAcceptedDeltaPixels, lastAcceptedDeltaPixels > 0 else {
      return sign * min(max(16, magnitude), 1_600)
    }

    let blendedMagnitude = Int(round(Double(magnitude + lastAcceptedDeltaPixels) / 2.0))
    let lowerBound = max(16, Int(Double(lastAcceptedDeltaPixels) * 0.55))
    let upperBound = max(lowerBound + 28, Int(Double(lastAcceptedDeltaPixels) * 1.85))
    let clampedMagnitude = min(max(lowerBound, blendedMagnitude), upperBound)
    return sign * clampedMagnitude
  }

  private func stitchCapturedImage(
    _ capturedImage: CGImage,
    expectedSignedDeltaPixels: Int?,
    renderMergedImage: Bool
  ) async -> (ScrollingCaptureStitchUpdate?, ScrollingCaptureStitcher?) {
    let currentStitcher = stitcher
    let maxOutputHeight = maxOutputHeight

    return await withCheckedContinuation { continuation in
      processingQueue.async {
        autoreleasepool {
          if let currentStitcher {
            let update = currentStitcher.append(
              capturedImage,
              maxOutputHeight: maxOutputHeight,
              expectedSignedDeltaPixels: expectedSignedDeltaPixels,
              renderMergedImage: renderMergedImage
            )
            continuation.resume(returning: (update, currentStitcher))
          } else {
            let newStitcher = ScrollingCaptureStitcher()
            let update = newStitcher.start(with: capturedImage)
            continuation.resume(returning: (update, newStitcher))
          }
        }
      }
    }
  }

  private func minimumRefreshSpacing() -> TimeInterval {
    lastAcceptedDeltaPixels == nil ? defaultMinimumRefreshSpacing : fastMinimumRefreshSpacing
  }

  private func scrollSettleDelay() -> TimeInterval {
    lastAcceptedDeltaPixels == nil ? defaultScrollSettleDelay : fastScrollSettleDelay
  }

  private func minimumPendingScrollPoints() -> CGFloat {
    lastAcceptedDeltaPixels == nil ? defaultMinimumPendingScrollPoints : fastMinimumPendingScrollPoints
  }

  private func forcedRefreshScrollPoints() -> CGFloat {
    guard let lastAcceptedDeltaPixels, lastAcceptedDeltaPixels > 0 else {
      return defaultForcedRefreshScrollPoints
    }

    let estimatedPoints = CGFloat(lastAcceptedDeltaPixels) / max(captureScaleFactor, 1)
    let adaptivePoints = estimatedPoints * 0.42
    return min(defaultForcedRefreshScrollPoints, max(fastForcedRefreshScrollPoints, adaptivePoints))
  }

  private func initialAutoScrollStepPoints() -> CGFloat {
    guard let selectedRect else { return 96 }
    return min(maxAutoScrollStepPoints(), max(48, selectedRect.height * 0.24))
  }

  private func maxAutoScrollStepPoints() -> CGFloat {
    guard let selectedRect else { return 180 }
    return max(96, min(240, selectedRect.height * 0.46))
  }

  private func scaleFactor(for rect: CGRect) -> CGFloat {
    let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) ?? NSScreen.main
    return screen?.backingScaleFactor ?? 2
  }

  private func previewRuntimeState() -> ScrollingCaptureRuntimeState {
    guard let sessionModel, sessionModel.phase == .capturing else { return .ready }
    if sessionModel.isUsingLivePreview, sessionModel.livePreviewImage != nil {
      return .previewing
    }
    return .streaming
  }

  private func performScheduledCommit(_ request: ScrollingCaptureCommitScheduler.Request) async {
    guard sessionModel?.phase == .capturing else { return }
    let update = await refreshPreview(
      reason: request.reason,
      expectedSignedDeltaPixelsOverride: request.expectedSignedDeltaPixels
    )
    lastScheduledCommitSequenceNumber = request.sequenceNumber
    lastScheduledCommitUpdate = update
    updatePreviewTruthState()
  }

  private func makeCommitScheduler() -> ScrollingCaptureCommitScheduler {
    ScrollingCaptureCommitScheduler(
      onRequestCoalesced: { [weak self] in
        self?.sessionMetrics.recordCommitCoalesced()
      },
      operation: { [weak self] request in
        guard let self else { return }
        await self.performScheduledCommit(request)
      }
    )
  }

  @discardableResult
  private func scheduleCommitRefresh(
    reason: String,
    expectedSignedDeltaPixelsOverride: Int? = nil
  ) -> ScrollingCaptureCommitScheduler.Request? {
    guard let sessionModel, sessionModel.phase == .capturing else { return nil }
    sessionMetrics.recordCommitScheduled()
    let request = commitScheduler?.schedule(
      reason: reason,
      expectedSignedDeltaPixels: expectedSignedDeltaPixelsOverride
    )
    updatePreviewTruthState()
    return request
  }

  private func scheduleCommitRefreshAndWait(
    reason: String,
    expectedSignedDeltaPixelsOverride: Int? = nil
  ) async -> ScrollingCaptureStitchUpdate? {
    guard let commitScheduler else {
      return await refreshPreview(
        reason: reason,
        expectedSignedDeltaPixelsOverride: expectedSignedDeltaPixelsOverride
      )
    }

    guard let request = scheduleCommitRefresh(
      reason: reason,
      expectedSignedDeltaPixelsOverride: expectedSignedDeltaPixelsOverride
    ) else {
      return nil
    }

    await commitScheduler.waitForIdle()
    guard lastScheduledCommitSequenceNumber >= request.sequenceNumber else { return nil }
    return lastScheduledCommitUpdate
  }

  private func waitForAutoScrollFrameObservation(after sequenceNumber: Int) async -> AutoScrollFrameObservation {
    guard let sessionModel else { return .timedOut(waitDurationMs: 0) }

    if !sessionModel.isUsingLivePreview {
      let startedAt = CFAbsoluteTimeGetCurrent()
      try? await Task.sleep(nanoseconds: autoScrollFallbackCaptureDelayNanoseconds)
      let waitDurationMs = Self.elapsedMilliseconds(since: startedAt)
      sessionMetrics.recordAutoScrollFrameObservation(
        waitDurationMs: waitDurationMs,
        didObserveFrame: false
      )
      return .fallbackDelay(waitDurationMs: waitDurationMs)
    }

    let startedAt = CFAbsoluteTimeGetCurrent()
    while !Task.isCancelled {
      if livePreviewFrameSequence > sequenceNumber {
        let waitDurationMs = Self.elapsedMilliseconds(since: startedAt)
        sessionMetrics.recordAutoScrollFrameObservation(
          waitDurationMs: waitDurationMs,
          didObserveFrame: true
        )
        return .frameArrived(waitDurationMs: waitDurationMs)
      }

      let elapsedNanoseconds = UInt64((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000_000_000)
      if elapsedNanoseconds >= autoScrollFrameWaitTimeoutNanoseconds {
        let waitDurationMs = Self.elapsedMilliseconds(since: startedAt)
        sessionMetrics.recordAutoScrollFrameObservation(
          waitDurationMs: waitDurationMs,
          didObserveFrame: false
        )
        return .timedOut(waitDurationMs: waitDurationMs)
      }

      try? await Task.sleep(nanoseconds: livePreviewFramePollIntervalNanoseconds)
    }

    let waitDurationMs = Self.elapsedMilliseconds(since: startedAt)
    sessionMetrics.recordAutoScrollFrameObservation(
      waitDurationMs: waitDurationMs,
      didObserveFrame: false
    )
    return .timedOut(waitDurationMs: waitDurationMs)
  }

  private func beginFinalizing() {
    guard let sessionModel else { return }

    stopAutoScrollLoop()
    pendingRefreshTask?.cancel()
    pendingRefreshTask = nil
    sessionModel.phase = .finalizing
    sessionModel.runtimeState = .finalizing
    sessionModel.statusText =
      "Finalizing the current capture. Snapzy is locking the latest stitched result before saving."
    sessionModel.previewCaption = "Finalizing stitched result..."
    sessionMetrics.recordFinalizingStarted(at: ProcessInfo.processInfo.systemUptime)
    updatePreviewTruthState()
  }

  private func installSessionKeyMonitorsIfNeeded() {
    guard localSessionKeyMonitor == nil else { return }

    localSessionKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard event.keyCode == 53 else { return event }
      guard let self else { return event }
      return self.handleSessionEscapeKey() ? nil : event
    }

    globalSessionKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard event.keyCode == 53 else { return }
      DispatchQueue.main.async {
        _ = self?.handleSessionEscapeKey()
      }
    }
  }

  private func removeSessionKeyMonitors() {
    if let localSessionKeyMonitor {
      NSEvent.removeMonitor(localSessionKeyMonitor)
      self.localSessionKeyMonitor = nil
    }

    if let globalSessionKeyMonitor {
      NSEvent.removeMonitor(globalSessionKeyMonitor)
      self.globalSessionKeyMonitor = nil
    }
  }

  @discardableResult
  private func handleSessionEscapeKey() -> Bool {
    guard let sessionModel else { return false }

    switch sessionModel.phase {
    case .ready:
      sessionMetrics.recordPreStartEscapeCancel()
      cancel()
      return true
    case .finalizing, .saving:
      sessionMetrics.recordFinalizingBlockedInput()
      return true
    case .capturing:
      return false
    }
  }

  private func recordCommittedObservation(for outcome: ScrollingCaptureStitchOutcome) {
    switch outcome {
    case .initialized, .appended, .ignoredNoMovement:
      lastCommittedObservationAt = ProcessInfo.processInfo.systemUptime
    case .ignoredAlignmentFailed, .reachedHeightLimit:
      break
    }
  }

  private func finalizingPreviewCaption(for update: ScrollingCaptureStitchUpdate) -> String {
    switch update.outcome {
    case .initialized:
      return "Finalizing stitched result • \(update.acceptedFrameCount) frames locked"
    case .ignoredNoMovement:
      return update.likelyReachedBoundary
        ? "Finalizing current result • no new content"
        : "Finalizing stitched result • \(update.acceptedFrameCount) frames locked"
    case .appended(let deltaY):
      return "Final frame locked • \(update.acceptedFrameCount) frames • +\(deltaY) px"
    case .ignoredAlignmentFailed:
      return "Finalizing current stitched result • last frame skipped"
    case .reachedHeightLimit:
      return "\(update.acceptedFrameCount) frames stitched • height limit reached"
    }
  }

  private func finalizingStatusText(for update: ScrollingCaptureStitchUpdate) -> String {
    switch update.outcome {
    case .initialized, .appended:
      return "Locking the current capture. Snapzy is sealing \(update.acceptedFrameCount) stitched frames before saving."
    case .ignoredNoMovement:
      return update.likelyReachedBoundary
        ? "No new content was detected. Snapzy is saving the current stitched result."
        : "Locking the current capture. Snapzy is sealing \(update.acceptedFrameCount) stitched frames before saving."
    case .ignoredAlignmentFailed:
      return "Couldn't align the last frame cleanly. Snapzy will save the current stitched result."
    case .reachedHeightLimit:
      return "Height limit reached. Snapzy is saving the current stitched result."
    }
  }

  private func updatePreviewTruthState() {
    guard let sessionModel else { return }

    let schedulerPendingCount = commitScheduler?.activeRequestCount ?? 0
    let pendingCommitCount = max(schedulerPendingCount, isRefreshingPreview ? 1 : 0)
    sessionModel.pendingCommitCount = pendingCommitCount

    let previewLagMs: Int
    if let lastLivePreviewPublishedAt {
      if let lastCommittedObservationAt {
        previewLagMs = max(
          0,
          Int(((lastLivePreviewPublishedAt - lastCommittedObservationAt) * 1_000).rounded())
        )
      } else if sessionModel.isUsingLivePreview {
        previewLagMs = previewTruthLagToleranceMs + 1
      } else {
        previewLagMs = 0
      }
    } else {
      previewLagMs = 0
    }
    sessionModel.previewCommitLagMs = previewLagMs

    let previewTruthState: ScrollingCapturePreviewTruthState
    switch sessionModel.phase {
    case .ready:
      previewTruthState = .ready
    case .capturing:
      if sessionModel.runtimeState == .paused {
        if sessionModel.livePreviewImage != nil || sessionModel.isUsingLivePreview {
          previewTruthState = .pausedRecovery
        } else if sessionModel.previewImage != nil || sessionModel.acceptedFrameCount > 0 {
          previewTruthState = .committedOnly
        } else {
          previewTruthState = .pausedRecovery
        }
      } else if sessionModel.isUsingLivePreview, sessionModel.livePreviewImage != nil {
        let hasCommittedTruth = lastCommittedObservationAt != nil || sessionModel.acceptedFrameCount > 0
        let isLiveAhead = !hasCommittedTruth
          || pendingCommitCount > 0
          || previewLagMs > previewTruthLagToleranceMs
        previewTruthState = isLiveAhead ? .liveAhead : .liveSynced
      } else if sessionModel.previewImage != nil || sessionModel.acceptedFrameCount > 0 {
        previewTruthState = .committedOnly
      } else {
        previewTruthState = .ready
      }
    case .finalizing:
      previewTruthState = .finalizing
    case .saving:
      previewTruthState = .saving
    }

    sessionModel.previewTruthState = previewTruthState
    if previewTruthState == .liveAhead {
      sessionMetrics.recordPreviewTruthLiveAhead(lagMs: previewLagMs)
    }
  }

  private func flushSessionMetricsIfNeeded(reason: String) {
    guard !didFlushSessionMetrics else { return }
    guard sessionMetrics.hadActivity else { return }

    didFlushSessionMetrics = true
    DiagnosticLogger.shared.log(
      .info,
      .capture,
      "Scrolling capture session metrics",
      context: sessionMetrics.summaryContext(reason: reason)
    )
  }

  private static func elapsedMilliseconds(since startedAt: CFAbsoluteTime) -> Int {
    Int(((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000).rounded())
  }
}

extension ScrollingCaptureCoordinator: RecordingRegionOverlayDelegate {
  func overlayDidRequestReselection(_ overlay: RecordingRegionOverlayWindow) {}

  func overlay(_ overlay: RecordingRegionOverlayWindow, didMoveRegionTo rect: CGRect) {
    guard let sessionModel, sessionModel.phase == .ready else { return }
    updateSelectedRect(rect, reprepareSession: false)
    sessionModel.statusText = "Release to lock the updated scrolling region."
  }

  func overlayDidFinishMoving(_ overlay: RecordingRegionOverlayWindow) {
    guard let sessionModel, sessionModel.phase == .ready else { return }
    refreshSelectionPreparation()
    sessionModel.statusText =
      "Region updated. Keep only the moving content inside, then press Start Capture. Press Esc to cancel."
  }

  func overlay(_ overlay: RecordingRegionOverlayWindow, didReselectWithRect rect: CGRect) {
    guard let sessionModel, sessionModel.phase == .ready else { return }
    updateSelectedRect(rect, reprepareSession: true)
    sessionModel.statusText =
      "Region updated. Keep only the moving content inside, then press Start Capture. Press Esc to cancel."
  }

  func overlay(_ overlay: RecordingRegionOverlayWindow, didResizeRegionTo rect: CGRect) {
    guard let sessionModel, sessionModel.phase == .ready else { return }
    updateSelectedRect(rect, reprepareSession: false)
    sessionModel.statusText = "Release to lock the updated scrolling region."
  }

  func overlayDidFinishResizing(_ overlay: RecordingRegionOverlayWindow) {
    guard let sessionModel, sessionModel.phase == .ready else { return }
    refreshSelectionPreparation()
    sessionModel.statusText =
      "Region updated. Keep only the moving content inside, then press Start Capture. Press Esc to cancel."
  }
}
