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
  private let maxOutputHeight = ScrollingCaptureConfiguration.maxOutputHeight
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
  private let previewTruthLagToleranceMs = 90
  private let scrollHitSlop: CGFloat = 32
  private let previewRenderScale: CGFloat = 2
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
  private var livePreviewFrameSequence = 0
  private var lastScheduledCommitSequenceNumber = 0
  private var lastScheduledCommitUpdate: ScrollingCaptureStitchUpdate?
  private var lastLivePreviewPublishedAt: TimeInterval?
  private var lastCommittedObservationAt: TimeInterval?
  private var onSessionEnded: (@MainActor () -> Void)?

  var isActive: Bool {
    sessionModel != nil
  }

  func beginSession(
    rect: CGRect,
    saveDirectory: URL,
    format: ImageFormat,
    prefetchedContentTask: ShareableContentPrefetchTask?,
    onSessionEnded: (@MainActor () -> Void)? = nil
  ) {
    cancel()
    sessionGeneration += 1

    self.onSessionEnded = onSessionEnded
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
    self.liveFrameSource = nil
    self.commitScheduler = makeCommitScheduler()
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
    updatePreviewTruthState()

    if ScrollingCaptureConfiguration.showHints {
      AppToastManager.shared.show(
        message: L10n.ScrollingCaptureStatus.readyHintToast,
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
    commitScheduler = nil
    livePreviewFrameSequence = 0
    lastScheduledCommitSequenceNumber = 0
    lastScheduledCommitUpdate = nil
    lastLivePreviewPublishedAt = nil
    lastCommittedObservationAt = nil
    sessionMetrics = ScrollingCaptureSessionMetrics()
    didFlushSessionMetrics = false

    let sessionEndHandler = onSessionEnded
    onSessionEnded = nil
    sessionEndHandler?()
  }

  private func startCapture() {
    guard let sessionModel else { return }
    guard sessionModel.phase == .ready else { return }

    setRegionOverlayInteractionEnabled(false)
    sessionModel.phase = .capturing
    sessionModel.runtimeState = .streaming
    sessionModel.setStatus(
      L10n.ScrollingCaptureStatus.capturingFirstFrame,
      guidance: .holdSteady
    )
    updatePreviewTruthState()
    installScrollMonitorIfNeeded()

    Task { @MainActor in
      await startLivePreviewIfPossible()
      _ = await refreshPreview(reason: "Initial frame captured")
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
        sessionModel.setStatus(
          L10n.ScrollingCaptureStatus.noSavableResultReady,
          guidance: .keepCapturing
        )
        sessionModel.previewCaption = L10n.ScrollingCapture.captionNoSavableResultReady
        updatePreviewTruthState()
        AppToastManager.shared.show(message: L10n.ScrollingCapture.toastNoStitchedFrameReady, style: .warning)
        return
      }

      sessionMetrics.recordFinalizingCompleted(at: ProcessInfo.processInfo.systemUptime)
      sessionModel.phase = .saving
      sessionModel.runtimeState = .saving
      sessionModel.setStatus(
        L10n.ScrollingCaptureStatus.savingStitchedImage,
        guidance: .savingLongScreenshot
      )
      sessionModel.previewCaption = L10n.ScrollingCapture.captionSavingStitchedResult
      updatePreviewTruthState()

      let result = await captureManager.saveProcessedImage(
        latestImage,
        to: saveDirectory,
        format: format,
        scaleFactor: captureScaleFactor
      )

      switch result {
      case .success:
        flushSessionMetricsIfNeeded(reason: "saved")
        SoundManager.playScreenshotCapture()
        AppToastManager.shared.show(
          message: L10n.ScrollingCapture.toastSavedStitchedImage,
          style: .info
        )
        cancel()
      case .failure(let error):
        sessionModel.phase = .capturing
        sessionModel.runtimeState = .paused
        sessionModel.setStatus(
          L10n.ScrollingCaptureStatus.saveFailedResultStillReady,
          guidance: .tryDoneAgain
        )
        sessionModel.previewCaption = L10n.ScrollingCapture.captionSaveFailedResultStillReady
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
      sessionModel.setStatus(
        L10n.ScrollingCaptureStatus.directionChanged,
        guidance: .keepOneDirection
      )
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

    sessionModel.setStatus(
      L10n.ScrollingCaptureStatus.aligningLatestContent,
      guidance: .scrollDownSteadily
    )
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
        sessionModel.setStatus(
          isFinalizingRefresh
            ? L10n.ScrollingCaptureStatus.mixedDirectionsFinalizing
            : L10n.ScrollingCaptureStatus.mixedDirectionsDetected,
          guidance: isFinalizingRefresh ? .lockingCurrentCapture : .keepOneDirection
        )
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
        sessionModel.setStatus(
          isFinalizingRefresh
            ? L10n.ScrollingCaptureStatus.couldntCaptureLastFrame
            : L10n.ScrollingCaptureStatus.unableToCaptureArea,
          guidance: isFinalizingRefresh ? .lockingCurrentCapture : .previewNeedsRecovery
        )
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
        sessionModel.setStatus(
          isFinalizingRefresh
            ? L10n.ScrollingCaptureStatus.couldntRefreshLastFrame
            : L10n.ScrollingCaptureStatus.unableToRenderPreview,
          guidance: isFinalizingRefresh ? .lockingCurrentCapture : .previewNeedsRecovery
        )
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
      }
      if let processedStitcher {
        sessionModel.previewImage =
          makePreviewImage(from: processedStitcher)
          ?? update.mergedImage
          ?? sessionModel.previewImage
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
        sessionModel.setStatus(
          finalizingStatusText(for: update),
          guidance: finalizingGuidanceKind(for: update)
        )
        updatePreviewTruthState()
        return update
      }

      switch update.outcome {
      case .initialized:
        lastAcceptedDeltaPixels = nil
        sessionModel.runtimeState = previewRuntimeState()
        sessionModel.previewCaption = L10n.ScrollingCapture.captionFirstFrameLocked
        sessionModel.setStatus(
          L10n.ScrollingCaptureStatus.firstFrameLocked,
          guidance: .holdSteady
        )
      case .appended(let deltaY):
        lastAcceptedDeltaPixels = deltaY
        sessionModel.runtimeState = previewRuntimeState()
        sessionModel.previewCaption = L10n.ScrollingCapture.framesStitchedDelta(update.acceptedFrameCount, deltaY)
        sessionModel.setStatus(
          L10n.ScrollingCaptureStatus.sessionActive(update.acceptedFrameCount, update.outputHeight),
          guidance: .scrollDownSteadily
        )
      case .ignoredNoMovement:
        sessionModel.runtimeState = previewRuntimeState()
        if update.likelyReachedBoundary {
          sessionModel.previewCaption = L10n.ScrollingCapture.framesStitchedNoNewContent(update.acceptedFrameCount)
          sessionModel.setStatus(
            L10n.ScrollingCaptureStatus.endReachedNoNewContent,
            guidance: .pressDoneNoNewContent
          )
        } else {
          sessionModel.setStatus(
            L10n.ScrollingCaptureStatus.waitingForNewContent,
            guidance: .keepScrollingDown
          )
        }
      case .ignoredAlignmentFailed:
        sessionModel.runtimeState = update.matchFailureCount >= 2 ? .paused : previewRuntimeState()
        if update.matchFailureCount >= 2 {
          sessionModel.setStatus(
            L10n.ScrollingCaptureStatus.alignmentPaused,
            guidance: .slowDown
          )
        } else {
          sessionModel.setStatus(
            L10n.ScrollingCaptureStatus.couldntAlignFrame,
            guidance: .keepSteadierPace
          )
        }
      case .reachedHeightLimit:
        sessionModel.runtimeState = .paused
        sessionModel.previewCaption = L10n.ScrollingCapture.framesStitchedHeightLimitReached(update.acceptedFrameCount)
        sessionModel.setStatus(
          L10n.ScrollingCaptureStatus.heightLimitReached(maxOutputHeight),
          guidance: .heightLimitReached
        )
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
      sessionModel.setStatus(
        isFinalizingRefresh
          ? L10n.ScrollingCaptureStatus.finalizingCurrentCapture
          : L10n.ScrollingCaptureStatus.previewRefreshFailed,
        guidance: isFinalizingRefresh ? .lockingCurrentCapture : .previewNeedsRecovery
      )
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
    livePreviewFrameSequence = 0
    lastScheduledCommitSequenceNumber = 0
    lastScheduledCommitUpdate = nil
    lastLivePreviewPublishedAt = nil
    lastCommittedObservationAt = nil
    sessionModel.previewImage = nil
    sessionModel.livePreviewImage = nil
    sessionModel.isUsingLivePreview = false
    sessionModel.previewCaption = L10n.ScrollingCapture.captionStartCaptureToLockFirstFrame
    sessionModel.acceptedFrameCount = 0
    sessionModel.stitchedPixelHeight = 0
    sessionModel.runtimeState = .ready
    sessionModel.setStatus(
      L10n.ScrollingCaptureStatus.adjustRegion,
      guidance: .frameOnlyScrollingContent
    )

    prewarmCaptureContext(for: selectedRect)
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
      sessionModel.previewCaption = L10n.ScrollingCapture.captionLivePreviewRunning
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

  private func beginFinalizing() {
    guard let sessionModel else { return }

    pendingRefreshTask?.cancel()
    pendingRefreshTask = nil
    sessionModel.phase = .finalizing
    sessionModel.runtimeState = .finalizing
    sessionModel.setStatus(
      L10n.ScrollingCaptureStatus.finalizingCurrentCapture,
      guidance: .lockingCurrentCapture
    )
    sessionModel.previewCaption = L10n.ScrollingCapture.captionFinalizingStitchedResult
    sessionMetrics.recordFinalizingStarted(at: ProcessInfo.processInfo.systemUptime)
    updatePreviewTruthState()
  }

  private func makePreviewImage(from stitcher: ScrollingCaptureStitcher) -> CGImage? {
    stitcher.previewImage(
      maxPixelWidth: Int((ScrollingCapturePreviewLayout.previewWidth * previewRenderScale).rounded()),
      maxPixelHeight: Int((ScrollingCapturePreviewLayout.maxPreviewHeight * previewRenderScale).rounded())
    )
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
      return L10n.ScrollingCapture.finalizingFramesLocked(update.acceptedFrameCount)
    case .ignoredNoMovement:
      return update.likelyReachedBoundary
        ? L10n.ScrollingCapture.captionFinalizingCurrentResultNoNewContent
        : L10n.ScrollingCapture.finalizingFramesLocked(update.acceptedFrameCount)
    case .appended(let deltaY):
      return L10n.ScrollingCapture.finalFrameLocked(update.acceptedFrameCount, deltaY)
    case .ignoredAlignmentFailed:
      return L10n.ScrollingCapture.captionFinalizingCurrentResultLastFrameSkipped
    case .reachedHeightLimit:
      return L10n.ScrollingCapture.framesStitchedHeightLimitReached(update.acceptedFrameCount)
    }
  }

  private func finalizingStatusText(for update: ScrollingCaptureStitchUpdate) -> String {
    switch update.outcome {
    case .initialized, .appended:
      return L10n.ScrollingCaptureStatus.finalizingFrames(update.acceptedFrameCount)
    case .ignoredNoMovement:
      return update.likelyReachedBoundary
        ? L10n.ScrollingCaptureStatus.finalizingNoNewContent
        : L10n.ScrollingCaptureStatus.finalizingFrames(update.acceptedFrameCount)
    case .ignoredAlignmentFailed:
      return L10n.ScrollingCaptureStatus.finalizingCouldntAlignLastFrame
    case .reachedHeightLimit:
      return L10n.ScrollingCaptureStatus.finalizingHeightLimitReached
    }
  }

  private func finalizingGuidanceKind(for update: ScrollingCaptureStitchUpdate) -> ScrollingCaptureSelectionGuidanceKind {
    switch update.outcome {
    case .reachedHeightLimit:
      return .savingCurrentResult
    case .initialized, .appended, .ignoredNoMovement, .ignoredAlignmentFailed:
      return .lockingCurrentCapture
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
    sessionModel.setStatus(
      L10n.ScrollingCaptureStatus.releaseToLockUpdatedRegion,
      guidance: .releaseToLockArea
    )
  }

  func overlayDidFinishMoving(_ overlay: RecordingRegionOverlayWindow) {
    guard let sessionModel, sessionModel.phase == .ready else { return }
    refreshSelectionPreparation()
    sessionModel.setStatus(
      L10n.ScrollingCaptureStatus.regionUpdated,
      guidance: .areaUpdated
    )
  }

  func overlay(_ overlay: RecordingRegionOverlayWindow, didReselectWithRect rect: CGRect) {
    guard let sessionModel, sessionModel.phase == .ready else { return }
    updateSelectedRect(rect, reprepareSession: true)
    sessionModel.setStatus(
      L10n.ScrollingCaptureStatus.regionUpdated,
      guidance: .areaUpdated
    )
  }

  func overlay(_ overlay: RecordingRegionOverlayWindow, didResizeRegionTo rect: CGRect) {
    guard let sessionModel, sessionModel.phase == .ready else { return }
    updateSelectedRect(rect, reprepareSession: false)
    sessionModel.setStatus(
      L10n.ScrollingCaptureStatus.releaseToLockUpdatedRegion,
      guidance: .releaseToLockArea
    )
  }

  func overlayDidFinishResizing(_ overlay: RecordingRegionOverlayWindow) {
    guard let sessionModel, sessionModel.phase == .ready else { return }
    refreshSelectionPreparation()
    sessionModel.setStatus(
      L10n.ScrollingCaptureStatus.regionUpdated,
      guidance: .areaUpdated
    )
  }
}
