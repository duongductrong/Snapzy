//
//  AnnotateExportSaveTests.swift
//  SnapzyTests
//
//  Characterization tests for AnnotateExporter render + save paths.
//  ALWAYS-RUN: renderFinalImage non-nil + dims (NO pixel equality — retina
//  pixel fidelity is already covered in AnnotateCoreTests), saveToOriginal /
//  saveToFile writing to a temp dir. CI-SKIP: saveAs (NSSavePanel),
//  copyToClipboard (NSPasteboard).
//

import AppKit
import CoreGraphics
import XCTest
@testable import Snapzy

@MainActor
final class AnnotateExportSaveTests: XCTestCase {
  private static var retainedAnnotateStates: [AnnotateState] = []

  private var tempDir: URL!

  override func setUp() {
    super.setUp()
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_ExportSave_\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDir)
    tempDir = nil
    super.tearDown()
  }

  private func makeAnnotateState() -> AnnotateState {
    let state = AnnotateState()
    Self.retainedAnnotateStates.append(state)
    return state
  }

  private func makeImage(width: Int, height: Int) throws -> NSImage {
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: width, height: height))
    return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
  }

  // MARK: - renderFinalImage (dims only)

  func testRenderFinalImageReturnsNonNilImageMatchingSourceDimensions() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 200, height: 120))

    let rendered = try XCTUnwrap(AnnotateExporter.renderFinalImage(state: state))

    // Default state: no crop, backgroundStyle == .none (padding 0), 1x image.
    // Point-size equals source point-size; pixel dims equal source pixel dims.
    XCTAssertEqual(rendered.size.width, 200, accuracy: 0.0001)
    XCTAssertEqual(rendered.size.height, 120, accuracy: 0.0001)

    let renderedCG = try XCTUnwrap(AnnotateExporter.bestCGImage(from: rendered))
    XCTAssertEqual(renderedCG.width, 200)
    XCTAssertEqual(renderedCG.height, 120)
  }

  func testRenderFinalImageReturnsNilWhenNoSourceImage() {
    let state = makeAnnotateState()
    XCTAssertNil(AnnotateExporter.renderFinalImage(state: state))
  }

  func testRenderFinalImageWithAnnotationsKeepsSourceDimensions() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 160, height: 160))
    state.annotations = [
      AnnotationItem(
        type: .rectangle,
        bounds: CGRect(x: 10, y: 10, width: 40, height: 40),
        properties: AnnotationProperties()
      )
    ]

    let rendered = try XCTUnwrap(AnnotateExporter.renderFinalImage(state: state))
    XCTAssertEqual(rendered.size.width, 160, accuracy: 0.0001)
    XCTAssertEqual(rendered.size.height, 160, accuracy: 0.0001)
  }

  func testRenderFinalImageUsesCombinedBoundsGapAndPadding() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 200, height: 100))
    state.importImage(try makeImage(width: 100, height: 100))
    state.setCombineDirection(.horizontal)
    state.setCombineGap(10)
    state.padding = 24

    let rendered = try XCTUnwrap(AnnotateExporter.renderFinalImage(state: state))

    XCTAssertEqual(rendered.size.width, 358, accuracy: 0.001)
    XCTAssertEqual(rendered.size.height, 148, accuracy: 0.001)
  }

  // MARK: - saveToOriginal (writes to state.sourceURL)

  func testSaveToOriginalWritesReadableFileAndReturnsTrue() throws {
    let state = makeAnnotateState()
    let url = tempDir.appendingPathComponent("capture.png")
    state.loadImage(try makeImage(width: 80, height: 60), url: url)

    let didSave = AnnotateExporter.saveToOriginal(state: state)

    XCTAssertTrue(didSave)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    let reloaded = try XCTUnwrap(NSImage(contentsOf: url))
    XCTAssertGreaterThan(reloaded.size.width, 0)
    XCTAssertGreaterThan(reloaded.size.height, 0)
  }

  func testSaveToOriginalReturnsFalseWhenNoSourceURL() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 40, height: 40))  // no URL

    XCTAssertFalse(AnnotateExporter.saveToOriginal(state: state))
  }

  // MARK: - saveToFile (writes pre-rendered image to state.sourceURL)

  func testSaveToFileWritesRenderedImageToTempURLAndReturnsTrue() throws {
    let state = makeAnnotateState()
    let url = tempDir.appendingPathComponent("background-save.png")
    state.loadImage(try makeImage(width: 100, height: 100), url: url)
    let rendered = AnnotateExporter.renderFinalImage(state: state)

    let didSave = AnnotateExporter.saveToFile(image: rendered, state: state)

    XCTAssertTrue(didSave)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    let reloaded = try XCTUnwrap(NSImage(contentsOf: url))
    XCTAssertGreaterThan(reloaded.size.width, 0)
  }

  func testSaveToFileReturnsFalseWhenImageIsNil() throws {
    let state = makeAnnotateState()
    let url = tempDir.appendingPathComponent("noimage.png")
    state.loadImage(try makeImage(width: 40, height: 40), url: url)

    XCTAssertFalse(AnnotateExporter.saveToFile(image: nil, state: state))
  }

  func testSaveToFileReturnsFalseWhenNoSourceURL() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 40, height: 40))  // no URL
    let rendered = AnnotateExporter.renderFinalImage(state: state)

    XCTAssertFalse(AnnotateExporter.saveToFile(image: rendered, state: state))
  }

  // MARK: - CI-SKIP (NSPasteboard / NSSavePanel)

  // copyToClipboard mutates the shared NSPasteboard (process-global, nondeterministic
  // under parallel CI). Local-only smoke test: must not crash.
  func testCopyToClipboardRunsWithoutCrashing() throws {
    try skipIfRunningInCI("copyToClipboard touches shared NSPasteboard")
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 50, height: 50))

    AnnotateExporter.copyToClipboard(state: state)
    // No return value; success = no crash + a non-nil render underneath.
    XCTAssertNotNil(AnnotateExporter.renderFinalImage(state: state))
  }

  // saveAs presents a modal NSSavePanel; there is no headless path, so this is
  // documented as CI-SKIP and intentionally not driven (would block on the panel).
  func testSaveAsIsCoveredByManualInteractionOnly() throws {
    try skipIfRunningInCI("saveAs presents a modal NSSavePanel (no headless path)")
    // Intentionally not invoked: AnnotateExporter.saveAs(state:) opens a modal
    // panel that cannot be dismissed in an automated run. Placeholder to record
    // the CI-SKIP classification without hanging the suite.
    XCTAssertTrue(true)
  }
}
