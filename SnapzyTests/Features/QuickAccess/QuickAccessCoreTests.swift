//
//  QuickAccessCoreTests.swift
//  SnapzyTests
//
//  Unit tests for Quick Access models and countdown behavior.
//

import AppKit
import XCTest
@testable import Snapzy

private final class QuickAccessPinMockMagnifyEvent: NSEvent {
  let delta: CGFloat
  let location: NSPoint

  init(delta: CGFloat, location: NSPoint = NSPoint(x: 200, y: 150)) {
    self.delta = delta
    self.location = location
    super.init()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override var type: NSEvent.EventType { .magnify }
  override var magnification: CGFloat { delta }
  override var locationInWindow: NSPoint { location }
  override var phase: NSEvent.Phase { .changed }
}

private final class QuickAccessPinMockScrollWheelEvent: NSEvent {
  let eventDeltaX: CGFloat
  let eventDeltaY: CGFloat
  let flags: NSEvent.ModifierFlags
  let precise: Bool
  let location: NSPoint

  init(
    deltaX: CGFloat = 0,
    deltaY: CGFloat,
    modifierFlags: NSEvent.ModifierFlags = [],
    hasPreciseDeltas: Bool,
    location: NSPoint = NSPoint(x: 200, y: 150)
  ) {
    eventDeltaX = deltaX
    eventDeltaY = deltaY
    flags = modifierFlags
    precise = hasPreciseDeltas
    self.location = location
    super.init()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override var type: NSEvent.EventType { .scrollWheel }
  override var scrollingDeltaX: CGFloat { eventDeltaX }
  override var scrollingDeltaY: CGFloat { eventDeltaY }
  override var modifierFlags: NSEvent.ModifierFlags { flags }
  override var hasPreciseScrollingDeltas: Bool { precise }
  override var locationInWindow: NSPoint { location }
  override var phase: NSEvent.Phase { .changed }
}

@MainActor
final class QuickAccessCoreTests: XCTestCase {
  // Keep MainActor ObservableObjects alive for the test process; XCTest scope
  // cleanup can crash while deinitializing app-level observable stores.
  private static var retainedActionStores: [QuickAccessActionConfigurationStore] = []
  private static var retainedPinZoomModeStores: [QuickAccessPinZoomModeStore] = []
  private static var retainedPinWindowStates: [QuickAccessPinWindowState] = []

  func testQuickAccessSound_respectsGlobalAndQuickAccessPreferences() {
    let defaults = UserDefaultsFactory.make()

    XCTAssertTrue(QuickAccessSound.appear.shouldPlay(reduceMotion: false, defaults: defaults))

    defaults.set(false, forKey: PreferencesKeys.quickAccessPlaySounds)
    XCTAssertFalse(QuickAccessSound.appear.shouldPlay(reduceMotion: false, defaults: defaults))
    XCTAssertTrue(QuickAccessSound.failed.shouldPlay(reduceMotion: false, defaults: defaults))

    defaults.set(true, forKey: PreferencesKeys.quickAccessPlaySounds)
    defaults.set(false, forKey: PreferencesKeys.playSounds)
    XCTAssertFalse(QuickAccessSound.appear.shouldPlay(reduceMotion: false, defaults: defaults))
    XCTAssertFalse(QuickAccessSound.failed.shouldPlay(reduceMotion: false, defaults: defaults))

    defaults.set(true, forKey: PreferencesKeys.playSounds)
    XCTAssertFalse(QuickAccessSound.appear.shouldPlay(reduceMotion: true, defaults: defaults))
  }

  func testQuickAccessItem_formatsVideoDurationAndOmitsInvalidDurations() {
    let thumbnail = NSImage(size: CGSize(width: 16, height: 16))
    let video = QuickAccessItem(
      url: URL(fileURLWithPath: "/tmp/demo.mov"),
      thumbnail: thumbnail,
      duration: 90.9
    )
    let invalidVideo = QuickAccessItem(
      id: UUID(),
      url: URL(fileURLWithPath: "/tmp/bad.mov"),
      thumbnail: thumbnail,
      capturedAt: Date(),
      itemType: .video,
      duration: -.infinity
    )
    let screenshot = QuickAccessItem(
      url: URL(fileURLWithPath: "/tmp/demo.png"),
      thumbnail: thumbnail
    )

    XCTAssertTrue(video.isVideo)
    XCTAssertEqual(video.formattedDuration, "01:30s")
    // Durations >= 1 hour surface the hours field instead of overflowing minutes.
    let hourLongVideo = QuickAccessItem(
      url: URL(fileURLWithPath: "/tmp/long.mov"),
      thumbnail: thumbnail,
      duration: 3661
    )
    XCTAssertEqual(hourLongVideo.formattedDuration, "1:01:01s")
    XCTAssertNil(invalidVideo.formattedDuration)
    XCTAssertFalse(screenshot.isVideo)
    XCTAssertNil(screenshot.formattedDuration)
  }

  func testQuickAccessProcessingState_identifiesProcessingOnly() {
    XCTAssertFalse(QuickAccessProcessingState.idle.isProcessing)
    XCTAssertTrue(QuickAccessProcessingState.processing(progress: nil).isProcessing)
    XCTAssertTrue(QuickAccessProcessingState.processing(progress: 0.4).isProcessing)
    XCTAssertFalse(QuickAccessProcessingState.complete.isProcessing)
    XCTAssertFalse(QuickAccessProcessingState.failed.isProcessing)
  }

  func testQuickAccessItem_thumbnailReplacementPreservesEditorSessionState() throws {
    let id = UUID()
    let url = URL(fileURLWithPath: "/tmp/demo.mov")
    let cloudURL = try XCTUnwrap(URL(string: "https://example.com/demo"))
    let thumbnail = NSImage(size: CGSize(width: 16, height: 16))
    var item = QuickAccessItem(
      id: id,
      url: url,
      thumbnail: thumbnail,
      capturedAt: Date(),
      itemType: .video,
      duration: 1,
      cloudURL: cloudURL,
      cloudKey: "demo-key",
      isCloudStale: true,
      isPinned: true,
      isWindowOpen: true
    )
    item.processingState = .processing(progress: 0.5)

    let updated = item.replacingThumbnail(NSImage(size: CGSize(width: 32, height: 32)))

    XCTAssertEqual(updated.id, id)
    XCTAssertEqual(updated.url, url)
    XCTAssertEqual(updated.cloudURL, cloudURL)
    XCTAssertEqual(updated.cloudKey, "demo-key")
    XCTAssertTrue(updated.isCloudStale)
    XCTAssertTrue(updated.isPinned)
    XCTAssertTrue(updated.isWindowOpen)
    XCTAssertEqual(updated.processingState, .processing(progress: 0.5))
    XCTAssertNotEqual(updated.thumbnailVersion, item.thumbnailVersion)
  }

  func testQuickAccessItem_urlReplacementPreservesEditorSessionState() {
    let originalURL = URL(fileURLWithPath: "/tmp/original.mov")
    let replacementURL = URL(fileURLWithPath: "/tmp/replacement.mov")
    var item = QuickAccessItem(
      id: UUID(),
      url: originalURL,
      thumbnail: NSImage(size: CGSize(width: 16, height: 16)),
      capturedAt: Date(),
      itemType: .video,
      duration: 1,
      cloudKey: "demo-key",
      isPinned: true,
      isWindowOpen: true
    )
    item.processingState = .complete

    let updated = item.replacingURL(replacementURL)

    XCTAssertEqual(updated.url, replacementURL)
    XCTAssertEqual(updated.cloudKey, "demo-key")
    XCTAssertTrue(updated.isPinned)
    XCTAssertTrue(updated.isWindowOpen)
    XCTAssertEqual(updated.processingState, .complete)
  }

  func testQuickAccessCardDragPolicy_classifiesRightPanelDirections() {
    let policy = QuickAccessCardDragPolicy(dismissDirection: 1)

    XCTAssertEqual(policy.intent(forHorizontalTranslation: 30), .undetermined)
    XCTAssertEqual(policy.intent(forHorizontalTranslation: 31), .swipeToDismiss)
    XCTAssertEqual(policy.intent(forHorizontalTranslation: -31), .dragToApp)
  }

  func testQuickAccessCardDragPolicy_classifiesLeftPanelDirections() {
    let policy = QuickAccessCardDragPolicy(dismissDirection: -1)

    XCTAssertEqual(policy.intent(forHorizontalTranslation: -31), .swipeToDismiss)
    XCTAssertEqual(policy.intent(forHorizontalTranslation: 31), .dragToApp)
  }

  func testQuickAccessCardDragPolicy_directDragUsesTwoDimensionalThreshold() {
    XCTAssertFalse(
      QuickAccessCardDragPolicy.shouldBeginDirectDrag(
        horizontalTranslation: 4,
        verticalTranslation: 4
      )
    )
    XCTAssertTrue(
      QuickAccessCardDragPolicy.shouldBeginDirectDrag(
        horizontalTranslation: 6,
        verticalTranslation: 0
      )
    )
    XCTAssertTrue(
      QuickAccessCardDragPolicy.shouldBeginDirectDrag(
        horizontalTranslation: 0,
        verticalTranslation: -6
      )
    )
    XCTAssertFalse(
      QuickAccessCardDragPolicy.shouldBeginDirectDrag(
        horizontalTranslation: .nan,
        verticalTranslation: 10
      )
    )
    XCTAssertFalse(
      QuickAccessCardDragPolicy.shouldBeginDirectDrag(
        horizontalTranslation: 12,
        verticalTranslation: 2,
        reservedScrollAxis: .horizontal
      )
    )
    XCTAssertTrue(
      QuickAccessCardDragPolicy.shouldBeginDirectDrag(
        horizontalTranslation: 6,
        verticalTranslation: 8,
        reservedScrollAxis: .horizontal
      )
    )
    XCTAssertFalse(
      QuickAccessCardDragPolicy.shouldBeginDirectDrag(
        horizontalTranslation: 2,
        verticalTranslation: 12,
        reservedScrollAxis: .vertical
      )
    )
    XCTAssertTrue(
      QuickAccessCardDragPolicy.shouldBeginDirectDrag(
        horizontalTranslation: 8,
        verticalTranslation: 6,
        reservedScrollAxis: .vertical
      )
    )
    XCTAssertTrue(
      QuickAccessCardDragPolicy.isPrimaryScrollGesture(
        horizontalTranslation: 12,
        verticalTranslation: 2,
        reservedScrollAxis: .horizontal
      )
    )
    XCTAssertFalse(
      QuickAccessCardDragPolicy.isPrimaryScrollGesture(
        horizontalTranslation: 6,
        verticalTranslation: 8,
        reservedScrollAxis: .horizontal
      )
    )
  }

