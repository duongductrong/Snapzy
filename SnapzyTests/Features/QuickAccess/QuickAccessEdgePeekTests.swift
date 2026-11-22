//
//  QuickAccessEdgePeekTests.swift
//  SnapzyTests
//
//  Collapse-to-edge (#591): swipe resolution, peek strip geometry, stack
//  visibility, peek windows and config round-trip.
//

import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Snapzy

@MainActor
final class QuickAccessEdgePeekTests: XCTestCase {
  private let allEnabled: (QuickAccessActionKind) -> Bool = { _ in true }
  private let visibleFrame = CGRect(x: 0, y: 80, width: 1440, height: 800)

  private func resolver(
    left: QuickAccessActionKind? = .dismiss,
    right: QuickAccessActionKind? = .dismiss,
    collapses: Bool,
    edge: CGFloat
  ) -> QuickAccessSwipeResolver {
    QuickAccessSwipeResolver(
      leftAction: left,
      rightAction: right,
      hideCardWhenWindowOpen: true,
      collapsesTowardEdge: collapses,
      edgeDirection: edge
    )
  }

  private func makeItem(collapsed: Bool = false) -> QuickAccessItem {
    QuickAccessItem(
      id: UUID(),
      url: URL(fileURLWithPath: "/tmp/peek-\(UUID().uuidString).png"),
      thumbnail: NSImage(size: CGSize(width: 32, height: 20)),
      capturedAt: Date(),
      itemType: .screenshot,
      duration: nil,
      isCollapsed: collapsed
    )
  }

  // MARK: - Swipe resolution

  func testResolver_settingOffKeepsConfiguredActionTowardEdge() {
    let resolver = resolver(collapses: false, edge: 1)

    XCTAssertEqual(
      resolver.resolveEnd(translation: 120, velocity: 0, isActionEnabled: allEnabled),
      .perform(.dismiss, hidesCard: true)
    )
  }

  func testResolver_rightPanelSwipeTowardEdgeCollapses() {
    let resolver = resolver(left: .copy, right: .dismiss, collapses: true, edge: 1)

    XCTAssertEqual(resolver.resolveEnd(translation: 120, velocity: 0, isActionEnabled: allEnabled), .collapse)
    XCTAssertEqual(resolver.resolveEnd(translation: 10, velocity: 400, isActionEnabled: allEnabled), .collapse)
    // Away from the edge still runs that side's action.
    XCTAssertEqual(
      resolver.resolveEnd(translation: -120, velocity: 0, isActionEnabled: allEnabled),
      .perform(.copy, hidesCard: false)
    )
  }

  func testResolver_leftPanelSwipeTowardEdgeCollapses() {
    let resolver = resolver(left: .dismiss, right: .copy, collapses: true, edge: -1)

    XCTAssertEqual(resolver.resolveEnd(translation: -120, velocity: 0, isActionEnabled: allEnabled), .collapse)
    XCTAssertEqual(
      resolver.resolveEnd(translation: 120, velocity: 0, isActionEnabled: allEnabled),
      .perform(.copy, hidesCard: false)
    )
  }

  func testResolver_collapseNeedsThresholdButNoConfiguredAction() {
    let resolver = resolver(left: nil, right: nil, collapses: true, edge: 1)

    XCTAssertEqual(resolver.resolveEnd(translation: 80, velocity: 300, isActionEnabled: allEnabled), .snapBack)
    XCTAssertEqual(resolver.resolveEnd(translation: 81, velocity: 0, isActionEnabled: { _ in false }), .collapse)
    XCTAssertEqual(resolver.liveTranslation(50), 50, "card follows the pointer toward the edge")
    XCTAssertEqual(resolver.liveTranslation(-50), 0, "no action away from the edge")
  }

  // MARK: - Peek geometry

