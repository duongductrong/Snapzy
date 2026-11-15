//
//  AnnotateAutoTranslateTests.swift
//  SnapzyTests
//
//  Annotate Auto Translate: layout blocks, filtering, remote JSON, text fitting,
//  style sampling, persistence, resize/edit behaviour and the export toggle.
//

import AppKit
import Carbon.HIToolbox
import CoreGraphics
import SwiftUI
import XCTest
@testable import Snapzy

@MainActor
final class AnnotateAutoTranslateTests: XCTestCase {
  private static var retainedAnnotateStates: [AnnotateState] = []

  private func makeAnnotateState() -> AnnotateState {
    let state = AnnotateState()
    Self.retainedAnnotateStates.append(state)
    return state
  }

  private func makeImage(width: Int, height: Int) throws -> NSImage {
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: width, height: height))
    return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
  }

  private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 0.04) -> OCRTextLine {
    OCRTextLine(text: text, confidence: 1, boundingBox: CGRect(x: x, y: y, width: width, height: height))
  }

  private func translationItem(
    text: String = "Xin chào thế giới",
    bounds: CGRect = CGRect(x: 10, y: 10, width: 200, height: 30),
    fontSize: CGFloat = 18
  ) -> AnnotationItem {
    let block = TranslatedTextBlock(
      sourceText: "Hello world",
      translatedText: text,
      sourceLanguage: "en",
      targetLanguage: "vi",
      cover: .solid,
      alignment: .leading,
      isBold: false,
      isFontSizeManual: false,
      baseFontSize: fontSize,
      groupID: UUID()
    )
    var properties = AnnotationProperties()
    properties.fontSize = fontSize
    properties.strokeColor = .black
    properties.fillColor = .white
    return AnnotationItem(type: .translation(block), bounds: bounds, properties: properties)
  }

  // MARK: - Layout blocks

  func testBlocksKeepSeparateColumnsApart() {
    let formatter = OCRTextLayoutFormatter(imageSize: CGSize(width: 1000, height: 1000), prefersCJK: false)
    let lines = [
      line("Sidebar item", x: 0.02, y: 0.90, width: 0.15),
      line("Main heading text goes here", x: 0.40, y: 0.90, width: 0.40),
      line("Another sidebar", x: 0.02, y: 0.85, width: 0.15),
      line("and the paragraph continues here", x: 0.40, y: 0.85, width: 0.40),
    ]

    let blocks = formatter.blocks(lines)

    XCTAssertTrue(blocks.allSatisfy { $0.box.maxX < 0.3 || $0.box.minX > 0.3 },
                  "No block may span both columns: \(blocks.map(\.text))")
    XCTAssertTrue(blocks.contains { $0.text.contains("Main heading") })
  }

  func testBlocksSplitSameRowLabelsWithLargeGap() {
    let formatter = OCRTextLayoutFormatter(imageSize: CGSize(width: 1000, height: 200), prefersCJK: false)
    let lines = [
      line("File", x: 0.05, y: 0.5, width: 0.04, height: 0.1),
      line("Settings", x: 0.40, y: 0.5, width: 0.08, height: 0.1),
    ]

    let blocks = formatter.blocks(lines)

    XCTAssertEqual(blocks.map(\.text), ["File", "Settings"])
  }

  func testBlocksMergeWrappedParagraphRows() {
    let formatter = OCRTextLayoutFormatter(imageSize: CGSize(width: 1000, height: 1000), prefersCJK: false)
    let lines = [
      line("This is a long paragraph of text that wraps", x: 0.1, y: 0.80, width: 0.6, height: 0.03),
      line("onto a second visual row in the screenshot", x: 0.1, y: 0.765, width: 0.58, height: 0.03),
    ]

    let blocks = formatter.blocks(lines)

    XCTAssertEqual(blocks.count, 1)
    XCTAssertEqual(blocks.first?.rowBoxes.count, 2)
    XCTAssertEqual(blocks.first?.text, "This is a long paragraph of text that wraps onto a second visual row in the screenshot")
  }

  // MARK: - Filtering

  func testShouldTranslateSkipsNumbersLinksAndTargetLanguage() {
    let vietnamese = TranslationLanguage(identifier: "vi")
    XCTAssertFalse(AnnotateAutoTranslateLayout.shouldTranslate("12:45", targetLanguage: vietnamese))
    XCTAssertFalse(AnnotateAutoTranslateLayout.shouldTranslate("https://example.com/path", targetLanguage: vietnamese))
    XCTAssertFalse(AnnotateAutoTranslateLayout.shouldTranslate("x", targetLanguage: vietnamese))
    XCTAssertTrue(AnnotateAutoTranslateLayout.shouldTranslate("Settings", targetLanguage: vietnamese))
    XCTAssertFalse(AnnotateAutoTranslateLayout.shouldTranslate(
      "Đây là một đoạn văn bản tiếng Việt khá dài để nhận diện ngôn ngữ",
      targetLanguage: vietnamese
    ))
    XCTAssertTrue(AnnotateAutoTranslateLayout.shouldTranslate("設定", targetLanguage: vietnamese))
  }

  func testCandidatesUseAnnotateCoordinatesAndPadding() {
    let block = OCRTextBlock(
      text: "Hello world",
      box: CGRect(x: 0.1, y: 0.8, width: 0.4, height: 0.05),
      rowBoxes: [CGRect(x: 0.1, y: 0.8, width: 0.4, height: 0.05)]
    )

    let candidates = AnnotateAutoTranslateLayout.makeCandidates(
      from: [block],
      imageSize: CGSize(width: 1000, height: 400),
      targetLanguage: TranslationLanguage(identifier: "vi")
    )

    let candidate = try? XCTUnwrap(candidates.first)
    XCTAssertEqual(candidates.count, 1)
    // Bottom-left annotate space: a box near the top keeps a large y.
    XCTAssertGreaterThan(candidate?.bounds.minY ?? 0, 300)
    XCTAssertTrue(candidate?.bounds.contains(CGRect(x: 100, y: 320, width: 400, height: 20)) ?? false)
    XCTAssertEqual(candidate?.rowHeight ?? 0, 20, accuracy: 0.001)
  }

  func testAlignmentDetection() {
    let centered = [
      CGRect(x: 40, y: 0, width: 120, height: 10),
      CGRect(x: 70, y: 12, width: 60, height: 10),
    ]
    XCTAssertEqual(AnnotateAutoTranslateLayout.alignment(of: centered, rowHeight: 10), .center)

    let leading = [
      CGRect(x: 20, y: 0, width: 120, height: 10),
      CGRect(x: 20, y: 12, width: 60, height: 10),
    ]
    XCTAssertEqual(AnnotateAutoTranslateLayout.alignment(of: leading, rowHeight: 10), .leading)
  }

  // MARK: - Remote JSON

  func testRemoteParseMapsResultsById() {
    let content = """
    ```json
    {"items":[{"id":1,"text":"Hai"},{"id":"0","text":"Một"},{"id":7,"text":"ignored"},{"id":2,"text":"  "}]}
    ```
    """

    let texts = RemoteBlockTranslator.parse(content, count: 3)

    XCTAssertEqual(texts, ["Một", "Hai", nil])
  }

  func testRemoteParseAcceptsBareArrayAndRejectsGarbage() {
    XCTAssertEqual(RemoteBlockTranslator.parse(#"[{"id":0,"text":"A"}]"#, count: 1), ["A"])
    XCTAssertEqual(RemoteBlockTranslator.parse("Sorry, I can't help.", count: 2), [nil, nil])
  }

  func testRemotePromptCarriesEveryBlockAsJSON() {
    let prompt = RemoteBlockTranslator.prompt(blocks: ["Hello", "Line \"two\""], target: TranslationLanguage(identifier: "vi"))

    XCTAssertTrue(prompt.contains("Vietnamese"))
    XCTAssertTrue(prompt.contains(#""id":0"#))
    XCTAssertTrue(prompt.contains(#"Line \"two\""#))
  }

  // MARK: - Fitting

  func testFitKeepsBaseSizeWhenTextFits() {
    let result = AnnotateTranslationTextLayout.fit(
      text: "OK",
      in: CGRect(x: 0, y: 0, width: 200, height: 40),
      baseFontSize: 16,
      fontName: "SF Pro",
      isBold: false
    )
    XCTAssertEqual(result.fontSize, 16)
    XCTAssertEqual(result.bounds, CGRect(x: 0, y: 0, width: 200, height: 40))
  }

  func testFitShrinksLongTextAndGrowsDownwardOnlyWhenAllowed() {
    let bounds = CGRect(x: 0, y: 100, width: 80, height: 20)
    let long = String(repeating: "translation ", count: 12)

    let grown = AnnotateTranslationTextLayout.fit(text: long, in: bounds, baseFontSize: 16, fontName: "SF Pro", isBold: false)
    XCTAssertLessThan(grown.fontSize, 16)
    XCTAssertGreaterThan(grown.bounds.height, bounds.height)
    XCTAssertEqual(grown.bounds.maxY, bounds.maxY, accuracy: 0.001, "Growth keeps the top edge (bottom-left space)")
    XCTAssertLessThanOrEqual(grown.bounds.height, bounds.height * 1.5 + 0.001)

    let fixed = AnnotateTranslationTextLayout.fit(
      text: long, in: bounds, baseFontSize: 16, fontName: "SF Pro", isBold: false, allowsGrowth: false
    )
    XCTAssertEqual(fixed.bounds, bounds)
  }

  // MARK: - Style sampling

  func testStyleUsesRingAsBackgroundAndInkAsText() {
    let ring = Array(repeating: AnnotateSampledColor.white, count: 200)
    let inner = Array(repeating: AnnotateSampledColor.white, count: 300)
      + Array(repeating: AnnotateSampledColor(red: 0.1, green: 0.2, blue: 0.6), count: 60)

    let style = AnnotateTranslationStyleSampler.style(ring: ring, inner: inner)

    XCTAssertEqual(style.background, .white)
    XCTAssertEqual(style.cover, .solid)
    XCTAssertEqual(style.text.blue, 0.6, accuracy: 0.01)
  }

  func testStyleTreatsNoisyBackgroundAsFrostedAndFixesLowContrast() {
    let noisy = (0..<200).map { index -> AnnotateSampledColor in
      index.isMultiple(of: 2) ? .white : AnnotateSampledColor(red: 0.2, green: 0.2, blue: 0.2)
    }
    XCTAssertEqual(AnnotateTranslationStyleSampler.style(ring: noisy, inner: []).cover, .frosted)

    let gray = AnnotateSampledColor(red: 0.5, green: 0.5, blue: 0.5)
    let nearGray = AnnotateSampledColor(red: 0.72, green: 0.72, blue: 0.72)
    let style = AnnotateTranslationStyleSampler.style(
      ring: Array(repeating: gray, count: 100),
      inner: Array(repeating: nearGray, count: 100)
    )
    XCTAssertGreaterThanOrEqual(style.text.contrastRatio(with: style.background), 3)
  }

  // MARK: - Persistence

  func testTranslationRoundTripsThroughPersistence() throws {
    let item = translationItem()
    let data = try JSONEncoder().encode(PersistedAnnotationItem(item: item))
    let decoded = try JSONDecoder().decode(PersistedAnnotationItem.self, from: data)

    guard case .translation(let block)? = decoded.annotationItem?.type,
          case .translation(let original) = item.type else {
      return XCTFail("Expected a translation item")
    }
    XCTAssertEqual(block, original)
    XCTAssertEqual(decoded.annotationItem?.bounds, item.bounds)
  }

  // MARK: - State

  func testExportSnapshotHonoursIncludeToggle() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 300, height: 200))
    state.annotations = [translationItem()]

    XCTAssertEqual(state.makeRenderSnapshot()?.annotations.count, 1)
    state.setIncludesTranslationsInExport(false)
    XCTAssertEqual(state.makeRenderSnapshot()?.annotations.count, 0)
    XCTAssertEqual(state.annotations.count, 1, "The canvas keeps the translation")
  }

  func testResizeRefitsUnlessFontSizeIsManual() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 600, height: 400))
    let item = translationItem(bounds: CGRect(x: 10, y: 10, width: 300, height: 40), fontSize: 20)
    state.annotations = [item]

    state.updateAnnotationBounds(id: item.id, bounds: CGRect(x: 10, y: 10, width: 300, height: 20))
    XCTAssertLessThan(state.annotations[0].properties.fontSize, 20)

    state.setTranslationFontSize(id: item.id, size: 30)
    state.updateAnnotationBounds(id: item.id, bounds: CGRect(x: 10, y: 10, width: 100, height: 10))
    XCTAssertEqual(state.annotations[0].properties.fontSize, 30)
  }

  func testMoveKeepsTranslationPayload() {
    let item = translationItem()
    let moved = item.translatedBy(dx: 40, dy: -12)

    XCTAssertEqual(moved.bounds.origin, CGPoint(x: 50, y: -2))
    XCTAssertEqual(moved.type, item.type)
    XCTAssertTrue(moved.containsPoint(CGPoint(x: 60, y: 10)))
  }

  func testRemoveAllTranslationsIsUndoable() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 300, height: 200))
    state.annotations = [translationItem(), translationItem()]

    state.removeAllTranslations()
    XCTAssertEqual(state.translationAnnotationCount, 0)

    state.undo()
    XCTAssertEqual(state.translationAnnotationCount, 2)
  }

  func testEditingTranslationTextUpdatesPayload() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 300, height: 200))
    let item = translationItem()
    state.annotations = [item]

    state.setTranslationText(id: item.id, text: "Chào")

    guard case .translation(let block) = state.annotations[0].type else { return XCTFail("Expected translation") }
    XCTAssertEqual(block.translatedText, "Chào")
    XCTAssertEqual(block.sourceText, "Hello world")
  }

  func testPeekOnlyWhenTranslationsExist() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 300, height: 200))

    state.setPeekingOriginalTranslations(true)
    XCTAssertFalse(state.isPeekingOriginalTranslations)

    state.annotations = [translationItem()]
    state.setPeekingOriginalTranslations(true)
    XCTAssertTrue(state.isPeekingOriginalTranslations)
  }

  // MARK: - Translate Area

  func testCandidatesInAreaAreOffsetByAreaOrigin() {
    let block = OCRTextBlock(
      text: "Hello world",
      box: CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
      rowBoxes: [CGRect(x: 0, y: 0, width: 0.5, height: 0.5)]
    )

    let candidates = AnnotateAutoTranslateLayout.makeCandidates(
      from: [block],
      imageSize: CGSize(width: 100, height: 40),
      origin: CGPoint(x: 200, y: 300),
      clampRect: CGRect(x: 0, y: 0, width: 1000, height: 1000),
      targetLanguage: TranslationLanguage(identifier: "vi")
    )

    XCTAssertEqual(candidates.count, 1)
    let bounds = candidates[0].bounds
    XCTAssertTrue(bounds.contains(CGRect(x: 200, y: 300, width: 50, height: 20)))
    XCTAssertLessThan(bounds.maxX, 260)
  }

  func testRegionCropMapsAnnotateSpaceToPixelsAndBack() throws {
    // 2× image: 200×100 points, 400×200 pixels.
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: 400, height: 200))
    let crop = try XCTUnwrap(AnnotateAutoTranslateLayout.regionCrop(
      of: cgImage,
      imageSize: CGSize(width: 200, height: 100),
      region: CGRect(x: 50, y: 60, width: 40, height: 30)
    ))

    XCTAssertEqual(crop.image.width, 80)
    XCTAssertEqual(crop.image.height, 60)
    XCTAssertEqual(crop.origin.x, 50, accuracy: 0.001)
    XCTAssertEqual(crop.origin.y, 60, accuracy: 0.001)
    XCTAssertEqual(crop.size.width, 40, accuracy: 0.001)
    XCTAssertNil(AnnotateAutoTranslateLayout.regionCrop(
      of: cgImage, imageSize: CGSize(width: 200, height: 100), region: CGRect(x: 500, y: 500, width: 10, height: 10)
    ))
  }

  func testTranslateAreaDragBuildsMarqueeAndClickKeepsWaiting() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 300, height: 200))

    state.beginTranslateAreaSelection()
    XCTAssertTrue(state.isTranslateAreaSelecting)

    XCTAssertTrue(state.updateTranslateAreaDrag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 10)))
    state.updateTranslateAreaDrag(from: nil, to: CGPoint(x: 400, y: 60))
    XCTAssertEqual(state.translateAreaDraft, CGRect(x: 10, y: 10, width: 290, height: 50), "Clamped to the image")

    // A click (tiny area) keeps the mode on.
    state.updateTranslateAreaDrag(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 20, y: 20))
    XCTAssertTrue(state.finishTranslateAreaDrag(at: CGPoint(x: 22, y: 21)))
    XCTAssertTrue(state.isTranslateAreaSelecting)
    XCTAssertNil(state.translateAreaDraft)

    state.activateTool(.rectangle)
    XCTAssertFalse(state.isTranslateAreaSelecting)
    XCTAssertFalse(state.updateTranslateAreaDrag(from: .zero, to: .zero), "Canvas is not intercepted any more")
  }

  func testTranslateAreaShortcutDefaultsToOptionCommandT() {
    let config = AnnotateShortcutManager.defaultTranslateArea
    XCTAssertEqual(config.keyCode, UInt32(kVK_ANSI_T))
    XCTAssertEqual(config.modifiers, UInt32(cmdKey | optionKey))
    XCTAssertNotEqual(config, AnnotateShortcutManager.defaultAutoTranslate)
  }

}
