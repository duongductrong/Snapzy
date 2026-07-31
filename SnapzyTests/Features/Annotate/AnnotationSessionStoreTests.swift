//
//  AnnotationSessionStoreTests.swift
//  SnapzyTests
//
//  Unit tests for persisted editable annotation session sidecars.
//

import AppKit
import SwiftUI
import XCTest
@testable import Snapzy

@MainActor
final class AnnotationSessionStoreTests: XCTestCase {

  private var tempDirectory: URL!
  private var sessionsDirectory: URL!
  private var sourceDirectory: URL!
  private var store: AnnotationSessionStore!

  override func setUp() {
    super.setUp()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_AnnotationSessionStore_\(UUID().uuidString)", isDirectory: true)
    sessionsDirectory = tempDirectory.appendingPathComponent("AnnotationSessions", isDirectory: true)
    sourceDirectory = tempDirectory.appendingPathComponent("Sources", isDirectory: true)
    try? FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    store = AnnotationSessionStore(rootDirectory: sessionsDirectory)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDirectory)
    store = nil
    tempDirectory = nil
    sessionsDirectory = nil
    sourceDirectory = nil
    super.tearDown()
  }

  func testPersistAndLoad_roundTripsEditableSession() throws {
    let sourceURL = try writeSourceImage(named: "capture.png")
    let assetId = UUID()
    let sessionData = try makeSessionData(assetId: assetId)

    XCTAssertTrue(store.persist(sessionData, for: sourceURL))

    let loaded = try XCTUnwrap(store.load(for: sourceURL))
    XCTAssertEqual(loaded.originalImageData, sessionData.originalImageData)
    XCTAssertEqual(loaded.annotations.count, 4)
    XCTAssertEqual(loaded.annotations.map(\.id), sessionData.annotations.map(\.id))
    XCTAssertEqual(loaded.canvasEffects.padding, 18)
    XCTAssertEqual(loaded.canvasEffects.shadowIntensity, 0.7)
    XCTAssertEqual(loaded.canvasEffects.aspectRatio, .ratio16x9)
    XCTAssertEqual(loaded.selectedCanvasPresetId, sessionData.selectedCanvasPresetId)
    XCTAssertEqual(loaded.cropRect, sessionData.cropRect)
    XCTAssertEqual(loaded.cutoutImageData, sessionData.cutoutImageData)
    XCTAssertEqual(loaded.embeddedImageAssetsData[assetId], Data("embedded-asset".utf8))

    guard case .text("Editable text") = loaded.annotations[0].type else {
      return XCTFail("Expected text annotation")
    }
    guard case .arrow(let geometry) = loaded.annotations[1].type else {
      return XCTFail("Expected arrow annotation")
    }
    XCTAssertEqual(geometry.style, .curvedRight)
    XCTAssertEqual(geometry.bendDirection, .alternate)
    XCTAssertEqual(loaded.annotations[1].properties.lineStyle, .dashed)
    guard case .blur(.gaussian) = loaded.annotations[2].type else {
      return XCTFail("Expected gaussian blur annotation")
    }
    guard case .embeddedImage(let loadedAssetId) = loaded.annotations[3].type else {
      return XCTFail("Expected embedded image annotation")
    }
    XCTAssertEqual(loadedAssetId, assetId)
  }

  func testLoad_returnsNilWhenSourceSignatureChanges() throws {
    let sourceURL = try writeSourceImage(named: "capture.png")
    let sessionData = try makeSessionData()

    XCTAssertTrue(store.persist(sessionData, for: sourceURL))
    XCTAssertNotNil(store.load(for: sourceURL))

    try Data("changed flattened image bytes".utf8).write(to: sourceURL, options: .atomic)
    try FileManager.default.setAttributes(
      [.modificationDate: Date().addingTimeInterval(60)],
      ofItemAtPath: sourceURL.path
    )

    XCTAssertNil(store.load(for: sourceURL))
  }

  func testMoveSession_rekeysSidecarToNewSourcePath() throws {
    let sourceURL = try writeSourceImage(named: "capture.png")
    let destinationURL = sourceDirectory.appendingPathComponent("exported.png")
    let sessionData = try makeSessionData()

    XCTAssertTrue(store.persist(sessionData, for: sourceURL))
    try FileManager.default.moveItem(at: sourceURL, to: destinationURL)

    XCTAssertTrue(store.moveSession(from: sourceURL, to: destinationURL))
    XCTAssertNil(store.load(for: sourceURL))
    XCTAssertEqual(store.load(for: destinationURL)?.annotations.count, sessionData.annotations.count)
    XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarDirectory(for: sourceURL).path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarDirectory(for: destinationURL).path))
  }

  func testCleanup_removesMissingAndInactiveSidecarsButKeepsActiveMatches() throws {
    let activeURL = try writeSourceImage(named: "active.png")
    let missingURL = try writeSourceImage(named: "missing.png")
    let inactiveURL = try writeSourceImage(named: "inactive.png")
    let sessionData = try makeSessionData()

    XCTAssertTrue(store.persist(sessionData, for: activeURL))
    XCTAssertTrue(store.persist(sessionData, for: missingURL))
    XCTAssertTrue(store.persist(sessionData, for: inactiveURL))
    try FileManager.default.removeItem(at: missingURL)

    store.cleanup(keepingScreenshotFilePaths: [activeURL.path])

    XCTAssertNotNil(store.load(for: activeURL))
    XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarDirectory(for: activeURL).path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarDirectory(for: missingURL).path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarDirectory(for: inactiveURL).path))
  }

  // MARK: - Helpers

  private func writeSourceImage(named fileName: String) throws -> URL {
    let url = sourceDirectory.appendingPathComponent(fileName)
    try makeImageData(width: 24, height: 16).write(to: url, options: .atomic)
    return url
  }

  private func makeSessionData(assetId: UUID = UUID()) throws -> AnnotationSessionData {
    let originalData = try makeImageData(width: 24, height: 16)
    let cutoutData = try makeImageData(width: 8, height: 8)
    let presetId = UUID()
    let arrowGeometry = ArrowGeometry(
      start: CGPoint(x: 4, y: 5),
      end: CGPoint(x: 50, y: 60),
      style: .curvedRight,
      bendDirection: .alternate
    )
    return AnnotationSessionData(
      originalImageData: originalData,
      annotations: [
        AnnotationItem(
          id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
          type: .text("Editable text"),
          bounds: CGRect(x: 1, y: 2, width: 30, height: 16),
          properties: AnnotationProperties(
            strokeColor: .yellow,
            fillColor: .blue,
            strokeWidth: 4,
            cornerRadius: 3,
            fontSize: 18,
            fontName: "SF Pro",
            opacity: 0.8,
            rotationDegrees: 12,
            watermarkStyle: .diagonal
          )
        ),
        AnnotationItem(
          id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
          type: .arrow(arrowGeometry),
          bounds: arrowGeometry.bounds(),
          properties: AnnotationProperties(strokeColor: .red, strokeWidth: 5, lineStyle: .dashed)
        ),
        AnnotationItem(
          id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
          type: .blur(.gaussian),
          bounds: CGRect(x: 10, y: 12, width: 44, height: 22),
          properties: AnnotationProperties()
        ),
        AnnotationItem(
          id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
          type: .embeddedImage(assetId),
          bounds: CGRect(x: 2, y: 3, width: 12, height: 9),
          properties: AnnotationProperties()
        )
      ],
      canvasEffects: AnnotationCanvasEffects(
        backgroundStyle: .gradient(.blueGreen),
        isBlurredBackgroundEnabled: true,
        blurredBackgroundEffect: .vivid,
        padding: 18,
        inset: 6,
        autoBalance: false,
        shadowIntensity: 0.7,
        cornerRadius: 11,
        imageAlignment: .bottomRight,
        aspectRatio: .ratio16x9,
        aspectRatioOrientation: .vertical
      ),
      selectedCanvasPresetId: presetId,
      isSelectedCanvasPresetDirty: true,
      cropRect: CGRect(x: 1, y: 1, width: 20, height: 12),
      isCutoutApplied: true,
      cutoutImageData: cutoutData,
      didCutoutAutoApplyCrop: true,
      cutoutAutoAppliedCropRect: CGRect(x: 2, y: 2, width: 10, height: 6),
      embeddedImageAssetsData: [assetId: Data("embedded-asset".utf8)]
    )
  }

  private func makeImageData(width: Int, height: Int) throws -> Data {
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: width, height: height))
    let image = NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
    return try XCTUnwrap(AnnotateExporter.imageData(from: image, for: "png"))
  }

  private func sidecarDirectory(for sourceURL: URL) -> URL {
    let normalizedPath = AnnotationSessionStore.normalizedPath(for: sourceURL)
    return sessionsDirectory.appendingPathComponent(
      AnnotationSessionStore.pathHash(for: normalizedPath),
      isDirectory: true
    )
  }
}
