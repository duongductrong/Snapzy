//
//  AnnotateCoreTests.swift
//  SnapzyTests
//
//  Unit tests for annotation creation and geometry helpers.
//

import CoreGraphics
import AppKit
import SwiftUI
import XCTest
@testable import Snapzy

final class AnnotateCoreTests: XCTestCase {
  // Keep AnnotateState alive for the test process; XCTest scope cleanup can
  // crash while deinitializing this MainActor app-level ObservableObject.
  @MainActor private static var retainedAnnotateStates: [AnnotateState] = []
  @MainActor private static var retainedCanvasPresetStores: [AnnotateCanvasPresetStore] = []
  @MainActor private static var retainedUserDefaults: [UserDefaults] = []

  @MainActor
  private func makeAnnotateState() -> AnnotateState {
    let state = AnnotateState()
    Self.retainedAnnotateStates.append(state)
    return state
  }

  @MainActor
  private func makeAnnotateState(defaults: UserDefaults) -> AnnotateState {
    let state = AnnotateState(defaults: defaults)
    Self.retainedUserDefaults.append(defaults)
    Self.retainedAnnotateStates.append(state)
    return state
  }

  @MainActor
  private func makeCanvasPresetStore() -> (AnnotateCanvasPresetStore, UserDefaults) {
    let defaults = UserDefaultsFactory.make()
    let store = AnnotateCanvasPresetStore(defaults: defaults)
    Self.retainedUserDefaults.append(defaults)
    Self.retainedCanvasPresetStores.append(store)
    return (store, defaults)
  }

  func testAnnotateCanvasDefaultsUseNoCornerRadius() {
    XCTAssertEqual(AnnotateCanvasDefaults.cornerRadius, 0)
    XCTAssertEqual(AnnotationCanvasEffects().cornerRadius, 0)
    XCTAssertFalse(AnnotationCanvasEffects().isBlurredBackgroundEnabled)
    XCTAssertEqual(AnnotationCanvasEffects().blurredBackgroundEffect, .soft)
  }

  func testAnnotateDragCompletionPolicyClosesOnSuccessfulDragWhenEnabled() {
    XCTAssertEqual(
      AnnotateDragCompletionPolicy.action(
        success: true,
        closeAfterDrag: true,
        bringForwardAfterDrag: false
      ),
      .closeAndDismiss
    )
  }

  func testAnnotateDragCompletionPolicyRestoresInBackgroundWhenKeepingEditor() {
    XCTAssertEqual(
      AnnotateDragCompletionPolicy.action(
        success: true,
        closeAfterDrag: false,
        bringForwardAfterDrag: false
      ),
      .restore(presentation: .background)
    )
  }

  func testAnnotateDragCompletionPolicyRestoresInForegroundWhenRequested() {
    XCTAssertEqual(
      AnnotateDragCompletionPolicy.action(
        success: true,
        closeAfterDrag: false,
        bringForwardAfterDrag: true
      ),
      .restore(presentation: .foreground)
    )
  }

  func testAnnotateDragCompletionPolicyRestoresWithActivationWhenDragFails() {
    XCTAssertEqual(
      AnnotateDragCompletionPolicy.action(
        success: false,
        closeAfterDrag: true,
        bringForwardAfterDrag: false
      ),
      .restore(presentation: .foreground)
    )
    XCTAssertEqual(
      AnnotateDragCompletionPolicy.action(
        success: false,
        closeAfterDrag: false,
        bringForwardAfterDrag: true
      ),
      .restore(presentation: .foreground)
    )
  }

  private class MockAnnotateWindow: AnnotateWindow {
    var stubbedIsKeyWindow = false
    var stubbedIsMainWindow = false

    override var isKeyWindow: Bool { stubbedIsKeyWindow }
    override var isMainWindow: Bool { stubbedIsMainWindow }
  }