  func testQuickAccessCardDragPolicy_dismissesByDistanceOrVelocity() {
    let policy = QuickAccessCardDragPolicy(dismissDirection: 1)

    XCTAssertFalse(policy.shouldDismiss(horizontalTranslation: 80, horizontalVelocity: 300))
    XCTAssertTrue(policy.shouldDismiss(horizontalTranslation: 81, horizontalVelocity: 0))
    XCTAssertTrue(policy.shouldDismiss(horizontalTranslation: 10, horizontalVelocity: 301))
    XCTAssertFalse(policy.shouldDismiss(horizontalTranslation: -81, horizontalVelocity: 0))
    XCTAssertFalse(policy.shouldDismiss(horizontalTranslation: -10, horizontalVelocity: -301))
  }

  func testQuickAccessTrackpadSwipeHelpers_requiresPreciseDominantHorizontalScroll() {
    XCTAssertEqual(
      QuickAccessTrackpadSwipeHelpers.horizontalDelta(
        scrollingDeltaX: 12,
        scrollingDeltaY: 2,
        hasPreciseScrollingDeltas: true,
        sensitivityMultiplier: 1.0
      ),
      12
    )
    XCTAssertNil(
      QuickAccessTrackpadSwipeHelpers.horizontalDelta(
        scrollingDeltaX: 12,
        scrollingDeltaY: 10,
        hasPreciseScrollingDeltas: true,
        sensitivityMultiplier: 1.0
      )
    )
    XCTAssertNil(
      QuickAccessTrackpadSwipeHelpers.horizontalDelta(
        scrollingDeltaX: 0.25,
        scrollingDeltaY: 0,
        hasPreciseScrollingDeltas: true,
        sensitivityMultiplier: 1.0
      )
    )
    XCTAssertNil(
      QuickAccessTrackpadSwipeHelpers.horizontalDelta(
        scrollingDeltaX: 12,
        scrollingDeltaY: 0,
        hasPreciseScrollingDeltas: false,
        sensitivityMultiplier: 1.0
      )
    )
    XCTAssertNil(
      QuickAccessTrackpadSwipeHelpers.horizontalDelta(
        scrollingDeltaX: .nan,
        scrollingDeltaY: 0,
        hasPreciseScrollingDeltas: true,
        sensitivityMultiplier: 1.0
      )
    )
  }

  func testQuickAccessTrackpadSwipeHelpers_sensitivityMultiplierAmplifiesDelta() {
    XCTAssertEqual(
      QuickAccessTrackpadSwipeHelpers.horizontalDelta(
        scrollingDeltaX: 10,
        scrollingDeltaY: 1,
        hasPreciseScrollingDeltas: true,
        sensitivityMultiplier: 0.5
      ),
      5
    )
    XCTAssertEqual(
      QuickAccessTrackpadSwipeHelpers.horizontalDelta(
        scrollingDeltaX: 10,
        scrollingDeltaY: 1,
        hasPreciseScrollingDeltas: true,
        sensitivityMultiplier: 3.0
      ),
      30
    )
    XCTAssertNil(
      QuickAccessTrackpadSwipeHelpers.horizontalDelta(
        scrollingDeltaX: 10,
        scrollingDeltaY: 1,
        hasPreciseScrollingDeltas: false,
        sensitivityMultiplier: 3.0
      )
    )
  }

  func testQuickAccessTrackpadSwipeHelpers_dismissesByDistanceOrVelocity() {
    XCTAssertFalse(
      QuickAccessTrackpadSwipeHelpers.shouldDismiss(
        horizontalTranslation: 80,
        horizontalVelocity: 300
      )
    )
    XCTAssertTrue(
      QuickAccessTrackpadSwipeHelpers.shouldDismiss(
        horizontalTranslation: 81,
        horizontalVelocity: 0
      )
    )
    XCTAssertTrue(
      QuickAccessTrackpadSwipeHelpers.shouldDismiss(
        horizontalTranslation: 10,
        horizontalVelocity: 301
      )
    )
  }

  func testQuickAccessTrackpadSwipeModeStore_persistsMode() {
    let defaults = makeIsolatedDefaults()

    let store = QuickAccessTrackpadSwipeModeStore(defaults: defaults)
    XCTAssertEqual(store.mode, .inverted)

    store.setMode(.natural)
    XCTAssertEqual(store.mode, .natural)

    let reloadedStore = QuickAccessTrackpadSwipeModeStore(defaults: defaults)
    XCTAssertEqual(reloadedStore.mode, .natural)
  }

  func testQuickAccessTrackpadSwipeModeStore_resetToDefault() {
    let defaults = makeIsolatedDefaults()

    let store = QuickAccessTrackpadSwipeModeStore(defaults: defaults)
    store.setMode(.natural)
    store.resetToDefault()

    XCTAssertEqual(store.mode, .inverted)
  }

  func testQuickAccessPinZoomModeStore_defaultsToFixedViewportAndPersistsExplicitSelection() {
    let suiteName = "QuickAccessPinZoomModeStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = QuickAccessPinZoomModeStore(defaults: defaults)
    Self.retainedPinZoomModeStores.append(store)
    XCTAssertEqual(store.mode, .fixedViewport)
    store.setMode(.windowFollowsImage)
    let reloadedStore = QuickAccessPinZoomModeStore(defaults: defaults)
    Self.retainedPinZoomModeStores.append(reloadedStore)
    XCTAssertEqual(reloadedStore.mode, .windowFollowsImage)
  }

  func testQuickAccessPinWindowState_defaultsToFixedViewport() {
    let image = NSImage(size: CGSize(width: 400, height: 300))
    let state = QuickAccessPinWindowState(
      id: UUID(),
      url: URL(fileURLWithPath: "/tmp/default-pinned.png"),
      image: image,
      thumbnail: image,
      baseSize: CGSize(width: 600, height: 450)
    )
    Self.retainedPinWindowStates.append(state)

    XCTAssertEqual(state.zoomMode, .fixedViewport)
  }

  func testQuickAccessDragMonitorView_scopesScrollEventsToCardBounds() {
    final class MockLocationEvent: NSEvent {
      private let point: NSPoint

      init(point: NSPoint) {
        self.point = point
        super.init()
      }

      @available(*, unavailable)
      required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
      }

      override var locationInWindow: NSPoint { point }
    }

    let monitor = QuickAccessDragMonitorView(
      fileURL: URL(fileURLWithPath: "/tmp/demo.png"),
      thumbnail: NSImage(size: CGSize(width: 16, height: 16)),
      dismissDirection: 1,
      dragDropEnabled: true,
      twoFingerSwipeToDismissEnabled: true,
      swipeMode: .natural,
      swipeSensitivity: 1.0,
      onDragStarted: {},
      onDragEnded: { _ in },
      onSwipeChanged: { _ in },
      onSwipeEnded: { _, _ in }
    )
    monitor.frame = NSRect(x: 0, y: 0, width: 180, height: 112)

    XCTAssertTrue(monitor.containsEventLocation(MockLocationEvent(point: NSPoint(x: 90, y: 56))))
    XCTAssertFalse(monitor.containsEventLocation(MockLocationEvent(point: NSPoint(x: 200, y: 56))))
    XCTAssertFalse(monitor.containsEventLocation(MockLocationEvent(point: NSPoint(x: 90, y: 140))))
  }

  func testQuickAccessItemEquality_tracksMutablePresentationState() {
    let id = UUID()
    let thumbnail = NSImage(size: CGSize(width: 16, height: 16))
    let capturedAt = Date()
    let thumbnailVersion = UUID()
    let base = QuickAccessItem(
      id: id,
      url: URL(fileURLWithPath: "/tmp/demo.png"),
      thumbnail: thumbnail,
      capturedAt: capturedAt,
      itemType: .screenshot,
      duration: nil,
      thumbnailVersion: thumbnailVersion
    )
    var uploaded = base
    uploaded.cloudURL = URL(string: "https://cdn.example.com/demo.png")

    XCTAssertEqual(base, base)
    XCTAssertNotEqual(base, uploaded)

    var pinned = base
    pinned.isPinned = true
    XCTAssertNotEqual(base, pinned)
  }

  func testQuickAccessPinWindowSizing_enforcesMinimumInteractiveSizeForTinyImages() {
    let size = QuickAccessPinWindowSizing.size(
      for: CGSize(width: 24, height: 16),
      visibleSize: CGSize(width: 1440, height: 900)
    )
    let minimumSize = QuickAccessPinWindowSizing.minimumInteractiveSize

    XCTAssertGreaterThanOrEqual(size.width, minimumSize.width)
    XCTAssertGreaterThanOrEqual(size.height, minimumSize.height)
    XCTAssertLessThanOrEqual(size.width, 1440)
    XCTAssertLessThanOrEqual(size.height, 900)
  }

