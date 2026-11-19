//
//  AnnotateAgentToolboxTests.swift
//  SnapzyTests
//
//  Annotate AI prompt, phase 1: tool calls → annotations. Coordinates (agent space
//  is top-left), one undo per run, argument validation, stable ids.
//

import AppKit
import CoreGraphics
import SwiftUI
import XCTest
@testable import Snapzy

@MainActor
final class AnnotateAgentToolboxTests: XCTestCase {
  private static var retainedAnnotateStates: [AnnotateState] = []

  private let imageSize = CGSize(width: 800, height: 600)

  private func makeState() throws -> AnnotateState {
    let state = AnnotateState()
    Self.retainedAnnotateStates.append(state)
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: Int(imageSize.width), height: Int(imageSize.height)))
    state.loadImage(NSImage(cgImage: cgImage, size: imageSize))
    return state
  }

  /// "Sign in" near the TOP of the image (Vision y 0.90…0.95) and a two-row paragraph lower down.
  private func makeAnalysis() -> AnnotateAgentImageAnalysis {
    let signIn = OCRTextBlock(
      text: "Sign in",
      box: CGRect(x: 0.40, y: 0.90, width: 0.10, height: 0.05),
      rowBoxes: [CGRect(x: 0.40, y: 0.90, width: 0.10, height: 0.05)]
    )
    let paragraph = OCRTextBlock(
      text: "Forgot your password? Reset it here",
      box: CGRect(x: 0.10, y: 0.40, width: 0.50, height: 0.10),
      rowBoxes: [
        CGRect(x: 0.10, y: 0.45, width: 0.50, height: 0.05),
        CGRect(x: 0.10, y: 0.40, width: 0.30, height: 0.05),
      ]
    )
    let email = OCRTextBlock(
      text: "trường@example.com",
      box: CGRect(x: 0.60, y: 0.10, width: 0.25, height: 0.04),
      rowBoxes: [CGRect(x: 0.60, y: 0.10, width: 0.25, height: 0.04)]
    )
    return AnnotateAgentImageAnalysis(
      textBlocks: AnnotateAgentImageAnalysis.textBlocks(from: [signIn, paragraph, email], imageSize: imageSize),
      elements: [CGRect(x: 300, y: 500, width: 200, height: 60)]
    )
  }

  private func makeToolbox() throws -> (AnnotateState, AnnotateAgentToolbox) {
    let state = try makeState()
    let toolbox = AnnotateAgentToolbox(state: state, analysis: makeAnalysis())
    toolbox.beginRun()
    return (state, toolbox)
  }

  @discardableResult
  private func call(_ toolbox: AnnotateAgentToolbox, _ name: String, _ json: String) -> [String: Any] {
    let result = toolbox.execute(name: name, argumentsJSON: json)
    let object = (try? JSONSerialization.jsonObject(with: Data(result.text.utf8))) as? [String: Any] ?? [:]
    return object
  }

  @discardableResult
  private func callOK(_ toolbox: AnnotateAgentToolbox, _ name: String, _ json: String, file: StaticString = #filePath, line: UInt = #line) -> [String: Any] {
    let result = toolbox.execute(name: name, argumentsJSON: json)
    XCTAssertFalse(result.isError, result.text, file: file, line: line)
    return (try? JSONSerialization.jsonObject(with: Data(result.text.utf8))) as? [String: Any] ?? [:]
  }

  // MARK: - Targets & coordinates

  func testTargetDecodesEveryShape() throws {
    let decoder = JSONDecoder()
    func decode(_ json: String) throws -> AnnotateAgentTarget {
      try decoder.decode(AnnotateAgentTarget.self, from: Data(json.utf8))
    }
    XCTAssertEqual(try decode(#""t3""#), .reference("t3"))
    XCTAssertEqual(try decode(#""Sign in""#), .text("Sign in"))
    XCTAssertEqual(try decode(#"{"text":"OK"}"#), .text("OK"))
    XCTAssertEqual(try decode(#"{"id":"a2"}"#), .reference("a2"))
    XCTAssertEqual(try decode(#"{"element":"e1"}"#), .reference("e1"))
    XCTAssertEqual(try decode(#"{"rect":[1,2,3,4]}"#), .rect(CGRect(x: 1, y: 2, width: 3, height: 4)))
    XCTAssertEqual(try decode(#"{"point":[5,6]}"#), .point(CGPoint(x: 5, y: 6)))
    XCTAssertEqual(try decode(#"[5,6]"#), .point(CGPoint(x: 5, y: 6)))
    XCTAssertEqual(try decode(#"{"x":1,"y":2,"width":3,"height":4}"#), .rect(CGRect(x: 1, y: 2, width: 3, height: 4)))
    XCTAssertThrowsError(try decode(#"{"foo":1}"#))
  }

  func testTextNearTopOfImageIsReportedNearTopInAgentSpace() throws {
    let (state, toolbox) = try makeToolbox()
    let analysis = toolbox.analysis

    // Annotate space is bottom-left: text at the top has a large y.
    let signIn = try XCTUnwrap(analysis.textBlocks.first)
    XCTAssertEqual(signIn.bounds.maxY, 0.95 * imageSize.height, accuracy: 0.5)

    // Agent space is top-left: the same block sits near y = 0.
    let scene = try XCTUnwrap(toolbox.scene())
    let rect = try XCTUnwrap(scene.texts.first).rect.rect
    XCTAssertEqual(rect.minY, 0.05 * imageSize.height, accuracy: 0.5)
    XCTAssertEqual(scene.image.width, 800)
    XCTAssertEqual(scene.image.height, 600)
    XCTAssertEqual(state.annotations.count, 0)
  }

  func testRectTargetIsFlippedIntoAnnotateSpace() throws {
    let (state, toolbox) = try makeToolbox()
    callOK(toolbox, "add_box", #"{"target":{"rect":[10,20,100,50]},"padding":0}"#)

    let item = try XCTUnwrap(state.annotations.last)
    XCTAssertEqual(item.type, .rectangle)
    XCTAssertEqual(item.bounds.minX, 10, accuracy: 0.5)
    XCTAssertEqual(item.bounds.minY, imageSize.height - 70, accuracy: 0.5)
    XCTAssertEqual(item.bounds.width, 100, accuracy: 0.5)
    XCTAssertEqual(item.bounds.height, 50, accuracy: 0.5)
  }

  func testBoxAroundTextEnclosesTheBlockWithPadding() throws {
    let (state, toolbox) = try makeToolbox()
    let result = callOK(toolbox, "add_box", #"{"target":"Sign in","color":"blue"}"#)
    XCTAssertEqual(result["id"] as? String, "a1")

    let item = try XCTUnwrap(state.annotations.first)
    let block = toolbox.analysis.textBlocks[0].bounds
    XCTAssertTrue(item.bounds.contains(block))
    XCTAssertEqual(item.bounds.minX, block.minX - 6, accuracy: 0.5)
    XCTAssertEqual(AnnotateAgentColor.describe(item.properties.strokeColor), "blue")
  }

  func testUnknownTextAndOutOfImageRectAreReadableErrors() throws {
    let (state, toolbox) = try makeToolbox()
    let missing = toolbox.execute(name: "add_box", argumentsJSON: #"{"target":"Checkout"}"#)
    XCTAssertTrue(missing.isError)
    XCTAssertTrue(missing.text.contains("Checkout"))

    let outside = toolbox.execute(name: "add_box", argumentsJSON: #"{"target":{"rect":[2000,2000,10,10]}}"#)
    XCTAssertTrue(outside.isError)
    XCTAssertTrue(outside.text.contains("800×600"))

    let badColor = toolbox.execute(name: "add_box", argumentsJSON: #"{"target":"t1","color":"sparkly"}"#)
    XCTAssertTrue(badColor.isError)
    XCTAssertTrue(badColor.text.contains("#RRGGBB"))

    XCTAssertTrue(toolbox.execute(name: "make_coffee", argumentsJSON: "{}").isError)
    XCTAssertTrue(toolbox.execute(name: "add_box", argumentsJSON: "{}").isError)

    XCTAssertTrue(state.annotations.isEmpty)
    XCTAssertFalse(state.canUndo, "failed calls must not leave an undo step")
  }

  // MARK: - Undo transaction

  func testWholeRunIsOneUndoStep() throws {
    let (state, toolbox) = try makeToolbox()
    let existing = AnnotationItem(type: .rectangle, bounds: CGRect(x: 0, y: 0, width: 20, height: 20), properties: AnnotationProperties())
    state.annotations = [existing]

    callOK(toolbox, "add_box", #"{"target":"t1"}"#)
    callOK(toolbox, "add_arrow", #"{"to":"t2"}"#)
    callOK(toolbox, "add_counter", #"{"target":"t1"}"#)
    callOK(toolbox, "update_annotation", #"{"id":"a1","color":"green"}"#)
    XCTAssertEqual(state.annotations.count, 4)

    state.undo()
    XCTAssertEqual(state.annotations.map(\.id), [existing.id])
    XCTAssertFalse(state.canUndo)
  }

  func testReadOnlyRunLeavesNoUndoStep() throws {
    let (state, toolbox) = try makeToolbox()
    XCTAssertFalse(toolbox.execute(name: "get_scene", argumentsJSON: "").isError)
    let found = callOK(toolbox, "find_text", #"{"query":"PASSWORD"}"#)
    let matches = try XCTUnwrap(found["matches"] as? [[String: Any]])
    XCTAssertEqual(matches.first?["id"] as? String, "t2")
    XCTAssertFalse(state.canUndo)
  }

  func testFinishRunSelectsCreatedItemsAndNextRunGetsItsOwnUndo() throws {
    let (state, toolbox) = try makeToolbox()
    callOK(toolbox, "add_box", #"{"target":"t1"}"#)
    callOK(toolbox, "add_blur", #"{"target":"t3"}"#)
    let summary = toolbox.finishRun()
    XCTAssertEqual(summary.createdAnnotationIDs.count, 2)
    XCTAssertEqual(state.selectedAnnotationIds, Set(summary.createdAnnotationIDs))

    toolbox.beginRun()
    // Ids survive across prompts of the same conversation.
    callOK(toolbox, "update_annotation", ##"{"id":"a1","color":"#00FF00"}"##)
    state.undo()
    XCTAssertEqual(state.annotations.count, 2, "undo only reverts the second run")
    state.undo()
    XCTAssertTrue(state.annotations.isEmpty)
  }

  // MARK: - Tools

  func testArrowPointsAtTargetFromFreeSpace() throws {
    let (state, toolbox) = try makeToolbox()
    callOK(toolbox, "add_arrow", #"{"to":"e1","color":"red"}"#)
    guard case .arrow(let geometry) = try XCTUnwrap(state.annotations.first).type else {
      return XCTFail("expected an arrow")
    }
    let element = toolbox.analysis.elements[0]
    XCTAssertFalse(element.contains(geometry.start), "starts outside the target")
    XCTAssertLessThan(element.insetBy(dx: -8, dy: -8).contains(geometry.end) ? 0 : 1, 1, "ends at the target's edge")
    XCTAssertTrue(state.sourceImageBounds.contains(geometry.start))
  }

  func testEdgePointStopsAtBorderPlusGap() {
    let rect = CGRect(x: 0, y: 0, width: 100, height: 50)
    let point = AnnotateAgentToolbox.edgePoint(of: rect, toward: CGPoint(x: 300, y: 25), gap: 6)
    XCTAssertEqual(point.x, 106, accuracy: 0.01)
    XCTAssertEqual(point.y, 25, accuracy: 0.01)
    XCTAssertEqual(AnnotateAgentToolbox.edgePoint(of: rect, toward: CGPoint(x: 10, y: 10), gap: 6), CGPoint(x: 50, y: 25))
  }

  func testCalloutSitsBesideTargetAndPointsAtIt() throws {
    let (state, toolbox) = try makeToolbox()
    callOK(toolbox, "add_text", #"{"text":"Click here","target":"t1","color":"red"}"#)
    let item = try XCTUnwrap(state.annotations.first)
    guard case .text("Click here") = item.type else { return XCTFail("expected text") }
    XCTAssertEqual(item.properties.textPresentation, .callout)
    let target = toolbox.analysis.textBlocks[0].bounds
    XCTAssertFalse(item.bounds.intersects(target))
    XCTAssertTrue(state.sourceImageBounds.contains(item.bounds))
    let tail = try XCTUnwrap(item.properties.calloutTailTarget)
    XCTAssertEqual(tail.x, target.midX, accuracy: 1)
    XCTAssertEqual(tail.y, target.midY, accuracy: 1)
    XCTAssertEqual(AnnotateAgentColor.describe(item.properties.fillColor), "red")
  }

  func testHighlightMakesOneBarPerTextRow() throws {
    let (state, toolbox) = try makeToolbox()
    let result = callOK(toolbox, "add_highlight", #"{"target":"t2"}"#)
    XCTAssertEqual((result["ids"] as? [String])?.count, 2)
    XCTAssertEqual(state.annotations.count, 2)
    XCTAssertTrue(state.annotations.allSatisfy { $0.type.isHighlight })
  }

  func testCountersNumberThemselvesInOrder() throws {
    let (state, toolbox) = try makeToolbox()
    callOK(toolbox, "add_counter", #"{"target":"t1"}"#)
    callOK(toolbox, "add_counter", #"{"target":"t2"}"#)
    callOK(toolbox, "add_counter", #"{"target":"t3","number":7}"#)
    let values = state.annotations.compactMap { item -> Int? in
      if case .counter(let value) = item.type { return value }
      return nil
    }
    XCTAssertEqual(values, [1, 2, 7])
  }

  func testUpdateMoveDeleteAndArrange() throws {
    let (state, toolbox) = try makeToolbox()
    callOK(toolbox, "add_box", #"{"target":"t1"}"#)
    callOK(toolbox, "add_text", #"{"text":"Note"}"#)

    callOK(toolbox, "update_annotation", #"{"id":"a2","style":"plain","color":"green","text":"Updated","move_to":"t3"}"#)
    let text = try XCTUnwrap(state.annotations.first { if case .text = $0.type { return true }; return false })
    guard case .text("Updated") = text.type else { return XCTFail("text not updated") }
    XCTAssertEqual(text.properties.textPresentation, .plain)
    XCTAssertEqual(AnnotateAgentColor.describe(text.properties.strokeColor), "green")
    let email = toolbox.analysis.textBlocks[2].bounds
    XCTAssertEqual(text.bounds.midX, email.midX, accuracy: 1)

    callOK(toolbox, "arrange", #"{"ids":"a1","order":"front"}"#)
    XCTAssertEqual(toolbox.reference(for: try XCTUnwrap(state.annotations.last).id), "a1")

    XCTAssertTrue(toolbox.execute(name: "delete_annotations", argumentsJSON: #"{"ids":["a9"]}"#).isError)
    callOK(toolbox, "delete_annotations", #"{"ids":["all"]}"#)
    XCTAssertTrue(state.annotations.isEmpty)
  }

  func testCanvasChangesRevertWithTheRun() throws {
    let (state, toolbox) = try makeToolbox()
    state.backgroundStyle = .none
    state.padding = 0
    state.shadowIntensity = 0.3
    callOK(toolbox, "set_canvas", #"{"background":"blue-purple","shadow":0.8}"#)
    XCTAssertEqual(state.backgroundStyle, .gradient(.bluePurple))
    XCTAssertEqual(state.padding, 48, "a background needs padding to show")
    XCTAssertEqual(state.shadowIntensity, 0.8, accuracy: 0.001)
    XCTAssertTrue(toolbox.execute(name: "set_canvas", argumentsJSON: #"{"background":"plaid"}"#).isError)

    toolbox.revertCanvasChanges()
    XCTAssertEqual(state.backgroundStyle, .none)
    XCTAssertEqual(state.padding, 0)
    XCTAssertEqual(state.shadowIntensity, 0.3, accuracy: 0.001)
  }

  func testChangeLimitPerRun() throws {
    let (state, toolbox) = try makeToolbox()
    for _ in 0 ..< AnnotateAgentToolbox.maximumChangesPerRun {
      callOK(toolbox, "add_box", #"{"target":{"point":[100,100]}}"#)
    }
    let over = toolbox.execute(name: "add_box", argumentsJSON: #"{"target":{"point":[100,100]}}"#)
    XCTAssertTrue(over.isError)
    XCTAssertEqual(state.annotations.count, AnnotateAgentToolbox.maximumChangesPerRun)
    // Reading still works after the limit.
    XCTAssertFalse(toolbox.execute(name: "get_scene", argumentsJSON: "{}").isError)
  }

  // MARK: - Pure helpers

  func testTextMatcherPrefersExactAndIgnoresAccents() {
    let texts = ["Sign in with Google", "Sign in", "Đăng nhập"]
    XCTAssertEqual(AnnotateAgentTextMatcher.matches("sign IN", in: texts).first, 1)
    XCTAssertEqual(AnnotateAgentTextMatcher.matches("dang nhap", in: texts), [2])
    XCTAssertEqual(AnnotateAgentTextMatcher.matches("", in: texts), [])
  }

  func testElementsDropHugeTinyDuplicateAndTextBoxes() {
    let size = CGSize(width: 1000, height: 1000)
    let boxes = [
      CGRect(x: 0, y: 0, width: 1, height: 1),          // whole image
      CGRect(x: 0.1, y: 0.1, width: 0.005, height: 0.5), // too thin
      CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.1),
      CGRect(x: 0.201, y: 0.2, width: 0.3, height: 0.1), // duplicate
      CGRect(x: 0.6, y: 0.6, width: 0.2, height: 0.05),  // same as a text block
    ]
    let text = [CGRect(x: 600, y: 600, width: 200, height: 50)]
    let elements = AnnotateAgentImageAnalysis.elements(fromVisionBoxes: boxes, imageSize: size, textBounds: text)
    XCTAssertEqual(elements.count, 1)
    XCTAssertEqual(elements.first?.minX ?? 0, 200, accuracy: 2)
  }

  func testColorParsing() {
    XCTAssertNotNil(AnnotateAgentColor.parse("Red"))
    XCTAssertNotNil(AnnotateAgentColor.parse("grey"))
    XCTAssertNotNil(AnnotateAgentColor.parse("#ff8800"))
    XCTAssertNotNil(AnnotateAgentColor.parse("FF8800"))
    XCTAssertNil(AnnotateAgentColor.parse("sparkly"))
    XCTAssertEqual(AnnotateAgentColor.describe(AnnotateAgentColor.parse("#123456")!), "#123456")
  }

  func testCatalogCoversEveryToolWithObjectSchema() throws {
    XCTAssertEqual(Set(AnnotateAgentToolCatalog.all.map(\.name)), Set(AnnotateAgentToolName.allCases))
    for spec in AnnotateAgentToolCatalog.all {
      let object = try XCTUnwrap(
        JSONSerialization.jsonObject(with: Data(spec.parameters.serialized.utf8)) as? [String: Any],
        spec.name.rawValue
      )
      XCTAssertEqual(object["type"] as? String, "object", spec.name.rawValue)
    }
  }

  // MARK: - Review regressions

  func testNoOpArrangeAndUpdateLeaveNoUndoStep() throws {
    let (state, toolbox) = try makeToolbox()
    let existing = AnnotationItem(type: .text("Note"), bounds: CGRect(x: 10, y: 10, width: 50, height: 50), properties: AnnotationProperties())
    state.annotations = [existing]
    XCTAssertNotNil(toolbox.scene()) // assigns a1

    let arranged = callOK(toolbox, "arrange", #"{"ids":["a1"],"order":"front"}"#)
    XCTAssertEqual(arranged["changed"] as? Bool, false)
    let updated = callOK(toolbox, "update_annotation", #"{"id":"a1","text":"   "}"#)
    XCTAssertEqual(updated["changed"] as? Bool, false)
    callOK(toolbox, "update_annotation", #"{"id":"a1"}"#)
    XCTAssertFalse(state.canUndo)
    XCTAssertEqual(toolbox.finishRun().changeCount, 0)
  }

  func testFailedUpdateChangesNothing() throws {
    let (state, toolbox) = try makeToolbox()
    callOK(toolbox, "add_box", #"{"target":"t1","stroke_width":3}"#)
    let before = try XCTUnwrap(state.annotations.first)
    XCTAssertTrue(toolbox.execute(name: "update_annotation", argumentsJSON: #"{"id":"a1","stroke_width":9,"color":"sparkly"}"#).isError)
    XCTAssertTrue(toolbox.execute(name: "update_annotation", argumentsJSON: #"{"id":"a1","stroke_width":9,"style":"label"}"#).isError)
    let after = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(after.properties, before.properties)
  }

  func testStyleChangeKeepsTextReadable() throws {
    let (state, toolbox) = try makeToolbox()
    callOK(toolbox, "add_text", #"{"text":"Dark","style":"plain","color":"black"}"#)
    callOK(toolbox, "update_annotation", #"{"id":"a1","style":"label"}"#)
    var item = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(AnnotateAgentColor.describe(item.properties.fillColor), "black")
    XCTAssertEqual(AnnotateAgentColor.describe(item.properties.strokeColor), "white")

    callOK(toolbox, "update_annotation", #"{"id":"a1","style":"plain"}"#)
    item = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(item.properties.fillColor, .clear)
    XCTAssertEqual(AnnotateAgentColor.describe(item.properties.strokeColor), "black")
  }

  func testHugeNumbersFailWithoutCrashing() throws {
    let (_, toolbox) = try makeToolbox()
    XCTAssertTrue(toolbox.execute(name: "add_counter", argumentsJSON: #"{"target":{"point":[1e30,5]}}"#).isError)
    XCTAssertTrue(toolbox.execute(name: "add_box", argumentsJSON: #"{"target":{"rect":[1e19,0,1e19,10]}}"#).isError)
  }

  func testCounterAndPointBoxStayOnCanvasNearEdges() throws {
    let (state, toolbox) = try makeToolbox()
    callOK(toolbox, "add_counter", #"{"target":{"point":[2,2]},"placement":"above"}"#)
    callOK(toolbox, "add_box", #"{"target":{"point":[799,599]}}"#)
    for item in state.annotations {
      XCTAssertTrue(state.sourceImageBounds.insetBy(dx: -0.5, dy: -0.5).contains(item.bounds), "\(item.type)")
    }
    let box = try XCTUnwrap(state.annotations.last)
    XCTAssertEqual(box.bounds.width, 120, accuracy: 0.5, "shifted, not shrunk")
  }

  func testMoveToCentersVertically() throws {
    let (state, toolbox) = try makeToolbox()
    callOK(toolbox, "add_box", #"{"target":"t1"}"#)
    callOK(toolbox, "update_annotation", #"{"id":"a1","move_to":{"point":[100,500]}}"#)
    let item = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(item.bounds.midX, 100, accuracy: 0.5)
    XCTAssertEqual(item.bounds.midY, imageSize.height - 500, accuracy: 0.5)
  }

  func testPendingTextEditIsCommittedBeforeTheRun() throws {
    let state = try makeState()
    let note = AnnotationItem(type: .text("Draft"), bounds: CGRect(x: 10, y: 10, width: 80, height: 24), properties: AnnotationProperties())
    state.annotations = [note]
    state.beginTextEditing(id: note.id)
    let toolbox = AnnotateAgentToolbox(state: state, analysis: makeAnalysis())
    toolbox.beginRun()
    XCTAssertNil(state.editingTextAnnotationId)

    callOK(toolbox, "add_box", #"{"target":"t1"}"#)
    state.undo()
    XCTAssertEqual(state.annotations.map(\.id), [note.id], "the run's undo keeps the user's text")
  }

  func testUndoRedoOfDeletingRunKeepsReferences() throws {
    let (state, toolbox) = try makeToolbox()
    callOK(toolbox, "add_box", #"{"target":"t1"}"#)
    toolbox.finishRun()
    toolbox.beginRun()
    callOK(toolbox, "delete_annotations", #"{"ids":["a1"]}"#)
    XCTAssertTrue(state.annotations.isEmpty)
    state.undo()
    XCTAssertEqual(state.annotations.count, 1)
    toolbox.beginRun()
    callOK(toolbox, "update_annotation", #"{"id":"a1","color":"purple"}"#)
    state.undo()
    state.redo()
    XCTAssertEqual(AnnotateAgentColor.describe(try XCTUnwrap(state.annotations.first).properties.strokeColor), "purple")
  }

  func testBlurKindIsCaseInsensitiveAndEmptyBackgroundIsRejected() throws {
    let (state, toolbox) = try makeToolbox()
    callOK(toolbox, "add_blur", #"{"target":"t3","kind":"Gaussian"}"#)
    guard case .blur(.gaussian) = try XCTUnwrap(state.annotations.first).type else { return XCTFail("expected gaussian") }
    XCTAssertTrue(toolbox.execute(name: "set_canvas", argumentsJSON: ##"{"background":"#"}"##).isError)
  }
}