  func testLayout_bottomRightColumnHugsRightEdgeFromBottomCorner() {
    let frames = QuickAccessEdgePeekLayout.stripFrames(
      count: 2,
      position: .bottomRight,
      visibleFrame: visibleFrame,
      scale: 1
    )

    XCTAssertEqual(frames.count, 2)
    for frame in frames {
      XCTAssertEqual(frame.maxX, visibleFrame.maxX)
      XCTAssertEqual(frame.width, QuickAccessEdgePeekLayout.restingVisibleWidth)
      XCTAssertEqual(frame.height, QuickAccessLayout.cardHeight, "peek keeps the full card height")
    }
    // Last card sits on the bottom padding; first card is above it.
    XCTAssertEqual(frames[1].minY, visibleFrame.minY + QuickAccessEdgePeekLayout.edgePadding)
    XCTAssertEqual(frames[0].minY, frames[1].maxY + QuickAccessEdgePeekLayout.spacing)
  }

  func testLayout_topLeftColumnHugsLeftEdgeFromTopCorner() {
    let frames = QuickAccessEdgePeekLayout.stripFrames(
      count: 3,
      position: .topLeft,
      visibleFrame: visibleFrame,
      scale: 1.25
    )

    XCTAssertEqual(frames[0].maxY, visibleFrame.maxY - QuickAccessEdgePeekLayout.edgePadding)
    XCTAssertEqual(frames[0].height, QuickAccessLayout.scaledCardHeight(1.25))
    for frame in frames {
      XCTAssertEqual(frame.minX, visibleFrame.minX)
    }
    XCTAssertGreaterThan(frames[0].minY, frames[1].maxY)
    XCTAssertGreaterThan(frames[1].minY, frames[2].maxY)
  }

  func testLayout_crowdedColumnOverlapsCardsInsteadOfShrinkingThem() {
    let shortFrame = CGRect(x: 0, y: 0, width: 1280, height: 400)
    let frames = QuickAccessEdgePeekLayout.stripFrames(
      count: 5, position: .bottomRight, visibleFrame: shortFrame, scale: 1.5
    )
    let cardHeight = QuickAccessLayout.scaledCardHeight(1.5)

    XCTAssertEqual(frames[0].height, cardHeight, "card size never changes")
    XCTAssertLessThan(frames[1].maxY, frames[0].maxY)
    XCTAssertGreaterThan(frames[1].maxY, frames[0].minY, "cards overlap like a deck")
    let visibleShare = (frames[0].maxY - frames[1].maxY) / cardHeight
    XCTAssertGreaterThanOrEqual(visibleShare, QuickAccessEdgePeekLayout.minimumVisibleShare - 0.001)
  }

  func testLayout_windowIsFixedAndFlushWithEdge() {
    let strip = CGRect(x: 1424, y: 100, width: 16, height: 112)
    let inset = QuickAccessEdgePeekLayout.shadowInset
    let right = QuickAccessEdgePeekLayout.windowFrame(forStrip: strip, position: .bottomRight)

    XCTAssertEqual(right.maxX, strip.maxX)
    XCTAssertEqual(right.width, QuickAccessEdgePeekLayout.hoverVisibleWidth + inset)
    XCTAssertEqual(right.minY, strip.minY - inset)
    XCTAssertEqual(right.height, strip.height + inset * 2)

    let leftStrip = CGRect(x: 0, y: 100, width: 16, height: 112)
    let left = QuickAccessEdgePeekLayout.windowFrame(forStrip: leftStrip, position: .topLeft)
    XCTAssertEqual(left.minX, leftStrip.minX)
    XCTAssertEqual(left.width, right.width)
  }

  func testLayout_cardOffsetRevealsRequestedSliverFromEdge() {
    let windowWidth: CGFloat = 56
    let cardWidth: CGFloat = 180

    // Right edge: card's leading edge sits `visible` points inside the window's right edge.
    let resting = QuickAccessEdgePeekLayout.cardOffsetX(
      visibleWidth: 16, windowWidth: windowWidth, cardWidth: cardWidth, isLeftSide: false
    )
    XCTAssertEqual(windowWidth - resting, 16)
    let hover = QuickAccessEdgePeekLayout.cardOffsetX(
      visibleWidth: 44, windowWidth: windowWidth, cardWidth: cardWidth, isLeftSide: false
    )
    XCTAssertEqual(windowWidth - hover, 44)
    let hidden = QuickAccessEdgePeekLayout.cardOffsetX(
      visibleWidth: QuickAccessEdgePeekLayout.hiddenVisibleWidth,
      windowWidth: windowWidth, cardWidth: cardWidth, isLeftSide: false
    )
    XCTAssertGreaterThanOrEqual(hidden, windowWidth, "hidden card and shadow sit past the edge")

    // Left edge: card's trailing edge sits `visible` points inside the window's left edge.
    let leftResting = QuickAccessEdgePeekLayout.cardOffsetX(
      visibleWidth: 16, windowWidth: windowWidth, cardWidth: cardWidth, isLeftSide: true
    )
    XCTAssertEqual(leftResting + cardWidth, 16)
  }