  func testQuickAccessPinWindowSizing_fixedViewportFitsWidthAndCapsHeight() {
    let size = QuickAccessPinWindowSizing.size(
      for: CGSize(width: 1200, height: 2400),
      visibleSize: CGSize(width: 1200, height: 900),
      mode: .fixedViewport
    )
    XCTAssertEqual(size.width, 1200 * 0.8, accuracy: 0.001)
    XCTAssertEqual(size.height, 900 * 0.8, accuracy: 0.001)
  }

  func testQuickAccessPinWindowSizing_windowFollowsImageUsesEightyPercentScreenLimit() {
    let size = QuickAccessPinWindowSizing.size(
      for: CGSize(width: 2400, height: 1200),
      visibleSize: CGSize(width: 1200, height: 900)
    )

    XCTAssertEqual(size.width, 1200 * 0.8, accuracy: 0.001)
    XCTAssertEqual(size.height, 480, accuracy: 0.001)
  }

  func testQuickAccessPinWindowState_keepsMinimumInteractiveFrameAtMinimumZoom() {
    let minimumSize = QuickAccessPinWindowSizing.minimumInteractiveSize
    let image = NSImage(size: CGSize(width: 24, height: 16))
    let state = QuickAccessPinWindowState(
      id: UUID(),
      url: URL(fileURLWithPath: "/tmp/tiny.png"),
      image: image,
      thumbnail: image,
      baseSize: minimumSize,
      zoomMode: .windowFollowsImage
    )
    Self.retainedPinWindowStates.append(state)

    state.setZoomPercent(10)

    XCTAssertEqual(state.displaySize, minimumSize)
    XCTAssertEqual(state.imageDisplaySize.width, 96, accuracy: 0.001)
    XCTAssertEqual(state.imageDisplaySize.height, 64, accuracy: 0.001)
    XCTAssertEqual(state.zoomPercent, 40)
    XCTAssertTrue(state.zoomMenuPercents.contains(800))

    state.setZoomPercent(900)
    XCTAssertEqual(state.zoomPercent, 800)
  }

  func testQuickAccessPinWindowState_preservesFortyPercentForLargeImagesAndFixedViewportSize() {
    let image = NSImage(size: CGSize(width: 1200, height: 900))
    let followsState = QuickAccessPinWindowState(
      id: UUID(),
      url: URL(fileURLWithPath: "/tmp/large.png"),
      image: image,
      thumbnail: image,
      baseSize: image.size,
      zoomMode: .windowFollowsImage
    )
    let fixedBaseSize = CGSize(width: 600, height: 420)
    let fixedState = QuickAccessPinWindowState(
      id: UUID(),
      url: URL(fileURLWithPath: "/tmp/large-fixed.png"),
      image: image,
      thumbnail: image,
      baseSize: fixedBaseSize,
      zoomMode: .fixedViewport
    )
    Self.retainedPinWindowStates.append(contentsOf: [followsState, fixedState])

    followsState.updateZoomFactor(0.4)
    fixedState.updateZoomFactor(0.4)

    XCTAssertEqual(followsState.displaySize, CGSize(width: 480, height: 360))
    XCTAssertEqual(fixedState.displaySize, fixedBaseSize)
    XCTAssertEqual(fixedState.imageDisplaySize, CGSize(width: 240, height: 180))
  }

  func testQuickAccessPinWindowState_switchingModesResetsZoomAndPan() {
    let image = NSImage(size: CGSize(width: 400, height: 300))
    let state = QuickAccessPinWindowState(
      id: UUID(),
      url: URL(fileURLWithPath: "/tmp/pinned.png"),
      image: image,
      thumbnail: image,
      baseSize: CGSize(width: 400, height: 300),
      zoomMode: .windowFollowsImage
    )
    Self.retainedPinWindowStates.append(state)
    state.updateZoomFactor(2)

    let fixedSize = QuickAccessPinWindowSizing.size(
      for: image.size,
      visibleSize: CGSize(width: 1200, height: 900),
      mode: .fixedViewport
    )
    state.setZoomMode(.fixedViewport, baseSize: fixedSize)

    XCTAssertEqual(state.zoomMode, .fixedViewport)
    XCTAssertEqual(state.zoomFactor, 1, accuracy: 0.001)
    XCTAssertEqual(state.panOffset, .zero)
    XCTAssertEqual(state.displaySize, fixedSize)

    state.updateViewport(magnification: 2, panOffset: CGPoint(x: 60, y: -40))
    state.setZoomMode(.windowFollowsImage, baseSize: CGSize(width: 400, height: 300))

    XCTAssertEqual(state.zoomMode, .windowFollowsImage)
    XCTAssertEqual(state.zoomFactor, 1, accuracy: 0.001)
    XCTAssertEqual(state.panOffset, .zero)
    XCTAssertEqual(state.displaySize, CGSize(width: 400, height: 300))
  }

  func testQuickAccessPinWindowState_sameModeKeepsZoomPanAndFrameWhileModeChangeResetsThem() {
    let image = NSImage(size: CGSize(width: 400, height: 300))
    let state = QuickAccessPinWindowState(
      id: UUID(),
      url: URL(fileURLWithPath: "/tmp/pinned.png"),
      image: image,
      thumbnail: image,
      baseSize: image.size,
      zoomMode: .windowFollowsImage
    )
    Self.retainedPinWindowStates.append(state)

    state.updateZoomFactor(2)
    let windowFollowingSize = state.displaySize
    XCTAssertFalse(state.setZoomMode(.windowFollowsImage, baseSize: image.size))
    XCTAssertEqual(state.zoomFactor, 2, accuracy: 0.001)
    XCTAssertEqual(state.panOffset, .zero)
    XCTAssertEqual(state.displaySize, windowFollowingSize)

    let fixedBaseSize = CGSize(width: 600, height: 450)
    XCTAssertTrue(state.setZoomMode(.fixedViewport, baseSize: fixedBaseSize))
    state.updateViewport(magnification: 2, panOffset: CGPoint(x: 60, y: -40))
    let fixedFrameSize = state.displaySize

    XCTAssertFalse(state.setZoomMode(.fixedViewport, baseSize: fixedBaseSize))
    XCTAssertEqual(state.zoomFactor, 2, accuracy: 0.001)
    XCTAssertEqual(state.panOffset, CGPoint(x: 60, y: -40))
    XCTAssertEqual(state.displaySize, fixedFrameSize)

    XCTAssertTrue(state.setZoomMode(.windowFollowsImage, baseSize: image.size))
    XCTAssertEqual(state.zoomFactor, 1, accuracy: 0.001)
    XCTAssertEqual(state.panOffset, .zero)
    XCTAssertEqual(state.displaySize, image.size)
  }

  func testQuickAccessPinWindowState_reclampsViewportPanWhenBaseSizeChanges() {
    let image = NSImage(size: CGSize(width: 400, height: 300))
    let state = QuickAccessPinWindowState(
      id: UUID(),
      url: URL(fileURLWithPath: "/tmp/pinned.png"),
      image: image,
      thumbnail: image,
      baseSize: CGSize(width: 400, height: 300),
      zoomMode: .fixedViewport
    )
    Self.retainedPinWindowStates.append(state)

    state.updateViewport(
      magnification: 2,
      panOffset: CGPoint(x: 190, y: 140)
    )
    let displaySize = state.updateSizing(baseSize: CGSize(width: 300, height: 225))

    XCTAssertEqual(state.zoomPercent, 200)
    XCTAssertEqual(state.panOffset.x, 150, accuracy: 0.001)
    XCTAssertEqual(state.panOffset.y, 112.5, accuracy: 0.001)
    XCTAssertEqual(displaySize.width, 300, accuracy: 0.001)
    XCTAssertEqual(displaySize.height, 225, accuracy: 0.001)
  }

  func testQuickAccessPinImageGeometry_clampsPanAndRoundTripsScrollCoordinates() {
    let viewport = CGSize(width: 400, height: 300)
    let clamped = QuickAccessPinImageGeometry.clampedPanOffset(
      CGPoint(x: 999, y: -999),
      viewportSize: viewport,
      contentSize: CGSize(width: 800, height: 200)
    )
    XCTAssertEqual(clamped.x, 200, accuracy: 0.001)
    XCTAssertEqual(clamped.y, 0, accuracy: 0.001)

    let visibleOrigin = QuickAccessPinImageGeometry.visibleRectOrigin(
      panOffset: CGPoint(x: 120, y: -80),
      documentSize: CGSize(width: 400, height: 300),
      visibleSize: CGSize(width: 200, height: 150),
      magnification: 2
    )
    let restoredPan = QuickAccessPinImageGeometry.panOffset(
      documentSize: CGSize(width: 400, height: 300),
      visibleRect: CGRect(origin: visibleOrigin, size: CGSize(width: 200, height: 150)),
      magnification: 2
    )
    XCTAssertEqual(restoredPan.x, 120, accuracy: 0.001)
    XCTAssertEqual(restoredPan.y, -80, accuracy: 0.001)
  }

  func testQuickAccessPinWindowSizing_constrainedFrameClampsOversizedWindows() {
    let frame = NSRect(x: 100, y: 100, width: 900, height: 700)
    let visibleFrame = NSRect(x: 0, y: 0, width: 800, height: 600)

    let constrainedFrame = QuickAccessPinWindowSizing.constrainedFrame(
      frame,
      visibleFrame: visibleFrame
    )

    XCTAssertEqual(constrainedFrame.minX, 24, accuracy: 0.001)
    XCTAssertEqual(constrainedFrame.minY, 24, accuracy: 0.001)
    XCTAssertEqual(constrainedFrame.width, 752, accuracy: 0.001)
    XCTAssertEqual(constrainedFrame.height, 552, accuracy: 0.001)
  }

