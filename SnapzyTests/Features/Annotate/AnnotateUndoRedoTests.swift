//
//  AnnotateUndoRedoTests.swift
//  SnapzyTests
//
//  Characterization tests for AnnotateState undo/redo checkpoint semantics:
//  saveState pushes a snapshot, undo restores the prior snapshot, redo reapplies
//  it, and a new mutating checkpoint after undo invalidates the redo stack.
//  Text-specific undo/redo is already covered in AnnotateCoreTests; these lock
//  down the generic stack contract via canUndo/canRedo + annotation snapshots.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class AnnotateUndoRedoTests: XCTestCase {
  @MainActor private static var retainedAnnotateStates: [AnnotateState] = []

  @MainActor
  private func makeAnnotateState() -> AnnotateState {
    let state = AnnotateState()
    Self.retainedAnnotateStates.append(state)
    return state
  }

  @MainActor
  private func makeRectangle() -> AnnotationItem {
    AnnotationItem(
      type: .rectangle,
      bounds: CGRect(x: 10, y: 10, width: 40, height: 40),
      properties: AnnotationProperties()
    )
  }

  @MainActor
  func testSaveStateEnablesUndoAndMarksUnsavedChanges() {
    let state = makeAnnotateState()
    XCTAssertFalse(state.canUndo)
    XCTAssertFalse(state.canRedo)

    state.saveState()

    XCTAssertTrue(state.canUndo)
    XCTAssertFalse(state.canRedo)
    XCTAssertTrue(state.hasUnsavedChanges)
  }

  @MainActor
  func testUndoRestoresPriorAnnotationSnapshotAndEnablesRedo() {
    let state = makeAnnotateState()

    state.saveState()
    state.annotations = [makeRectangle()]

    XCTAssertEqual(state.annotations.count, 1)

    state.undo()

    XCTAssertTrue(state.annotations.isEmpty)
    XCTAssertFalse(state.canUndo)
    XCTAssertTrue(state.canRedo)
  }

  @MainActor
  func testRedoReappliesUndoneAnnotationSnapshot() {
    let state = makeAnnotateState()

    state.saveState()
    let rectangle = makeRectangle()
    state.annotations = [rectangle]

    state.undo()
    XCTAssertTrue(state.annotations.isEmpty)

    state.redo()

    XCTAssertEqual(state.annotations.count, 1)
    XCTAssertEqual(state.annotations.first?.id, rectangle.id)
    XCTAssertTrue(state.canUndo)
    XCTAssertFalse(state.canRedo)
  }

  @MainActor
  func testUndoWithoutCheckpointIsNoOp() {
    let state = makeAnnotateState()
    state.annotations = [makeRectangle()]

    state.undo()

    XCTAssertEqual(state.annotations.count, 1)
    XCTAssertFalse(state.canUndo)
    XCTAssertFalse(state.canRedo)
  }

  @MainActor
  func testNewCheckpointAfterUndoInvalidatesRedoStack() {
    let state = makeAnnotateState()

    state.saveState()
    state.annotations = [makeRectangle()]

    state.undo()
    XCTAssertTrue(state.canRedo)

    // A fresh checkpoint (new mutating action) must clear the redo stack.
    state.saveState()

    XCTAssertFalse(state.canRedo)
    XCTAssertTrue(state.canUndo)
  }

  @MainActor
  func testSequentialCheckpointsUndoInReverseOrder() throws {
    let state = makeAnnotateState()
    let first = makeRectangle()
    let second = AnnotationItem(
      type: .oval,
      bounds: CGRect(x: 60, y: 60, width: 30, height: 30),
      properties: AnnotationProperties()
    )

    state.saveState()
    state.annotations = [first]
    state.saveState()
    state.annotations = [first, second]

    state.undo()
    XCTAssertEqual(state.annotations.map(\.id), [first.id])

    state.undo()
    XCTAssertTrue(state.annotations.isEmpty)
    XCTAssertFalse(state.canUndo)
  }

  @MainActor
  func testDuplicateSelectionIsAtomicAndUndoRedoRestoresSelection() {
    let state = makeAnnotateState()
    let first = makeRectangle()
    let second = AnnotationItem(
      type: .oval,
      bounds: CGRect(x: 80, y: 80, width: 30, height: 30),
      properties: AnnotationProperties()
    )
    state.annotations = [first, second]
    state.setSelectedAnnotationIds([first.id, second.id])

    XCTAssertTrue(state.duplicateSelectedAnnotations())
    let duplicatedIds = Set(state.annotations.suffix(2).map(\.id))
    XCTAssertEqual(state.annotations.count, 4)
    XCTAssertEqual(state.selectedAnnotationIds, duplicatedIds)

    state.undo()
    XCTAssertEqual(state.annotations.map(\.id), [first.id, second.id])
    XCTAssertEqual(state.selectedAnnotationIds, [first.id, second.id])
    XCTAssertFalse(state.canUndo)
    XCTAssertTrue(state.canRedo)

    state.redo()
    XCTAssertEqual(state.annotations.count, 4)
    XCTAssertEqual(state.selectedAnnotationIds, duplicatedIds)
    XCTAssertTrue(state.canUndo)
    XCTAssertFalse(state.canRedo)
  }
}