  func testLayout_emptyColumn() {
    XCTAssertTrue(
      QuickAccessEdgePeekLayout.stripFrames(count: 0, position: .bottomRight, visibleFrame: visibleFrame, scale: 1).isEmpty
    )
  }

  func testModel_visibleWidthFollowsPhaseAndHover() {
    let model = QuickAccessEdgePeekModel(item: makeItem(collapsed: true), isLeftSide: false, scale: 1)
    XCTAssertEqual(model.visibleWidth, QuickAccessEdgePeekLayout.hiddenVisibleWidth)

    model.phase = .resting
    XCTAssertEqual(model.visibleWidth, QuickAccessEdgePeekLayout.restingVisibleWidth)

    model.isHovered = true
    XCTAssertEqual(model.visibleWidth, QuickAccessEdgePeekLayout.hoverVisibleWidth)

    model.phase = .hidden
    XCTAssertEqual(model.visibleWidth, QuickAccessEdgePeekLayout.hiddenVisibleWidth)
  }

  // MARK: - Item state

  func testItem_collapsedCardsLeaveTheStack() {
    var item = makeItem()
    item.isCollapsed = true

    XCTAssertFalse(item.isShownInPanel(hideCardWhenWindowOpen: true))
    XCTAssertFalse(item.isShownInPanel(hideCardWhenWindowOpen: false))
  }

  func testItem_equalityAndReplacementTrackCollapsedState() {
    let item = makeItem()
    var collapsed = item
    collapsed.isCollapsed = true

    XCTAssertNotEqual(item, collapsed)
    XCTAssertTrue(collapsed.replacingThumbnail(NSImage(size: CGSize(width: 8, height: 8))).isCollapsed)
    XCTAssertTrue(collapsed.replacingURL(URL(fileURLWithPath: "/tmp/other.png")).isCollapsed)
  }

  // MARK: - Peek windows

  func testController_createsOneStripWindowPerCollapsedItemInStackOrder() throws {
    let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first, "No screen available")
    let controller = QuickAccessEdgePeekController()
    defer { controller.closeAll() }

    let first = makeItem(collapsed: true)
    let visible = makeItem()
    let second = makeItem(collapsed: true)

    controller.sync(items: [first, visible, second], position: .bottomRight, scale: 1, screen: screen)

    XCTAssertEqual(controller.collapsedIDs, [first.id, second.id])
    XCTAssertNil(controller.window(for: visible.id))
    let window = try XCTUnwrap(controller.window(for: first.id))
    XCTAssertTrue(window.isVisible)
    XCTAssertFalse(window.canBecomeKey)
    XCTAssertEqual(window.level, .floating)

    var restored = first
    restored.isCollapsed = false
    controller.sync(items: [restored, visible, second], position: .bottomRight, scale: 1, screen: screen)
    XCTAssertEqual(controller.collapsedIDs, [second.id])
    XCTAssertNil(controller.window(for: first.id))