  func testQuickAccessPinWindowSizing_preservesCenterWhenPinResizes() {
    let original = NSRect(x: 130, y: 270, width: 640, height: 480)
    let center = CGPoint(x: original.midX, y: original.midY)
    let resized = QuickAccessPinWindowSizing.frame(
      size: CGSize(width: 320, height: 240),
      centeredAt: center
    )

    XCTAssertEqual(resized.midX, original.midX, accuracy: 0.001)
    XCTAssertEqual(resized.midY, original.midY, accuracy: 0.001)
    XCTAssertEqual(resized.size.width, 320, accuracy: 0.001)
    XCTAssertEqual(resized.size.height, 240, accuracy: 0.001)

    let anchoredResize = QuickAccessPinWindowSizing.resizedFrame(
      original,
      to: CGSize(width: 800, height: 600),
      preservingAnchorFraction: CGPoint(x: 0.5, y: 0.5)
    )
    XCTAssertEqual(anchoredResize.midX, original.midX, accuracy: 0.001)
    XCTAssertEqual(anchoredResize.midY, original.midY, accuracy: 0.001)
  }

  func testQuickAccessPinWindowSizing_modeChangePreservesCenterUnlessFrameWouldLeaveVisibleArea() {
    let visibleFrame = NSRect(x: 100, y: 100, width: 1200, height: 800)
    let original = NSRect(x: 500, y: 400, width: 200, height: 100)
    let centered = QuickAccessPinWindowSizing.resizedFrame(
      original,
      to: CGSize(width: 600, height: 400),
      within: visibleFrame
    )

    XCTAssertEqual(centered.midX, original.midX, accuracy: 0.001)
    XCTAssertEqual(centered.midY, original.midY, accuracy: 0.001)
    XCTAssertGreaterThanOrEqual(centered.minX, visibleFrame.minX)
    XCTAssertGreaterThanOrEqual(centered.minY, visibleFrame.minY)
    XCTAssertLessThanOrEqual(centered.maxX, visibleFrame.maxX)
    XCTAssertLessThanOrEqual(centered.maxY, visibleFrame.maxY)

    let nearUpperRight = NSRect(x: 1200, y: 800, width: 200, height: 100)
    let edgeAdjusted = QuickAccessPinWindowSizing.resizedFrame(
      nearUpperRight,
      to: CGSize(width: 500, height: 400),
      within: visibleFrame
    )

    XCTAssertEqual(edgeAdjusted.maxX, visibleFrame.maxX, accuracy: 0.001)
    XCTAssertEqual(edgeAdjusted.maxY, visibleFrame.maxY, accuracy: 0.001)
    XCTAssertEqual(edgeAdjusted.width, 500, accuracy: 0.001)
    XCTAssertEqual(edgeAdjusted.height, 400, accuracy: 0.001)
    XCTAssertGreaterThanOrEqual(edgeAdjusted.minX, visibleFrame.minX)
    XCTAssertGreaterThanOrEqual(edgeAdjusted.minY, visibleFrame.minY)
  }

  func testQuickAccessPinImageDocumentView_magnifyCallbackUpdatesZoomAndRejectsLock() throws {
    let image = NSImage(size: CGSize(width: 400, height: 300))
    let state = QuickAccessPinWindowState(
      id: UUID(),
      url: URL(fileURLWithPath: "/tmp/pinned.png"),
      image: image,
      thumbnail: image,
      baseSize: CGSize(width: 400, height: 300),
      zoomMode: .fixedViewport
    )
    Self.retainedPinWindowStates.append(state)
    let scrollView = QuickAccessPinImageScrollView(frame: NSRect(origin: .zero, size: state.baseSize))
    scrollView.isLockedProvider = { state.isLocked }
    scrollView.onViewportChange = { magnification, panOffset in
      state.updateViewport(magnification: magnification, panOffset: panOffset)
    }
    scrollView.update(image: image, viewportSize: state.baseSize, imageSize: state.baseSize, zoomMode: .fixedViewport, magnification: 1, panOffset: .zero)
    let documentView = try XCTUnwrap(scrollView.documentView as? QuickAccessPinImageDocumentView)
    XCTAssertTrue(documentView.needsPanelToBecomeKey)
    XCTAssertTrue(documentView.acceptsFirstResponder)
    XCTAssertFalse(documentView.gestureRecognizers.contains { $0 is NSMagnificationGestureRecognizer })

    documentView.magnify(with: QuickAccessPinMockMagnifyEvent(delta: 0.5))
    XCTAssertEqual(scrollView.magnification, 1.5, accuracy: 0.001)
    XCTAssertEqual(state.zoomFactor, 1.5, accuracy: 0.001)

    documentView.magnify(with: QuickAccessPinMockMagnifyEvent(delta: 20))
    XCTAssertEqual(scrollView.magnification, 8, accuracy: 0.001)
    documentView.magnify(with: QuickAccessPinMockMagnifyEvent(delta: -20))
    XCTAssertEqual(scrollView.magnification, 0.4, accuracy: 0.001)

    state.isLocked = true
    let zoomBeforeLock = state.zoomFactor
    documentView.magnify(with: QuickAccessPinMockMagnifyEvent(delta: 0.5))
    XCTAssertEqual(state.zoomFactor, zoomBeforeLock, accuracy: 0.001)
  }

  func testQuickAccessPinImageDocumentView_magnifyKeepsFocalImagePointAtViewportLocation() throws {
    let image = NSImage(size: CGSize(width: 400, height: 300))
    let state = QuickAccessPinWindowState(
      id: UUID(),
      url: URL(fileURLWithPath: "/tmp/pinned.png"),
      image: image,
      thumbnail: image,
      baseSize: image.size,
      zoomMode: .fixedViewport
    )
    Self.retainedPinWindowStates.append(state)
    let scrollView = QuickAccessPinImageScrollView(frame: NSRect(origin: .zero, size: image.size))
    scrollView.isLockedProvider = { state.isLocked }
    scrollView.onViewportChange = { magnification, panOffset in
      state.updateViewport(magnification: magnification, panOffset: panOffset)
    }
    scrollView.update(
      image: image,
      viewportSize: state.baseSize,
      imageSize: image.size,
      zoomMode: .fixedViewport,
      magnification: 1,
      panOffset: .zero
    )
    let documentView = try XCTUnwrap(scrollView.documentView)
    let contentFocalPoint = CGPoint(x: 105, y: 72)
    let documentPointBefore = documentView.convert(contentFocalPoint, from: scrollView.contentView)

    scrollView.applyMagnificationDelta(
      0.5,
      centeredAtContentPoint: contentFocalPoint,
      windowPoint: contentFocalPoint
    )

    let documentPointAfter = documentView.convert(contentFocalPoint, from: scrollView.contentView)
    XCTAssertEqual(documentPointAfter.x, documentPointBefore.x, accuracy: 0.5)
    XCTAssertEqual(documentPointAfter.y, documentPointBefore.y, accuracy: 0.5)
    XCTAssertEqual(scrollView.magnification, 1.5, accuracy: 0.001)
  }

  func testQuickAccessPinImageDocumentView_magnifyEventRequestsResizeAtEventAnchor() throws {
    let image = NSImage(size: CGSize(width: 400, height: 300))
    let scrollView = QuickAccessPinImageScrollView(frame: NSRect(origin: .zero, size: image.size))
    scrollView.update(
      image: image,
      viewportSize: image.size,
      imageSize: image.size,
      zoomMode: .windowFollowsImage,
      magnification: 1,
      panOffset: .zero
    )
    var requestedSize: CGSize?
    var requestedFraction: CGPoint?
    scrollView.stateResizeRequest = { size, fraction in
      requestedSize = size
      requestedFraction = fraction
    }
    let documentView = try XCTUnwrap(scrollView.documentView as? QuickAccessPinImageDocumentView)
    let location = NSPoint(x: 105, y: 72)
    let viewportPoint = scrollView.convert(location, from: nil)
    let contentPoint = scrollView.contentView.convert(location, from: nil)
    let documentPointBeforeZoom = documentView.convert(contentPoint, from: scrollView.contentView)

    documentView.magnify(with: QuickAccessPinMockMagnifyEvent(delta: 0.5, location: location))

    let zoomedSize = try XCTUnwrap(requestedSize)
    let zoomedFraction = try XCTUnwrap(requestedFraction)
    XCTAssertEqual(scrollView.magnification, 1.5, accuracy: 0.001)
    XCTAssertEqual(zoomedSize.width, image.size.width * 1.5, accuracy: 0.001)
    XCTAssertEqual(zoomedSize.height, image.size.height * 1.5, accuracy: 0.001)
    XCTAssertEqual(zoomedFraction.x, viewportPoint.x / scrollView.bounds.width, accuracy: 0.001)
    XCTAssertEqual(zoomedFraction.y, viewportPoint.y / scrollView.bounds.height, accuracy: 0.001)
    XCTAssertNotEqual(zoomedFraction.x, 0.5, accuracy: 0.001)
    XCTAssertNotEqual(zoomedFraction.y, 0.5, accuracy: 0.001)
    let documentPointAfterZoom = documentView.convert(contentPoint, from: scrollView.contentView)
    XCTAssertEqual(documentPointAfterZoom.x, documentPointBeforeZoom.x, accuracy: 0.5)
    XCTAssertEqual(documentPointAfterZoom.y, documentPointBeforeZoom.y, accuracy: 0.5)

    documentView.magnify(with: QuickAccessPinMockMagnifyEvent(delta: -0.2, location: location))

    let zoomedOutSize = try XCTUnwrap(requestedSize)
    let zoomedOutFraction = try XCTUnwrap(requestedFraction)
    XCTAssertEqual(scrollView.magnification, 1.2, accuracy: 0.001)
    XCTAssertEqual(zoomedOutSize.width, image.size.width * 1.2, accuracy: 0.001)
    XCTAssertEqual(zoomedOutSize.height, image.size.height * 1.2, accuracy: 0.001)
    XCTAssertEqual(zoomedOutFraction.x, zoomedFraction.x, accuracy: 0.001)
    XCTAssertEqual(zoomedOutFraction.y, zoomedFraction.y, accuracy: 0.001)
    let documentPointAfterZoomOut = documentView.convert(contentPoint, from: scrollView.contentView)
    XCTAssertEqual(documentPointAfterZoomOut.x, documentPointBeforeZoom.x, accuracy: 0.5)
    XCTAssertEqual(documentPointAfterZoomOut.y, documentPointBeforeZoom.y, accuracy: 0.5)
  }

