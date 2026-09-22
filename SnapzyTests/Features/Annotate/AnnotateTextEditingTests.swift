//
//  AnnotateTextEditingTests.swift
//  SnapzyTests
//
//  Characterization tests for the text-editing lifecycle state machine:
//  begin -> update -> commit / finish. Undo/redo of text edits and text
//  bounds resizing are covered in AnnotateCoreTests and are not duplicated
//  here; this file locks down the editing-target id transitions and the
//  empty-commit deletion behavior.
//

import CoreGraphics
import AppKit
import SwiftUI
import XCTest
@testable import Snapzy

@MainActor
final class AnnotateTextEditingTests: XCTestCase {
  // Keep AnnotateState alive for the test process; XCTest scope cleanup can
  // crash while deinitializing this MainActor app-level ObservableObject.
  private static var retainedAnnotateStates: [AnnotateState] = []

  private func makeAnnotateState() -> AnnotateState {
    let state = AnnotateState()
    Self.retainedAnnotateStates.append(state)
    return state
  }

  /// Persistence tests run against a scratch defaults suite so they neither read
  /// nor write the developer's real Snapzy preferences.
  private func makeAnnotateState(defaults: UserDefaults) -> AnnotateState {
    let state = AnnotateState(defaults: defaults, appliesDefaultCanvasPresetOnNewImages: false)
    Self.retainedAnnotateStates.append(state)
    return state
  }

  private func makeTextAnnotation(_ text: String) -> AnnotationItem {
    AnnotationItem(
      type: .text(text),
      bounds: CGRect(x: 20, y: 20, width: 140, height: 32),
      properties: AnnotationProperties(fontSize: 18)
    )
  }

  func testBeginTextEditingSetsEditingTargetId() {
    let state = makeAnnotateState()
    let annotation = makeTextAnnotation("Hello")
    state.annotations = [annotation]

    XCTAssertNil(state.editingTextAnnotationId)

    state.beginTextEditing(id: annotation.id)

    XCTAssertEqual(state.editingTextAnnotationId, annotation.id)
  }

  func testFinishTextEditingClearsEditingTargetId() {
    let state = makeAnnotateState()
    let annotation = makeTextAnnotation("Hello")
    state.annotations = [annotation]

    state.beginTextEditing(id: annotation.id)
    state.finishTextEditing()

    XCTAssertNil(state.editingTextAnnotationId)
  }

  func testBeginUpdateCommitPersistsTextAndClearsEditingState() throws {
    let state = makeAnnotateState()
    state.sourceImage = NSImage(size: CGSize(width: 300, height: 200))
    let annotation = makeTextAnnotation("Original")
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id

    state.beginTextEditing(id: annotation.id)
    state.updateAnnotationText(id: annotation.id, text: "Updated text")
    state.commitTextEditing()

    let committed = try XCTUnwrap(state.annotations.first)
    guard case .text(let text) = committed.type else {
      return XCTFail("Expected text annotation, got \(committed.type)")
    }
    XCTAssertEqual(text, "Updated text")
    XCTAssertNil(state.editingTextAnnotationId)
  }

  func testCommitTrimsSurroundingWhitespaceFromText() throws {
    let state = makeAnnotateState()
    state.sourceImage = NSImage(size: CGSize(width: 300, height: 200))
    let annotation = makeTextAnnotation("")
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id

    state.beginTextEditing(id: annotation.id)
    state.updateAnnotationText(id: annotation.id, text: "   padded value   ")
    state.commitTextEditing()

    let committed = try XCTUnwrap(state.annotations.first)
    guard case .text(let text) = committed.type else {
      return XCTFail("Expected text annotation, got \(committed.type)")
    }
    XCTAssertEqual(text, "padded value")
  }

  func testCommitEmptyTextDeletesAnnotationAndClearsSelection() {
    let state = makeAnnotateState()
    let annotation = makeTextAnnotation("")
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id

    state.beginTextEditing(id: annotation.id, recordsUndo: false)
    state.commitTextEditing()

    XCTAssertTrue(state.annotations.isEmpty)
    XCTAssertNil(state.selectedAnnotationId)
    XCTAssertNil(state.editingTextAnnotationId)
    XCTAssertTrue(state.hasUnsavedChanges)
  }

  func testCommitWhitespaceOnlyTextIsTreatedAsEmptyAndDeletes() {
    let state = makeAnnotateState()
    let annotation = makeTextAnnotation("   \n  ")
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id

    state.beginTextEditing(id: annotation.id, recordsUndo: false)
    state.commitTextEditing()

    XCTAssertTrue(state.annotations.isEmpty)
    XCTAssertNil(state.editingTextAnnotationId)
  }

  func testFinishTextEditingKeepsUncommittedTextAndItem() throws {
    let state = makeAnnotateState()
    state.sourceImage = NSImage(size: CGSize(width: 300, height: 200))
    let annotation = makeTextAnnotation("")
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id

    state.beginTextEditing(id: annotation.id)
    state.updateAnnotationText(id: annotation.id, text: "not committed")
    // finishTextEditing only clears the editing id; it does not trim/delete.
    state.finishTextEditing()

    XCTAssertNil(state.editingTextAnnotationId)
    let item = try XCTUnwrap(state.annotations.first)
    guard case .text(let text) = item.type else {
      return XCTFail("Expected text annotation, got \(item.type)")
    }
    XCTAssertEqual(text, "not committed")
  }

  func testCommitWithoutActiveEditingTargetIsNoOp() {
    let state = makeAnnotateState()
    let annotation = makeTextAnnotation("Kept")
    state.annotations = [annotation]

    // No beginTextEditing call -> editingTextAnnotationId is nil.
    state.commitTextEditing()

    XCTAssertEqual(state.annotations.count, 1)
    XCTAssertNil(state.editingTextAnnotationId)
  }

  func testAutomaticTextWidthGrowsWithTypedContent() throws {
    let state = makeAnnotateState()
    state.sourceImage = NSImage(size: CGSize(width: 600, height: 300))
    let annotation = makeTextAnnotation("")
    state.annotations = [annotation]
    state.useAutomaticTextWidth(for: annotation.id)

    state.updateAnnotationText(id: annotation.id, text: "A natural width text label")

    let updated = try XCTUnwrap(state.annotations.first)
    XCTAssertGreaterThan(updated.bounds.width, 140)
    XCTAssertLessThan(updated.bounds.width, 300)
  }

  func testManualTextResizeDoesNotPinWidthAndTextAutoSizes() throws {
    let state = makeAnnotateState()
    state.sourceImage = NSImage(size: CGSize(width: 600, height: 300))
    let annotation = makeTextAnnotation("")
    state.annotations = [annotation]
    state.useAutomaticTextWidth(for: annotation.id)
    state.updateAnnotationBounds(
      id: annotation.id,
      bounds: CGRect(x: 20, y: 20, width: 180, height: 32)
    )

    state.updateAnnotationText(id: annotation.id, text: "This text should wrap in the width chosen by the user")

    let updated = try XCTUnwrap(state.annotations.first)
    XCTAssertNotEqual(updated.bounds.width, 180, accuracy: 0.5)
    XCTAssertGreaterThan(updated.bounds.width, 140)
  }

