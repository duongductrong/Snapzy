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

  func testManualTextResizeKeepsFixedWidthWhileEditing() throws {
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
    XCTAssertEqual(updated.bounds.width, 180, accuracy: 0.5)
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
    XCTAssertTrue(AnnotateColorPaletteStore.colorsMatch(updated.properties.fillColor, .clear))
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

  func testBubbleWidthAndInsetsGrowWithFontAndPresentation() {
    let font = AnnotateTextLayout.font(size: 20)
    let plainWidth = AnnotateTextLayout.preferredAutoWidth(
      text: "Note",
      font: font,
      minimumWidth: AnnotateTextLayout.minWidth,
      presentation: .plain
    )
    let bubbleWidth = AnnotateTextLayout.preferredAutoWidth(
      text: "Note",
      font: font,
      minimumWidth: AnnotateTextLayout.minWidth,
      presentation: .callout
    )
    let bounds = AnnotateTextLayout.bounds(
      text: "Note",
      font: font,
      origin: .zero,
      constrainedWidth: bubbleWidth,
      presentation: .callout
    )

    XCTAssertGreaterThan(bubbleWidth, plainWidth)
    XCTAssertGreaterThan(bounds.height, AnnotateTextLayout.minimumHeight(for: font, presentation: .plain))
    XCTAssertGreaterThan(TextBubbleGeometry.cornerRadius(in: bounds, fontSize: font.pointSize), 0)
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
    let tailBounds = TextBubbleGeometry.tailPath(in: bounds, to: target, fontSize: 20).boundingBoxOfPath

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

  func testNewCalloutTextStartsWithItsOwnDefaultTailInsteadOfInheritingPreviousTail() throws {
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

    let second = AnnotationItem(
      type: .text("Second"),
      bounds: CGRect(x: 220, y: 80, width: 140, height: 40),
      properties: AnnotationProperties(fillColor: .black, fontSize: 18, textPresentation: .callout)
    )
    state.annotations.append(second)
    state.prepareTextCalloutTail(for: second.id)

    let secondTail = try XCTUnwrap(state.annotations.last?.properties.calloutTailTarget)
    let expectedTail = TextBubbleGeometry.defaultTailTarget(for: second.bounds, fontSize: 18)
    XCTAssertEqual(secondTail.x, expectedTail.x, accuracy: 0.5)
    XCTAssertEqual(secondTail.y, expectedTail.y, accuracy: 0.5)
  }

  func testCalloutTailChangesAttachmentSideAsTheTargetMoves() {
    let bounds = CGRect(x: 100, y: 100, width: 180, height: 48)

    let left = TextBubbleGeometry.tailPath(
      in: bounds,
      to: CGPoint(x: 45, y: bounds.midY),
      fontSize: 20
    ).boundingBoxOfPath
    let right = TextBubbleGeometry.tailPath(
      in: bounds,
      to: CGPoint(x: 335, y: bounds.midY),
      fontSize: 20
    ).boundingBoxOfPath
    let centered = TextBubbleGeometry.tailPath(
      in: bounds,
      to: CGPoint(x: bounds.midX, y: 74),
      fontSize: 20
    ).boundingBoxOfPath

    XCTAssertLessThan(left.minX, bounds.minX)
    XCTAssertGreaterThan(right.maxX, bounds.maxX)
    XCTAssertLessThan(centered.minY, bounds.minY)
    XCTAssertEqual(centered.midX, bounds.midX, accuracy: 0.5)
  }

  func testCalloutTailReachStaysClampedToTheBubble() {
    let bounds = CGRect(x: 100, y: 100, width: 180, height: 48)
    let requested = CGPoint(x: 200, y: -600)
    let resolved = TextBubbleGeometry.resolvedTailTarget(
      in: bounds,
      requestedTarget: requested,
      fontSize: 20
    )
    XCTAssertEqual(resolved.x, requested.x, accuracy: 0.5)
    XCTAssertEqual(resolved.y, bounds.minY - 80, accuracy: 0.5)
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
        textBorderWidth: 2
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

  func testTextLabelWithClearBackgroundAutomaticallyConvertsToPlainText() throws {
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
    XCTAssertEqual(updated.properties.textPresentation, .plain)
    XCTAssertTrue(AnnotateColorPaletteStore.isClear(updated.properties.fillColor))
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
    XCTAssertNil(updated.properties.calloutTailTarget)
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
}