  func testQuickAccessPinImageScrollView_tinyFortyPercentZoomKeepsStateAndEventWindowSizesAligned() throws {
    let image = NSImage(size: CGSize(width: 24, height: 16))
    let minimumSize = QuickAccessPinWindowSizing.minimumInteractiveSize
    let state = QuickAccessPinWindowState(
      id: UUID(),
      url: URL(fileURLWithPath: "/tmp/tiny.png"),
      image: image,
      thumbnail: image,
      baseSize: minimumSize,
      zoomMode: .windowFollowsImage
    )
    Self.retainedPinWindowStates.append(state)
    var stateResizeRequests: [CGSize] = []
    state.onWindowResize = { size, _ in stateResizeRequests.append(size) }

    state.updateZoomFactor(0.4)
    XCTAssertEqual(stateResizeRequests.last, minimumSize)
    state.updateZoomFactor(1)

    let scrollView = QuickAccessPinImageScrollView(frame: NSRect(origin: .zero, size: state.displaySize))
    scrollView.onViewportChange = { magnification, panOffset in
      state.updateViewport(magnification: magnification, panOffset: panOffset)
    }
    var eventResizeRequest: CGSize?
    scrollView.stateResizeRequest = { size, _ in eventResizeRequest = size }
    scrollView.update(
      image: image,
      viewportSize: state.displaySize,
      imageSize: state.baseSize,
      zoomMode: state.zoomMode,
      magnification: state.zoomFactor,
      panOffset: state.panOffset
    )

    scrollView.applyMagnificationDelta(
      -0.8,
      centeredAtContentPoint: CGPoint(x: 120, y: 90),
      windowPoint: CGPoint(x: 120, y: 90)
    )

    let requestedEventSize = try XCTUnwrap(eventResizeRequest)
    XCTAssertEqual(state.zoomFactor, 0.4, accuracy: 0.001)
    XCTAssertEqual(state.displaySize, minimumSize)
    XCTAssertEqual(requestedEventSize, state.displaySize)
    XCTAssertEqual(state.imageDisplaySize, CGSize(width: 96, height: 64))
    XCTAssertEqual(scrollView.currentPanOffset.x, 0, accuracy: 0.001)
    XCTAssertEqual(scrollView.currentPanOffset.y, 0, accuracy: 0.001)

    state.updateZoomFactor(0.4)
    XCTAssertEqual(stateResizeRequests.last, requestedEventSize)
  }

  func testQuickAccessPinImageScrollView_magnifiesFromFixedViewportMarginAndRejectsLock() throws {
    let image = NSImage(size: CGSize(width: 80, height: 60))
    let viewportSize = CGSize(width: 300, height: 220)
    let state = QuickAccessPinWindowState(
      id: UUID(),
      url: URL(fileURLWithPath: "/tmp/small-fixed.png"),
      image: image,
      thumbnail: image,
      baseSize: viewportSize,
      zoomMode: .fixedViewport
    )
    Self.retainedPinWindowStates.append(state)

    let scrollView = QuickAccessPinImageScrollView(frame: NSRect(origin: .zero, size: viewportSize))
    scrollView.isLockedProvider = { state.isLocked }
    scrollView.onViewportChange = { magnification, panOffset in
      state.updateViewport(magnification: magnification, panOffset: panOffset)
    }
    scrollView.update(
      image: image,
      viewportSize: viewportSize,
      imageSize: image.size,
      zoomMode: .fixedViewport,
      magnification: 1,
      panOffset: .zero
    )
    let documentView = try XCTUnwrap(scrollView.documentView)
    XCTAssertLessThan(documentView.frame.width, scrollView.contentSize.width)
    XCTAssertLessThan(documentView.frame.height, scrollView.contentSize.height)

    scrollView.magnify(
      with: QuickAccessPinMockMagnifyEvent(delta: 0.5, location: NSPoint(x: 250, y: 180))
    )

    XCTAssertEqual(scrollView.magnification, 1.5, accuracy: 0.001)
    XCTAssertEqual(state.zoomFactor, 1.5, accuracy: 0.001)

    state.isLocked = true
    scrollView.magnify(
      with: QuickAccessPinMockMagnifyEvent(delta: 0.5, location: NSPoint(x: 250, y: 180))
    )

    XCTAssertEqual(scrollView.magnification, 1.5, accuracy: 0.001)
    XCTAssertEqual(state.zoomFactor, 1.5, accuracy: 0.001)
  }

  func testQuickAccessPinImageScrollView_windowResizingZoomKeepsCursorDocumentPointAcrossInOutCycle() throws {
    let image = NSImage(size: CGSize(width: 400, height: 300))
    let baseSize = CGSize(width: 400, height: 300)
    let state = QuickAccessPinWindowState(
      id: UUID(),
      url: URL(fileURLWithPath: "/tmp/pinned.png"),
      image: image,
      thumbnail: image,
      baseSize: baseSize,
      zoomMode: .windowFollowsImage
    )
    Self.retainedPinWindowStates.append(state)
    let scrollView = QuickAccessPinImageScrollView(frame: NSRect(origin: .zero, size: baseSize))
    scrollView.isLockedProvider = { state.isLocked }
    scrollView.onViewportChange = { magnification, panOffset in
      state.updateViewport(magnification: magnification, panOffset: panOffset)
    }
    scrollView.update(
      image: image,
      viewportSize: baseSize,
      imageSize: baseSize,
      zoomMode: .windowFollowsImage,
      magnification: 1,
      panOffset: .zero
    )

    let initialFrame = NSRect(x: 130, y: 270, width: baseSize.width, height: baseSize.height)
    let window = QuickAccessPinWindow(
      contentRect: initialFrame,
      state: state
    )
    defer {
      window.contentView = nil
      window.close()
    }
    window.contentView = scrollView

    let cursorViewPoint = NSPoint(x: 300, y: 200)
    let documentView = try XCTUnwrap(scrollView.documentView)
    let cursorBasePoint = scrollView.convert(cursorViewPoint, to: nil)
    let cursorScreenRect = window.convertToScreen(NSRect(origin: cursorBasePoint, size: .zero))
    let cursorScreenPoint = cursorScreenRect.origin
    let documentPointBefore = documentView.convert(cursorBasePoint, from: nil)

    scrollView.stateResizeRequest = { [weak window] size, fraction in
      guard let window else { return }
      let resized = QuickAccessPinWindowSizing.resizedFrame(
        window.frame,
        to: size,
        preservingAnchorFraction: fraction
      )
      window.setFrame(resized, display: false)
      window.contentView?.frame = NSRect(origin: .zero, size: size)
    }

    func cursorBaseUnderScreenPoint() -> NSPoint {
      window.convertFromScreen(NSRect(origin: cursorScreenPoint, size: .zero)).origin
    }
    let documentPointUnderCursorAfter = { () -> NSPoint in
      documentView.convert(cursorBaseUnderScreenPoint(), from: nil)
    }

    scrollView.applyMagnificationDelta(0.5, centeredAtContentPoint: cursorViewPoint, windowPoint: cursorViewPoint)
    XCTAssertEqual(scrollView.magnification, 1.5, accuracy: 0.001)
    XCTAssertEqual(window.frame.width, 600, accuracy: 1.0)
    let documentPointDuring = documentPointUnderCursorAfter()
    XCTAssertEqual(documentPointDuring.x, documentPointBefore.x, accuracy: 2.0)
    XCTAssertEqual(documentPointDuring.y, documentPointBefore.y, accuracy: 2.0)

    let cursorViewPointAfterReturn = scrollView.convert(cursorBaseUnderScreenPoint(), from: nil)
    scrollView.applyMagnificationDelta(-0.33333, centeredAtContentPoint: cursorViewPointAfterReturn, windowPoint: cursorViewPointAfterReturn)
    XCTAssertEqual(scrollView.magnification, 1, accuracy: 0.001)
    XCTAssertEqual(window.frame.width, initialFrame.width, accuracy: 1.0)
    XCTAssertEqual(window.frame.height, initialFrame.height, accuracy: 1.0)
    XCTAssertEqual(window.frame.minX, initialFrame.minX, accuracy: 1.0)
    XCTAssertEqual(window.frame.minY, initialFrame.minY, accuracy: 1.0)
    XCTAssertEqual(scrollView.currentPanOffset.x, 0, accuracy: 1.0)
    XCTAssertEqual(scrollView.currentPanOffset.y, 0, accuracy: 1.0)
    let documentPointAfter = documentPointUnderCursorAfter()
    XCTAssertEqual(documentPointAfter.x, documentPointBefore.x, accuracy: 2.0)
    XCTAssertEqual(documentPointAfter.y, documentPointBefore.y, accuracy: 2.0)
  }