  func testTextPresentationKeepsTextColorAndRetainsBackgroundChoice() throws {
    let state = makeAnnotateState()
    let annotation = AnnotationItem(
      type: .text("Label"),
      bounds: CGRect(x: 40, y: 80, width: 120, height: 32),
      properties: AnnotationProperties(strokeColor: .green, fillColor: .clear)
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    state.selectedTool = .text

    state.setTextPresentation(.label)
    var updated = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(updated.properties.textPresentation, .label)
    XCTAssertEqual(updated.properties.strokeColor, .green)
    XCTAssertFalse(AnnotateColorPaletteStore.isClear(updated.properties.fillColor))

    state.setTextPresentation(.plain)
    updated = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(updated.properties.textPresentation, .plain)
    XCTAssertTrue(AnnotateColorPaletteStore.colorsMatch(updated.properties.fillColor, .white))
  }

  func testCalloutTailFollowsItsDraggedTargetAndMovesWithText() throws {
    let state = makeAnnotateState()
    let annotation = AnnotationItem(
      type: .text("Callout"),
      bounds: CGRect(x: 40, y: 80, width: 160, height: 40),
      properties: AnnotationProperties(strokeColor: .black, fillColor: .white, textPresentation: .callout)
    )
    state.annotations = [annotation]
    state.prepareTextCalloutTail(for: annotation.id)
    state.updateTextCalloutTail(id: annotation.id, target: CGPoint(x: 40, y: 360))
    let resolvedTail = try XCTUnwrap(state.annotations.first?.properties.calloutTailTarget)
    state.updateAnnotationBounds(
      id: annotation.id,
      bounds: CGRect(x: 100, y: 100, width: annotation.bounds.width, height: annotation.bounds.height)
    )

    let updated = try XCTUnwrap(state.annotations.first)
    let updatedTail = try XCTUnwrap(updated.properties.calloutTailTarget)
    XCTAssertEqual(updatedTail.x, resolvedTail.x + 60, accuracy: 0.5)
    XCTAssertEqual(updatedTail.y, resolvedTail.y + 20, accuracy: 0.5)
  }

  /// Text, Text Label and Callout Label share one set of insets, so switching
  /// between them can neither resize the annotation nor re-wrap the text.
  func testBubbleInsetsAreIdenticalAcrossPresentations() {
    let font = AnnotateTextLayout.font(size: 20)
    let width: (TextPresentation) -> CGFloat = { presentation in
      AnnotateTextLayout.preferredAutoWidth(
        text: "Note",
        font: font,
        minimumWidth: AnnotateTextLayout.minWidth,
        presentation: presentation
      )
    }

    XCTAssertEqual(width(.plain), width(.label), accuracy: 0.0001)
    XCTAssertEqual(width(.plain), width(.callout), accuracy: 0.0001)

    let bounds = AnnotateTextLayout.bounds(
      text: "Note",
      font: font,
      origin: .zero,
      constrainedWidth: width(.callout),
      presentation: .callout
    )
    XCTAssertGreaterThanOrEqual(
      bounds.height,
      AnnotateTextLayout.minimumHeight(for: font, presentation: .plain)
    )
    XCTAssertGreaterThan(TextBubbleGeometry.cornerRadius(in: bounds, fontSize: font.pointSize), 0)

    // The whole point of the widened insets: the text never touches the edge.
    let insets = TextBubbleGeometry.contentInsets(for: .label, fontSize: font.pointSize)
    let textRect = AnnotateTextLayout.textRect(for: "Note", font: font, in: bounds, presentation: .label)
    XCTAssertEqual(textRect.minX - bounds.minX, insets.width, accuracy: 0.0001)
    XCTAssertGreaterThanOrEqual(textRect.minY - bounds.minY, insets.height - 0.0001)
  }

  func testDefaultCalloutTailFollowsAutomaticTextGrowth() throws {
    let state = makeAnnotateState()
    state.sourceImage = NSImage(size: CGSize(width: 600, height: 300))
    let annotation = AnnotationItem(
      type: .text(""),
      bounds: CGRect(x: 30, y: 120, width: 30, height: 30),
      properties: AnnotationProperties(fillColor: .black, fontSize: 18, textPresentation: .callout)
    )
    state.annotations = [annotation]
    state.useAutomaticTextWidth(for: annotation.id)
    state.prepareTextCalloutTail(for: annotation.id)

    state.updateAnnotationText(id: annotation.id, text: "A growing callout label")

    let updated = try XCTUnwrap(state.annotations.first)
    let tail = try XCTUnwrap(updated.properties.calloutTailTarget)
    let expected = TextBubbleGeometry.defaultTailTarget(for: updated.bounds, fontSize: updated.properties.fontSize)
    XCTAssertEqual(tail.x, expected.x, accuracy: 0.5)
    XCTAssertEqual(tail.y, expected.y, accuracy: 0.5)
  }

  func testDefaultCalloutTailStartsFromTheLowerRightAndHasVisibleDepth() {
    let bounds = CGRect(x: 20, y: 60, width: 180, height: 48)
    let target = TextBubbleGeometry.defaultTailTarget(for: bounds, fontSize: 20)
    let tailBounds = TextBubbleGeometry.tailPath(
      in: bounds,
      to: target,
      cornerRadius: TextBubbleGeometry.cornerRadius(in: bounds, fontSize: 20),
      fontSize: 20
    ).boundingBoxOfPath

    XCTAssertGreaterThan(target.x, bounds.midX)
    XCTAssertLessThan(target.y, bounds.minY)
    XCTAssertLessThan(tailBounds.minY, bounds.minY)
  }

  func testCalloutTailClampsAnOverlyDistantManualTargetNearTheBubble() {
    let bounds = CGRect(x: 20, y: 60, width: 180, height: 48)
    let resolved = TextBubbleGeometry.resolvedTailTarget(
      in: bounds,
      requestedTarget: CGPoint(x: 120, y: -500),
      fontSize: 20
    )

    XCTAssertEqual(resolved.x, 120, accuracy: 24)
    XCTAssertLessThan(resolved.y, bounds.minY)
    XCTAssertGreaterThan(resolved.y, -200)
  }

  /// Supersedes the earlier "a new callout starts from the default corner"
  /// guarantee: the user asked for a new annotation to continue the previous
  /// one, tail direction included.
  func testNewCalloutTextContinuesThePreviousCalloutTailDirection() throws {
    let state = makeAnnotateState()
    state.sourceImage = NSImage(size: CGSize(width: 600, height: 300))
    let first = AnnotationItem(
      type: .text("First"),
      bounds: CGRect(x: 40, y: 120, width: 140, height: 40),
      properties: AnnotationProperties(fillColor: .black, fontSize: 18, textPresentation: .callout)
    )
    state.annotations = [first]
    state.prepareTextCalloutTail(for: first.id)
    state.updateTextCalloutTail(id: first.id, target: CGPoint(x: 320, y: 260))
    state.setTextPresentation(.callout)

    let oldTail = try XCTUnwrap(state.annotations.first?.properties.calloutTailTarget)
    XCTAssertNotEqual(oldTail, TextBubbleGeometry.defaultTailTarget(for: first.bounds, fontSize: 18))
    let oldBounds = try XCTUnwrap(state.annotations.first).bounds

    let secondBounds = CGRect(x: 220, y: 80, width: 140, height: 40)
    let inherited = try XCTUnwrap(
      state.initialCalloutTailTarget(for: secondBounds, fontSize: 18),
      "a callout with a placed tail must hand its direction to the next one"
    )

    // Same side of the bubble as the tail it came from, and not the tucked
    // default — the direction carried over rather than snapping back.
    XCTAssertEqual(
      inherited.x > secondBounds.midX,
      oldTail.x > oldBounds.midX,
      "inherited tail flipped horizontally"
    )
    XCTAssertEqual(
      inherited.y > secondBounds.midY,
      oldTail.y > oldBounds.midY,
      "inherited tail flipped vertically"
    )
    XCTAssertFalse(TextBubbleGeometry.isDefaultTail(inherited, for: secondBounds, fontSize: 18))
  }

  func testNewCalloutFallsBackToTheDefaultTailWhenThereIsNothingToContinue() {
    let state = makeAnnotateState()
    state.sourceImage = NSImage(size: CGSize(width: 600, height: 300))
    let bounds = CGRect(x: 220, y: 80, width: 140, height: 40)

    // No text annotation yet.
    XCTAssertNil(state.initialCalloutTailTarget(for: bounds, fontSize: 18))

    // A label has no tail to continue.
    let label = AnnotationItem(
      type: .text("Label"),
      bounds: CGRect(x: 40, y: 120, width: 140, height: 40),
      properties: AnnotationProperties(fillColor: .black, fontSize: 18, textPresentation: .label)
    )
    state.annotations = [label]
    XCTAssertNil(state.initialCalloutTailTarget(for: bounds, fontSize: 18))

    // A callout that never had a tail placed has nothing to hand over either.
    let callout = AnnotationItem(
      type: .text("Callout"),
      bounds: CGRect(x: 40, y: 120, width: 140, height: 40),
      properties: AnnotationProperties(fillColor: .black, fontSize: 18, textPresentation: .callout)
    )
    state.annotations = [callout]
    XCTAssertNil(state.initialCalloutTailTarget(for: bounds, fontSize: 18))
  }

  func testNewTextAnnotationInheritsThePreviousAnnotationsWholeStyle() throws {
    let state = makeAnnotateState()
    state.sourceImage = NSImage(size: CGSize(width: 600, height: 300))
    let source = AnnotationItem(
      type: .text("Source"),
      bounds: CGRect(x: 40, y: 120, width: 140, height: 40),
      properties: AnnotationProperties(
        strokeColor: .orange,
        fillColor: .black,
        strokeWidth: 5,
        cornerRadius: 17,
        fontSize: 26,
        fontName: "Courier",
        textPresentation: .callout,
        textBorderColor: .green,
        textBorderWidth: 3,
        isBorderEnabled: true,
        latentTextColor: .purple
      )
    )
    state.annotations = [source]
    state.prepareTextCalloutTail(for: source.id)
    state.updateTextCalloutTail(id: source.id, target: CGPoint(x: 320, y: 260))

    let inherited = state.annotationCreationProperties(for: .text)

    // Position-free properties carry over verbatim...
    XCTAssertEqual(inherited.cornerRadius, 17)
    XCTAssertEqual(inherited.fontSize, 26)
    XCTAssertEqual(inherited.fontName, "Courier")
    XCTAssertEqual(inherited.textPresentation, .callout)
    XCTAssertEqual(inherited.strokeWidth, 5)
    XCTAssertEqual(inherited.textBorderWidth, 3)
    XCTAssertTrue(inherited.isBorderEnabled)
    XCTAssertEqual(inherited.latentTextColor, .purple)
    XCTAssertTrue(AnnotateColorPaletteStore.colorsMatch(inherited.strokeColor, .orange))
    XCTAssertTrue(AnnotateColorPaletteStore.colorsMatch(inherited.fillColor, .black))
    XCTAssertTrue(AnnotateColorPaletteStore.colorsMatch(inherited.textBorderColor, .green))
    // ...but the tail is an absolute point tied to the old bounds, so the new
    // annotation re-derives it instead of copying it.
    XCTAssertNil(inherited.calloutTailTarget)
  }

  func testTextAnnotationWithoutAPredecessorKeepsTheFactoryDefaults() throws {
    // A scratch suite, or the developer's own persisted Text tool defaults would
    // stand in for the factory path this test is about.
    let suiteName = "AnnotateTextEditingTests.noPredecessor.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let state = makeAnnotateState(defaults: defaults)
    state.sourceImage = NSImage(size: CGSize(width: 600, height: 300))
    state.annotations = []

    let properties = state.annotationCreationProperties(for: .text)

    XCTAssertEqual(properties.textPresentation, .label)
    XCTAssertEqual(properties.cornerRadius, AnnotateState.SystemTextStylePreset.cornerRadius)
    XCTAssertEqual(properties.fontSize, state.recommendedTextFontSize())
  }

  func testCalloutTailChangesAttachmentSideAsTheTargetMoves() {
    let bounds = CGRect(x: 100, y: 100, width: 180, height: 48)

    let cornerRadius = TextBubbleGeometry.cornerRadius(in: bounds, fontSize: 20)
    let left = TextBubbleGeometry.tailPath(
      in: bounds,
      to: CGPoint(x: 45, y: bounds.midY),
      cornerRadius: cornerRadius,
      fontSize: 20
    ).boundingBoxOfPath
    let right = TextBubbleGeometry.tailPath(
      in: bounds,
      to: CGPoint(x: 335, y: bounds.midY),
      cornerRadius: cornerRadius,
      fontSize: 20
    ).boundingBoxOfPath
    let centered = TextBubbleGeometry.tailPath(
      in: bounds,
      to: CGPoint(x: bounds.midX, y: 74),
      cornerRadius: cornerRadius,
      fontSize: 20
    ).boundingBoxOfPath

    XCTAssertLessThan(left.minX, bounds.minX)
    XCTAssertGreaterThan(right.maxX, bounds.maxX)
    XCTAssertLessThan(centered.minY, bounds.minY)
    XCTAssertEqual(centered.midX, bounds.midX, accuracy: 0.5)
  }

  /// A distant target becomes a guide, not a needle: the tail stops at the reach
  /// cap, which is a fraction of the bubble's shorter side rather than a multiple
  /// of it.
  func testCalloutTailReachStaysClampedToTheBubble() {
    let bounds = CGRect(x: 100, y: 100, width: 180, height: 48)
    let requested = CGPoint(x: 200, y: -600)
    let resolved = TextBubbleGeometry.resolvedTailTarget(
      in: bounds,
      requestedTarget: requested,
      fontSize: 20
    )
    let reachCap = min(bounds.height * 0.6, 20 * 2.4)
    XCTAssertEqual(resolved.x, requested.x, accuracy: 0.5)
    XCTAssertEqual(resolved.y, bounds.minY - reachCap, accuracy: 0.5)
  }

  func testCalloutTailKeepsFixedLengthInsideTheShortSegment() {
    let bounds = CGRect(x: 100, y: 100, width: 180, height: 48)
    let near = CGPoint(x: 150, y: 88)
    let closer = CGPoint(x: 150, y: 92)
    let farResolved = TextBubbleGeometry.resolvedTailTarget(in: bounds, requestedTarget: near, fontSize: 20)
    let closeResolved = TextBubbleGeometry.resolvedTailTarget(in: bounds, requestedTarget: closer, fontSize: 20)

    let farLength = hypot(farResolved.x - 150, farResolved.y - bounds.minY)
    let closeLength = hypot(closeResolved.x - 150, closeResolved.y - bounds.minY)
    XCTAssertEqual(farLength, closeLength, accuracy: 0.5)
    XCTAssertGreaterThan(farLength, 0)
  }

  /// Points a path's segments end at, in order: one per `move`/`line`/`curve`.
  ///
  /// For a curve the destination is the *last* of its three points; the first
  /// two are control points.
  private func pathDestinations(_ path: CGPath) -> [CGPoint] {
    var points: [CGPoint] = []
    path.applyWithBlock { element in
      let element = element.pointee
      switch element.type {
      case .moveToPoint, .addLineToPoint:
        points.append(element.points[0])
      case .addQuadCurveToPoint:
        points.append(element.points[1])
      case .addCurveToPoint:
        points.append(element.points[2])
      case .closeSubpath:
        break
      @unknown default:
        break
      }
    }
    return points
  }

  /// Where a tail meets the bubble outline. A tail path is built as
  /// `move(entry) -> curve(tip) -> curve(exit) -> close`, so these are its first
  /// and last destinations.
  private func tailRootPoints(of path: CGPath) -> (entry: CGPoint, exit: CGPoint)? {
    let points = pathDestinations(path)
    guard let entry = points.first, let exit = points.last, points.count >= 3 else { return nil }
    return (entry, exit)
  }

  /// The tail's on-path point: the second destination of a tail path.
  private func tailTip(of path: CGPath) -> CGPoint? {
    let points = pathDestinations(path)
    return points.count >= 3 ? points[1] : nil
  }

  /// Resolving an already-resolved tail must be a no-op. The damped extension
  /// this replaces shortened the tail a little on every re-resolve, which is why
  /// changing the font size kept eating the tail.
  func testResolvingACalloutTailTwiceIsAFixedPoint() {
    let bounds = CGRect(x: 40, y: 60, width: 200, height: 44)
    let targets = [
      CGPoint(x: 340, y: 20),
      CGPoint(x: -60, y: 200),
      CGPoint(x: 240, y: -300),
      CGPoint(x: 140, y: 8),
      CGPoint(x: 139, y: 190),
    ]

    for target in targets {
      let once = TextBubbleGeometry.resolvedTailTarget(in: bounds, requestedTarget: target, fontSize: 18)
      let twice = TextBubbleGeometry.resolvedTailTarget(in: bounds, requestedTarget: once, fontSize: 18)
      XCTAssertEqual(once.x, twice.x, accuracy: 0.01, "target \(target)")
      XCTAssertEqual(once.y, twice.y, accuracy: 0.01, "target \(target)")
    }
  }

  /// Defect fix: with the corner radius at its maximum the side has no straight
  /// span left, so the tail has to be rooted in the corner arc itself instead of
  /// hanging off a point floating outside it. Here `radius == height / 2`, so
  /// both right corners share one centre and the whole right side is a single
  /// semicircle: both root points must sit exactly on it.
  func testFullRadiusCalloutTailRootsOnTheCornerArc() throws {
    let bounds = CGRect(x: 0, y: 0, width: 200, height: 40)
    let radius = TextBubbleGeometry.resolvedCornerRadius(storedValue: 999, in: bounds, fontSize: 18)
    XCTAssertEqual(radius, bounds.height / 2, accuracy: 0.01)

    let target = CGPoint(x: 272, y: 10)
    let tail = TextBubbleGeometry.tailPath(
      in: bounds, to: target, cornerRadius: radius, fontSize: 18
    )
    let roots = try XCTUnwrap(tailRootPoints(of: tail))
    let center = CGPoint(x: bounds.maxX - radius, y: bounds.midY)
    XCTAssertEqual(
      hypot(roots.entry.x - center.x, roots.entry.y - center.y), radius, accuracy: 0.5,
      "the tail must leave from the arc, not from a point floating outside it"
    )
    XCTAssertEqual(hypot(roots.exit.x - center.x, roots.exit.y - center.y), radius, accuracy: 0.5)
    // Both sub-arcs of the split corner stay non-empty.
    XCTAssertGreaterThanOrEqual(roots.entry.y, center.y)
    XCTAssertLessThan(roots.exit.y, center.y)
    XCTAssertGreaterThan(tail.boundingBoxOfPath.maxX, bounds.maxX)

    // The bubble keeps its pill outline everywhere the tail is not attached.
    let bubble = TextBubbleGeometry.bubblePath(
      in: bounds, cornerRadius: radius, tailTarget: target, fontSize: 18
    )
    XCTAssertEqual(bubble.boundingBoxOfPath.minX, bounds.minX, accuracy: 0.01)
    XCTAssertEqual(bubble.boundingBoxOfPath.minY, bounds.minY, accuracy: 0.01)
    XCTAssertEqual(bubble.boundingBoxOfPath.maxY, bounds.maxY, accuracy: 0.01)
  }

  /// The attachment mode is decided from the corner radius and the side length
  /// alone, so growing the tail must never move its root from the arc to the
  /// straight span or back — that would be a visible jump mid-drag.
  func testFullRadiusCalloutTailStaysRootedInTheArcAtEveryLength() throws {
    let bounds = CGRect(x: 0, y: 0, width: 200, height: 40)
    let radius = bounds.height / 2
    let center = CGPoint(x: bounds.maxX - radius, y: bounds.midY)

    for offset in stride(from: CGFloat(8), through: 400, by: 8) {
      let tail = TextBubbleGeometry.tailPath(
        in: bounds,
        to: CGPoint(x: bounds.maxX + offset, y: bounds.midY - 10),
        cornerRadius: radius,
        fontSize: 18
      )
      let roots = try XCTUnwrap(tailRootPoints(of: tail), "offset \(offset)")
      XCTAssertEqual(
        hypot(roots.entry.x - center.x, roots.entry.y - center.y), radius, accuracy: 0.5,
        "offset \(offset)"
      )
      XCTAssertEqual(
        hypot(roots.exit.x - center.x, roots.exit.y - center.y), radius, accuracy: 0.5,
        "offset \(offset)"
      )
    }
  }

  /// A tail stays blunt at every target, not just every length. The tip angle
  /// (the angle between the two tail walls at the tip) used to collapse to ~14°
  /// at full reach, which is the needle beta testers reported — and separately
  /// whenever the target sat well past a side, because the root is clamped along
  /// the edge and the tail then left the wall at a glancing angle with its tip
  /// almost in line with its own root.
  ///
  /// Two sweeps: straight out from the middle of a side (length), and sideways at
  /// a fixed depth (the corner drag that used to flatten the wedge).
  func testCalloutTailTipAngleStaysBluntAtEveryLength() throws {
    let bubbles = [
      CGRect(x: 0, y: 0, width: 200, height: 40),
      CGRect(x: 0, y: 0, width: 180, height: 48),
      CGRect(x: 0, y: 0, width: 400, height: 80),
      CGRect(x: 0, y: 0, width: 60, height: 200),
    ]

    var sharpest = (degrees: CGFloat.infinity, description: "")
    var bluntest: CGFloat = 0
    func measure(_ bounds: CGRect, target: CGPoint, radius: CGFloat, _ label: String) {
      let tail = TextBubbleGeometry.tailPath(
        in: bounds, to: target, cornerRadius: radius, fontSize: 20
      )
      guard let roots = tailRootPoints(of: tail), let tip = tailTip(of: tail) else { return }
      let into = CGPoint(x: roots.entry.x - tip.x, y: roots.entry.y - tip.y)
      let out = CGPoint(x: roots.exit.x - tip.x, y: roots.exit.y - tip.y)
      let intoLength = hypot(into.x, into.y)
      let outLength = hypot(out.x, out.y)
      guard intoLength > 0.01, outLength > 0.01 else { return }
      let cosine = min(max((into.x * out.x + into.y * out.y) / (intoLength * outLength), -1), 1)
      let degrees = acos(cosine) * 180 / .pi
      if degrees < sharpest.degrees {
        sharpest = (degrees, "\(label) \(bounds) radius \(radius)")
      }
      bluntest = max(bluntest, degrees)
    }

    for bounds in bubbles {
      for radius in [CGFloat(0), bounds.height * 0.25, bounds.height / 2] as [CGFloat] {
        for offset in stride(from: CGFloat(20), through: 300, by: 20) {
          measure(
            bounds,
            target: CGPoint(x: bounds.midX, y: bounds.minY - offset),
            radius: radius,
            "straight offset \(offset)"
          )
        }
        // Sideways past the corner: the target ends up well beyond the side the
        // tail is rooted on, which is where the glancing-angle collapse lived.
        for dx in stride(from: CGFloat(-60), through: bounds.width + 60, by: 20) {
          measure(
            bounds,
            target: CGPoint(x: bounds.minX + dx, y: bounds.minY - 18),
            radius: radius,
            "sideways dx \(dx)"
          )
          measure(
            bounds,
            target: CGPoint(x: bounds.minX + dx, y: bounds.midY + 18),
            radius: radius,
            "sideways above dx \(dx)"
          )
        }
      }
    }

    // A tail on a straight span measures the design figure of 52°, and the sweep
    // bottoms out at ~43° on a pill whose corner arc hosts the whole root: the
    // entry point lands on the arc's boundary and that wall comes out shorter than
    // the other, which costs the wedge a few degrees. The floor is the measured
    // bound rather than the ideal, so this fails if the shape regresses towards
    // the 14° spike while leaving the corner case room to breathe.
    XCTAssertGreaterThanOrEqual(
      sharpest.degrees, 40,
      "sharpest tip over the whole sweep was \(sharpest.degrees)° (\(sharpest.description))"
    )
    XCTAssertLessThanOrEqual(bluntest, 75, "the tail must stay a wedge, not balloon into a fan")
  }

  func testOutlineTextLabelStaysTextLabelWhenBackgroundCleared() throws {
    let state = makeAnnotateState()
    let annotation = AnnotationItem(
      type: .text("Outline"),
      bounds: CGRect(x: 40, y: 80, width: 140, height: 36),
      properties: AnnotationProperties(
        strokeColor: .blue,
        fillColor: .white,
        textPresentation: .label,
        textBorderColor: .blue,
        textBorderWidth: 2,
        isBorderEnabled: true
      )
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    state.selectedTool = .text

    state.quickTextBackgroundBinding.wrappedValue = .clear

    let updated = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(updated.properties.textPresentation, .label)
    XCTAssertTrue(AnnotateColorPaletteStore.isClear(updated.properties.fillColor))
    XCTAssertEqual(updated.properties.textBorderColor, .blue)
  }

  func testCalloutTailDisappearsWhenTheTargetMovesInsideTheBubble() {
    let bounds = CGRect(x: 100, y: 100, width: 180, height: 48)
    let internalTarget = CGPoint(x: bounds.midX, y: bounds.midY)
    let path = TextBubbleGeometry.bubblePath(
      in: bounds,
      cornerRadius: TextBubbleGeometry.cornerRadius(in: bounds, fontSize: 20),
      tailTarget: internalTarget,
      fontSize: 20
    )

    XCTAssertEqual(path.boundingBoxOfPath.minX, bounds.minX, accuracy: 0.01)
    XCTAssertEqual(path.boundingBoxOfPath.minY, bounds.minY, accuracy: 0.01)
    XCTAssertEqual(path.boundingBoxOfPath.maxX, bounds.maxX, accuracy: 0.01)
    XCTAssertEqual(path.boundingBoxOfPath.maxY, bounds.maxY, accuracy: 0.01)
  }



  func testRecommendedTextFontSizeTracksCurrentCanvasShortSide() {
    let state = makeAnnotateState()
    state.sourceImage = NSImage(size: CGSize(width: 1600, height: 900))

    XCTAssertEqual(state.recommendedTextFontSize(), 30)

    state.sourceImage = NSImage(size: CGSize(width: 480, height: 1200))
    XCTAssertEqual(state.recommendedTextFontSize(), 16)
  }

  func testBeginTextEditingOnDifferentItemCommitsPreviousEdit() throws {
    let state = makeAnnotateState()
    state.sourceImage = NSImage(size: CGSize(width: 400, height: 300))
    let first = makeTextAnnotation("first")
    let second = AnnotationItem(
      type: .text("second"),
      bounds: CGRect(x: 200, y: 20, width: 140, height: 32),
      properties: AnnotationProperties(fontSize: 18)
    )
    state.annotations = [first, second]

    state.beginTextEditing(id: first.id)
    state.updateAnnotationText(id: first.id, text: "first edited")
    // Switching editing target to another item commits the first.
    state.beginTextEditing(id: second.id)

    XCTAssertEqual(state.editingTextAnnotationId, second.id)
    let firstItem = try XCTUnwrap(state.annotations.first(where: { $0.id == first.id }))
    guard case .text(let firstText) = firstItem.type else {
      return XCTFail("Expected text annotation, got \(firstItem.type)")
    }
    XCTAssertEqual(firstText, "first edited")
  }

  /// T-02/T-03: a transparent background is a fill property, not a shape
  /// decision, so a Text Label keeps its outline instead of collapsing to plain
  /// text.
  func testTextLabelWithClearBackgroundKeepsLabelShapeAndOutline() throws {
    let state = makeAnnotateState()
    let annotation = AnnotationItem(
      type: .text("Label"),
      bounds: CGRect(x: 40, y: 80, width: 120, height: 32),
      properties: AnnotationProperties(strokeColor: .green, fillColor: .white, textPresentation: .label)
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    state.selectedTool = .text
    state.quickTextBackgroundBinding.wrappedValue = .clear

    let updated = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(updated.properties.textPresentation, .label)
    XCTAssertTrue(AnnotateColorPaletteStore.isClear(updated.properties.fillColor))
    // Without a fill the outline is the only thing separating the label from
    // plain text, so it must be forced on.
    XCTAssertTrue(updated.properties.isBorderEnabled)
    XCTAssertGreaterThan(updated.properties.textBorderWidth, 0)
  }

  /// T-02: same rule for a callout — the tail and outline survive an empty fill.
  func testCalloutWithClearBackgroundKeepsCalloutShapeTailAndOutline() throws {
    let state = makeAnnotateState()
    let annotation = AnnotationItem(
      type: .text("Callout"),
      bounds: CGRect(x: 40, y: 80, width: 160, height: 44),
      properties: AnnotationProperties(strokeColor: .black, fillColor: .white, textPresentation: .callout)
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    state.selectedTool = .text
    state.prepareTextCalloutTail(for: annotation.id)
    let tailBefore = try XCTUnwrap(state.annotations.first?.properties.calloutTailTarget)

    state.quickTextBackgroundBinding.wrappedValue = .clear

    let updated = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(updated.properties.textPresentation, .callout)
    XCTAssertTrue(AnnotateColorPaletteStore.isClear(updated.properties.fillColor))
    XCTAssertEqual(updated.properties.calloutTailTarget?.x ?? .nan, tailBefore.x, accuracy: 0.01)
    XCTAssertEqual(updated.properties.calloutTailTarget?.y ?? .nan, tailBefore.y, accuracy: 0.01)
    XCTAssertTrue(updated.properties.isBorderEnabled)
  }

  /// T-03/T-08: switching to plain text removes the container, so the text color
  /// has to stay legible against whatever the canvas shows underneath.
  func testSwitchingToPlainReplacesUnreadableTextColor() throws {
    let state = makeAnnotateState()
    let annotation = AnnotationItem(
      type: .text("Label"),
      bounds: CGRect(x: 40, y: 80, width: 140, height: 36),
      properties: AnnotationProperties(
        strokeColor: .white,
        fillColor: Color(red: 1.0, green: 0.98, blue: 0.9),
        textPresentation: .label
      )
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    state.selectedTool = .text

    state.setTextPresentation(.plain)

    let updated = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(updated.properties.textPresentation, .plain)
    // No source image in this state, so the sampled backdrop falls back to
    // white and the unreadable white text must be swapped for black.
    XCTAssertTrue(AnnotateColorPaletteStore.colorsMatch(updated.properties.strokeColor, .black))
    XCTAssertGreaterThanOrEqual(
      AnnotateState.contrastRatio(updated.properties.strokeColor, .white),
      AnnotateState.minimumReadableContrastRatio
    )
  }

  /// T-08: a readable color is left exactly as the user chose it.
  func testSwitchingToPlainKeepsReadableTextColor() throws {
    let state = makeAnnotateState()
    let annotation = AnnotationItem(
      type: .text("Label"),
      bounds: CGRect(x: 40, y: 80, width: 140, height: 36),
      properties: AnnotationProperties(strokeColor: .black, fillColor: .white, textPresentation: .label)
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    state.selectedTool = .text

    state.setTextPresentation(.plain)

    let updated = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(updated.properties.textPresentation, .plain)
    XCTAssertTrue(AnnotateColorPaletteStore.colorsMatch(updated.properties.strokeColor, .black))
  }

  /// The T-08 substitute is a stopgap, not a new chosen colour: dropping the
  /// bubble must hand the user's own colour back with it, so a white label on a
  /// red bubble returns to white rather than staying on the black it was
  /// switched to for readability against the screenshot.
  func testLeavingPlainRestoresTheColorTheSubstituteReplaced() throws {
    let state = makeAnnotateState()
    let bubbleRed = Color(red: 1.0, green: 0.27, blue: 0.23)
    let annotation = AnnotationItem(
      type: .text("Label"),
      bounds: CGRect(x: 40, y: 80, width: 140, height: 36),
      properties: AnnotationProperties(strokeColor: .white, fillColor: bubbleRed, textPresentation: .label)
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    state.selectedTool = .text

    state.setTextPresentation(.plain)

    let plain = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(plain.properties.textPresentation, .plain)
    XCTAssertTrue(AnnotateColorPaletteStore.colorsMatch(plain.properties.strokeColor, .black))
    XCTAssertTrue(
      AnnotateColorPaletteStore.colorsMatch(try XCTUnwrap(plain.properties.latentTextColor), .white),
      "The displaced colour has to be parked, not discarded"
    )

    state.setTextPresentation(.label)

    let restored = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(restored.properties.textPresentation, .label)
    XCTAssertTrue(AnnotateColorPaletteStore.colorsMatch(restored.properties.strokeColor, .white))
    XCTAssertNil(restored.properties.latentTextColor)
  }

  /// Round-tripping twice must land in the same place: the second switch to
  /// plain stashes the restored colour again instead of stranding it.
  func testPlainRoundTripIsStableAcrossRepeatedSwitches() throws {
    let state = makeAnnotateState()
    let annotation = AnnotationItem(
      type: .text("Label"),
      bounds: CGRect(x: 40, y: 80, width: 140, height: 36),
      properties: AnnotationProperties(strokeColor: .white, fillColor: .black, textPresentation: .label)
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    state.selectedTool = .text

    for _ in 0 ..< 2 {
      state.setTextPresentation(.plain)
      XCTAssertTrue(
        AnnotateColorPaletteStore.colorsMatch(
          try XCTUnwrap(state.annotations.first?.properties.strokeColor), .black
        )
      )
      state.setTextPresentation(.label)
      let restored = try XCTUnwrap(state.annotations.first)
      XCTAssertTrue(AnnotateColorPaletteStore.colorsMatch(restored.properties.strokeColor, .white))
      XCTAssertNil(restored.properties.latentTextColor)
    }
  }

  /// Picking a colour while plain is the user settling the question themselves,
  /// so the parked colour must not come back and overwrite it later.
  func testChoosingATextColorWhilePlainSupersedesTheParkedColor() throws {
    let state = makeAnnotateState()
    let chosen = Color(red: 0.1, green: 0.7, blue: 0.3)
    let annotation = AnnotationItem(
      type: .text("Label"),
      bounds: CGRect(x: 40, y: 80, width: 140, height: 36),
      properties: AnnotationProperties(strokeColor: .white, fillColor: .black, textPresentation: .label)
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    state.selectedTool = .text
    state.setTextPresentation(.plain)
    XCTAssertNotNil(try XCTUnwrap(state.annotations.first).properties.latentTextColor)

    state.updateAnnotationProperties(id: annotation.id, strokeColor: chosen)

    XCTAssertNil(try XCTUnwrap(state.annotations.first).properties.latentTextColor)

    state.setTextPresentation(.label)

    let after = try XCTUnwrap(state.annotations.first)
    XCTAssertTrue(
      AnnotateColorPaletteStore.colorsMatch(after.properties.strokeColor, chosen),
      "The explicit pick has to survive going back into a bubble"
    )
  }

  func testCalloutTailDraggedInsideBubbleConvertsToTextLabel() throws {
    let state = makeAnnotateState()
    let annotation = AnnotationItem(
      type: .text("Callout"),
      bounds: CGRect(x: 40, y: 80, width: 160, height: 40),
      properties: AnnotationProperties(strokeColor: .black, fillColor: .white, textPresentation: .callout)
    )
    state.annotations = [annotation]
    state.prepareTextCalloutTail(for: annotation.id)

    state.updateTextCalloutTail(id: annotation.id, target: CGPoint(x: 90, y: 95))

    let updated = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(updated.properties.textPresentation, .label)
    XCTAssertNotNil(updated.properties.calloutTailTarget)
  }

  func testSwitchingToPlainKeepsLatentContainerAndRestoresIt() throws {
    let state = makeAnnotateState()
    let annotation = AnnotationItem(
      type: .text("Label"),
      bounds: CGRect(x: 40, y: 80, width: 140, height: 36),
      properties: AnnotationProperties(
        strokeColor: .black,
        fillColor: .yellow,
        cornerRadius: 14,
        textPresentation: .label,
        textBorderColor: .blue,
        textBorderWidth: 2,
        isBorderEnabled: true
      )
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    state.selectedTool = .text

    state.setTextPresentation(.plain)
    let plain = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(plain.properties.textPresentation, .plain)
    XCTAssertEqual(plain.properties.fillColor, .yellow)

    state.setTextPresentation(.label)
    let restored = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(restored.properties.textPresentation, .label)
    XCTAssertEqual(restored.properties.fillColor, .yellow)
    XCTAssertTrue(restored.properties.isBorderEnabled)
    XCTAssertEqual(restored.properties.cornerRadius, 14)
  }

  func testResolvedCornerRadiusDoesNotDependOnPresentation() {
    let bounds = CGRect(x: 20, y: 60, width: 180, height: 48)
    let radius = TextBubbleGeometry.resolvedCornerRadius(storedValue: 20, in: bounds, fontSize: 18)
    XCTAssertEqual(radius, 20, accuracy: 0.01)
  }

  func testResolvedCornerRadiusIsSquareAtZeroAndPillAtMaximum() {
    let bounds = CGRect(x: 20, y: 60, width: 180, height: 48)

    XCTAssertEqual(TextBubbleGeometry.resolvedCornerRadius(storedValue: 0, in: bounds, fontSize: 18), 0)

    let maximum = TextBubbleGeometry.resolvedCornerRadius(storedValue: 999, in: bounds, fontSize: 18)
    XCTAssertEqual(maximum, bounds.height / 2, accuracy: 0.01)
  }

  /// Leftmost x inside `rect` at which `path` contains a point just below the
  /// top edge. For a corner of radius `r` this lands at `minX + r - sqrt(0.2r)`,
  /// which distinguishes a correct radius from a doubled one without reaching
  /// into the path's Bezier data.
  private func topEdgeProbe(_ path: CGPath, in rect: CGRect) -> CGFloat? {
    let y = rect.maxY - 0.1
    var x = rect.minX
    while x <= rect.midX {
      if path.contains(CGPoint(x: x, y: y)) { return x }
      x += 0.01
    }
    return nil
  }

  func testBubblePathRadiusMatchesBetweenTailedAndTailLessBubbles() throws {
    let rect = CGRect(x: 0, y: 0, width: 180, height: 60)
    let radius = TextBubbleGeometry.resolvedCornerRadius(storedValue: 20, in: rect, fontSize: 18)

    let tailLess = TextBubbleGeometry.bubblePath(
      in: rect,
      cornerRadius: radius,
      tailTarget: nil,
      fontSize: 18
    )
    let tailed = TextBubbleGeometry.bubblePath(
      in: rect,
      cornerRadius: radius,
      tailTarget: CGPoint(x: rect.midX + 20, y: rect.minY - 40),
      fontSize: 18
    )

    let tailLessProbe = try XCTUnwrap(topEdgeProbe(tailLess, in: rect))
    let tailedProbe = try XCTUnwrap(topEdgeProbe(tailed, in: rect))
    XCTAssertEqual(
      tailLessProbe,
      tailedProbe,
      accuracy: 0.05,
      "Text Label and Callout Label must round their corners the same way"
    )

    // Regression: `cornerWidth` is a radius, so a `* 2` here would land at ~2r.
    XCTAssertEqual(tailLessProbe, rect.minX + radius - (0.2 * radius).squareRoot(), accuracy: 0.15)
  }

  func testBubbleInsetsDoNotDependOnPresentation() {
    let fontSize: CGFloat = 18
    let plain = TextBubbleGeometry.contentInsets(for: .plain, fontSize: fontSize)
    let label = TextBubbleGeometry.contentInsets(for: .label, fontSize: fontSize)
    let callout = TextBubbleGeometry.contentInsets(for: .callout, fontSize: fontSize)

    XCTAssertEqual(plain, label)
    XCTAssertEqual(plain, callout)
  }

  func testSwitchingTextPresentationKeepsBoundsStable() throws {
    let state = makeAnnotateState()
    state.sourceImage = NSImage(size: CGSize(width: 600, height: 400))
    let annotation = AnnotationItem(
      type: .text("Stable"),
      bounds: CGRect(x: 40, y: 80, width: 160, height: 40),
      properties: AnnotationProperties(fontSize: 18, textPresentation: .label)
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    state.selectedTool = .text

    // Switching auto-sizes the annotation once, so settle on a baseline first.
    state.setTextPresentation(.label)
    let initialBounds = try XCTUnwrap(state.annotations.first).bounds
    for presentation in [TextPresentation.callout, .plain, .label] {
      state.setTextPresentation(presentation)
      let current = try XCTUnwrap(state.annotations.first)
      XCTAssertEqual(current.properties.textPresentation, presentation)
      XCTAssertEqual(
        current.bounds,
        initialBounds,
        "switching to \(presentation) moved or resized the text"
      )
    }
  }

  /// The tool-default path (nothing selected) used to wipe the container
  /// properties when switching to Text, unlike the selected-annotation path.
  func testToolDefaultsKeepContainerPropertiesAcrossPlainRoundTrip() throws {
    let suiteName = "AnnotateTextEditingTests.plainRoundTrip"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let state = makeAnnotateState(defaults: defaults)
    state.sourceImage = NSImage(size: CGSize(width: 300, height: 200))
    state.selectedTool = .text
    state.annotations = []

    state.setTextPresentation(.label)
    state.quickTextBackgroundBinding.wrappedValue = .yellow

    state.setTextPresentation(.plain)
    let plain = state.annotationCreationProperties(for: .text)
    XCTAssertEqual(plain.textPresentation, .plain)
    XCTAssertFalse(
      AnnotateColorPaletteStore.isClear(plain.fillColor),
      "switching to Text must not throw away the stored background"
    )

    state.setTextPresentation(.label)
    let restored = state.annotationCreationProperties(for: .text)
    XCTAssertEqual(restored.textPresentation, .label)
    XCTAssertTrue(AnnotateColorPaletteStore.colorsMatch(restored.fillColor, .yellow))
  }

  func testPickingBackgroundColorOnPlainPromotesToTextLabel() throws {
    let suiteName = "AnnotateTextEditingTests.plainPromotion"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let state = makeAnnotateState(defaults: defaults)
    state.sourceImage = NSImage(size: CGSize(width: 300, height: 200))
    state.selectedTool = .text
    state.annotations = []

    state.setTextPresentation(.plain)
    XCTAssertEqual(state.quickTextPresentation, .plain)

    state.quickTextBackgroundBinding.wrappedValue = .yellow

    XCTAssertEqual(
      state.quickTextPresentation,
      .label,
      "choosing a background colour is a request for a background"
    )
    let properties = state.annotationCreationProperties(for: .text)
    XCTAssertTrue(AnnotateColorPaletteStore.colorsMatch(properties.fillColor, .yellow))
  }

  func testPlainTextToolDefaultStillReportsItsStoredBackground() throws {
    let suiteName = "AnnotateTextEditingTests.plainReportsFill"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let state = makeAnnotateState(defaults: defaults)
    state.sourceImage = NSImage(size: CGSize(width: 300, height: 200))
    state.selectedTool = .text
    state.annotations = []

    state.quickTextBackgroundBinding.wrappedValue = .yellow
    state.setTextPresentation(.plain)

    XCTAssertTrue(
      AnnotateColorPaletteStore.colorsMatch(state.quickTextBackgroundBinding.wrappedValue, .yellow),
      "a stored background must stay visible to the picker while the text is plain"
    )
  }

  func testTextToolFactoryDefaultsToTextLabel() throws {
    let suiteName = "AnnotateTextEditingTests.textFactoryDefaults"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let state = makeAnnotateState(defaults: defaults)
    state.selectedTool = .text
    state.annotations = []

    let properties = state.annotationCreationProperties(for: .text)

    XCTAssertEqual(properties.textPresentation, .label)
    XCTAssertTrue(AnnotateColorPaletteStore.colorsMatch(properties.fillColor, .white))
    XCTAssertEqual(properties.cornerRadius, AnnotateState.SystemTextStylePreset.cornerRadius)
    XCTAssertTrue(
      AnnotateColorPaletteStore.colorsMatch(properties.strokeColor, .red),
      "annotation text should default to red"
    )
  }

  /// The tooltips used to be hardcoded English literals; they must now resolve
  /// through `L10n` so every locale gets translated copy.
  func testTextPresentationHelpTextComesFromLocalization() {
    XCTAssertEqual(TextPresentation.plain.helpText, L10n.AnnotateUI.textPresentationPlain)
    XCTAssertEqual(TextPresentation.label.helpText, L10n.AnnotateUI.textPresentationLabel)
    XCTAssertEqual(TextPresentation.callout.helpText, L10n.AnnotateUI.textPresentationCallout)

    for presentation in TextPresentation.allCases {
      XCTAssertFalse(presentation.helpText.isEmpty, "\(presentation) needs a tooltip")
    }
    for value in [
      L10n.AnnotateUI.textPresentationPlain,
      L10n.AnnotateUI.textPresentationLabel,
      L10n.AnnotateUI.textPresentationCallout,
      L10n.AnnotateUI.textBackgroundPlainHint,
      L10n.AnnotateUI.textStylePreviewSample,
    ] {
      XCTAssertFalse(value.isEmpty)
    }
  }

  func testFontSizeChangeRemapsCalloutTailRelativeToNewBounds() throws {
    let state = makeAnnotateState()
    state.sourceImage = NSImage(size: CGSize(width: 900, height: 600))
    let annotation = AnnotationItem(
      type: .text("Callout"),
      bounds: CGRect(x: 100, y: 100, width: 160, height: 40),
      properties: AnnotationProperties(strokeColor: .black, fillColor: .white, fontSize: 16, textPresentation: .callout)
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    state.selectedTool = .text
    state.prepareTextCalloutTail(for: annotation.id)
    state.updateTextCalloutTail(id: annotation.id, target: CGPoint(x: 40, y: 360))
    state.useAutomaticTextWidth(for: annotation.id)
    let oldBounds = try XCTUnwrap(state.annotations.first).bounds
    let oldTail = try XCTUnwrap(state.annotations.first?.properties.calloutTailTarget)

    state.updateAnnotationProperties(id: annotation.id, fontSize: 28)

    let after = try XCTUnwrap(state.annotations.first)
    let afterTail = try XCTUnwrap(after.properties.calloutTailTarget)
    XCTAssertEqual(after.properties.fontSize, 28)
    XCTAssertNotEqual(after.bounds.size, oldBounds.size)
    XCTAssertNotEqual(afterTail, oldTail)
    XCTAssertGreaterThan(afterTail.y, after.bounds.maxY)
    XCTAssertGreaterThan(after.bounds.height, oldBounds.height)
  }

  /// A different family measures differently, so changing it has to re-flow the
  /// bubble the same way a size change does. Without the re-measure the label
  /// kept the wrap it was sized for in the old face and clipped the text.
  func testFontNameChangeRemeasuresTextBounds() throws {
    let state = makeAnnotateState()
    state.sourceImage = NSImage(size: CGSize(width: 900, height: 600))
    let annotation = AnnotationItem(
      type: .text("Wrapping horizontally"),
      bounds: CGRect(x: 100, y: 100, width: 160, height: 40),
      properties: AnnotationProperties(
        strokeColor: .black,
        fillColor: .white,
        fontSize: 16,
        fontName: "",
        textPresentation: .label
      )
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    state.selectedTool = .text
    state.useAutomaticTextWidth(for: annotation.id)
    let oldBounds = try XCTUnwrap(state.annotations.first).bounds

    state.updateAnnotationProperties(id: annotation.id, fontName: "Menlo")

    let after = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(after.properties.fontName, "Menlo")
    // Menlo is the wider face at the same point size, and the text is auto-sized,
    // so the bubble must grow with it. The top edge stays anchored.
    XCTAssertGreaterThan(after.bounds.width, oldBounds.width)
    XCTAssertEqual(after.bounds.maxY, oldBounds.maxY, accuracy: 0.001)
  }

  func testFontNameChangeRemapsCalloutTailRelativeToNewBounds() throws {
    let state = makeAnnotateState()
    state.sourceImage = NSImage(size: CGSize(width: 900, height: 600))
    let annotation = AnnotationItem(
      type: .text("Callout"),
      bounds: CGRect(x: 100, y: 100, width: 160, height: 40),
      properties: AnnotationProperties(
        strokeColor: .black,
        fillColor: .white,
        fontSize: 16,
        fontName: "",
        textPresentation: .callout
      )
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    state.selectedTool = .text
    state.prepareTextCalloutTail(for: annotation.id)
    state.updateTextCalloutTail(id: annotation.id, target: CGPoint(x: 40, y: 360))
    state.useAutomaticTextWidth(for: annotation.id)
    let oldBounds = try XCTUnwrap(state.annotations.first).bounds
    let oldTail = try XCTUnwrap(state.annotations.first?.properties.calloutTailTarget)

    state.updateAnnotationProperties(id: annotation.id, fontName: "Menlo")

    let after = try XCTUnwrap(state.annotations.first)
    let afterTail = try XCTUnwrap(after.properties.calloutTailTarget)
    XCTAssertEqual(after.properties.fontName, "Menlo")
    XCTAssertNotEqual(after.bounds.size, oldBounds.size)
    XCTAssertNotEqual(afterTail, oldTail)
    // The tail has to stay outside the wall it is rooted on, which moved.
    XCTAssertGreaterThan(afterTail.y, after.bounds.maxY)
  }

  func testLowContrastTextAndBackgroundRaisesSameColorWarning() {
    let state = makeAnnotateState()
    let annotation = AnnotationItem(
      type: .text("Dim"),
      bounds: CGRect(x: 40, y: 80, width: 120, height: 32),
      properties: AnnotationProperties(strokeColor: .black, fillColor: .black, textPresentation: .label)
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    state.selectedTool = .text

    XCTAssertTrue(state.quickTextUsesSameColorAsBackground)
  }

  func testCornerRadiusPreservedWhenSwitchingTextLabelToCallout() throws {
    let state = makeAnnotateState()
    let annotation = AnnotationItem(
      type: .text("Label"),
      bounds: CGRect(x: 40, y: 80, width: 140, height: 36),
      properties: AnnotationProperties(
        strokeColor: .black,
        fillColor: .white,
        cornerRadius: 18,
        fontSize: 18,
        textPresentation: .label
      )
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    state.selectedTool = .text

    state.setTextPresentation(.callout)

    let updated = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(updated.properties.cornerRadius, 18)
    XCTAssertNotNil(updated.properties.calloutTailTarget)
  }

  /// The first presentation switch re-fits the annotation to its text. Insets no
  /// longer differ by presentation, so this is an auto-size check, not a padding
  /// check — `testSwitchingTextPresentationKeepsBoundsStable` covers the rest.
  func testSwitchingToTextLabelAutoSizesTheAnnotation() throws {
    let state = makeAnnotateState()
    state.sourceImage = NSImage(size: CGSize(width: 600, height: 300))
    var annotation = makeTextAnnotation("Short")
    annotation.properties.fontSize = 18
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    state.selectedTool = .text
    let originalBounds = try XCTUnwrap(state.annotations.first).bounds

    state.setTextPresentation(.label)

    let updated = try XCTUnwrap(state.annotations.first)
    XCTAssertNotEqual(updated.bounds.size, originalBounds.size)
    XCTAssertGreaterThan(updated.bounds.width, 40)
    XCTAssertGreaterThanOrEqual(updated.bounds.height, 20)
  }

  // MARK: - T-01: text presentation survives a restart

  func testTextPresentationToolDefaultSurvivesReload() throws {
    let suiteName = "AnnotateTextEditingTests.presentation.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let first = makeAnnotateState(defaults: defaults)
    first.selectedTool = .text
    first.setTextPresentation(.callout)

    let reloaded = makeAnnotateState(defaults: defaults)
    reloaded.selectedTool = .text
    XCTAssertEqual(reloaded.quickTextPresentation, .callout)

    // History is untouched: the tool default only seeds new annotations.
    XCTAssertTrue(reloaded.annotations.isEmpty)
  }

  // MARK: - T-04: three system presets plus two custom slots

  func testStylePresetSlotsExposeThreeSystemAndTwoCustomSlots() {
    XCTAssertEqual(AnnotateState.systemTextStylePresetCount, 3)
    XCTAssertEqual(AnnotateState.customTextStylePresetSlotCount, 2)
    XCTAssertEqual(AnnotateState.savedTextStylePresetLimit, 5)
  }

  func testSystemStylePresetsAreAlwaysAvailableAndCannotBeDeleted() throws {
    let state = makeAnnotateState()
    let expectedPresentations: [TextPresentation] = [.label, .label, .callout]
    for index in 0 ..< AnnotateState.systemTextStylePresetCount {
      let preset = try XCTUnwrap(state.savedTextStylePreset(at: index))
      XCTAssertEqual(preset.textPresentation, expectedPresentations[index], "preset \(index)")
      XCTAssertFalse(state.canDeleteSavedTextStylePreset(at: index))

      state.deleteSavedTextStylePreset(at: index)
      XCTAssertNotNil(
        state.savedTextStylePreset(at: index),
        "system preset \(index) must survive a delete request"
      )
    }
    XCTAssertTrue(state.isSystemTextStylePreset(at: 0))
    XCTAssertFalse(state.isSystemTextStylePreset(at: AnnotateState.systemTextStylePresetCount))
  }

  func testSavingStylePresetsFillsCustomSlotsThenAsksBeforeOverwriting() throws {
    let suiteName = "AnnotateTextEditingTests.stylePresets.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let state = makeAnnotateState(defaults: defaults)

    let first = makeTextAnnotation("One")
    state.annotations = [first]
    state.selectedAnnotationId = first.id
    state.selectedTool = .text
    XCTAssertEqual(state.saveCurrentTextStylePreset(), .saved)

    var second = makeTextAnnotation("Two")
    second.properties.strokeColor = .red
    second.properties.fontSize = 26
    state.annotations = [second]
    state.selectedAnnotationId = second.id
    XCTAssertEqual(state.saveCurrentTextStylePreset(), .saved)

    // Both custom slots are taken now, so a third style has to be routed
    // through the overwrite prompt instead of silently dropping a slot.
    var third = makeTextAnnotation("Three")
    third.properties.strokeColor = .blue
    third.properties.fontSize = 32
    state.annotations = [third]
    state.selectedAnnotationId = third.id
    XCTAssertEqual(state.saveCurrentTextStylePreset(), .needsOverwriteChoice)

    let customStart = AnnotateState.systemTextStylePresetCount
    XCTAssertTrue(state.canDeleteSavedTextStylePreset(at: customStart))
    XCTAssertTrue(state.overwriteSavedTextStylePreset(at: 0))
    XCTAssertEqual(state.savedTextStylePreset(at: customStart)?.fontSize, 32)
    XCTAssertEqual(state.savedTextStylePresetsCount, 2)

    // Deleting compacts the custom slots rather than leaving a hole.
    state.deleteSavedTextStylePreset(at: customStart)
    XCTAssertEqual(state.savedTextStylePresetsCount, 1)
    state.deleteSavedTextStylePreset(at: customStart)
    XCTAssertEqual(state.savedTextStylePresetsCount, 0)
    XCTAssertNil(state.savedTextStylePreset(at: customStart))
    XCTAssertFalse(state.canDeleteSavedTextStylePreset(at: customStart))
  }

  func testSavingAStyleThatAlreadyHasASlotRefreshesItInsteadOfAskingAgain() throws {
    let suiteName = "AnnotateTextEditingTests.styleRefresh.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let state = makeAnnotateState(defaults: defaults)

    let annotation = makeTextAnnotation("Same")
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    state.selectedTool = .text

    XCTAssertEqual(state.saveCurrentTextStylePreset(), .saved)
    XCTAssertEqual(state.saveCurrentTextStylePreset(), .saved)
    XCTAssertEqual(state.savedTextStylePresetsCount, 1)
  }

  func testApplyingAStylePresetKeepsThePlacedCalloutTail() throws {
    let suiteName = "AnnotateTextEditingTests.styleTail.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let state = makeAnnotateState(defaults: defaults)
    state.sourceImage = NSImage(size: CGSize(width: 600, height: 400))

    let annotation = AnnotationItem(
      type: .text("Target"),
      bounds: CGRect(x: 100, y: 100, width: 180, height: 48),
      properties: AnnotationProperties(fillColor: .white, textPresentation: .callout)
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    state.selectedTool = .text
    state.prepareTextCalloutTail(for: annotation.id)
    let placedTail = try XCTUnwrap(state.annotations.first?.properties.calloutTailTarget)

    // The built-in callout preset is a style, not a position: applying it must
    // leave the arrow pointing where the user put it.
    state.applySavedTextStylePreset(at: 2)

    let updated = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(updated.properties.textPresentation, .callout)
    XCTAssertEqual(updated.properties.calloutTailTarget?.x ?? .nan, placedTail.x, accuracy: 0.01)
    XCTAssertEqual(updated.properties.calloutTailTarget?.y ?? .nan, placedTail.y, accuracy: 0.01)
  }

  /// Matching runs on the fields the text renderer actually paints, so two styles
  /// that differ in one of them must take separate slots rather than refreshing
  /// each other's.
  func testVisiblyDifferentTextStylesTakeSeparatePresetSlots() throws {
    let suiteName = "AnnotateTextEditingTests.styleDistinct.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let state = makeAnnotateState(defaults: defaults)
    state.selectedTool = .text

    var first = makeTextAnnotation("One")
    first.properties.fillColor = .white
    first.properties.cornerRadius = 8
    state.annotations = [first]
    state.selectedAnnotationId = first.id
    XCTAssertEqual(state.saveCurrentTextStylePreset(), .saved)

    // Identical apart from the corner radius, which is painted for a `.label`.
    var second = first
    second.properties.cornerRadius = 24
    state.annotations = [second]
    state.selectedAnnotationId = second.id
    XCTAssertEqual(state.saveCurrentTextStylePreset(), .saved)

    let customStart = AnnotateState.systemTextStylePresetCount
    XCTAssertEqual(state.savedTextStylePresetsCount, 2)
    XCTAssertEqual(state.savedTextStylePreset(at: customStart)?.cornerRadius, 8)
    XCTAssertEqual(state.savedTextStylePreset(at: customStart + 1)?.cornerRadius, 24)
  }

  /// The shape, dash, rotation and alpha fields are inert for `.text` — the renderer
  /// reads `textBorderWidth` for the outline and only consumes those four in the
  /// shape, arrow and watermark branches. Two presets that differ only in them paint
  /// identically, so they are the same style and share one slot on purpose. Widening
  /// the comparison instead would make the highlight stop matching presets that look
  /// exactly like the selection.
  func testInertTextFieldsDoNotConsumeASecondPresetSlot() throws {
    let suiteName = "AnnotateTextEditingTests.styleInert.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let state = makeAnnotateState(defaults: defaults)
    state.selectedTool = .text

    var first = makeTextAnnotation("One")
    first.properties.fillColor = .white
    first.properties.strokeWidth = 2
    state.annotations = [first]
    state.selectedAnnotationId = first.id
    XCTAssertEqual(state.saveCurrentTextStylePreset(), .saved)

    var second = first
    second.properties.strokeWidth = 9
    second.properties.lineStyle = .dotted
    second.properties.opacity = 0.5
    second.properties.rotationDegrees = 12
    state.annotations = [second]
    state.selectedAnnotationId = second.id
    XCTAssertEqual(state.saveCurrentTextStylePreset(), .saved)

    XCTAssertEqual(state.savedTextStylePresetsCount, 1)
  }

  /// Clicking a preset the UI already highlights must not change the annotation.
  /// `strokeWidth` is not part of the text look, but the selection chrome reads it
  /// (`selectionBounds` padding and the hit-test tolerance), so copying it out of a
  /// preset would move the handles for no visible reason on a control that claimed
  /// to be a no-op.
  func testApplyingAHighlightedStylePresetChangesNothing() throws {
    let suiteName = "AnnotateTextEditingTests.styleNoop.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let state = makeAnnotateState(defaults: defaults)
    state.selectedTool = .text

    var annotation = makeTextAnnotation("Stable")
    annotation.properties.strokeWidth = 7
    annotation.properties.opacity = 0.42
    annotation.properties.rotationDegrees = 15
    annotation.properties.lineStyle = .dashed
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    XCTAssertEqual(state.saveCurrentTextStylePreset(), .saved)

    let slot = AnnotateState.systemTextStylePresetCount

    // Drift the inert fields away from the preset, the way another tool's defaults
    // could. None of them paints anything for a text annotation.
    var drifted = try XCTUnwrap(state.annotations.first)
    drifted.properties.strokeWidth = 3
    drifted.properties.opacity = 1
    drifted.properties.rotationDegrees = 0
    drifted.properties.lineStyle = .solid
    state.annotations = [drifted]

    XCTAssertTrue(state.isSavedTextStylePresetSelected(at: slot))

    state.applySavedTextStylePreset(at: slot)

    let applied = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(applied.properties.strokeWidth, 3, accuracy: 0.0001)
    XCTAssertEqual(applied.properties.opacity, 1, accuracy: 0.0001)
    XCTAssertEqual(applied.properties.rotationDegrees, 0, accuracy: 0.0001)
    XCTAssertEqual(applied.properties.lineStyle, .solid)
    // The visible style still matches the preset, so the highlight stays honest.
    XCTAssertTrue(state.isSavedTextStylePresetSelected(at: slot))
  }

  /// Save and highlight must answer with the same predicate. A stored value outside
  /// the control range is clamped on the way into the preset, so the raw annotation
  /// side has to be clamped too or the preset could never match the annotation it
  /// was just saved from.
  func testAnOutOfRangeStoredFontSizeStillHighlightsItsOwnPreset() throws {
    let suiteName = "AnnotateTextEditingTests.styleClamp.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let state = makeAnnotateState(defaults: defaults)
    state.selectedTool = .text

    var annotation = makeTextAnnotation("Huge")
    annotation.properties.fontSize = 200
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id

    XCTAssertEqual(state.saveCurrentTextStylePreset(), .saved)

    let slot = AnnotateState.systemTextStylePresetCount
    XCTAssertTrue(state.isSavedTextStylePresetSelected(at: slot))
  }

  // MARK: - T-06: toolbar follows the selected annotation

  func testToolbarPresentationFollowsSelectedAnnotation() throws {
    let state = makeAnnotateState()
    let annotation = AnnotationItem(
      type: .text("Sync"),
      bounds: CGRect(x: 30, y: 30, width: 140, height: 40),
      properties: AnnotationProperties(fillColor: .white, textPresentation: .callout)
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    state.selectedTool = .text

    XCTAssertEqual(state.quickTextPresentation, .callout)

    state.setTextPresentation(.label)
    XCTAssertEqual(state.quickTextPresentation, .label)

    state.setTextPresentation(.plain)
    XCTAssertEqual(state.quickTextPresentation, .plain)
  }

  /// The "text and background are the same colour" warning describes a surface the
  /// user can see. `.plain` paints no bubble, so the fill it still stores — kept on
  /// purpose so the switch back finds it — must not raise the warning. Nothing is
  /// cleared along the way: going back to `.label` restores both the container and
  /// the warning.
  func testPlainTextDoesNotWarnAboutAMatchingStoredFill() throws {
    let suiteName = "AnnotateTextEditingTests.plainFillWarning.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let state = makeAnnotateState(defaults: defaults)
    state.selectedTool = .text

    // Black on a black fill: unreadable while the bubble is drawn, and the text has
    // enough contrast against the (unsampled) white backdrop that the plain-mode
    // readability protection leaves the colour alone.
    let annotation = AnnotationItem(
      type: .text("Same"),
      bounds: CGRect(x: 20, y: 20, width: 140, height: 32),
      properties: AnnotationProperties(strokeColor: .black, fillColor: .black, textPresentation: .label)
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id

    XCTAssertTrue(state.quickTextHasBackground)
    XCTAssertTrue(state.quickTextHasVisibleContainer)
    XCTAssertTrue(state.quickTextUsesSameColorAsBackground)

    state.setTextPresentation(.plain)

    // The fill and the text colour survive the switch untouched ...
    XCTAssertTrue(state.quickTextHasBackground)
    XCTAssertEqual(state.quickTextStrokeColor, .black)
    // ... but no container is painted, so there is no background to collide with.
    XCTAssertEqual(state.quickTextPresentation, .plain)
    XCTAssertFalse(state.quickTextHasVisibleContainer)
    XCTAssertFalse(state.quickTextUsesSameColorAsBackground)

    state.setTextPresentation(.label)

    XCTAssertTrue(state.quickTextHasVisibleContainer)
    XCTAssertTrue(state.quickTextUsesSameColorAsBackground)
  }

  // MARK: - T-09: five font slots

  func testFontMenuStartsWithTheThreeBuiltInFaces() throws {
    // Isolated suite: the menu appends whatever custom fonts the machine has saved,
    // so `makeAnnotateState()` would read the developer's real preferences and see
    // more than the built-in faces. This asserts the built-in prefix on a fresh store.
    let suiteName = "AnnotateTextEditingTests.fontMenu.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let state = makeAnnotateState(defaults: defaults)

    XCTAssertEqual(AnnotateTextLayout.fixedTextFontOptions.count, 3)
    XCTAssertEqual(state.textFontOptions, AnnotateTextLayout.fixedTextFontOptions)
    XCTAssertEqual(state.textFontOptions.count, AnnotateState.textFontOptionLimit - 2)
  }

  func testCustomFontsFillTwoSlotsThenReportFullAndCanBeDeleted() throws {
    let suiteName = "AnnotateTextEditingTests.fonts.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let state = makeAnnotateState(defaults: defaults)

    XCTAssertTrue(state.saveTextFont("Courier"))
    XCTAssertTrue(state.saveTextFont("Georgia"))
    XCTAssertEqual(state.savedTextFontNamesCount, 2)
    XCTAssertEqual(state.textFontOptions.count, AnnotateState.textFontOptionLimit)

    // Both slots are taken: the third font has to go through the overwrite
    // prompt rather than silently displacing a saved one.
    XCTAssertFalse(state.saveTextFont("Papyrus"))

    // Saving a font that already has a slot is idempotent, not an error.
    XCTAssertTrue(state.saveTextFont("Courier"))
    XCTAssertEqual(state.savedTextFontNamesCount, 2)

    // The built-in faces never occupy a custom slot.
    XCTAssertFalse(state.saveTextFont("Menlo"))
    XCTAssertEqual(state.savedTextFontNamesCount, 2)

    state.overwriteSavedTextFont(at: 0, with: "Papyrus")
    XCTAssertEqual(state.savedTextFontName(at: 0), "Papyrus")

    state.deleteSavedTextFont(at: 0)
    XCTAssertNil(state.savedTextFontName(at: 0))
    XCTAssertFalse(state.canDeleteSavedTextFont(at: 0))
    XCTAssertTrue(state.saveTextFont("Papyrus"))
  }

  func testCustomFontsSurviveReload() throws {
    let suiteName = "AnnotateTextEditingTests.fontsReload.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let first = makeAnnotateState(defaults: defaults)
    XCTAssertTrue(first.saveTextFont("Courier"))

    let reloaded = makeAnnotateState(defaults: defaults)
    XCTAssertEqual(reloaded.savedTextFontName(at: 0), "Courier")
    XCTAssertTrue(reloaded.textFontOptions.contains("Courier"))
  }

  // MARK: - Image-relative system preset sizes

  func testSystemStylePresetFontSizeTracksTheCanvasInsteadOfAFixedPointSize() throws {
    let state = makeAnnotateState()
    state.sourceImage = NSImage(size: CGSize(width: 1600, height: 900))
    let largeCanvasSize = state.recommendedTextFontSize()

    for index in 0 ..< AnnotateState.systemTextStylePresetCount {
      XCTAssertEqual(
        state.savedTextStylePreset(at: index)?.fontSize,
        largeCanvasSize,
        "system preset \(index) must not be pinned to a fixed point size"
      )
    }

    state.sourceImage = NSImage(size: CGSize(width: 480, height: 1200))
    let smallCanvasSize = state.recommendedTextFontSize()

    XCTAssertLessThan(smallCanvasSize, largeCanvasSize)
    for index in 0 ..< AnnotateState.systemTextStylePresetCount {
      XCTAssertEqual(state.savedTextStylePreset(at: index)?.fontSize, smallCanvasSize)
    }
  }

  func testApplyingASystemPresetStillReadsAsSelectedAfterTheSizeIsDerived() throws {
    let state = makeAnnotateState()
    state.sourceImage = NSImage(size: CGSize(width: 1600, height: 900))
    let annotation = makeTextAnnotation("Selected")
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    state.selectedTool = .text

    state.applySavedTextStylePreset(at: 0)

    XCTAssertTrue(
      state.isSavedTextStylePresetSelected(at: 0),
      "the applied preset must keep matching the annotation it produced"
    )
  }

  func testCustomStylePresetsKeepThePointSizeTheUserSaved() throws {
    let suiteName = "AnnotateTextEditingTests.customPresetSize.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let state = makeAnnotateState(defaults: defaults)
    state.sourceImage = NSImage(size: CGSize(width: 1600, height: 900))

    var annotation = makeTextAnnotation("Custom")
    annotation.properties.fontSize = 44
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id
    state.selectedTool = .text
    XCTAssertEqual(state.saveCurrentTextStylePreset(), .saved)

    let slot = AnnotateState.systemTextStylePresetCount
    XCTAssertEqual(state.savedTextStylePreset(at: slot)?.fontSize, 44)
    XCTAssertNotEqual(state.savedTextStylePreset(at: slot)?.fontSize, state.recommendedTextFontSize())
  }
}