  @MainActor
  func testAnnotateWindowFocusSyncKeepsInactiveWindowAtRestingLevel() {
    let window = MockAnnotateWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600)
    )
    defer { window.close() }

    let activeLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    
    // 1. Neither key nor main -> should be normal
    window.stubbedIsKeyWindow = false
    window.stubbedIsMainWindow = false
    window.syncLevelWithFocusState()
    XCTAssertEqual(window.level, .normal)

    // 2. Key but not main -> should be activeLevel
    window.stubbedIsKeyWindow = true
    window.stubbedIsMainWindow = false
    window.syncLevelWithFocusState()
    XCTAssertEqual(window.level, activeLevel)

    // 3. Main but not key -> should be activeLevel (crucial for popovers/dropdowns)
    window.stubbedIsKeyWindow = false
    window.stubbedIsMainWindow = true
    window.syncLevelWithFocusState()
    XCTAssertEqual(window.level, activeLevel)

    // 4. Both key and main -> should be activeLevel
    window.stubbedIsKeyWindow = true
    window.stubbedIsMainWindow = true
    window.syncLevelWithFocusState()
    XCTAssertEqual(window.level, activeLevel)

    // 5. Rest resting level test
    window.setRestingLevel(.floating)
    window.stubbedIsKeyWindow = false
    window.stubbedIsMainWindow = false
    window.syncLevelWithFocusState()
    XCTAssertEqual(window.level, .floating)
  }

  @MainActor
  func testAnnotateStateToggleSidebarVisibilitySkipsPreviewMode() {
    let state = makeAnnotateState()

    state.toggleSidebarVisibility()
    XCTAssertTrue(state.showSidebar)

    state.editorMode = .preview
    state.toggleSidebarVisibility()
    XCTAssertTrue(state.showSidebar)

    state.editorMode = .annotate
    state.toggleSidebarVisibility()
    XCTAssertFalse(state.showSidebar)
  }

  func testSensitiveDataDetectorFindsCommonSensitivePatterns() {
    let detector = AnnotateSensitiveDataDetector()
    let text = """
    Email admin@example.com, URL https://snapzy.app/share, card 4111 1111 1111 1111,
    invalid raw card 4111111111111112, token ghp_abcdefghijklmnopqrstuvwxyz123456,
    api_key = sk-localSecret12345
    """

    let matches = detector.detect(in: text)
    let kinds = Set(matches.map(\.kind))

    XCTAssertTrue(kinds.contains(.email))
    XCTAssertTrue(kinds.contains(.url))
    XCTAssertTrue(kinds.contains(.creditCard))
    XCTAssertTrue(kinds.contains(.accessToken))
    XCTAssertTrue(kinds.contains(.credential))
    XCTAssertEqual(matches.filter { $0.kind == .creditCard }.count, 1)
  }

  func testSensitiveDataDetectorTreatsGroupedPaymentCardsAsSensitiveEvenWhenLuhnInvalid() {
    let detector = AnnotateSensitiveDataDetector()

    let groupedMatches = detector.detect(in: "Card 4532 3100 9999 1048")
    let rawMatches = detector.detect(in: "Build 4532310099991048")
    let genericGroupedMatches = detector.detect(in: "Order 1234 5678 9012 3456")

    XCTAssertTrue(groupedMatches.contains { $0.kind == .creditCard })
    XCTAssertFalse(rawMatches.contains { $0.kind == .creditCard })
    XCTAssertFalse(genericGroupedMatches.contains { $0.kind == .creditCard })
  }

  func testSensitiveRedactionContextDetectsPaymentCardFieldsSplitByOCR() {
    let imageSize = CGSize(width: 544.5, height: 398)
    let lines = [
      AnnotateSensitiveOCRLine(text: "/ BANK NAME", bounds: CGRect(x: 111, y: 102, width: 141, height: 20), confidence: 1),
      AnnotateSensitiveOCRLine(text: "4532 3100 9999", bounds: CGRect(x: 106, y: 210, width: 211, height: 20), confidence: 1),
      AnnotateSensitiveOCRLine(text: "1048", bounds: CGRect(x: 333, y: 211, width: 61, height: 20), confidence: 1),
      AnnotateSensitiveOCRLine(text: "MEMBER", bounds: CGRect(x: 108, y: 255, width: 37, height: 8), confidence: 1),
      AnnotateSensitiveOCRLine(text: "SINCE", bounds: CGRect(x: 108, y: 264, width: 25, height: 9), confidence: 1),
      AnnotateSensitiveOCRLine(text: "00", bounds: CGRect(x: 152, y: 255, width: 21, height: 14), confidence: 1),
      AnnotateSensitiveOCRLine(text: "VALID", bounds: CGRect(x: 215, y: 255, width: 26, height: 8), confidence: 1),
      AnnotateSensitiveOCRLine(text: "THRU", bounds: CGRect(x: 215, y: 264, width: 24, height: 8), confidence: 1),
      AnnotateSensitiveOCRLine(text: "00-00", bounds: CGRect(x: 260, y: 254, width: 48, height: 15), confidence: 1),
      AnnotateSensitiveOCRLine(text: "CARDHOLDER NAME", bounds: CGRect(x: 108, y: 290, width: 155, height: 15), confidence: 1)
    ]

    let regions = AnnotateSensitiveRedactionService.contextualRegions(from: lines, imageSize: imageSize)
    let kinds = Set(regions.map(\.kind))

    XCTAssertTrue(kinds.contains(.creditCard))
    XCTAssertTrue(kinds.contains(.paymentCardExpiration))
    XCTAssertTrue(kinds.contains(.paymentCardholderName))
    XCTAssertEqual(regions.filter { $0.kind == .creditCard }.count, 1)
    XCTAssertTrue(
      regions.contains {
        $0.kind == .creditCard
          && $0.bounds.contains(CGRect(x: 106, y: 210, width: 288, height: 21))
      }
    )
    XCTAssertFalse(regions.contains { $0.bounds.intersects(CGRect(x: 152, y: 255, width: 21, height: 14)) && $0.kind != .creditCard })
  }

  func testSensitiveRedactionContextDetectsPaymentCardFieldsSplitIntoFourOCRFragments() {
    let imageSize = CGSize(width: 667, height: 521.5)
    let cardNumberBounds = CGRect(x: 145, y: 238.4, width: 285, height: 22.9)
    let lines = [
      AnnotateSensitiveOCRLine(text: "/ BANK NAME", bounds: CGRect(x: 154, y: 131.9, width: 135, height: 16), confidence: 1),
      AnnotateSensitiveOCRLine(text: "4532", bounds: CGRect(x: 145, y: 238.7, width: 58.1, height: 20.2), confidence: 1),
      AnnotateSensitiveOCRLine(text: "3100", bounds: CGRect(x: 211.1, y: 238.4, width: 66.8, height: 22.6), confidence: 1),
      AnnotateSensitiveOCRLine(text: "9999", bounds: CGRect(x: 294, y: 238.7, width: 59.1, height: 20.2), confidence: 1),
      AnnotateSensitiveOCRLine(text: "1048", bounds: CGRect(x: 370, y: 238.8, width: 60, height: 20), confidence: 1),
      AnnotateSensitiveOCRLine(text: "MEMBER", bounds: CGRect(x: 143.9, y: 283.4, width: 38.1, height: 8.6), confidence: 1),
      AnnotateSensitiveOCRLine(text: "SINCE", bounds: CGRect(x: 145, y: 291.7, width: 25, height: 9), confidence: 1),
      AnnotateSensitiveOCRLine(text: "00", bounds: CGRect(x: 189, y: 282.7, width: 21, height: 14), confidence: 1),
      AnnotateSensitiveOCRLine(text: "VALID", bounds: CGRect(x: 252, y: 283.7, width: 25, height: 8), confidence: 1),
      AnnotateSensitiveOCRLine(text: "THRU", bounds: CGRect(x: 252, y: 292.7, width: 23, height: 8), confidence: 1),
      AnnotateSensitiveOCRLine(text: "00-00", bounds: CGRect(x: 297, y: 282.7, width: 48, height: 14), confidence: 1),
      AnnotateSensitiveOCRLine(text: "CARDHOLDER NAME", bounds: CGRect(x: 145, y: 318.7, width: 154, height: 14), confidence: 1)
    ]

    let regions = AnnotateSensitiveRedactionService.contextualRegions(from: lines, imageSize: imageSize)

    XCTAssertEqual(regions.filter { $0.kind == .creditCard }.count, 1)
    XCTAssertTrue(regions.contains { $0.kind == .creditCard && $0.bounds.contains(cardNumberBounds) })
    XCTAssertTrue(regions.contains { $0.kind == .paymentCardExpiration })
    XCTAssertTrue(regions.contains { $0.kind == .paymentCardholderName })
    XCTAssertFalse(regions.contains { $0.bounds.intersects(CGRect(x: 189, y: 282.7, width: 21, height: 14)) && $0.kind != .creditCard })
  }

  func testSensitiveRedactionContextDetectsPaymentCardInsideAnnotateWindowScreenshotOCRNoise() {
    let imageSize = CGSize(width: 1272, height: 826)
    let cardNumberBounds = CGRect(x: 482.5, y: 437.9, width: 284.8, height: 22.2)
    let lines = [
      AnnotateSensitiveOCRLine(text: "Save as...", bounds: CGRect(x: 1094.5, y: 40.5, width: 61, height: 13.1), confidence: 1),
      AnnotateSensitiveOCRLine(text: "Done", bounds: CGRect(x: 1185.1, y: 40.7, width: 33.3, height: 12.9), confidence: 1),
      AnnotateSensitiveOCRLine(text: "Selected Blur", bounds: CGRect(x: 94.3, y: 88.5, width: 74, height: 9.5), confidence: 1),
      AnnotateSensitiveOCRLine(text: "Blur Type", bounds: CGRect(x: 245.9, y: 88.5, width: 48.2, height: 11.4), confidence: 1),
      AnnotateSensitiveOCRLine(text: "4532 3100", bounds: CGRect(x: 482.5, y: 437.9, width: 131.3, height: 22.2), confidence: 1),
      AnnotateSensitiveOCRLine(text: "9999 1048", bounds: CGRect(x: 630.5, y: 437.9, width: 136.8, height: 22.2), confidence: 1),
      AnnotateSensitiveOCRLine(text: "MEMBER 00", bounds: CGRect(x: 482.5, y: 482.3, width: 64.7, height: 14.8), confidence: 1),
      AnnotateSensitiveOCRLine(text: "SINCE", bounds: CGRect(x: 482.5, y: 491.5, width: 24, height: 9.2), confidence: 1),
      AnnotateSensitiveOCRLine(text: "VALID", bounds: CGRect(x: 589.8, y: 482.3, width: 25.9, height: 11.1), confidence: 1),
      AnnotateSensitiveOCRLine(text: "THRU", bounds: CGRect(x: 589.8, y: 491.5, width: 24, height: 9.2), confidence: 1),
      AnnotateSensitiveOCRLine(text: "00-00", bounds: CGRect(x: 632.3, y: 482.3, width: 49.9, height: 16.6), confidence: 1),
      AnnotateSensitiveOCRLine(text: "CARDHOLDER NAME", bounds: CGRect(x: 480.7, y: 519.3, width: 157.2, height: 14.8), confidence: 1)
    ]

    let regions = AnnotateSensitiveRedactionService.contextualRegions(from: lines, imageSize: imageSize)

    XCTAssertEqual(regions.filter { $0.kind == .creditCard }.count, 1)
    XCTAssertTrue(regions.contains { $0.kind == .creditCard && $0.bounds.contains(cardNumberBounds) })
    XCTAssertTrue(regions.contains { $0.kind == .paymentCardExpiration })
    XCTAssertTrue(regions.contains { $0.kind == .paymentCardholderName })
  }

  func testSensitiveDataDetectorPrecisionRecallGateMeetsP99OnCuratedCorpus() {
    struct Sample {
      let text: String
      let expectedKinds: Set<AnnotateSensitiveDataKind>
    }

    let detector = AnnotateSensitiveDataDetector()
    let samples: [Sample] = [
      Sample(text: "Email admin@example.com", expectedKinds: [.email]),
      Sample(text: "URL https://snapzy.app/share", expectedKinds: [.url]),
      Sample(text: "Phone +1 415-555-2671", expectedKinds: [.phoneNumber]),
      Sample(text: "Card 4111 1111 1111 1111", expectedKinds: [.creditCard]),
      Sample(text: "Mock card 4532 3100 9999 1048", expectedKinds: [.creditCard]),
      Sample(text: "api_key = sk-localSecret12345", expectedKinds: [.credential]),
      Sample(text: "Authorization: Bearer abcdefghijklmnop", expectedKinds: [.accessToken]),
      Sample(text: "GitHub ghp_abcdefghijklmnopqrstuvwxyz123456", expectedKinds: [.accessToken]),
      Sample(text: "Build 4532310099991048", expectedKinds: []),
      Sample(text: "Order 1234 5678 9012 3456", expectedKinds: []),
      Sample(text: "Version 2026-06-07 build 973", expectedKinds: []),
      Sample(text: "Member since 00", expectedKinds: []),
      Sample(text: "Invoice total 1048", expectedKinds: [])
    ]

    var truePositives = 0
    var falsePositives = 0
    var falseNegatives = 0

    for sample in samples {
      let actualKinds = Set(detector.detect(in: sample.text).map(\.kind))
      truePositives += actualKinds.intersection(sample.expectedKinds).count
      falsePositives += actualKinds.subtracting(sample.expectedKinds).count
      falseNegatives += sample.expectedKinds.subtracting(actualKinds).count
    }

    let precision = Double(truePositives) / Double(max(truePositives + falsePositives, 1))
    let recall = Double(truePositives) / Double(max(truePositives + falseNegatives, 1))

    XCTAssertGreaterThanOrEqual(precision, 0.99)
    XCTAssertGreaterThanOrEqual(recall, 0.99)
  }

  func testSensitiveRedactionVisionBoxConvertsToImageCoordinates() {
    let rect = AnnotateSensitiveRedactionService.imageRect(
      fromVisionBoundingBox: CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.1),
      imageSize: CGSize(width: 400, height: 200)
    )

    XCTAssertEqual(rect.origin.x, 100, accuracy: 0.0001)
    XCTAssertEqual(rect.origin.y, 140, accuracy: 0.0001)
    XCTAssertEqual(rect.width, 200, accuracy: 0.0001)
    XCTAssertEqual(rect.height, 20, accuracy: 0.0001)
  }

  func testSensitiveRedactionRectUsesFullLineBoundsWhenMatchCoversMostOCRLine() {
    let text = "admin@example.com"
    let matchRange = NSRange(text.startIndex..<text.endIndex, in: text)
    let lineRect = CGRect(x: 10, y: 18, width: 120, height: 18)
    let tightMatchRect = CGRect(x: 28, y: 22, width: 80, height: 10)

    let rect = AnnotateSensitiveRedactionService.redactionRect(
      forMatchRect: tightMatchRect,
      lineRect: lineRect,
      matchRange: matchRange,
      text: text,
      kind: .email,
      imageSize: CGSize(width: 200, height: 100)
    )

    XCTAssertTrue(rect.contains(lineRect))
  }

  func testSensitiveRedactionRectKeepsSubstringBoundsScopedInsideLongOCRLine() {
    let text = "Email admin@example.com sent to finance"
    let matchRange = (text as NSString).range(of: "admin@example.com")
    let lineRect = CGRect(x: 10, y: 18, width: 240, height: 18)
    let tightMatchRect = CGRect(x: 60, y: 22, width: 100, height: 10)

    let rect = AnnotateSensitiveRedactionService.redactionRect(
      forMatchRect: tightMatchRect,
      lineRect: lineRect,
      matchRange: matchRange,
      text: text,
      kind: .email,
      imageSize: CGSize(width: 300, height: 100)
    )

    XCTAssertTrue(rect.contains(tightMatchRect))
    XCTAssertFalse(rect.contains(lineRect))
    XCTAssertGreaterThan(rect.minX, lineRect.minX)
    XCTAssertLessThan(rect.maxX, lineRect.maxX)
  }

  @MainActor
  func testApplySensitiveRedactionsAddsEditableBlurBatchWithSingleUndo() throws {
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: 200, height: 100))
    let image = NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 100))
    let state = makeAnnotateState()
    state.loadImage(image)
    let expectedBlurProperties = state.annotationCreationProperties(for: .blur)

    let insertedCount = state.applySensitiveRedactionRegions([
      AnnotateSensitiveRedactionRegion(
        kind: .email,
        bounds: CGRect(x: 10, y: 12, width: 80, height: 18),
        confidence: 0.95
      ),
      AnnotateSensitiveRedactionRegion(
        kind: .accessToken,
        bounds: CGRect(x: 120, y: 48, width: 60, height: 16),
        confidence: 0.98
      )
    ])

    XCTAssertEqual(insertedCount, 2)
    XCTAssertEqual(state.annotations.count, 2)
    XCTAssertEqual(state.selectedAnnotationIds.count, 2)
    XCTAssertTrue(state.hasUnsavedChanges)
    XCTAssertTrue(state.canUndo)
    for annotation in state.annotations {
      guard case .blur(.pixelated) = annotation.type else {
        XCTFail("Expected pixelated blur annotation")
        return
      }
      XCTAssertEqual(annotation.properties, expectedBlurProperties)
    }

    state.undo()

    XCTAssertTrue(state.annotations.isEmpty)
    XCTAssertFalse(state.hasSelectedAnnotations)
  }

  @MainActor
  func testApplySensitiveRedactionsUsesBlurQuickPropertiesDefaults() throws {
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: 200, height: 100))
    let image = NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 100))
    let state = makeAnnotateState(defaults: UserDefaultsFactory.make())
    state.loadImage(image)
    state.activateTool(.blur)

    XCTAssertEqual(state.annotationCreationProperties(for: .blur).strokeWidth, 1)
    XCTAssertEqual(state.quickStrokeWidthDisplayText, "8")

    state.quickStrokeWidthBinding.wrappedValue = 6
    state.setActiveBlurType(.gaussian)
    let expectedBlurProperties = state.annotationCreationProperties(for: .blur)

    let insertedCount = state.applySensitiveRedactionRegions([
      AnnotateSensitiveRedactionRegion(
        kind: .email,
        bounds: CGRect(x: 10, y: 12, width: 80, height: 18),
        confidence: 0.95
      )
    ])

    XCTAssertEqual(insertedCount, 1)
    let annotation = try XCTUnwrap(state.annotations.first)
    guard case .blur(.gaussian) = annotation.type else {
      XCTFail("Expected gaussian blur annotation")
      return
    }
    XCTAssertEqual(annotation.properties, expectedBlurProperties)
    XCTAssertEqual(state.quickPropertiesTool, .blur)
    XCTAssertTrue(state.quickPropertiesSupportsBlurType)
    XCTAssertTrue(state.quickPropertiesSupportsStrokeWidth)
    XCTAssertEqual(state.quickStrokeWidthBinding.wrappedValue, 6)
  }

  @MainActor
  func testActivateToolNotifiesOnlyForExplicitActivation() {
    let state = makeAnnotateState(defaults: UserDefaultsFactory.make())
    var activatedTools: [AnnotationToolType] = []
    state.onToolActivated = { activatedTools.append($0) }

    state.activateTool(.arrow)
    state.selectedTool = .text

    XCTAssertEqual(state.selectedTool, .text)
    XCTAssertEqual(activatedTools, [.arrow])
  }

  func testInlineAreaControls_nearFullscreenSelectionUsesBottomInnerPlacement() {
    let containerSize = CGSize(width: 1512, height: 982)
    let rect = CGRect(origin: .zero, size: containerSize)

    let placement = InlineAreaControlGeometry.placement(
      for: rect,
      containerSize: containerSize,
      showsProperties: true,
      propertiesContentWidth: 0,
      controlInsets: .zero
    )

    let reservedHeight = InlineAreaLayout.reservedControlHeight(showsProperties: true)
    let expectedGroupTop = containerSize.height - InlineAreaLayout.screenPadding - reservedHeight
    XCTAssertEqual(
      placement.toolbarCenter.y,
      expectedGroupTop + InlineAreaLayout.toolbarHeight / 2,
      accuracy: 0.0001
    )
    XCTAssertEqual(
      placement.propertiesCenter.y + InlineAreaLayout.propertiesHeight / 2,
      containerSize.height - InlineAreaLayout.screenPadding,
      accuracy: 0.0001
    )
    XCTAssertGreaterThan(placement.toolbarCenter.y, containerSize.height / 2)
  }

  func testInlineAreaControls_respectsTopInsetWhenClampedAboveSelection() {
    let containerSize = CGSize(width: 1512, height: 982)
    let rect = CGRect(x: 80, y: 120, width: 1200, height: 862)
    let controlInsets = InlineAreaControlInsets(top: 60)

    let placement = InlineAreaControlGeometry.placement(
      for: rect,
      containerSize: containerSize,
      showsProperties: false,
      propertiesContentWidth: 0,
      controlInsets: controlInsets
    )

    XCTAssertEqual(
      placement.toolbarCenter.y - InlineAreaLayout.toolbarHeight / 2,
      controlInsets.controlTopPadding,
      accuracy: 0.0001
    )
    XCTAssertLessThanOrEqual(
      placement.toolbarCenter.y + InlineAreaLayout.toolbarHeight / 2,
      rect.minY + 0.0001
    )
  }

  func testInlineAreaControls_keepsAbovePlacementWhenThereIsEnoughRoom() {
    let containerSize = CGSize(width: 1512, height: 982)
    let rect = CGRect(x: 120, y: 200, width: 900, height: 300)

    let placement = InlineAreaControlGeometry.placement(
      for: rect,
      containerSize: containerSize,
      showsProperties: false,
      propertiesContentWidth: 0,
      controlInsets: .zero
    )

    XCTAssertEqual(
      placement.toolbarCenter.y,
      rect.minY - InlineAreaLayout.selectionGap - InlineAreaLayout.toolbarHeight / 2,
      accuracy: 0.0001
    )
  }

  func testInlineAreaActionRail_usesLeftOutsideWhenRightOutsideUnavailable() {
    let containerSize = CGSize(width: 400, height: 300)
    let rect = CGRect(x: 320, y: 60, width: 64, height: 180)

    let placement = InlineAreaControlGeometry.placement(
      for: rect,
      containerSize: containerSize,
      showsProperties: false,
      propertiesContentWidth: 0,
      controlInsets: .zero
    )

    XCTAssertLessThan(
      placement.actionRailCenter.x + InlineAreaLayout.actionRailWidth / 2,
      rect.minX
    )
  }

  func testInlineAreaActionRail_usesRightInnerWhenNoOutsideHorizontalRoom() {
    let containerSize = CGSize(width: 400, height: 300)
    let rect = CGRect(x: 0, y: 20, width: 400, height: 260)

    let placement = InlineAreaControlGeometry.placement(
      for: rect,
      containerSize: containerSize,
      showsProperties: false,
      propertiesContentWidth: 0,
      controlInsets: .zero
    )

    let maximumX = containerSize.width
      - InlineAreaLayout.actionRailWidth / 2
      - InlineAreaLayout.screenPadding
    XCTAssertEqual(placement.actionRailCenter.x, maximumX, accuracy: 0.0001)
    XCTAssertGreaterThan(placement.actionRailCenter.x, rect.midX)
    XCTAssertLessThanOrEqual(
      placement.actionRailCenter.x + InlineAreaLayout.actionRailWidth / 2,
      rect.maxX + 0.0001
    )
  }

  func testInlineAreaControlInsetsPreferVisibleFrameAndSafeArea() {
    let insets = InlineAreaControlInsets(
      screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
      visibleFrame: CGRect(x: 40, y: 50, width: 1432, height: 900),
      safeAreaInsets: NSEdgeInsets(top: 70, left: 12, bottom: 10, right: 24)
    )

    XCTAssertEqual(insets.top, 70)
    XCTAssertEqual(insets.leading, 40)
    XCTAssertEqual(insets.bottom, 50)
    XCTAssertEqual(insets.trailing, 40)
  }

  func testInlineAreaDesktopFrameUsesUnionOfDisplayFrames() {
    let desktopFrame = InlineAreaAnnotateSession.desktopFrame(for: [
      CGRect(x: 0, y: 0, width: 300, height: 200),
      CGRect(x: 300, y: -100, width: 200, height: 160),
    ])

    XCTAssertEqual(desktopFrame, CGRect(x: 0, y: -100, width: 500, height: 300))
  }

  func testInlineAreaLocalFrameMapsScreenFrameIntoTopLeftDesktopCoordinates() {
    let desktopFrame = CGRect(x: -200, y: -100, width: 700, height: 300)
    let screenFrame = CGRect(x: 300, y: -100, width: 200, height: 160)

    let localFrame = InlineAreaAnnotateSession.localFrame(for: screenFrame, in: desktopFrame)

    XCTAssertEqual(localFrame, CGRect(x: 500, y: 140, width: 200, height: 160))
  }

  func testInlineAreaScreenRectConvertsDesktopLocalSelectionToScreenCoordinates() {
    let desktopFrame = CGRect(x: -200, y: -100, width: 700, height: 300)
    let localRect = CGRect(x: 250, y: 40, width: 120, height: 80)

    let screenRect = InlineAreaAnnotateSession.screenRect(for: localRect, in: desktopFrame)

    XCTAssertEqual(screenRect, CGRect(x: 50, y: 80, width: 120, height: 80))
  }

  func testInlineAreaLocalRectConvertsAlignedScreenRectToDesktopLocalCoordinates() {
    let desktopFrame = CGRect(x: -200, y: -100, width: 700, height: 300)
    let screenRect = CGRect(x: 50, y: 80, width: 120.5, height: 80.5)

    let localRect = InlineAreaAnnotateSession.localRect(for: screenRect, in: desktopFrame)

    XCTAssertEqual(localRect.origin.x, 250.0, accuracy: 0.0001)
    XCTAssertEqual(localRect.origin.y, 39.5, accuracy: 0.0001)
    XCTAssertEqual(localRect.width, 120.5, accuracy: 0.0001)
    XCTAssertEqual(localRect.height, 80.5, accuracy: 0.0001)
  }

  func testInlineAreaDisplayIDsIntersectingSpanningSelectionReturnsAllTouchedDisplays() {
    let screenFramesByDisplayID: [CGDirectDisplayID: CGRect] = [
      1: CGRect(x: 0, y: 0, width: 200, height: 200),
      2: CGRect(x: 200, y: 0, width: 200, height: 200),
      3: CGRect(x: 0, y: 200, width: 200, height: 200),
    ]
    let selection = CGRect(x: 150, y: 40, width: 120, height: 80)

    let displayIDs = InlineAreaAnnotateSession.displayIDsIntersecting(
      selection,
      screenFramesByDisplayID: screenFramesByDisplayID
    )

    XCTAssertEqual(displayIDs, [1, 2])
  }

  func testInlineAreaPrimaryDisplayIDUsesLargestIntersection() {
    let screenFramesByDisplayID: [CGDirectDisplayID: CGRect] = [
      1: CGRect(x: 0, y: 0, width: 200, height: 200),
      2: CGRect(x: 200, y: 0, width: 200, height: 200),
    ]
    let selection = CGRect(x: 170, y: 40, width: 160, height: 80)

    let displayID = InlineAreaAnnotateSession.primaryDisplayID(
      for: selection,
      screenFramesByDisplayID: screenFramesByDisplayID,
      fallback: 1
    )

    XCTAssertEqual(displayID, 2)
  }

  @MainActor
  func testAnnotateState_undoAfterNewTextCreationRemovesTextAnnotation() {
    let state = makeAnnotateState()

    state.saveState()
    let annotation = AnnotationItem(
      type: .text("Hello"),
      bounds: CGRect(x: 20, y: 20, width: 120, height: 32),
      properties: AnnotationProperties(fontSize: 18)
    )
    state.annotations.append(annotation)
    state.selectedAnnotationId = annotation.id
    state.beginTextEditing(id: annotation.id, recordsUndo: false)
    state.commitTextEditing()

    state.undo()

    XCTAssertTrue(state.annotations.isEmpty)
  }

  @MainActor
  func testAnnotateState_undoRedoExistingTextEditRestoresText() throws {
    let state = makeAnnotateState()
    let annotation = AnnotationItem(
      type: .text("Original"),
      bounds: CGRect(x: 20, y: 20, width: 140, height: 32),
      properties: AnnotationProperties(fontSize: 18)
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id

    state.beginTextEditing(id: annotation.id)
    state.updateAnnotationText(id: annotation.id, text: "Changed")
    state.commitTextEditing()
    state.undo()

    let undone = try XCTUnwrap(state.annotations.first)
    guard case .text(let undoneText) = undone.type else {
      return XCTFail("Expected text annotation after undo")
    }
    XCTAssertEqual(undoneText, "Original")

    state.redo()

    let redone = try XCTUnwrap(state.annotations.first)
    guard case .text(let redoneText) = redone.type else {
      return XCTFail("Expected text annotation after redo")
    }
    XCTAssertEqual(redoneText, "Changed")
  }

  @MainActor
  func testAnnotateState_undoRedoTextFontSizeRestoresPropertiesAndBounds() throws {
    let state = makeAnnotateState()
    let originalBounds = CGRect(x: 20, y: 20, width: 180, height: 32)
    let annotation = AnnotationItem(
      type: .text("Resizable text"),
      bounds: originalBounds,
      properties: AnnotationProperties(fontSize: 18)
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id

    state.updateAnnotationProperties(id: annotation.id, fontSize: 36, recordsUndo: true)

    let resized = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(resized.properties.fontSize, 36)
    XCTAssertNotEqual(resized.bounds, originalBounds)

    state.undo()

    let undone = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(undone.properties.fontSize, 18)
    XCTAssertEqual(undone.bounds, originalBounds)

    state.redo()

    let redone = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(redone.properties.fontSize, 36)
  }

  @MainActor
  func testAnnotateState_replaceSourceImagePreservingAnnotationsAppliesOffset() throws {
    let state = makeAnnotateState()
    let rectangle = AnnotationItem(
      type: .rectangle,
      bounds: CGRect(x: 20, y: 30, width: 80, height: 44),
      properties: AnnotationProperties()
    )
    let line = AnnotationItem(
      type: .line(start: CGPoint(x: 12, y: 18), end: CGPoint(x: 48, y: 52)),
      bounds: CGRect(x: 12, y: 18, width: 36, height: 34),
      properties: AnnotationProperties()
    )
    state.annotations = [rectangle, line]

    state.replaceSourceImagePreservingAnnotations(
      NSImage(size: CGSize(width: 320, height: 220)),
      annotationOffset: CGPoint(x: 14, y: -6)
    )

    XCTAssertEqual(state.sourceImage?.size.width ?? 0, 320, accuracy: 0.0001)
    XCTAssertEqual(state.sourceImage?.size.height ?? 0, 220, accuracy: 0.0001)

    let shiftedRectangle = try XCTUnwrap(state.annotations.first(where: { $0.id == rectangle.id }))
    XCTAssertEqual(shiftedRectangle.bounds, rectangle.bounds.offsetBy(dx: 14, dy: -6))

    let shiftedLine = try XCTUnwrap(state.annotations.first(where: { $0.id == line.id }))
    guard case .line(let start, let end) = shiftedLine.type else {
      return XCTFail("Expected shifted line annotation")
    }
    XCTAssertEqual(start, CGPoint(x: 26, y: 12))
    XCTAssertEqual(end, CGPoint(x: 62, y: 46))
    XCTAssertEqual(shiftedLine.bounds, line.bounds.offsetBy(dx: 14, dy: -6))
  }

  @MainActor
  func testAnnotateState_updateTextKeepsWidthAndTopLeftAnchor() throws {
    let state = makeAnnotateState()
    state.sourceImage = NSImage(size: CGSize(width: 300, height: 200))
    let originalBounds = CGRect(x: 20, y: 140, width: 80, height: 28)
    let annotation = AnnotationItem(
      type: .text(""),
      bounds: originalBounds,
      properties: AnnotationProperties(fontSize: 18)
    )
    state.annotations = [annotation]

    state.updateAnnotationText(
      id: annotation.id,
      text: "A much longer textbox value"
    )

    let resized = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(resized.bounds.minX, originalBounds.minX, accuracy: 0.0001)
    XCTAssertEqual(resized.bounds.maxY, originalBounds.maxY, accuracy: 0.0001)
    XCTAssertEqual(resized.bounds.width, originalBounds.width, accuracy: 0.0001)
    XCTAssertGreaterThan(resized.bounds.height, originalBounds.height)
  }

  @MainActor
  func testAnnotateState_updateTextExpandsTooShortInitialHeight() throws {
    let state = makeAnnotateState()
    state.sourceImage = NSImage(size: CGSize(width: 300, height: 200))
    let originalBounds = CGRect(x: 20, y: 160, width: 200, height: 8)
    let annotation = AnnotationItem(
      type: .text(""),
      bounds: originalBounds,
      properties: AnnotationProperties(fontSize: 18)
    )
    state.annotations = [annotation]

    state.updateAnnotationText(id: annotation.id, text: "asdasdsad")

    let resized = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(resized.bounds.minX, originalBounds.minX, accuracy: 0.0001)
    XCTAssertEqual(resized.bounds.maxY, originalBounds.maxY, accuracy: 0.0001)
    XCTAssertGreaterThan(resized.bounds.height, originalBounds.height)
    XCTAssertGreaterThanOrEqual(
      resized.bounds.height,
      AnnotateTextLayout.minimumHeight(for: AnnotateTextLayout.font(size: 18))
    )
  }

  @MainActor
  func testAnnotateState_updateTextWrapsAtActiveCanvasRightEdge() throws {
    let state = makeAnnotateState()
    state.sourceImage = NSImage(size: CGSize(width: 120, height: 120))
    let originalBounds = CGRect(x: 80, y: 80, width: 30, height: 28)
    let annotation = AnnotationItem(
      type: .text(""),
      bounds: originalBounds,
      properties: AnnotationProperties(fontSize: 18)
    )
    state.annotations = [annotation]

    state.updateAnnotationText(
      id: annotation.id,
      text: "asdasdasdaasdasdasdaasdasdasdaasdasdasda"
    )

    let resized = try XCTUnwrap(state.annotations.first)
    XCTAssertLessThanOrEqual(resized.bounds.maxX, state.activeAnnotationBounds.maxX + 0.0001)
    XCTAssertEqual(resized.bounds.minX, originalBounds.minX, accuracy: 0.0001)
    XCTAssertEqual(resized.bounds.maxY, originalBounds.maxY, accuracy: 0.0001)
    XCTAssertGreaterThan(resized.bounds.height, originalBounds.height)
  }

  func testAnnotateTextLayout_textEditorInsetScalesWithCanvasZoom() {
    let halfScaleInset = AnnotateTextLayout.textEditorInset(scale: 0.5)
    XCTAssertEqual(halfScaleInset.width, AnnotateTextLayout.horizontalPadding * 0.5, accuracy: 0.0001)
    XCTAssertEqual(halfScaleInset.height, AnnotateTextLayout.verticalPadding * 0.5, accuracy: 0.0001)

    let doubleScaleInset = AnnotateTextLayout.textEditorInset(scale: 2)
    XCTAssertEqual(doubleScaleInset.width, AnnotateTextLayout.horizontalPadding * 2, accuracy: 0.0001)
    XCTAssertEqual(doubleScaleInset.height, AnnotateTextLayout.verticalPadding * 2, accuracy: 0.0001)
  }

  func testAnnotationFactory_createsCounterCenteredAtStart() {
    let annotation = AnnotationFactory.createAnnotation(
      tool: .counter,
      from: CGPoint(x: 50, y: 60),
      to: CGPoint(x: 50, y: 60),
      path: [],
      context: makeContext(counterValue: 5)
    )

    guard case .counter(5) = annotation?.type else {
      return XCTFail("Expected counter value 5, got \(String(describing: annotation?.type))")
    }
    XCTAssertEqual(annotation?.bounds, CGRect(x: 38, y: 48, width: 24, height: 24))
  }

  func testAnnotationFactory_rejectsNonDrawingToolsAndSinglePointPaths() {
    let context = makeContext()
    let start = CGPoint(x: 10, y: 20)

    XCTAssertNil(AnnotationFactory.createAnnotation(tool: .selection, from: start, to: start, path: [], context: context))
    XCTAssertNil(AnnotationFactory.createAnnotation(tool: .crop, from: start, to: start, path: [], context: context))
    XCTAssertNil(AnnotationFactory.createAnnotation(tool: .text, from: start, to: start, path: [], context: context))
    XCTAssertNil(AnnotationFactory.createAnnotation(tool: .mockup, from: start, to: start, path: [], context: context))
    XCTAssertNil(AnnotationFactory.createAnnotation(tool: .pencil, from: start, to: start, path: [start], context: context))
    XCTAssertNil(AnnotationFactory.createAnnotation(tool: .highlighter, from: start, to: start, path: [start], context: context))
  }

  func testAnnotationToolCreationPolicy_requiresDragExceptClickPlacementTools() {
    for tool in [AnnotationToolType.rectangle, .filledRectangle, .oval, .arrow, .line, .blur, .watermark] {
      XCTAssertTrue(tool.requiresDragToCreateAnnotation, "\(tool) should not create a new item from an empty click.")
    }

    for tool in [AnnotationToolType.selection, .crop, .text, .highlighter, .counter, .pencil, .mockup] {
      XCTAssertFalse(tool.requiresDragToCreateAnnotation, "\(tool) keeps its existing non-drag behavior.")
    }
  }

  @MainActor
  func testCanvasFirstMouseHandlingIsOptIn() {
    let state = makeAnnotateState()
    let editorCanvas = DrawingCanvasNSView(state: state)
    let inlineCanvas = DrawingCanvasNSView(state: state, acceptsFirstMouse: true)

    XCTAssertFalse(editorCanvas.acceptsFirstMouse(for: nil))
    XCTAssertTrue(inlineCanvas.acceptsFirstMouse(for: nil))
  }

  @MainActor
  func testCanvasBlankClickWithActiveShapeToolDeselectsItemButKeepsTool() {
    let state = makeAnnotateState()
    let annotation = AnnotationItem(
      type: .rectangle,
      bounds: CGRect(x: 10, y: 10, width: 40, height: 40),
      properties: AnnotationProperties()
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    state.selectedTool = .rectangle

    let canvas = DrawingCanvasNSView(state: state)
    canvas.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
    canvas.displayScale = 1
    canvas.canvasBounds = CGRect(x: 0, y: 0, width: 400, height: 300)

    let clickPoint = CGPoint(x: 220, y: 180)
    let mouseDown = makeMouseEvent(type: .leftMouseDown, location: clickPoint)
    let mouseUp = makeMouseEvent(type: .leftMouseUp, location: clickPoint)

    canvas.mouseDown(with: mouseDown)
    canvas.mouseUp(with: mouseUp)

    XCTAssertNil(state.selectedAnnotationId)
    XCTAssertFalse(state.hasSelectedAnnotations)
    XCTAssertEqual(state.selectedTool, .rectangle)
    XCTAssertEqual(state.annotations.count, 1)
  }

  func testAnnotationFactory_normalizesNearlyHorizontalHighlighterStroke() throws {
    let path = [
      CGPoint(x: 10, y: 100),
      CGPoint(x: 30, y: 102),
      CGPoint(x: 60, y: 98),
      CGPoint(x: 90, y: 101),
    ]

    let annotation = try XCTUnwrap(AnnotationFactory.createAnnotation(
      tool: .highlighter,
      from: path[0],
      to: path.last!,
      path: path,
      context: makeContext()
    ))

    guard case .highlight(let points) = annotation.type else {
      return XCTFail("Expected highlighter annotation, got \(annotation.type)")
    }
    XCTAssertEqual(points.count, 2)
    XCTAssertEqual(points[0].x, 10, accuracy: 0.0001)
    XCTAssertEqual(points[1].x, 90, accuracy: 0.0001)
    XCTAssertEqual(points[0].y, 100.5, accuracy: 0.0001)
    XCTAssertEqual(points[1].y, 100.5, accuracy: 0.0001)
    XCTAssertEqual(annotation.bounds, CGRect(x: 10, y: 100, width: 80, height: 1))
  }

  func testAnnotationFactory_smallWatermarkDragUsesCanvasSizedDefaultBounds() throws {
    let annotation = try XCTUnwrap(AnnotationFactory.createAnnotation(
      tool: .watermark,
      from: CGPoint(x: 500, y: 250),
      to: CGPoint(x: 504, y: 254),
      path: [],
      context: makeContext(watermarkText: "   ", bounds: CGRect(x: 0, y: 0, width: 1000, height: 500))
    ))

    guard case .watermark(let text) = annotation.type else {
      return XCTFail("Expected watermark annotation, got \(annotation.type)")
    }
    XCTAssertEqual(text, "Snapzy")
    XCTAssertEqual(annotation.bounds, CGRect(x: 290, y: 205, width: 420, height: 90))
  }

  func testAnnotationFactory_usesArrowStyleAndBoundsFromGeometry() throws {
    let annotation = try XCTUnwrap(AnnotationFactory.createAnnotation(
      tool: .arrow,
      from: CGPoint(x: 10, y: 20),
      to: CGPoint(x: 90, y: 80),
      path: [],
      context: makeContext(arrowStyle: .curvedRight)
    ))

    guard case .arrow(let geometry) = annotation.type else {
      return XCTFail("Expected arrow annotation, got \(annotation.type)")
    }
    XCTAssertEqual(geometry.style, .curvedRight)
    XCTAssertEqual(annotation.bounds, geometry.bounds())
    XCTAssertGreaterThan(annotation.bounds.width, 0)
    XCTAssertGreaterThan(annotation.bounds.height, 0)
  }

  func testAnnotationFactory_usesArrowBendDirectionFromContext() throws {
    let annotation = try XCTUnwrap(AnnotationFactory.createAnnotation(
      tool: .arrow,
      from: CGPoint(x: 10, y: 20),
      to: CGPoint(x: 90, y: 80),
      path: [],
      context: makeContext(arrowStyle: .curvedLeft, arrowBendDirection: .alternate)
    ))

    guard case .arrow(let geometry) = annotation.type else {
      return XCTFail("Expected arrow annotation, got \(annotation.type)")
    }
    XCTAssertEqual(geometry.style, .curvedRight) // alternating curvedLeft style flips it to curvedRight
    XCTAssertEqual(geometry.bendDirection, .alternate)
  }

  @MainActor
  func testAnnotateStateArrowBendDirectionUpdatesNextCreatedArrow() throws {
    let state = makeAnnotateState()
    state.arrowStyle = .curvedLeft
    state.setActiveArrowBendDirection(.alternate)

    let annotation = try XCTUnwrap(AnnotationFactory.createAnnotation(
      tool: .arrow,
      from: CGPoint(x: 10, y: 20),
      to: CGPoint(x: 90, y: 80),
      path: [],
      state: state
    ))

    guard case .arrow(let geometry) = annotation.type else {
      return XCTFail("Expected arrow annotation, got \(annotation.type)")
    }
    XCTAssertEqual(geometry.bendDirection, .alternate)
  }

  @MainActor
  func testAnnotateStateArrowBendDirectionUpdatesSelectedArrow() throws {
    let state = makeAnnotateState()
    let geometry = ArrowGeometry(
      start: CGPoint(x: 10, y: 20),
      end: CGPoint(x: 90, y: 80),
      style: .curvedLeft
    )
    let annotation = AnnotationItem(
      type: .arrow(geometry),
      bounds: geometry.bounds(),
      properties: AnnotationProperties()
    )
    state.annotations.append(annotation)
    state.selectedAnnotationId = annotation.id

    state.setActiveArrowBendDirection(.alternate)

    let updated = try XCTUnwrap(state.annotations.first)
    guard case .arrow(let updatedGeometry) = updated.type else {
      return XCTFail("Expected arrow annotation, got \(updated.type)")
    }
    XCTAssertEqual(updatedGeometry.bendDirection, .alternate)
    XCTAssertEqual(updated.bounds, updatedGeometry.bounds())
  }

  @MainActor
  func testAnnotateStateArrowBendDirectionRecordsUndoAndDirtyState() throws {
    let state = makeAnnotateState()
    let geometry = ArrowGeometry(
      start: CGPoint(x: 10, y: 20),
      end: CGPoint(x: 90, y: 80),
      style: .curvedLeft
    )
    let annotation = AnnotationItem(
      type: .arrow(geometry),
      bounds: geometry.bounds(),
      properties: AnnotationProperties()
    )
    state.annotations.append(annotation)
    state.selectedAnnotationId = annotation.id

    state.hasUnsavedChanges = false
    state.setActiveArrowBendDirection(.alternate)

    XCTAssertTrue(state.hasUnsavedChanges)
    XCTAssertTrue(state.canUndo)

    state.undo()

    let restored = try XCTUnwrap(state.annotations.first)
    guard case .arrow(let restoredGeometry) = restored.type else {
      return XCTFail("Expected arrow annotation, got \(restored.type)")
    }
    XCTAssertEqual(restoredGeometry.bendDirection, .primary)
    XCTAssertTrue(state.canRedo)
  }

  func testAnnotationProperties_clampControlValueAndDerivedSizes() {
    XCTAssertEqual(AnnotationProperties.clampedControlValue(-10), 1)
    XCTAssertEqual(AnnotationProperties.clampedControlValue(30), 20)
    XCTAssertEqual(AnnotationProperties.counterDiameter(for: 3), 24)
    XCTAssertEqual(AnnotationProperties.pixelatedBlurSize(for: 2), 10)
    XCTAssertEqual(AnnotationProperties.gaussianBlurRadius(for: 2), 16)
  }

  func testAnnotateExporterGenerateCopyURL_incrementsExistingCopies() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_AnnotateCopyURL_\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let original = directory.appendingPathComponent("capture.png")
    try Data("original".utf8).write(to: original)
    try Data("copy".utf8).write(to: directory.appendingPathComponent("capture_copy.png"))

    let copyURL = AnnotateExporter.generateCopyURL(from: original)

    XCTAssertEqual(copyURL.lastPathComponent, "capture_copy2.png")
  }

  @MainActor
  func testAnnotateExporter_renderFinalImagePreservesRetinaPixelDetail() throws {
    let state = makeAnnotateState()
    let sourceImage = try makeRetinaPixelPatternImage(pixelWidth: 96, pixelHeight: 48, scale: 2)
    state.loadImage(sourceImage)

    let renderedImage = try XCTUnwrap(AnnotateExporter.renderFinalImage(state: state))
    let sourceCGImage = try XCTUnwrap(sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let renderedCGImage = try XCTUnwrap(AnnotateExporter.bestCGImage(from: renderedImage))

    XCTAssertEqual(renderedImage.size.width, sourceImage.size.width, accuracy: 0.0001)
    XCTAssertEqual(renderedImage.size.height, sourceImage.size.height, accuracy: 0.0001)
    XCTAssertEqual(renderedCGImage.width, sourceCGImage.width)
    XCTAssertEqual(renderedCGImage.height, sourceCGImage.height)
    guard renderedCGImage.width == sourceCGImage.width, renderedCGImage.height == sourceCGImage.height else {
      return
    }

    let sourceBytes = try rgbaBytes(from: sourceCGImage)
    let renderedBytes = try rgbaBytes(from: renderedCGImage)
    XCTAssertEqual(renderedBytes.count, sourceBytes.count)
    guard renderedBytes.count == sourceBytes.count else { return }
    var mismatchedPixels = 0
    for index in stride(from: 0, to: sourceBytes.count, by: 4) {
      let pixelMatches = (0..<4).allSatisfy { channel in
        abs(Int(sourceBytes[index + channel]) - Int(renderedBytes[index + channel])) <= 2
      }
      if !pixelMatches {
        mismatchedPixels += 1
      }
    }
    XCTAssertEqual(mismatchedPixels, 0)

    var softenedStripePixels = 0
    let centerY = renderedCGImage.height / 2
    for x in 0..<renderedCGImage.width {
      let red = renderedBytes[rgbaIndex(x: x, y: centerY, width: renderedCGImage.width)]
      if red > 2 && red < 253 {
        softenedStripePixels += 1
      }
    }
    XCTAssertEqual(softenedStripePixels, 0)
  }

  @MainActor
  func testAnnotateExporter_renderFinalImageCropsRetinaSourceInImageCoordinates() throws {
    let scale: CGFloat = 2
    let state = makeAnnotateState()
    let sourceImage = try makeRetinaPixelPatternImage(pixelWidth: 96, pixelHeight: 48, scale: scale)
    let cropRect = CGRect(x: 4, y: 3, width: 20, height: 8)
    state.loadImage(sourceImage)
    state.cropRect = cropRect

    let renderedImage = try XCTUnwrap(AnnotateExporter.renderFinalImage(state: state))
    let sourceCGImage = try XCTUnwrap(sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let renderedCGImage = try XCTUnwrap(AnnotateExporter.bestCGImage(from: renderedImage))

    XCTAssertEqual(renderedCGImage.width, Int(cropRect.width * scale))
    XCTAssertEqual(renderedCGImage.height, Int(cropRect.height * scale))
    guard renderedCGImage.width == Int(cropRect.width * scale),
          renderedCGImage.height == Int(cropRect.height * scale) else {
      return
    }

    let sourceBytes = try rgbaBytes(from: sourceCGImage)
    let renderedBytes = try rgbaBytes(from: renderedCGImage)
    let sourceStartX = Int(cropRect.minX * scale)
    let sourceStartY = Int((sourceImage.size.height - cropRect.maxY) * scale)
    var mismatchedPixels = 0
    for y in 0..<renderedCGImage.height {
      for x in 0..<renderedCGImage.width {
        let sourceIndex = rgbaIndex(x: sourceStartX + x, y: sourceStartY + y, width: sourceCGImage.width)
        let renderedIndex = rgbaIndex(x: x, y: y, width: renderedCGImage.width)
        let pixelMatches = (0..<4).allSatisfy { channel in
          abs(Int(sourceBytes[sourceIndex + channel]) - Int(renderedBytes[renderedIndex + channel])) <= 2
        }
        if !pixelMatches {
          mismatchedPixels += 1
        }
      }
    }
    XCTAssertEqual(mismatchedPixels, 0)
  }

  func testAspectRatioOptionOriginalKeepsForegroundRatioWithMinimumPadding() {
    let foregroundSize = CGSize(width: 1000, height: 600)

    let canvasSize = AspectRatioOption.auto.canvasSize(
      for: foregroundSize,
      padding: 100,
      alignmentSpace: 0
    )

    XCTAssertEqual(canvasSize.height, 800, accuracy: 0.0001)
    XCTAssertEqual(canvasSize.width, 800 * (1000.0 / 600.0), accuracy: 0.0001)
    XCTAssertEqual(canvasSize.width / canvasSize.height, 1000.0 / 600.0, accuracy: 0.0001)
    XCTAssertGreaterThanOrEqual((canvasSize.width - foregroundSize.width) / 2, 100)
    XCTAssertGreaterThanOrEqual((canvasSize.height - foregroundSize.height) / 2, 100)
  }

  func testAspectRatioOptionFreeKeepsPaddingOnlyCanvasSize() {
    let canvasSize = AspectRatioOption.free.canvasSize(
      for: CGSize(width: 1000, height: 600),
      padding: 100,
      alignmentSpace: 0
    )

    XCTAssertEqual(canvasSize, CGSize(width: 1200, height: 800))
  }

  func testAspectRatioOptionVerticalOrientationInvertsFixedRatio() {
    let foregroundSize = CGSize(width: 1000, height: 600)

    let canvasSize = AspectRatioOption.ratio16x9.canvasSize(
      for: foregroundSize,
      padding: 100,
      alignmentSpace: 0,
      orientation: .vertical
    )

    XCTAssertEqual(canvasSize.width, 1200, accuracy: 0.0001)
    XCTAssertEqual(canvasSize.width / canvasSize.height, 9.0 / 16.0, accuracy: 0.0001)
    XCTAssertGreaterThanOrEqual((canvasSize.width - foregroundSize.width) / 2, 100)
    XCTAssertGreaterThanOrEqual((canvasSize.height - foregroundSize.height) / 2, 100)
  }

  @MainActor
  func testAnnotateExporter_renderFinalImageUsesSelectedBackgroundAspectRatio() throws {
    let state = makeAnnotateState()
    let sourceImage = try makeRetinaPixelPatternImage(pixelWidth: 1000, pixelHeight: 600, scale: 1)
    state.loadImage(sourceImage)
    state.backgroundStyle = .solidColor(.white)
    state.padding = 100
    state.aspectRatio = .ratio16x9

    let renderedImage = try XCTUnwrap(AnnotateExporter.renderFinalImage(state: state))

    XCTAssertEqual(renderedImage.size.width / renderedImage.size.height, 16.0 / 9.0, accuracy: 0.0001)
    XCTAssertGreaterThanOrEqual((renderedImage.size.width - sourceImage.size.width) / 2, 100)
    XCTAssertGreaterThanOrEqual((renderedImage.size.height - sourceImage.size.height) / 2, 100)
  }

  @MainActor
  func testAnnotateExporter_renderFinalImageUsesVerticalBackgroundAspectRatio() throws {
    let state = makeAnnotateState()
    let sourceImage = try makeRetinaPixelPatternImage(pixelWidth: 1000, pixelHeight: 600, scale: 1)
    state.loadImage(sourceImage)
    state.backgroundStyle = .solidColor(.white)
    state.padding = 100
    state.aspectRatio = .ratio16x9
    state.aspectRatioOrientation = .vertical

    let renderedImage = try XCTUnwrap(AnnotateExporter.renderFinalImage(state: state))

    XCTAssertEqual(renderedImage.size.width / renderedImage.size.height, 9.0 / 16.0, accuracy: 0.0001)
    XCTAssertGreaterThanOrEqual((renderedImage.size.width - sourceImage.size.width) / 2, 100)
    XCTAssertGreaterThanOrEqual((renderedImage.size.height - sourceImage.size.height) / 2, 100)
  }

  func testCodableBackgroundStyle_roundTripsSupportedStyles() throws {
    let wallpaperURL = URL(string: "file:///tmp/wallpaper.jpg")!
    let blurredURL = URL(string: "file:///tmp/blurred.jpg")!

    XCTAssertEqual(try XCTUnwrap(CodableBackgroundStyle(from: BackgroundStyle.none)).toBackgroundStyle(), .none)
    XCTAssertEqual(try XCTUnwrap(CodableBackgroundStyle(from: .gradient(.cyanBlue))).toBackgroundStyle(), .gradient(.cyanBlue))
    XCTAssertEqual(try XCTUnwrap(CodableBackgroundStyle(from: .wallpaper(wallpaperURL))).toBackgroundStyle(), .wallpaper(wallpaperURL))
    XCTAssertEqual(try XCTUnwrap(CodableBackgroundStyle(from: .blurred(blurredURL))).toBackgroundStyle(), .blurred(blurredURL))

    let solid = try XCTUnwrap(CodableBackgroundStyle(from: .solidColor(.red)))
    XCTAssertEqual(solid.kind, .solidColor)
    XCTAssertNotNil(solid.solidColorRGBA)
  }

  func testRGBAColorClampsComponents() {
    let color = RGBAColor(red: -1, green: 0.25, blue: 2, alpha: 1.5)

    XCTAssertEqual(color.red, 0)
    XCTAssertEqual(color.green, 0.25)
    XCTAssertEqual(color.blue, 1)
    XCTAssertEqual(color.alpha, 1)
  }

  func testAnnotateCanvasPresetPayloadApproximatelyEqualsHonorsTolerance() {
    let first = AnnotateCanvasPresetPayload(
      backgroundStyle: CodableBackgroundStyle(from: .gradient(.bluePurple))!,
      padding: 40,
      shadowIntensity: 0.3,
      cornerRadius: 12
    )
    let close = AnnotateCanvasPresetPayload(
      backgroundStyle: CodableBackgroundStyle(from: .gradient(.bluePurple))!,
      padding: 40.00005,
      shadowIntensity: 0.30005,
      cornerRadius: 12.00005
    )
    let different = AnnotateCanvasPresetPayload(
      backgroundStyle: CodableBackgroundStyle(from: .gradient(.orangeRed))!,
      padding: 40,
      shadowIntensity: 0.3,
      cornerRadius: 12
    )

    XCTAssertTrue(first.approximatelyEquals(close))
    XCTAssertFalse(first.approximatelyEquals(different))
  }

  func testAnnotateCanvasPresetPayloadDefaultsMissingAspectRatioToOriginal() throws {
    let data = Data("""
    {
      "backgroundStyle": {
        "kind": "gradient",
        "gradientPresetRawValue": "bluePurple"
      },
      "padding": 40,
      "shadowIntensity": 0.3,
      "cornerRadius": 12
    }
    """.utf8)

    let payload = try JSONDecoder().decode(AnnotateCanvasPresetPayload.self, from: data)

    XCTAssertEqual(payload.aspectRatio, .auto)
    XCTAssertEqual(payload.aspectRatioOrientation, .horizontal)
    XCTAssertFalse(payload.isBlurredBackgroundEnabled)
    XCTAssertEqual(payload.blurredBackgroundEffect, .soft)
  }

  func testAnnotateCanvasPresetPayloadApproximatelyEqualsIncludesBlurredBackgroundEffect() {
    let wallpaperURL = URL(fileURLWithPath: "/tmp/snapzy-wallpaper.png")
    let soft = AnnotateCanvasPresetPayload(
      backgroundStyle: CodableBackgroundStyle(from: .wallpaper(wallpaperURL))!,
      isBlurredBackgroundEnabled: true,
      blurredBackgroundEffect: .soft,
      padding: 40,
      shadowIntensity: 0.3,
      cornerRadius: 12
    )
    let vivid = AnnotateCanvasPresetPayload(
      backgroundStyle: CodableBackgroundStyle(from: .wallpaper(wallpaperURL))!,
      isBlurredBackgroundEnabled: true,
      blurredBackgroundEffect: .vivid,
      padding: 40,
      shadowIntensity: 0.3,
      cornerRadius: 12
    )

    XCTAssertFalse(soft.approximatelyEquals(vivid))
  }

  func testAnnotateCanvasPresetPayloadApproximatelyEqualsIncludesBlurredBackgroundEnabled() {
    let wallpaperURL = URL(fileURLWithPath: "/tmp/snapzy-wallpaper.png")
    let disabled = AnnotateCanvasPresetPayload(
      backgroundStyle: CodableBackgroundStyle(from: .wallpaper(wallpaperURL))!,
      isBlurredBackgroundEnabled: false,
      blurredBackgroundEffect: .soft,
      padding: 40,
      shadowIntensity: 0.3,
      cornerRadius: 12
    )
    let enabled = AnnotateCanvasPresetPayload(
      backgroundStyle: CodableBackgroundStyle(from: .wallpaper(wallpaperURL))!,
      isBlurredBackgroundEnabled: true,
      blurredBackgroundEffect: .soft,
      padding: 40,
      shadowIntensity: 0.3,
      cornerRadius: 12
    )

    XCTAssertFalse(disabled.approximatelyEquals(enabled))
  }

  func testAnnotateCanvasPresetPayloadApproximatelyEqualsIgnoresBlurredEffectForNonBlurredBackgrounds() {
    let soft = AnnotateCanvasPresetPayload(
      backgroundStyle: CodableBackgroundStyle(from: .gradient(.bluePurple))!,
      isBlurredBackgroundEnabled: false,
      blurredBackgroundEffect: .soft,
      padding: 40,
      shadowIntensity: 0.3,
      cornerRadius: 12
    )
    let vivid = AnnotateCanvasPresetPayload(
      backgroundStyle: CodableBackgroundStyle(from: .gradient(.bluePurple))!,
      isBlurredBackgroundEnabled: false,
      blurredBackgroundEffect: .vivid,
      padding: 40,
      shadowIntensity: 0.3,
      cornerRadius: 12
    )

    XCTAssertTrue(soft.approximatelyEquals(vivid))
  }

  func testAnnotateCanvasPresetPayloadApproximatelyEqualsIncludesAspectRatio() {
    let originalRatio = AnnotateCanvasPresetPayload(
      backgroundStyle: CodableBackgroundStyle(from: .gradient(.bluePurple))!,
      padding: 40,
      shadowIntensity: 0.3,
      cornerRadius: 12,
      aspectRatio: .auto
    )
    let fixedRatio = AnnotateCanvasPresetPayload(
      backgroundStyle: CodableBackgroundStyle(from: .gradient(.bluePurple))!,
      padding: 40,
      shadowIntensity: 0.3,
      cornerRadius: 12,
      aspectRatio: .ratio16x9
    )

    XCTAssertFalse(originalRatio.approximatelyEquals(fixedRatio))
  }

  func testAnnotateCanvasPresetPayloadApproximatelyEqualsIncludesAspectRatioOrientation() {
    let horizontalRatio = AnnotateCanvasPresetPayload(
      backgroundStyle: CodableBackgroundStyle(from: .gradient(.bluePurple))!,
      padding: 40,
      shadowIntensity: 0.3,
      cornerRadius: 12,
      aspectRatio: .ratio16x9,
      aspectRatioOrientation: .horizontal
    )
    let verticalRatio = AnnotateCanvasPresetPayload(
      backgroundStyle: CodableBackgroundStyle(from: .gradient(.bluePurple))!,
      padding: 40,
      shadowIntensity: 0.3,
      cornerRadius: 12,
      aspectRatio: .ratio16x9,
      aspectRatioOrientation: .vertical
    )

    XCTAssertFalse(horizontalRatio.approximatelyEquals(verticalRatio))
  }

  @MainActor
  func testAnnotateCanvasPresetStoreClearsInvalidDefaultPreset() {
    let (store, defaults) = makeCanvasPresetStore()
    let preset = AnnotateCanvasPreset(
      name: "Share",
      payload: AnnotateCanvasPresetPayload(
        backgroundStyle: CodableBackgroundStyle(from: .gradient(.bluePurple))!,
        padding: 40,
        shadowIntensity: 0.3,
        cornerRadius: 12
      )
    )

    store.savePresets([preset])
    store.saveDefaultPresetId(preset.id)
    XCTAssertEqual(store.loadDefaultPresetId(validating: [preset]), preset.id)

    store.savePresets([])

    XCTAssertNil(store.loadDefaultPresetId(validating: []))
    XCTAssertNil(defaults.string(forKey: PreferencesKeys.annotateDefaultCanvasPresetId))
  }

  @MainActor
  func testAnnotateCanvasPresetStoreClearsMalformedDefaultPresetId() {
    let (store, defaults) = makeCanvasPresetStore()
    defaults.set("not-a-uuid", forKey: PreferencesKeys.annotateDefaultCanvasPresetId)

    XCTAssertNil(store.loadDefaultPresetId(validating: []))
    XCTAssertNil(defaults.string(forKey: PreferencesKeys.annotateDefaultCanvasPresetId))
  }

  @MainActor
  func testAnnotateStateAppliesDefaultCanvasPresetToNewImageWithoutDirtyFlag() {
    let (store, _) = makeCanvasPresetStore()
    let preset = AnnotateCanvasPreset(
      name: "Default Share",
      payload: AnnotateCanvasPresetPayload(
        backgroundStyle: CodableBackgroundStyle(from: .gradient(.orangeRed))!,
        padding: 48,
        shadowIntensity: 0.35,
        cornerRadius: 16
      )
    )
    store.savePresets([preset])
    store.saveDefaultPresetId(preset.id)

    let state = AnnotateState(
      image: NSImage(size: NSSize(width: 20, height: 20)),
      url: URL(fileURLWithPath: "/tmp/snapzy-default-preset.png"),
      canvasPresetStore: store
    )
    Self.retainedAnnotateStates.append(state)

    XCTAssertEqual(state.defaultCanvasPresetId, preset.id)
    XCTAssertEqual(state.selectedCanvasPresetId, preset.id)
    XCTAssertEqual(state.backgroundStyle, .gradient(.orangeRed))
    XCTAssertEqual(state.padding, 48)
    XCTAssertEqual(state.shadowIntensity, 0.35)
    XCTAssertEqual(state.cornerRadius, 16)
    XCTAssertFalse(state.hasUnsavedChanges)
    XCTAssertTrue(state.isDefaultCanvasPresetAutoApplied)
    XCTAssertTrue(state.requiresRenderedOutputForSharing)

    state.applyCanvasPreset(preset)

    XCTAssertFalse(state.hasUnsavedChanges)
    XCTAssertTrue(state.isDefaultCanvasPresetAutoApplied)
    XCTAssertTrue(state.requiresRenderedOutputForSharing)
  }

  @MainActor
  func testAnnotateStateCanOptOutOfDefaultCanvasPresetApplication() {
    let (store, _) = makeCanvasPresetStore()
    let preset = AnnotateCanvasPreset(
      name: "Default Share",
      payload: AnnotateCanvasPresetPayload(
        backgroundStyle: CodableBackgroundStyle(from: .gradient(.orangeRed))!,
        padding: 48,
        shadowIntensity: 0.35,
        cornerRadius: 16
      )
    )
    store.savePresets([preset])
    store.saveDefaultPresetId(preset.id)

    let state = AnnotateState(
      image: NSImage(size: NSSize(width: 20, height: 20)),
      url: URL(fileURLWithPath: "/tmp/snapzy-default-preset.png"),
      canvasPresetStore: store,
      appliesDefaultCanvasPresetOnNewImages: false
    )
    Self.retainedAnnotateStates.append(state)

    XCTAssertEqual(state.defaultCanvasPresetId, preset.id)
    XCTAssertNil(state.selectedCanvasPresetId)
    XCTAssertEqual(state.backgroundStyle, .none)
    XCTAssertFalse(state.isDefaultCanvasPresetAutoApplied)
    XCTAssertFalse(state.requiresRenderedOutputForSharing)
  }

  func testCropAspectRatioNumericValues() {
    XCTAssertEqual(CropAspectRatio.free.ratio, 0)
    XCTAssertEqual(CropAspectRatio.square.ratio, 1)
    XCTAssertEqual(CropAspectRatio.ratio4x3.ratio, 4.0 / 3.0, accuracy: 0.0001)
    XCTAssertEqual(CropAspectRatio.ratio16x9.ratio, 16.0 / 9.0, accuracy: 0.0001)
    XCTAssertEqual(CropAspectRatio.ratio21x9.ratio, 21.0 / 9.0, accuracy: 0.0001)
  }

  func testAnnotationToolTypeDefaultShortcutsAreUniqueAndQuickPropertiesAreScoped() {
    let shortcuts = AnnotationToolType.allCases.map(\.defaultShortcut)
    XCTAssertEqual(Set(shortcuts).count, shortcuts.count)

    XCTAssertFalse(AnnotationToolType.selection.supportsQuickPropertiesBar)
    XCTAssertFalse(AnnotationToolType.crop.supportsQuickPropertiesBar)
    XCTAssertFalse(AnnotationToolType.mockup.supportsQuickPropertiesBar)
    XCTAssertTrue(AnnotationToolType.rectangle.supportsQuickPropertiesBar)
    XCTAssertTrue(AnnotationToolType.watermark.supportsQuickPropertiesBar)
    XCTAssertTrue(AnnotationToolType.filledRectangle.supportsQuickStrokeColor)
    XCTAssertFalse(AnnotationToolType.filledRectangle.supportsQuickFillColor)
    XCTAssertFalse(AnnotationToolType.rectangle.supportsQuickFillColor)
    XCTAssertTrue(AnnotationToolType.rectangle.supportsQuickCornerRadius)
    XCTAssertFalse(AnnotationToolType.oval.supportsQuickCornerRadius)
  }

  @MainActor
  func testFilledRectangleQuickColorUpdatesStrokeAndFill() throws {
    let state = makeAnnotateState()
    let annotation = AnnotationItem(
      type: .filledRectangle,
      bounds: CGRect(x: 0, y: 0, width: 80, height: 40),
      properties: AnnotationProperties(strokeColor: .red, fillColor: .green)
    )
    state.annotations = [annotation]
    state.setSelectedAnnotationIds([annotation.id])

    XCTAssertFalse(state.quickPropertiesSupportsFill)

    state.quickStrokeColorBinding.wrappedValue = .blue

    let updated = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(updated.properties.strokeColor, .blue)
    XCTAssertEqual(updated.properties.fillColor, .blue)
  }

  @MainActor
  func testFilledRectangleDefaultColorAppliesToStrokeAndFill() {
    let state = makeAnnotateState()
    state.activateTool(.filledRectangle)

    XCTAssertFalse(state.quickPropertiesSupportsFill)

    state.quickStrokeColorBinding.wrappedValue = .purple

    let properties = state.annotationCreationProperties(for: .filledRectangle)
    XCTAssertEqual(properties.strokeColor, .purple)
    XCTAssertEqual(properties.fillColor, .purple)
  }

  @MainActor
  func testPrimaryAnnotationColorAppliesAcrossToolDefaults() {
    let state = makeAnnotateState()
    state.activateTool(.rectangle)

    state.quickStrokeColorBinding.wrappedValue = .blue

    assertColorsMatch(state.annotationCreationProperties(for: .rectangle).strokeColor, .blue)
    assertColorsMatch(state.annotationCreationProperties(for: .arrow).strokeColor, .blue)
    assertColorsMatch(state.annotationCreationProperties(for: .text).strokeColor, .blue)
    assertColorsMatch(state.annotationCreationProperties(for: .filledRectangle).strokeColor, .blue)
    assertColorsMatch(state.annotationCreationProperties(for: .filledRectangle).fillColor, .blue)

    state.activateTool(.arrow)
    assertColorsMatch(state.quickStrokeColorBinding.wrappedValue, .blue)
  }

  @MainActor
  func testPrimaryAnnotationColorPersistsAcrossAnnotateStateInstances() {
    let defaults = UserDefaultsFactory.make()
    let firstState = makeAnnotateState(defaults: defaults)
    firstState.activateTool(.arrow)

    firstState.quickStrokeColorBinding.wrappedValue = .purple

    let reloadedState = makeAnnotateState(defaults: defaults)
    reloadedState.activateTool(.rectangle)

    assertColorsMatch(reloadedState.quickStrokeColorBinding.wrappedValue, .purple)
    assertColorsMatch(reloadedState.annotationCreationProperties(for: .filledRectangle).strokeColor, .purple)
    assertColorsMatch(reloadedState.annotationCreationProperties(for: .filledRectangle).fillColor, .purple)
  }

  @MainActor
  func testSelectedItemPrimaryColorAlsoUpdatesFutureToolDefaults() throws {
    let state = makeAnnotateState()
    let annotation = AnnotationItem(
      type: .rectangle,
      bounds: CGRect(x: 0, y: 0, width: 80, height: 40),
      properties: AnnotationProperties(strokeColor: .red, fillColor: .clear)
    )
    state.annotations = [annotation]
    state.setSelectedAnnotationIds([annotation.id])

    state.quickStrokeColorBinding.wrappedValue = .green

    let updated = try XCTUnwrap(state.annotations.first)
    assertColorsMatch(updated.properties.strokeColor, .green)
    assertColorsMatch(state.annotationCreationProperties(for: .line).strokeColor, .green)
    assertColorsMatch(state.annotationCreationProperties(for: .filledRectangle).fillColor, .green)
  }

  @MainActor
  func testStrokeWidthDefaultAppliesAcrossStrokeWidthTools() {
    let state = makeAnnotateState(defaults: UserDefaultsFactory.make())
    state.activateTool(.rectangle)

    state.quickStrokeWidthBinding.wrappedValue = 9

    XCTAssertEqual(state.annotationCreationProperties(for: .rectangle).strokeWidth, 9)
    XCTAssertEqual(state.annotationCreationProperties(for: .filledRectangle).strokeWidth, 9)
    XCTAssertEqual(state.annotationCreationProperties(for: .arrow).strokeWidth, 9)
    XCTAssertEqual(state.annotationCreationProperties(for: .blur).strokeWidth, 9)
    XCTAssertEqual(state.annotationCreationProperties(for: .pencil).strokeWidth, 9)

    state.activateTool(.arrow)
    XCTAssertEqual(state.quickStrokeWidthBinding.wrappedValue, 9)
  }

  @MainActor
  func testCornerRadiusDefaultAppliesAcrossRectangleTools() {
    let state = makeAnnotateState(defaults: UserDefaultsFactory.make())
    state.activateTool(.rectangle)

    state.quickCornerRadiusBinding.wrappedValue = 12

    XCTAssertEqual(state.annotationCreationProperties(for: .rectangle).cornerRadius, 12)
    XCTAssertEqual(state.annotationCreationProperties(for: .filledRectangle).cornerRadius, 12)

    state.activateTool(.filledRectangle)
    XCTAssertEqual(state.quickCornerRadiusBinding.wrappedValue, 12)
  }

  @MainActor
  func testFontSizeDefaultAppliesAcrossTextAndWatermarkTools() {
    let state = makeAnnotateState(defaults: UserDefaultsFactory.make())
    state.activateTool(.text)

    state.quickTextFontSizeBinding.wrappedValue = 30

    XCTAssertEqual(state.annotationCreationProperties(for: .text).fontSize, 30)
    XCTAssertEqual(state.annotationCreationProperties(for: .watermark).fontSize, 30)

    state.activateTool(.watermark)
    XCTAssertEqual(state.quickTextFontSizeBinding.wrappedValue, 30)
  }

  @MainActor
  func testSelectedItemNumericControlsDoNotUpdateFutureToolDefaults() throws {
    let state = makeAnnotateState(defaults: UserDefaultsFactory.make())
    let annotation = AnnotationItem(
      type: .rectangle,
      bounds: CGRect(x: 0, y: 0, width: 80, height: 40),
      properties: AnnotationProperties(strokeWidth: 3)
    )
    state.annotations = [annotation]
    state.setSelectedAnnotationIds([annotation.id])

    state.quickStrokeWidthBinding.wrappedValue = 12

    let updated = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(updated.properties.strokeWidth, 12)
    XCTAssertEqual(state.annotationCreationProperties(for: .arrow).strokeWidth, 3)
    XCTAssertEqual(state.annotationCreationProperties(for: .rectangle).strokeWidth, 3)
  }

  @MainActor
  func testQuickPropertiesSliderGestureRecordsSingleUndoCheckpoint() throws {
    let state = makeAnnotateState(defaults: UserDefaultsFactory.make())
    let annotation = AnnotationItem(
      type: .blur(.pixelated),
      bounds: CGRect(x: 0, y: 0, width: 120, height: 80),
      properties: AnnotationProperties(strokeWidth: 3)
    )
    state.annotations = [annotation]
    state.setSelectedAnnotationIds([annotation.id])

    state.setQuickPropertiesControlEditing(true)
    state.quickStrokeWidthBinding.wrappedValue = 8
    state.quickStrokeWidthBinding.wrappedValue = 12
    state.setQuickPropertiesControlEditing(false)

    XCTAssertEqual(try XCTUnwrap(state.annotations.first).properties.strokeWidth, 12)

    state.undo()

    XCTAssertEqual(try XCTUnwrap(state.annotations.first).properties.strokeWidth, 3)
    XCTAssertFalse(state.canUndo)
  }

  @MainActor
  func testPropertySliderGestureRecordsSingleUndoCheckpoint() throws {
    let state = makeAnnotateState()
    let annotation = AnnotationItem(
      type: .text("Sized text"),
      bounds: CGRect(x: 20, y: 20, width: 180, height: 32),
      properties: AnnotationProperties(fontSize: 18)
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id

    state.setPropertySliderGestureEditing(true)
    state.updateAnnotationProperties(id: annotation.id, fontSize: 24, recordsUndo: true)
    state.updateAnnotationProperties(id: annotation.id, fontSize: 36, recordsUndo: true)
    state.updateAnnotationProperties(id: annotation.id, fontSize: 48, recordsUndo: true)
    state.setPropertySliderGestureEditing(false)

    XCTAssertEqual(try XCTUnwrap(state.annotations.first).properties.fontSize, 48)

    state.undo()

    XCTAssertEqual(try XCTUnwrap(state.annotations.first).properties.fontSize, 18)
    XCTAssertFalse(state.canUndo)
  }

  @MainActor
  func testPropertySliderGestureWithoutChangeRecordsNoUndo() throws {
    let state = makeAnnotateState()
    let annotation = AnnotationItem(
      type: .text("Sized text"),
      bounds: CGRect(x: 20, y: 20, width: 180, height: 32),
      properties: AnnotationProperties(fontSize: 18)
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id

    state.setPropertySliderGestureEditing(true)
    state.setPropertySliderGestureEditing(false)

    XCTAssertFalse(state.canUndo)
  }

  @MainActor
  func testUndoStackIsCappedDuringRapidPropertyEdits() throws {
    let state = makeAnnotateState()
    let annotation = AnnotationItem(
      type: .text("Sized text"),
      bounds: CGRect(x: 20, y: 20, width: 180, height: 32),
      properties: AnnotationProperties(fontSize: 12)
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id

    // 60 individual (non-gesture) property edits push 60 undo checkpoints.
    for size in 13 ... 72 {
      state.updateAnnotationProperties(id: annotation.id, fontSize: CGFloat(size), recordsUndo: true)
    }

    var undoCount = 0
    while state.canUndo {
      state.undo()
      undoCount += 1
    }
    XCTAssertEqual(undoCount, 50)
    XCTAssertEqual(try XCTUnwrap(state.annotations.first).properties.fontSize, 22)
  }

  @MainActor
  func testSharedParameterDefaultsPersistAcrossAnnotateStateInstances() {
    let defaults = UserDefaultsFactory.make()
    let firstState = makeAnnotateState(defaults: defaults)

    firstState.activateTool(.rectangle)
    firstState.quickStrokeWidthBinding.wrappedValue = 11
    firstState.quickCornerRadiusBinding.wrappedValue = 7
    firstState.activateTool(.text)
    firstState.quickTextFontSizeBinding.wrappedValue = 32
    firstState.activateTool(.watermark)
    firstState.quickWatermarkOpacityBinding.wrappedValue = 0.4
    firstState.quickWatermarkRotationBinding.wrappedValue = -12

    let reloadedState = makeAnnotateState(defaults: defaults)

    XCTAssertEqual(reloadedState.annotationCreationProperties(for: .line).strokeWidth, 11)
    XCTAssertEqual(reloadedState.annotationCreationProperties(for: .blur).strokeWidth, 11)
    XCTAssertEqual(reloadedState.annotationCreationProperties(for: .filledRectangle).cornerRadius, 7)
    XCTAssertEqual(reloadedState.annotationCreationProperties(for: .text).fontSize, 32)
    XCTAssertEqual(reloadedState.annotationCreationProperties(for: .watermark).fontSize, 32)
    XCTAssertEqual(reloadedState.annotationCreationProperties(for: .watermark).opacity, 0.4)
    XCTAssertEqual(reloadedState.annotationCreationProperties(for: .watermark).rotationDegrees, -12)
  }

  @MainActor
  func testArrowPreferencesPersistAcrossAnnotateStateInstances() {
    let defaults = UserDefaultsFactory.make()
    let firstState = makeAnnotateState(defaults: defaults)

    firstState.activateTool(.arrow)
    firstState.quickArrowStyleBinding.wrappedValue = .curvedRight
    firstState.quickArrowTypeBinding.wrappedValue = .outlined
    firstState.quickArrowBendDirectionBinding.wrappedValue = .alternate

    let reloadedState = makeAnnotateState(defaults: defaults)

    XCTAssertEqual(reloadedState.arrowStyle, .curvedRight)
    XCTAssertEqual(reloadedState.arrowType, .outlined)
    XCTAssertEqual(reloadedState.arrowBendDirection, .alternate)
  }

  @MainActor
  func testQuickPropertiesSyncOffKeepsShapeDefaultsIndependent() {
    let defaults = UserDefaultsFactory.make()
    defaults.set(false, forKey: PreferencesKeys.annotateQuickPropertiesSyncEnabled)
    let state = makeAnnotateState(defaults: defaults)

    state.activateTool(.rectangle)
    state.quickStrokeColorBinding.wrappedValue = .blue
    state.quickStrokeWidthBinding.wrappedValue = 9
    state.quickCornerRadiusBinding.wrappedValue = 12

    state.activateTool(.arrow)
    state.quickStrokeColorBinding.wrappedValue = .green
    state.quickStrokeWidthBinding.wrappedValue = 5

    XCTAssertEqual(state.annotationCreationProperties(for: .rectangle).strokeWidth, 9)
    XCTAssertEqual(state.annotationCreationProperties(for: .rectangle).cornerRadius, 12)
    assertColorsMatch(state.annotationCreationProperties(for: .rectangle).strokeColor, .blue)

    XCTAssertEqual(state.annotationCreationProperties(for: .arrow).strokeWidth, 5)
    XCTAssertEqual(state.annotationCreationProperties(for: .arrow).cornerRadius, 0)
    assertColorsMatch(state.annotationCreationProperties(for: .arrow).strokeColor, .green)

    XCTAssertEqual(state.annotationCreationProperties(for: .filledRectangle).strokeWidth, 3)
    XCTAssertEqual(state.annotationCreationProperties(for: .filledRectangle).cornerRadius, 0)
    assertColorsMatch(state.annotationCreationProperties(for: .filledRectangle).strokeColor, .red)
  }

  @MainActor
  func testQuickPropertiesSyncOffKeepsTextAndWatermarkFontDefaultsIndependent() {
    let defaults = UserDefaultsFactory.make()
    defaults.set(false, forKey: PreferencesKeys.annotateQuickPropertiesSyncEnabled)
    let state = makeAnnotateState(defaults: defaults)

    state.activateTool(.text)
    state.quickTextFontSizeBinding.wrappedValue = 30

    XCTAssertEqual(state.annotationCreationProperties(for: .text).fontSize, 30)
    XCTAssertEqual(state.annotationCreationProperties(for: .watermark).fontSize, 36)

    state.activateTool(.watermark)
    state.quickTextFontSizeBinding.wrappedValue = 42

    XCTAssertEqual(state.annotationCreationProperties(for: .text).fontSize, 30)
    XCTAssertEqual(state.annotationCreationProperties(for: .watermark).fontSize, 42)
  }

  @MainActor
  func testQuickPropertiesSyncOffKeepsSelectedItemPrimaryColorLocal() throws {
    let defaults = UserDefaultsFactory.make()
    defaults.set(false, forKey: PreferencesKeys.annotateQuickPropertiesSyncEnabled)
    let state = makeAnnotateState(defaults: defaults)
    let annotation = AnnotationItem(
      type: .rectangle,
      bounds: CGRect(x: 0, y: 0, width: 80, height: 40),
      properties: AnnotationProperties(strokeColor: .red, fillColor: .clear)
    )
    state.annotations = [annotation]
    state.setSelectedAnnotationIds([annotation.id])

    state.quickStrokeColorBinding.wrappedValue = .green

    let updated = try XCTUnwrap(state.annotations.first)
    assertColorsMatch(updated.properties.strokeColor, .green)
    assertColorsMatch(state.annotationCreationProperties(for: .line).strokeColor, .red)
    assertColorsMatch(state.annotationCreationProperties(for: .rectangle).strokeColor, .red)
  }

  @MainActor
  func testQuickPropertiesSyncOffPersistsPerToolDefaultsAcrossStateInstances() {
    let defaults = UserDefaultsFactory.make()
    defaults.set(false, forKey: PreferencesKeys.annotateQuickPropertiesSyncEnabled)
    let firstState = makeAnnotateState(defaults: defaults)

    firstState.activateTool(.rectangle)
    firstState.quickStrokeColorBinding.wrappedValue = .blue
    firstState.quickStrokeWidthBinding.wrappedValue = 9
    firstState.quickCornerRadiusBinding.wrappedValue = 12

    firstState.activateTool(.arrow)
    firstState.quickStrokeColorBinding.wrappedValue = .green
    firstState.quickStrokeWidthBinding.wrappedValue = 5

    firstState.activateTool(.text)
    firstState.quickTextFontSizeBinding.wrappedValue = 30

    let reloadedState = makeAnnotateState(defaults: defaults)

    XCTAssertEqual(reloadedState.annotationCreationProperties(for: .rectangle).strokeWidth, 9)
    XCTAssertEqual(reloadedState.annotationCreationProperties(for: .rectangle).cornerRadius, 12)
    assertColorsMatch(reloadedState.annotationCreationProperties(for: .rectangle).strokeColor, .blue)

    XCTAssertEqual(reloadedState.annotationCreationProperties(for: .arrow).strokeWidth, 5)
    assertColorsMatch(reloadedState.annotationCreationProperties(for: .arrow).strokeColor, .green)

    XCTAssertEqual(reloadedState.annotationCreationProperties(for: .text).fontSize, 30)
    XCTAssertEqual(reloadedState.annotationCreationProperties(for: .watermark).fontSize, 36)
  }

  @MainActor
  func testQuickPropertiesSyncOffKeepsExistingSharedDefaultsAsBaseline() {
    let defaults = UserDefaultsFactory.make()
    let sharedState = makeAnnotateState(defaults: defaults)
    sharedState.activateTool(.rectangle)
    sharedState.quickStrokeColorBinding.wrappedValue = .blue
    sharedState.quickStrokeWidthBinding.wrappedValue = 9

    defaults.set(false, forKey: PreferencesKeys.annotateQuickPropertiesSyncEnabled)
    let independentState = makeAnnotateState(defaults: defaults)

    XCTAssertEqual(independentState.annotationCreationProperties(for: .rectangle).strokeWidth, 9)
    XCTAssertEqual(independentState.annotationCreationProperties(for: .arrow).strokeWidth, 9)
    assertColorsMatch(independentState.annotationCreationProperties(for: .rectangle).strokeColor, .blue)
    assertColorsMatch(independentState.annotationCreationProperties(for: .arrow).strokeColor, .blue)

    independentState.activateTool(.arrow)
    independentState.quickStrokeColorBinding.wrappedValue = .green
    independentState.quickStrokeWidthBinding.wrappedValue = 5

    XCTAssertEqual(independentState.annotationCreationProperties(for: .rectangle).strokeWidth, 9)
    XCTAssertEqual(independentState.annotationCreationProperties(for: .arrow).strokeWidth, 5)
    assertColorsMatch(independentState.annotationCreationProperties(for: .rectangle).strokeColor, .blue)
    assertColorsMatch(independentState.annotationCreationProperties(for: .arrow).strokeColor, .green)
  }

  @MainActor
  func testQuickPropertiesSyncOnOverridesPersistedIndependentDefaults() {
    let defaults = UserDefaultsFactory.make()
    let sharedState = makeAnnotateState(defaults: defaults)
    sharedState.activateTool(.rectangle)
    sharedState.quickStrokeColorBinding.wrappedValue = .blue
    sharedState.quickStrokeWidthBinding.wrappedValue = 9
    sharedState.quickCornerRadiusBinding.wrappedValue = 12
    sharedState.activateTool(.watermark)
    sharedState.quickWatermarkOpacityBinding.wrappedValue = 0.4
    sharedState.quickWatermarkRotationBinding.wrappedValue = -12

    defaults.set(false, forKey: PreferencesKeys.annotateQuickPropertiesSyncEnabled)
    let independentState = makeAnnotateState(defaults: defaults)
    independentState.activateTool(.arrow)
    independentState.quickStrokeColorBinding.wrappedValue = .green
    independentState.quickStrokeWidthBinding.wrappedValue = 5
    independentState.activateTool(.filledRectangle)
    independentState.quickCornerRadiusBinding.wrappedValue = 4
    independentState.activateTool(.watermark)
    independentState.quickWatermarkOpacityBinding.wrappedValue = 0.55
    independentState.quickWatermarkRotationBinding.wrappedValue = -3

    defaults.set(true, forKey: PreferencesKeys.annotateQuickPropertiesSyncEnabled)
    let syncedState = makeAnnotateState(defaults: defaults)

    XCTAssertEqual(syncedState.annotationCreationProperties(for: .rectangle).strokeWidth, 9)
    XCTAssertEqual(syncedState.annotationCreationProperties(for: .arrow).strokeWidth, 9)
    XCTAssertEqual(syncedState.annotationCreationProperties(for: .rectangle).cornerRadius, 12)
    XCTAssertEqual(syncedState.annotationCreationProperties(for: .filledRectangle).cornerRadius, 12)
    XCTAssertEqual(syncedState.annotationCreationProperties(for: .watermark).opacity, 0.4)
    XCTAssertEqual(syncedState.annotationCreationProperties(for: .watermark).rotationDegrees, -12)
    assertColorsMatch(syncedState.annotationCreationProperties(for: .rectangle).strokeColor, .blue)
    assertColorsMatch(syncedState.annotationCreationProperties(for: .arrow).strokeColor, .blue)
  }

  func testMockupPresetCatalogContainsUniqueBuiltInPresets() {
    let presets = MockupPreset.allPresets

    XCTAssertEqual(presets.count, 8)
    XCTAssertEqual(Set(presets.map(\.id)).count, presets.count)
    XCTAssertEqual(DefaultPresets.all, presets)
    XCTAssertEqual(DefaultPresets.preset(named: "Hero Shot"), .heroShot)
    XCTAssertNil(DefaultPresets.preset(named: "Missing"))
  }

  private func makeContext(
    properties: AnnotationProperties = AnnotationProperties(),
    arrowStyle: ArrowStyle = .straight,
    arrowBendDirection: ArrowBendDirection = .primary,
    blurType: BlurType = .pixelated,
    counterValue: Int = 1,
    watermarkText: String = "Snapzy",
    bounds: CGRect = CGRect(x: 0, y: 0, width: 400, height: 300)
  ) -> AnnotationFactory.CreationContext {
    AnnotationFactory.CreationContext(
      properties: properties,
      arrowStyle: arrowStyle,
      arrowBendDirection: arrowBendDirection,
      blurType: blurType,
      counterValue: counterValue,
      watermarkText: watermarkText,
      activeAnnotationBounds: bounds
    )
  }

  private func makeMouseEvent(type: NSEvent.EventType, location: CGPoint) -> NSEvent {
    NSEvent.mouseEvent(
      with: type,
      location: location,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      eventNumber: 0,
      clickCount: 1,
      pressure: 1
    )!
  }

  private func makeRetinaPixelPatternImage(
    pixelWidth: Int,
    pixelHeight: Int,
    scale: CGFloat
  ) throws -> NSImage {
    var pixels = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
    for y in 0..<pixelHeight {
      for x in 0..<pixelWidth {
        let index = rgbaIndex(x: x, y: y, width: pixelWidth)
        let whiteStripe = x.isMultiple(of: 2)
        let topBand = y < pixelHeight / 2
        pixels[index] = whiteStripe ? 255 : 0
        pixels[index + 1] = topBand ? 48 : 208
        pixels[index + 2] = topBand ? 32 : 192
        pixels[index + 3] = 255
      }
    }

    let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
    let cgImage = try XCTUnwrap(CGImage(
      width: pixelWidth,
      height: pixelHeight,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: pixelWidth * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: rgbaBitmapInfo,
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    ))

    return NSImage(
      cgImage: cgImage,
      size: CGSize(width: CGFloat(pixelWidth) / scale, height: CGFloat(pixelHeight) / scale)
    )
  }

  private func rgbaBytes(from image: CGImage) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try bytes.withUnsafeMutableBytes { buffer in
      let context = try XCTUnwrap(CGContext(
        data: buffer.baseAddress,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: image.width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: rgbaBitmapInfo.rawValue
      ))
      context.interpolationQuality = .none
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bytes
  }

  private func assertColorsMatch(
    _ lhs: Color,
    _ rhs: Color,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(RGBAColor(color: lhs), RGBAColor(color: rhs), file: file, line: line)
  }

  private var rgbaBitmapInfo: CGBitmapInfo {
    CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
  }

  private func rgbaIndex(x: Int, y: Int, width: Int) -> Int {
    (y * width + x) * 4
  }

  @MainActor
  func testSpotlightAnnotationCreation() {
    let defaults = UserDefaultsFactory.make()
    let state = makeAnnotateState(defaults: defaults)
    let start = CGPoint(x: 10, y: 10)
    let end = CGPoint(x: 100, y: 100)
    let item = AnnotationFactory.createAnnotation(
      tool: .spotlight,
      from: start,
      to: end,
      path: [],
      state: state
    )
    XCTAssertNotNil(item)
    XCTAssertEqual(item?.type, .spotlight)
    XCTAssertEqual(item?.bounds, CGRect(x: 10, y: 10, width: 90, height: 90))
    XCTAssertEqual(item?.properties.spotlightOpacity, 0.5)
    XCTAssertEqual(item?.properties.cornerRadius, 14)
  }

  @MainActor
  func testSpotlightAnnotationCreationDegenerateDrag() {
    let defaults = UserDefaultsFactory.make()
    let state = makeAnnotateState(defaults: defaults)
    let start = CGPoint(x: 10, y: 10)
    let end = CGPoint(x: 15, y: 15) // less than 8px drag
    let item = AnnotationFactory.createAnnotation(
      tool: .spotlight,
      from: start,
      to: end,
      path: [],
      state: state
    )
    XCTAssertNil(item)
  }

  @MainActor
  func testSpotlightCornerRadiusIsolation() {
    let defaults = UserDefaultsFactory.make()
    let state = makeAnnotateState(defaults: defaults)
    
    // Set rectangle corner radius default to 0
    state.selectedTool = .rectangle
    state.quickCornerRadiusBinding.wrappedValue = 0
    
    // Creating a spotlight annotation should still default to 14 corner radius
    let start = CGPoint(x: 10, y: 10)
    let end = CGPoint(x: 100, y: 100)
    let item = AnnotationFactory.createAnnotation(
      tool: .spotlight,
      from: start,
      to: end,
      path: [],
      state: state
    )
    XCTAssertEqual(item?.properties.cornerRadius, 14)
  }

  @MainActor
  func testSpotlightOpacityStoredPerItem() throws {
    // Verifies the opacity-source fix: per-item spotlightOpacity is what gets persisted
    // and read by the compositor, not the global state.spotlightOpacity.
    let defaults = UserDefaultsFactory.make()
    let state = makeAnnotateState(defaults: defaults)

    // Change global opacity before creating the item
    state.spotlightOpacity = 0.8

    let item = AnnotationFactory.createAnnotation(
      tool: .spotlight,
      from: CGPoint(x: 0, y: 0),
      to: CGPoint(x: 100, y: 100),
      path: [],
      state: state
    )
    let unwrapped = try XCTUnwrap(item)
    // Item must carry the opacity at creation time, not the default 0.5
    XCTAssertEqual(unwrapped.properties.spotlightOpacity, 0.8, accuracy: 0.001)
  }

  @MainActor
  func testSpotlightOpacityClamp() {
    XCTAssertEqual(AnnotationProperties.clampedSpotlightOpacity(0.0), 0.1, accuracy: 0.001)
    XCTAssertEqual(AnnotationProperties.clampedSpotlightOpacity(1.0), 0.9, accuracy: 0.001)
    XCTAssertEqual(AnnotationProperties.clampedSpotlightOpacity(0.5), 0.5, accuracy: 0.001)
  }

  @MainActor
  func testSpotlightRegionCarriesOpacity() {
    // SpotlightRegion must carry opacity so the compositor can source it per-item.
    let region = SpotlightRegion(rect: CGRect(x: 0, y: 0, width: 100, height: 100), cornerRadius: 14, opacity: 0.75)
    XCTAssertEqual(region.opacity, 0.75, accuracy: 0.001)
  }

  @MainActor
  func testSpotlightOpacityPersistence() throws {
    let defaults = UserDefaultsFactory.make()
    let firstState = makeAnnotateState(defaults: defaults)
    firstState.activateTool(.spotlight)

    // Change the spotlight opacity (darkness) tool default property
    firstState.quickSpotlightOpacityBinding.wrappedValue = 0.75

    // Re-initialize state with the same defaults to simulate reload/reopen
    let reloadedState = makeAnnotateState(defaults: defaults)

    // Assert that the default spotlight opacity for the spotlight tool has persisted
    let spotlightProperties = reloadedState.annotationCreationProperties(for: .spotlight)
    XCTAssertEqual(spotlightProperties.spotlightOpacity, 0.75, accuracy: 0.001)
  }
}