  func testQuickAccessPinImageZoom_resizePreservesOffCenterFocalAnchor() throws {
    let image = NSImage(size: CGSize(width: 400, height: 300))
    let scrollView = QuickAccessPinImageScrollView(frame: NSRect(origin: .zero, size: image.size))
    scrollView.update(
      image: image,
      viewportSize: image.size,
      imageSize: image.size,
      zoomMode: .windowFollowsImage,
      magnification: 1,
      panOffset: .zero
    )
    let focalPoint = CGPoint(x: 105, y: 72)
    var requestedSize: CGSize?
    var requestedFraction: CGPoint?
    scrollView.stateResizeRequest = { size, fraction in
      requestedSize = size
      requestedFraction = fraction
    }

    scrollView.applyMagnificationDelta(
      0.5,
      centeredAtContentPoint: focalPoint,
      windowPoint: focalPoint
    )

    let size = try XCTUnwrap(requestedSize)
    let fraction = try XCTUnwrap(requestedFraction)
    XCTAssertEqual(fraction.x, focalPoint.x / image.size.width, accuracy: 0.001)
    XCTAssertEqual(fraction.y, focalPoint.y / image.size.height, accuracy: 0.001)
    XCTAssertNotEqual(fraction.x, 0.5, accuracy: 0.001)
    XCTAssertNotEqual(fraction.y, 0.5, accuracy: 0.001)

    let originalFrame = NSRect(x: 130, y: 270, width: image.size.width, height: image.size.height)
    let resizedFrame = QuickAccessPinWindowSizing.resizedFrame(
      originalFrame,
      to: size,
      preservingAnchorFraction: fraction
    )
    XCTAssertEqual(
      originalFrame.minX + originalFrame.width * fraction.x,
      resizedFrame.minX + resizedFrame.width * fraction.x,
      accuracy: 0.001
    )
    XCTAssertEqual(
      originalFrame.minY + originalFrame.height * fraction.y,
      resizedFrame.minY + resizedFrame.height * fraction.y,
      accuracy: 0.001
    )
  }

  func testQuickAccessPinWindow_routesWindowMagnifyToImageScrollView() {
    let image = NSImage(size: CGSize(width: 400, height: 300))
    let state = QuickAccessPinWindowState(
      id: UUID(),
      url: URL(fileURLWithPath: "/tmp/pinned.png"),
      image: image,
      thumbnail: image,
      baseSize: CGSize(width: 400, height: 300),
      zoomMode: .fixedViewport
    )
    Self.retainedPinWindowStates.append(state)
    let scrollView = QuickAccessPinImageScrollView(frame: NSRect(origin: .zero, size: state.baseSize))
    scrollView.isLockedProvider = { state.isLocked }
    scrollView.onViewportChange = { magnification, panOffset in
      state.updateViewport(magnification: magnification, panOffset: panOffset)
    }
    scrollView.update(
      image: image,
      viewportSize: state.baseSize,
      imageSize: state.baseSize,
      zoomMode: .fixedViewport,
      magnification: 1,
      panOffset: .zero
    )
    let window = QuickAccessPinWindow(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
      state: state
    )
    defer { window.close() }
    window.contentView = scrollView
    window.contentView?.layoutSubtreeIfNeeded()

    window.sendEvent(QuickAccessPinMockMagnifyEvent(delta: 0.5, location: NSPoint(x: 200, y: 150)))
    XCTAssertEqual(state.zoomFactor, 1.5, accuracy: 0.001)

    state.isLocked = true
    window.sendEvent(QuickAccessPinMockMagnifyEvent(delta: 0.5, location: NSPoint(x: 200, y: 150)))
    XCTAssertEqual(state.zoomFactor, 1.5, accuracy: 0.001)
  }

  func testQuickAccessPinWindow_lockedModeIsClickThroughExceptUnlockButton() {
    let image = NSImage(size: CGSize(width: 400, height: 300))
    let state = QuickAccessPinWindowState(
      id: UUID(),
      url: URL(fileURLWithPath: "/tmp/pinned.png"),
      image: image,
      thumbnail: image,
      baseSize: CGSize(width: 320, height: 220)
    )
    Self.retainedPinWindowStates.append(state)

    let window = QuickAccessPinWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
      state: state
    )
    defer { window.close() }

    let mouseLocation = NSEvent.mouseLocation
    let imageFrameOrigin = NSPoint(
      x: mouseLocation.x - 160,
      y: mouseLocation.y - 110
    )
    window.setFrameOrigin(imageFrameOrigin)
    state.isLocked = true
    window.updateMousePassthrough(at: mouseLocation)

    XCTAssertTrue(window.frame.contains(mouseLocation))
    XCTAssertTrue(window.ignoresMouseEvents)

    let unlockFrameOrigin = NSPoint(
      x: mouseLocation.x - 296,
      y: mouseLocation.y - 196
    )
    window.setFrameOrigin(unlockFrameOrigin)
    window.updateMousePassthrough(at: mouseLocation)

    XCTAssertTrue(window.frame.contains(mouseLocation))
    XCTAssertFalse(window.ignoresMouseEvents)
  }

  func testQuickAccessPinImageScrollView_modifierCoarseAndLockedScrollAreRejected() {
    let image = NSImage(size: CGSize(width: 400, height: 300))
    let state = QuickAccessPinWindowState(
      id: UUID(),
      url: URL(fileURLWithPath: "/tmp/pinned.png"),
      image: image,
      thumbnail: image,
      baseSize: CGSize(width: 400, height: 300),
      zoomMode: .fixedViewport
    )
    Self.retainedPinWindowStates.append(state)

    state.updateZoomFactor(2)
    let scrollView = QuickAccessPinImageScrollView(frame: NSRect(origin: .zero, size: state.baseSize))
    scrollView.isLockedProvider = { state.isLocked }
    scrollView.onViewportChange = { magnification, panOffset in
      state.updateViewport(magnification: magnification, panOffset: panOffset)
    }
    scrollView.update(
      image: image,
      viewportSize: state.displaySize,
      imageSize: state.baseSize,
      zoomMode: state.zoomMode,
      magnification: state.zoomFactor,
      panOffset: state.panOffset
    )

    let zoomBeforeRejectedScrolls = state.zoomFactor
    let panBeforeRejectedScrolls = state.panOffset
    for modifier in [
      NSEvent.ModifierFlags.shift,
      .option,
      .control,
    ] {
      let event = QuickAccessPinMockScrollWheelEvent(
        deltaY: 10,
        modifierFlags: modifier,
        hasPreciseDeltas: true
      )
      XCTAssertEqual(scrollView.scrollAction(for: event), .reject("modifiers"))
      scrollView.scrollWheel(with: event)
    }

    let commandScrollEvent = QuickAccessPinMockScrollWheelEvent(
      deltaY: 10,
      modifierFlags: [.command],
      hasPreciseDeltas: true
    )
    XCTAssertEqual(scrollView.scrollAction(for: commandScrollEvent), .magnify)
    scrollView.scrollWheel(with: commandScrollEvent)
    XCTAssertEqual(state.zoomFactor, zoomBeforeRejectedScrolls * 0.9, accuracy: 0.001)

    let commandHorizontalScrollEvent = QuickAccessPinMockScrollWheelEvent(
      deltaX: 10,
      deltaY: 0,
      modifierFlags: [.command],
      hasPreciseDeltas: true
    )
    XCTAssertEqual(scrollView.scrollAction(for: commandHorizontalScrollEvent), .reject("horizontalOrZeroDelta"))

    let coarseEvent = QuickAccessPinMockScrollWheelEvent(
      deltaY: 10,
      hasPreciseDeltas: false
    )
    XCTAssertEqual(scrollView.scrollAction(for: coarseEvent), .reject("nonPrecise"))
    scrollView.scrollWheel(with: coarseEvent)

    state.isLocked = true
    let lockedEvent = QuickAccessPinMockScrollWheelEvent(
      deltaY: 10,
      hasPreciseDeltas: true
    )
    XCTAssertEqual(scrollView.scrollAction(for: lockedEvent), .reject("locked"))
    scrollView.scrollWheel(with: lockedEvent)

    XCTAssertEqual(state.zoomFactor, zoomBeforeRejectedScrolls * 0.9, accuracy: 0.001)
    XCTAssertEqual(state.panOffset, panBeforeRejectedScrolls)
  }