    controller.closeAll()
    XCTAssertTrue(controller.collapsedIDs.isEmpty)
  }

  func testController_stripWindowsFollowCaptureVisibilityRules() throws {
    let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first, "No screen available")
    let controller = QuickAccessEdgePeekController()
    defer { controller.closeAll() }
    let item = makeItem(collapsed: true)

    controller.sync(items: [item], position: .topLeft, scale: 1, screen: screen)

    let window = try XCTUnwrap(controller.window(for: item.id))
    let defaults = UserDefaults.standard
    let expected = CaptureChromeWindowRegistry.appWindowSharingType(
      includeInScreenshots: defaults.bool(forKey: PreferencesKeys.screenshotIncludeOwnApp),
      includeInRecordings: defaults.bool(forKey: PreferencesKeys.recordingIncludeOwnApp)
    )
    XCTAssertEqual(window.sharingType, expected)
  }

  // MARK: - Configuration

  func testConfig_defaultDocumentKeepsCollapseOff() throws {
    let document = try SimpleTOMLParser.parse(SnapzyConfigurationDefaultDocument.toml())

    XCTAssertEqual(document.value(at: "quick_access", "swipe_toward_edge_collapses")?.boolValue, false)
  }

  func testConfig_exportAndImportSwipeTowardEdgeCollapses() throws {
    let manager = QuickAccessManager.shared
    let original = manager.swipeTowardEdgeCollapses
    defer { manager.swipeTowardEdgeCollapses = original }

    manager.swipeTowardEdgeCollapses = true
    let exported = try SimpleTOMLParser.parse(
      SnapzyConfigurationExporter.exportTOML(defaults: UserDefaultsFactory.make())
    )
    XCTAssertEqual(exported.value(at: "quick_access", "swipe_toward_edge_collapses")?.boolValue, true)

    let result = SnapzyConfigurationImporter.importTOML(
      """
      schema_version = 1

      [quick_access]
      swipe_toward_edge_collapses = false
      """,
      defaults: UserDefaultsFactory.make()
    )
    XCTAssertFalse(result.hasErrors)
    XCTAssertFalse(manager.swipeTowardEdgeCollapses)
  }

  // MARK: - Collapse action and hover shortcut

  func testCollapseAction_shipsWithOptionHAndNoDuplicateDefault() {
    let optionH = ShortcutConfig(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(optionKey))
    XCTAssertEqual(QuickAccessActionShortcutStore.defaultShortcuts[.collapseToEdge], optionH)
    XCTAssertTrue(QuickAccessActionShortcutStore.hasRequiredModifier(optionH))

    let others = QuickAccessActionShortcutStore.defaultShortcuts
      .filter { $0.key != .collapseToEdge }
      .map(\.value)
    XCTAssertFalse(others.contains(optionH))
  }

  func testCollapseAction_optionHIsAcceptedWithoutConflict() {
    let optionH = ShortcutConfig(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(optionKey))
    let decision = ShortcutValidationService.shared.validateQuickAccessActionShortcut(optionH, for: .collapseToEdge)

    guard case let .accept(issue) = decision else {
      return XCTFail("⌥H should be accepted, got \(decision)")
    }
    XCTAssertNil(issue, "⌥H should not shadow a default global shortcut")
  }

  func testCollapseAction_isANonDestructiveCornerActionEnabledForExistingUsers() {
    XCTAssertEqual(QuickAccessActionKind.collapseToEdge.displayStyle, .corner)
    XCTAssertFalse(QuickAccessActionKind.collapseToEdge.isContextMenuDestructiveGroup)
    XCTAssertEqual(QuickAccessActionKind.defaultOrder.last, .collapseToEdge)
    XCTAssertFalse(QuickAccessActionSlot.defaultAssignments.values.contains(.collapseToEdge))
    XCTAssertEqual(QuickAccessActionKind.collapseToEdge.configKey, "collapse_to_edge")

    // A list saved before this action existed must not read as an explicit disable.
    let savedBefore = [QuickAccessActionKind.copy.rawValue]
    let knownBefore = QuickAccessActionKind.allCases.filter { $0 != .collapseToEdge }.map(\.rawValue)
    let enabled = QuickAccessActionConfigurationStore.normalizedEnabledActions(from: savedBefore, known: knownBefore)
    XCTAssertTrue(enabled.contains(.collapseToEdge))
    XCTAssertFalse(enabled.contains(.dismiss))
  }

  func testResolver_collapseAsSwipeActionCollapsesFromEitherDirection() {
    let resolver = resolver(left: .collapseToEdge, right: .collapseToEdge, collapses: false, edge: 1)

    XCTAssertEqual(resolver.liveTranslation(-40), -40)
    XCTAssertEqual(resolver.resolveEnd(translation: -120, velocity: 0, isActionEnabled: allEnabled), .collapse)
    XCTAssertEqual(resolver.resolveEnd(translation: 120, velocity: 0, isActionEnabled: allEnabled), .collapse)
    XCTAssertEqual(
      resolver.resolveEnd(translation: 120, velocity: 0, isActionEnabled: { $0 != .collapseToEdge }),
      .snapBack
    )
  }

  // MARK: - Two-finger vertical move

  func testVerticalHelpers_claimOnlyPreciseClearlyVerticalMoves() {
    XCTAssertTrue(QuickAccessVerticalSwipeHelpers.isVerticalDominant(
      scrollingDeltaX: 1, scrollingDeltaY: 4, hasPreciseScrollingDeltas: true
    ))
    XCTAssertFalse(QuickAccessVerticalSwipeHelpers.isVerticalDominant(
      scrollingDeltaX: 3, scrollingDeltaY: 4, hasPreciseScrollingDeltas: true
    ), "diagonal stays with the horizontal swipe")
    XCTAssertFalse(QuickAccessVerticalSwipeHelpers.isVerticalDominant(
      scrollingDeltaX: 0, scrollingDeltaY: 4, hasPreciseScrollingDeltas: false
    ), "mouse wheels never collapse cards")
    XCTAssertFalse(QuickAccessVerticalSwipeHelpers.isVerticalDominant(
      scrollingDeltaX: 0, scrollingDeltaY: 0.2, hasPreciseScrollingDeltas: true
    ))
    XCTAssertFalse(QuickAccessVerticalSwipeHelpers.isVerticalDominant(
      scrollingDeltaX: .nan, scrollingDeltaY: 4, hasPreciseScrollingDeltas: true
    ))
  }

  func testVerticalHelpers_fingerDirectionIgnoresScrollDirectionSetting() {
    // Natural scrolling (inverted from device): fingers down report positive deltas.
    XCTAssertEqual(QuickAccessVerticalSwipeHelpers.fingerDeltaY(scrollingDeltaY: 5, isDirectionInvertedFromDevice: true), 5)
    // Classic scrolling: fingers down report negative deltas.
    XCTAssertEqual(QuickAccessVerticalSwipeHelpers.fingerDeltaY(scrollingDeltaY: -5, isDirectionInvertedFromDevice: false), 5)
    XCTAssertEqual(QuickAccessVerticalSwipeHelpers.fingerDeltaY(scrollingDeltaY: .infinity, isDirectionInvertedFromDevice: true), 0)
  }

  func testVerticalTracker_accumulatesDistanceAndReleaseVelocity() {
    var tracker = QuickAccessVerticalSwipeTracker()

    XCTAssertNil(tracker.add(fingerDelta: 10, timestamp: 0), "ignored until begun")
    tracker.begin(timestamp: 1)
    XCTAssertEqual(tracker.add(fingerDelta: 20, timestamp: 1.1), .changed(distance: 20))
    XCTAssertEqual(tracker.add(fingerDelta: 30, timestamp: 1.15), .changed(distance: 50))
    XCTAssertEqual(tracker.velocity, 600, accuracy: 0.001)

    guard case let .ended(distance, velocity) = tracker.finish(cancelled: false) else {
      return XCTFail("expected ended")
    }
    XCTAssertEqual(distance, 50)
    XCTAssertEqual(velocity, 600, accuracy: 0.001)
    XCTAssertFalse(tracker.isTracking)
    XCTAssertNil(tracker.finish(cancelled: false))
  }

  func testVerticalTracker_cancelNeverCommits() {
    var tracker = QuickAccessVerticalSwipeTracker()
    tracker.begin(timestamp: 0)
    _ = tracker.add(fingerDelta: 200, timestamp: 0.1)

    XCTAssertEqual(tracker.finish(cancelled: true), .cancelled)
    XCTAssertEqual(tracker.distance, 0)
  }

  func testCollapseSwipePolicy_commitsOnDistanceOrFlickDownOnly() {
    XCTAssertFalse(QuickAccessCollapseSwipePolicy.shouldCollapse(distance: 59, velocity: 0))
    XCTAssertTrue(QuickAccessCollapseSwipePolicy.shouldCollapse(distance: 60, velocity: 0))
    XCTAssertTrue(QuickAccessCollapseSwipePolicy.shouldCollapse(distance: 20, velocity: 500), "flick")
    XCTAssertFalse(QuickAccessCollapseSwipePolicy.shouldCollapse(distance: 5, velocity: 2000), "twitch")
    XCTAssertFalse(QuickAccessCollapseSwipePolicy.shouldCollapse(distance: -200, velocity: -900), "moving up")
    XCTAssertFalse(QuickAccessCollapseSwipePolicy.shouldCollapse(distance: .nan, velocity: 0))

    XCTAssertTrue(QuickAccessCollapseSwipePolicy.shouldRestore(distance: -60, velocity: 0))
    XCTAssertTrue(QuickAccessCollapseSwipePolicy.shouldRestore(distance: -20, velocity: -500))
    XCTAssertFalse(QuickAccessCollapseSwipePolicy.shouldRestore(distance: 200, velocity: 900), "moving down")
  }

  func testCollapseSwipePolicy_progressAndCardMotion() {
    XCTAssertEqual(QuickAccessCollapseSwipePolicy.collapseProgress(distance: -40), 0)
    XCTAssertEqual(QuickAccessCollapseSwipePolicy.collapseProgress(distance: 60), 0.5)
    XCTAssertEqual(QuickAccessCollapseSwipePolicy.collapseProgress(distance: 500), 1)
    XCTAssertEqual(QuickAccessCollapseSwipePolicy.restoreProgress(distance: -60), 0.5)
    XCTAssertEqual(QuickAccessCollapseSwipePolicy.restoreProgress(distance: 60), 0)

    XCTAssertEqual(QuickAccessCollapseSwipePolicy.cardScale(progress: 0), 1)
    XCTAssertEqual(QuickAccessCollapseSwipePolicy.cardScale(progress: 1), QuickAccessCollapseSwipePolicy.collapsedScale)
    XCTAssertEqual(QuickAccessCollapseSwipePolicy.cardDrop(progress: 2), QuickAccessCollapseSwipePolicy.maxDrop)
    XCTAssertEqual(
      QuickAccessCollapseSwipePolicy.cardDrift(progress: 0.5, edgeDirection: -1),
      -QuickAccessCollapseSwipePolicy.edgeDrift / 2
    )
  }

  func testHorizontalHelpers_inwardSwipeLeavesTheEdgeOnEitherSide() {
    XCTAssertTrue(QuickAccessVerticalSwipeHelpers.isHorizontalDominant(
      scrollingDeltaX: 4, scrollingDeltaY: 1, hasPreciseScrollingDeltas: true
    ))
    XCTAssertFalse(QuickAccessVerticalSwipeHelpers.isHorizontalDominant(
      scrollingDeltaX: 4, scrollingDeltaY: 3, hasPreciseScrollingDeltas: true
    ))
    XCTAssertFalse(QuickAccessVerticalSwipeHelpers.isHorizontalDominant(
      scrollingDeltaX: 4, scrollingDeltaY: 0, hasPreciseScrollingDeltas: false
    ))

    // Fingers moving left, with natural and with classic scrolling.
    let leftNatural = QuickAccessVerticalSwipeHelpers.fingerDeltaX(scrollingDeltaX: -6, isDirectionInvertedFromDevice: true)
    let leftClassic = QuickAccessVerticalSwipeHelpers.fingerDeltaX(scrollingDeltaX: 6, isDirectionInvertedFromDevice: false)
    XCTAssertEqual(leftNatural, -6)
    XCTAssertEqual(leftClassic, -6)

    // Right-edge peek: moving left is inward. Left-edge peek: moving right is inward.
    XCTAssertEqual(QuickAccessVerticalSwipeHelpers.inwardDelta(fingerDeltaX: -6, isLeftSide: false), 6)
    XCTAssertEqual(QuickAccessVerticalSwipeHelpers.inwardDelta(fingerDeltaX: 6, isLeftSide: true), 6)
    XCTAssertEqual(QuickAccessVerticalSwipeHelpers.inwardDelta(fingerDeltaX: 6, isLeftSide: false), -6)

    // Inward travel maps to negative tracker distance, which restores.
    let inward = QuickAccessVerticalSwipeHelpers.inwardDelta(fingerDeltaX: -70, isLeftSide: false)
    XCTAssertTrue(QuickAccessCollapseSwipePolicy.shouldRestore(distance: -inward, velocity: 0))
    XCTAssertFalse(QuickAccessCollapseSwipePolicy.shouldRestore(distance: inward, velocity: 0), "outward never restores")
  }
}