  func testQuickAccessPinImageScrollView_fixedViewportPreciseScrollPans() {
    let image = NSImage(size: CGSize(width: 400, height: 300))
    let viewportSize = CGSize(width: 200, height: 150)
    let state = QuickAccessPinWindowState(
      id: UUID(),
      url: URL(fileURLWithPath: "/tmp/pinned.png"),
      image: image,
      thumbnail: image,
      baseSize: viewportSize,
      zoomMode: .fixedViewport
    )
    Self.retainedPinWindowStates.append(state)
    let scrollView = QuickAccessPinImageScrollView(frame: NSRect(origin: .zero, size: viewportSize))
    scrollView.isLockedProvider = { state.isLocked }
    scrollView.onViewportChange = { magnification, panOffset in
      state.updateViewport(magnification: magnification, panOffset: panOffset)
    }
    scrollView.update(
      image: image,
      viewportSize: viewportSize,
      imageSize: image.size,
      zoomMode: .fixedViewport,
      magnification: 2,
      panOffset: .zero
    )
    let event = QuickAccessPinMockScrollWheelEvent(
      deltaY: 14,
      hasPreciseDeltas: true,
      location: NSPoint(x: 100, y: 75)
    )
    XCTAssertEqual(scrollView.scrollAction(for: event), .pan)
    let oldOrigin = scrollView.contentView.bounds.origin
    scrollView.applyScrollPan(for: event) {
      scrollView.contentView.setBoundsOrigin(NSPoint(x: oldOrigin.x, y: oldOrigin.y + 14))
      scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    XCTAssertLessThan(state.panOffset.y, 0)
    XCTAssertEqual(state.panOffset.x, 0, accuracy: 0.001)
  }

  func testQuickAccessPinImageScrollView_windowFollowsImageZoomsOnVerticalScrollOnly() throws {
    let image = NSImage(size: CGSize(width: 400, height: 300))
    let state = QuickAccessPinWindowState(
      id: UUID(),
      url: URL(fileURLWithPath: "/tmp/pinned.png"),
      image: image,
      thumbnail: image,
      baseSize: image.size,
      zoomMode: .windowFollowsImage
    )
    Self.retainedPinWindowStates.append(state)
    let scrollView = QuickAccessPinImageScrollView(frame: NSRect(origin: .zero, size: image.size))
    scrollView.onViewportChange = { magnification, panOffset in
      state.updateViewport(magnification: magnification, panOffset: panOffset)
    }
    var requestedWindowSizes: [CGSize] = []
    scrollView.stateResizeRequest = { size, _ in requestedWindowSizes.append(size) }
    scrollView.update(
      image: image,
      viewportSize: image.size,
      imageSize: image.size,
      zoomMode: .windowFollowsImage,
      magnification: 1,
      panOffset: .zero
    )

    let verticalEvent = QuickAccessPinMockScrollWheelEvent(
      deltaY: 10,
      hasPreciseDeltas: false
    )
    XCTAssertEqual(scrollView.scrollAction(for: verticalEvent), .magnify)
    scrollView.scrollWheel(with: verticalEvent)
    let zoomAfterVerticalScroll = state.zoomFactor
    XCTAssertNotEqual(zoomAfterVerticalScroll, 1, accuracy: 0.001)
    let requestedSize = try XCTUnwrap(requestedWindowSizes.last)
    XCTAssertEqual(requestedSize.width, image.size.width * zoomAfterVerticalScroll, accuracy: 0.001)

    let horizontalEvent = QuickAccessPinMockScrollWheelEvent(
      deltaX: 10,
      deltaY: 0,
      hasPreciseDeltas: true
    )
    XCTAssertEqual(scrollView.scrollAction(for: horizontalEvent), .reject("horizontalOrZeroDelta"))
    scrollView.scrollWheel(with: horizontalEvent)
    XCTAssertEqual(state.zoomFactor, zoomAfterVerticalScroll, accuracy: 0.001)
  }

  func testQuickAccessPinImageScrollView_appliesPresetPanAndFitState() {
    let image = NSImage(size: CGSize(width: 400, height: 200))
    let state = QuickAccessPinWindowState(
      id: UUID(),
      url: URL(fileURLWithPath: "/tmp/pinned.png"),
      image: image,
      thumbnail: image,
      baseSize: CGSize(width: 400, height: 300),
      zoomMode: .fixedViewport
    )
    Self.retainedPinWindowStates.append(state)

    let scrollView = QuickAccessPinImageScrollView(frame: NSRect(origin: .zero, size: state.baseSize))
    scrollView.onViewportChange = { magnification, panOffset in
      state.updateViewport(magnification: magnification, panOffset: panOffset)
    }
    state.updateViewport(
      magnification: 2,
      panOffset: CGPoint(x: 60, y: -40)
    )
    scrollView.update(
      image: image,
      viewportSize: state.displaySize,
      imageSize: state.baseSize,
      zoomMode: state.zoomMode,
      magnification: state.zoomFactor,
      panOffset: state.panOffset
    )

    XCTAssertEqual(scrollView.magnification, 2, accuracy: 0.001)
    XCTAssertEqual(scrollView.currentPanOffset.x, 60, accuracy: 0.001)
    XCTAssertEqual(scrollView.currentPanOffset.y, -40, accuracy: 0.001)
    XCTAssertEqual(state.panOffset.x, 60, accuracy: 0.001)
    XCTAssertEqual(state.panOffset.y, -40, accuracy: 0.001)

    state.resetZoom()
    scrollView.update(
      image: image,
      viewportSize: state.displaySize,
      imageSize: state.baseSize,
      zoomMode: state.zoomMode,
      magnification: state.zoomFactor,
      panOffset: state.panOffset
    )

    XCTAssertEqual(scrollView.magnification, 1, accuracy: 0.001)
    XCTAssertEqual(scrollView.currentPanOffset.x, 0, accuracy: 0.001)
    XCTAssertEqual(scrollView.currentPanOffset.y, 0, accuracy: 0.001)
    XCTAssertEqual(scrollView.contentView.bounds.origin.x, 0, accuracy: 0.001)
    XCTAssertEqual(scrollView.contentView.bounds.origin.y, -50, accuracy: 0.001)
  }

  func testQuickAccessPinWindowState_fitRestoresWindowSizeAtCenter() throws {
    let image = NSImage(size: CGSize(width: 400, height: 300))
    let baseSize = CGSize(width: 400, height: 300)
    let state = QuickAccessPinWindowState(
      id: UUID(),
      url: URL(fileURLWithPath: "/tmp/pinned.png"),
      image: image,
      thumbnail: image,
      baseSize: baseSize,
      zoomMode: .windowFollowsImage
    )
    Self.retainedPinWindowStates.append(state)
    let initialFrame = NSRect(x: 130, y: 270, width: baseSize.width, height: baseSize.height)
    var requestedFrame: NSRect?
    state.onWindowResize = { size, fraction in
      requestedFrame = QuickAccessPinWindowSizing.resizedFrame(
        requestedFrame ?? initialFrame,
        to: size,
        preservingAnchorFraction: fraction
      )
    }

    state.updateZoomFactor(2)
    let zoomedFrame = try XCTUnwrap(requestedFrame)
    XCTAssertEqual(zoomedFrame.size.width, baseSize.width * 2, accuracy: 0.001)
    XCTAssertEqual(zoomedFrame.midX, initialFrame.midX, accuracy: 0.001)
    XCTAssertEqual(zoomedFrame.midY, initialFrame.midY, accuracy: 0.001)

    state.resetZoom()
    let fitFrame = try XCTUnwrap(requestedFrame)
    XCTAssertEqual(state.zoomFactor, 1, accuracy: 0.001)
    XCTAssertEqual(fitFrame.size.width, baseSize.width, accuracy: 0.001)
    XCTAssertEqual(fitFrame.size.height, baseSize.height, accuracy: 0.001)
    XCTAssertEqual(fitFrame.midX, initialFrame.midX, accuracy: 0.001)
    XCTAssertEqual(fitFrame.midY, initialFrame.midY, accuracy: 0.001)
  }

  func testQuickAccessPinWindow_levelSurvivesFloatingPanelConfiguration() {
    let image = NSImage(size: CGSize(width: 24, height: 16))
    let state = QuickAccessPinWindowState(
      id: UUID(),
      url: URL(fileURLWithPath: "/tmp/pinned.png"),
      image: image,
      thumbnail: image,
      baseSize: CGSize(width: 320, height: 220)
    )
    Self.retainedPinWindowStates.append(state)

    let window = QuickAccessPinWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
      state: state
    )
    defer { window.close() }

    XCTAssertTrue(window.isFloatingPanel)
    XCTAssertGreaterThan(window.level.rawValue, NSWindow.Level.floating.rawValue + 1)
  }

  func testQuickAccessWindowLevels_keepActiveEditorsAboveCardsAndBelowPins() {
    let panel = QuickAccessPanel(
      contentRect: NSRect(x: 0, y: 0, width: 204, height: 520)
    )
    defer { panel.close() }

    let pinWindow = makePinWindow()
    defer { pinWindow.close() }

    let annotateWindow = AnnotateWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600)
    )
    defer { annotateWindow.close() }

    let videoEditorWindow = VideoEditorWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600)
    )
    defer { videoEditorWindow.close() }

    annotateWindow.applyActiveEditorLevel()
    videoEditorWindow.applyActiveEditorLevel()

    XCTAssertEqual(panel.level, .floating)
    XCTAssertGreaterThan(annotateWindow.level.rawValue, panel.level.rawValue)
    XCTAssertGreaterThan(videoEditorWindow.level.rawValue, panel.level.rawValue)
    XCTAssertEqual(annotateWindow.level, videoEditorWindow.level)
    XCTAssertGreaterThan(pinWindow.level.rawValue, annotateWindow.level.rawValue)
    XCTAssertGreaterThan(pinWindow.level.rawValue, videoEditorWindow.level.rawValue)
  }

  func testQuickAccessPanel_interactiveRegionTracksVisibleCardsOnly() {
    let panelHeight =
      QuickAccessLayout.scaledCardHeight(1) * 5
      + QuickAccessLayout.cardSpacing * 4
      + QuickAccessLayout.containerPadding * 2
    let panel = QuickAccessPanel(
      contentRect: NSRect(x: 100, y: 100, width: 204, height: panelHeight)
    )
    defer { panel.close() }

    panel.updatePassthroughRegion(itemCount: 1, scale: 1)

    XCTAssertEqual(
      QuickAccessPanel.interactiveContentHeight(itemCount: 1, scale: 1, panelHeight: panelHeight),
      QuickAccessLayout.cardHeight + QuickAccessLayout.containerPadding * 2,
      accuracy: 0.001
    )
    XCTAssertTrue(panel.containsInteractivePoint(NSPoint(x: 150, y: 120)))
    XCTAssertFalse(panel.containsInteractivePoint(NSPoint(x: 150, y: panel.frame.maxY - 10)))
  }

  func testQuickAccessActionConfigurationStore_usesDefaultOrderAndEnabledActions() {
    let defaults = makeIsolatedDefaults()
    let store = makeActionConfigurationStore(defaults: defaults)

    XCTAssertEqual(store.actionOrder, QuickAccessActionKind.defaultOrder)
    XCTAssertEqual(store.orderedActions(includeDisabled: false), QuickAccessActionKind.defaultOrder)
    XCTAssertEqual(store.slotAssignments, QuickAccessActionSlot.defaultAssignments)
    XCTAssertTrue(store.isEnabled(.pinToScreen))
  }

  func testQuickAccessActionKind_contextMenuOrderKeepsCloseAndDeleteAtEnd() {
    let configuredOrder: [QuickAccessActionKind] = [
      .copy,
      .saveOrOpen,
      .dismiss,
      .delete,
      .edit,
      .uploadToCloud,
      .pinToScreen,
    ]

    XCTAssertEqual(
      QuickAccessActionKind.contextMenuOrder(from: configuredOrder),
      [.copy, .saveOrOpen, .edit, .uploadToCloud, .pinToScreen, .dismiss, .delete]
    )
  }

  func testQuickAccessActionConfigurationStore_filtersUnknownIdsAndAppendsMissingActions() {
    let defaults = makeIsolatedDefaults()
    defaults.set(
      [
        QuickAccessActionKind.delete.rawValue,
        "future-action",
        QuickAccessActionKind.copy.rawValue,
        QuickAccessActionKind.copy.rawValue,
      ],
      forKey: PreferencesKeys.quickAccessActionOrder
    )
    defaults.set(
      [
        QuickAccessActionKind.copy.rawValue,
        "future-action",
      ],
      forKey: PreferencesKeys.quickAccessEnabledActions
    )

    let store = makeActionConfigurationStore(defaults: defaults)

    XCTAssertEqual(
      store.actionOrder,
      [.delete, .copy, .saveOrOpen, .dismiss, .edit, .uploadToCloud, .pinToScreen]
    )
    XCTAssertEqual(store.orderedActions(includeDisabled: false), [.copy])
  }

  func testQuickAccessActionConfigurationStore_preservesExplicitPinToScreenDisable() {
    let defaults = makeIsolatedDefaults()
    defaults.set(
      QuickAccessActionKind.defaultOrder.map(\.rawValue),
      forKey: PreferencesKeys.quickAccessActionOrder
    )
    defaults.set(
      QuickAccessActionKind.defaultOrder
        .filter { $0 != .pinToScreen }
        .map(\.rawValue),
      forKey: PreferencesKeys.quickAccessEnabledActions
    )

    let store = makeActionConfigurationStore(defaults: defaults)

    XCTAssertFalse(store.isEnabled(.pinToScreen))
    XCTAssertFalse(store.orderedActions(includeDisabled: false).contains(.pinToScreen))
  }

  func testQuickAccessActionConfigurationStore_togglesMovesAndPersistsActions() {
    let defaults = makeIsolatedDefaults()
    let store = makeActionConfigurationStore(defaults: defaults)

    store.setEnabled(.uploadToCloud, enabled: false)
    store.moveAction(from: IndexSet(integer: 0), to: 3)

    XCTAssertFalse(store.isEnabled(.uploadToCloud))
    XCTAssertEqual(
      store.actionOrder,
      [.saveOrOpen, .dismiss, .copy, .delete, .edit, .uploadToCloud, .pinToScreen]
    )
    XCTAssertEqual(store.slotAssignments, QuickAccessActionSlot.defaultAssignments)

    let reloadedStore = makeActionConfigurationStore(defaults: defaults)
    XCTAssertFalse(reloadedStore.isEnabled(.uploadToCloud))
    XCTAssertEqual(reloadedStore.actionOrder, store.actionOrder)
    XCTAssertEqual(reloadedStore.slotAssignments, QuickAccessActionSlot.defaultAssignments)

    reloadedStore.assignAction(.uploadToCloud, to: .centerTop)
    reloadedStore.clearSlot(.bottomLeading)

    XCTAssertEqual(reloadedStore.action(in: .centerTop), .uploadToCloud)
    XCTAssertNil(reloadedStore.action(in: .bottomTrailing))
    XCTAssertNil(reloadedStore.action(in: .bottomLeading))

    let placementReload = makeActionConfigurationStore(defaults: defaults)
    XCTAssertEqual(placementReload.action(in: .centerTop), .uploadToCloud)
    XCTAssertNil(placementReload.action(in: .bottomTrailing))
    XCTAssertNil(placementReload.action(in: .bottomLeading))

    placementReload.resetToDefaults()
    XCTAssertEqual(placementReload.actionOrder, QuickAccessActionKind.defaultOrder)
    XCTAssertEqual(placementReload.orderedActions(includeDisabled: false), QuickAccessActionKind.defaultOrder)
    XCTAssertEqual(placementReload.slotAssignments, QuickAccessActionSlot.defaultAssignments)
  }

  func testQuickAccessActionConfigurationStore_filtersSlotAssignmentsAndPreservesEmptySlots() {
    let defaults = makeIsolatedDefaults()
    defaults.set(
      [
        QuickAccessActionSlot.centerTop.rawValue: "future-action",
        QuickAccessActionSlot.centerBottom.rawValue: "",
        QuickAccessActionSlot.topTrailing.rawValue: QuickAccessActionKind.delete.rawValue,
        QuickAccessActionSlot.topLeading.rawValue: QuickAccessActionKind.delete.rawValue,
      ],
      forKey: PreferencesKeys.quickAccessActionSlotAssignments
    )

    let store = makeActionConfigurationStore(defaults: defaults)

    XCTAssertNil(store.action(in: .centerTop))
    XCTAssertNil(store.action(in: .centerBottom))
    XCTAssertEqual(store.action(in: .topTrailing), .delete)
    XCTAssertNil(store.action(in: .topLeading))
    XCTAssertEqual(store.action(in: .bottomLeading), .edit)
    XCTAssertEqual(store.action(in: .bottomTrailing), .uploadToCloud)
  }

  func testQuickAccessCountdownTimer_pauseResumePreservesRemainingTime() async throws {
    try skipIfRunningInCI()
    var didExpire = false
    let expiration = expectation(description: "timer expires after resume")
    let clock = ManualQuickAccessCountdownTimerClock()
    let timer = QuickAccessCountdownTimer(duration: 0.08, clock: clock) {
      didExpire = true
      expiration.fulfill()
    }

    timer.start()
    await clock.waitForSleepCallCount(1)
    clock.advance(by: 0.03)
    timer.pause()

    XCTAssertTrue(timer.isPaused)
    XCTAssertFalse(timer.isRunning)

    clock.advance(by: 0.12)
    await Task.yield()
    XCTAssertFalse(didExpire)

    timer.resume()
    XCTAssertTrue(timer.isRunning)

    await clock.waitForSleepCallCount(2)
    clock.advance(by: 0.05)

    await fulfillment(of: [expiration], timeout: 1.0)
    XCTAssertTrue(didExpire)
  }

  func testQuickAccessCountdownTimer_cancelPreventsExpiration() async throws {
    try skipIfRunningInCI()
    var didExpire = false
    let clock = ManualQuickAccessCountdownTimerClock()
    let timer = QuickAccessCountdownTimer(duration: 0.03, clock: clock) {
      didExpire = true
    }

    timer.start()
    await clock.waitForSleepCallCount(1)
    timer.cancel()
    clock.advance(by: 0.08)
    await Task.yield()

    XCTAssertFalse(didExpire)
    XCTAssertFalse(timer.isRunning)
    XCTAssertFalse(timer.isPaused)
  }

  private func makeIsolatedDefaults() -> UserDefaults {
    let suiteName = "SnapzyTests.QuickAccess.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }

  private func makeActionConfigurationStore(
    defaults: UserDefaults
  ) -> QuickAccessActionConfigurationStore {
    let store = QuickAccessActionConfigurationStore(defaults: defaults)
    Self.retainedActionStores.append(store)
    return store
  }

  private func makePinWindow() -> QuickAccessPinWindow {
    let image = NSImage(size: CGSize(width: 24, height: 16))
    let state = QuickAccessPinWindowState(
      id: UUID(),
      url: URL(fileURLWithPath: "/tmp/pinned.png"),
      image: image,
      thumbnail: image,
      baseSize: CGSize(width: 320, height: 220)
    )
    Self.retainedPinWindowStates.append(state)

    return QuickAccessPinWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
      state: state
    )
  }
}

@MainActor
private final class ManualQuickAccessCountdownTimerClock: QuickAccessCountdownTimerClock {
  private struct SleepRequest {
    let wakeTime: TimeInterval
    let continuation: CheckedContinuation<Void, Never>
  }

  private(set) var now: TimeInterval = 0
  private var sleepRequests: [SleepRequest] = []
  private var sleepCallCount = 0
  private var sleepCallWaiters: [(expectedCount: Int, continuation: CheckedContinuation<Void, Never>)] = []

  func sleep(for duration: TimeInterval) async {
    await withCheckedContinuation { continuation in
      sleepCallCount += 1
      resumeSatisfiedSleepCallWaiters()

      let wakeTime = now + max(0, duration)
      guard wakeTime > now else {
        continuation.resume()
        return
      }

      sleepRequests.append(SleepRequest(wakeTime: wakeTime, continuation: continuation))
    }
  }

  func advance(by duration: TimeInterval) {
    now += duration

    var readyContinuations: [CheckedContinuation<Void, Never>] = []
    sleepRequests.removeAll { request in
      guard request.wakeTime <= now else { return false }
      readyContinuations.append(request.continuation)
      return true
    }

    readyContinuations.forEach { $0.resume() }
  }

  func waitForSleepCallCount(_ expectedCount: Int) async {
    guard sleepCallCount < expectedCount else { return }

    await withCheckedContinuation { continuation in
      sleepCallWaiters.append((expectedCount, continuation))
    }
  }

  private func resumeSatisfiedSleepCallWaiters() {
    var readyContinuations: [CheckedContinuation<Void, Never>] = []
    sleepCallWaiters.removeAll { waiter in
      guard sleepCallCount >= waiter.expectedCount else { return false }
      readyContinuations.append(waiter.continuation)
      return true
    }

    readyContinuations.forEach { $0.resume() }
  }
}
