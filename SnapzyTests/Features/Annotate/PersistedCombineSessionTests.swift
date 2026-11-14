//
//  PersistedCombineSessionTests.swift
//  SnapzyTests
//
//  Unit tests for persisted combine (stitch) session state and its restore fallbacks.
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class PersistedCombineSessionTests: XCTestCase {

  private var tempDirectory: URL!
  private var sessionsDirectory: URL!
  private var sourceDirectory: URL!
  private var store: AnnotationSessionStore!

  override func setUp() {
    super.setUp()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_CombineSession_\(UUID().uuidString)", isDirectory: true)
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

  // MARK: - End-to-end capture→stitch→save→reopen (repro for the "stitch not persisted" bug)

  /// Mirrors the failing user flow at the data layer: a capture-origin session stitches a
  /// second image, the combined render is committed to the source file, the session is
  /// snapshotted + persisted, then reloaded and reconstructed the way the controller does.
  /// The reconstructed session (and its re-render) must still be stitched.
  func testCaptureStitchSaveReopen_persistsStitchEverywhere() throws {
    // 1. Capture-origin session with a base image written to a real source file.
    let sourceURL = try writeSourceImage(named: "capture.png")
    let baseImage = try makeImage(width: 24, height: 16)
    let state = AnnotateState(image: baseImage, url: sourceURL, appliesDefaultCanvasPresetOnNewImages: false)
    let baseArea = baseImage.size.width * baseImage.size.height

    // 2. Drag & drop a second image → combine mode activates.
    let secondImage = try makeImage(width: 24, height: 16)
    let secondData = try XCTUnwrap(AnnotateExporter.imageData(from: secondImage, for: "png"))
    XCTAssertTrue(state.importImage(secondImage, sourceURL: nil, sourceData: secondData))
    XCTAssertTrue(state.isCombineMode)
    XCTAssertEqual(state.combineImageCount, 2)

    // 3. Live render must be stitched (canvas grew well beyond the single base image).
    let liveRender = try XCTUnwrap(AnnotateExporter.renderFinalImage(state: state))
    let liveArea = liveRender.size.width * liveRender.size.height
    XCTAssertGreaterThan(liveArea, baseArea * 1.5, "live combined render should be larger than the base image")

    // 4. Commit the render to the source file (what saveToFile does on close).
    XCTAssertTrue(AnnotateExporter.save(state: state, to: sourceURL))
    
    // Give file system time to flush attributes to prevent signature mismatch on slow CI runners
    Thread.sleep(forTimeInterval: 0.5)

    // 5. Snapshot from the LIVE state (what makeSessionSnapshot does) + persist.
    let baseData = try XCTUnwrap(AnnotateExporter.imageData(from: baseImage, for: "png"))
    let snapshot = AnnotationSessionData.snapshot(from: state, originalImageData: baseData)
    XCTAssertNotNil(snapshot.combineSession, "snapshot must capture the active combine session")
    XCTAssertFalse(snapshot.embeddedImageAssetsData.isEmpty, "snapshot must carry the stitched image bytes")
    XCTAssertTrue(store.persist(snapshot, for: sourceURL))

    // 6. Reload + reconstruct exactly as AnnotateWindowController.init(item:sessionData:) does.
    let loaded = try XCTUnwrap(store.load(for: sourceURL))
    let restored = AnnotateState(
      image: baseImage,
      url: sourceURL,
      appliesDefaultCanvasPresetOnNewImages: false
    )
    restored.restoreEmbeddedImageAssets(from: loaded.embeddedImageAssetsData)
    restored.annotations = loaded.annotations
    let restoredCombine = try XCTUnwrap(loaded.combineSession, "reloaded session lost the combine flags")
    restored.restoreCombineSession(restoredCombine)

    // 7. Reopened session is stitched and re-renders stitched.
    XCTAssertTrue(restored.isCombineMode)
    XCTAssertEqual(restored.combineImageCount, 2, "reopened session must still contain both images")
    let reRender = try XCTUnwrap(AnnotateExporter.renderFinalImage(state: restored))
    let reArea = reRender.size.width * reRender.size.height
    XCTAssertGreaterThan(reArea, baseArea * 1.5, "reopened combined render should still be stitched")
  }

  // MARK: - Store round-trip

  func testPersistAndLoad_roundTripsCombineSession() throws {
    let sourceURL = try writeSourceImage(named: "combined.png")
    let layerId = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    let combine = CombineSessionSnapshot(
      mode: .freeCanvas,
      direction: .vertical,
      gap: 24,
      freeBoundsByAnnotationID: [layerId: CGRect(x: 5, y: 6, width: 40, height: 30)]
    )
    let sessionData = try makeSessionData(combineSession: combine)

    XCTAssertTrue(store.persist(sessionData, for: sourceURL))

    let loaded = try XCTUnwrap(store.load(for: sourceURL))
    let restored = try XCTUnwrap(loaded.combineSession)
    XCTAssertEqual(restored.mode, .freeCanvas)
    XCTAssertEqual(restored.direction, .vertical)
    XCTAssertEqual(restored.gap, 24)
    XCTAssertEqual(restored.freeBoundsByAnnotationID[layerId], CGRect(x: 5, y: 6, width: 40, height: 30))
  }

  // MARK: - Codable backward compatibility

  func testPersistAndLoad_nilCombineSession_omitsKeyAndStaysNil() throws {
    let sourceURL = try writeSourceImage(named: "plain.png")
    let sessionData = try makeSessionData(combineSession: nil)

    XCTAssertTrue(store.persist(sessionData, for: sourceURL))

    // A manifest with no combine session must omit the key entirely — this is exactly the
    // shape of a legacy sidecar written before combine persistence existed, proving older
    // manifests decode without migration.
    let manifestURL = sidecarDirectory(for: sourceURL).appendingPathComponent("manifest.json")
    let rawManifest = try String(contentsOf: manifestURL, encoding: .utf8)
    XCTAssertFalse(rawManifest.contains("combineSession"))

    let loaded = try XCTUnwrap(store.load(for: sourceURL))
    XCTAssertNil(loaded.combineSession)
  }

  func testDecode_manifestWithoutCombineSessionField_succeedsWithNil() throws {
    // Encode a manifest that HAS a combine session, then decode a variant with the field
    // stripped — the schemaVersion stays 1 and decoding still succeeds.
    let sourceURL = try writeSourceImage(named: "combined.png")
    let combine = CombineSessionSnapshot(mode: .autoStitch, direction: .smart, gap: 0, freeBoundsByAnnotationID: [:])
    XCTAssertTrue(store.persist(try makeSessionData(combineSession: combine), for: sourceURL))

    let manifestURL = sidecarDirectory(for: sourceURL).appendingPathComponent("manifest.json")
    var json = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
    XCTAssertNotNil(json["combineSession"])
    json.removeValue(forKey: "combineSession")
    let strippedData = try JSONSerialization.data(withJSONObject: json)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let manifest = try decoder.decode(PersistedAnnotationSession.self, from: strippedData)
    XCTAssertNil(manifest.combineSession)
    XCTAssertEqual(manifest.schemaVersion, PersistedAnnotationSession.currentSchemaVersion)
  }

  func testEncodeDecode_persistedCombineSessionRoundTrips() throws {
    let original = PersistedCombineSession(
      modeRawValue: "autoStitch",
      directionRawValue: "horizontal",
      gap: 12.5,
      freeBoundsByAnnotationID: ["11111111-1111-1111-1111-111111111111": CGRect(x: 1, y: 2, width: 3, height: 4)]
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(PersistedCombineSession.self, from: data)
    XCTAssertEqual(decoded, original)
  }

  func testPersistAndLoad_roundTripsStitchRowsAndOverlays() throws {
    let sourceURL = try writeSourceImage(named: "grid.png")
    let a = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    let b = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    let overlay = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
    let combine = CombineSessionSnapshot(
      mode: .autoStitch,
      direction: .smart,
      gap: 0,
      freeBoundsByAnnotationID: [:],
      stitchRows: [[AnnotateState.combineBaseLayerID, a], [b]],
      overlayIDs: [overlay]
    )
    XCTAssertTrue(store.persist(try makeSessionData(combineSession: combine), for: sourceURL))

    let restored = try XCTUnwrap(store.load(for: sourceURL)?.combineSession)
    XCTAssertEqual(restored, combine)
    XCTAssertTrue(restored.stripsGrowDownward)
  }

  func testToSnapshot_missingLayoutRevisionIsLegacyUpwardStrip() {
    let persisted = PersistedCombineSession(
      modeRawValue: "autoStitch",
      directionRawValue: "vertical",
      gap: 0,
      freeBoundsByAnnotationID: [:]
    )
    let snapshot = persisted.toSnapshot()
    XCTAssertFalse(snapshot.stripsGrowDownward)
    XCTAssertNil(snapshot.stitchRows)
    XCTAssertTrue(snapshot.overlayIDs.isEmpty)
  }

  // MARK: - toSnapshot() fallbacks

  func testToSnapshot_unknownRawValuesFallBackToDefaults() {
    let persisted = PersistedCombineSession(
      modeRawValue: "tesseractStitch",
      directionRawValue: "diagonal",
      gap: 8,
      freeBoundsByAnnotationID: [:]
    )
    let snapshot = persisted.toSnapshot()
    XCTAssertEqual(snapshot.mode, .autoStitch)
    XCTAssertEqual(snapshot.direction, .smart)
    XCTAssertEqual(snapshot.gap, 8)
  }

  func testToSnapshot_dropsUnparseableUUIDKeys() {
    let validKey = "22222222-2222-2222-2222-222222222222"
    let persisted = PersistedCombineSession(
      modeRawValue: "freeCanvas",
      directionRawValue: "smart",
      gap: 0,
      freeBoundsByAnnotationID: [
        validKey: CGRect(x: 0, y: 0, width: 10, height: 10),
        "not-a-uuid": CGRect(x: 1, y: 1, width: 2, height: 2)
      ]
    )
    let snapshot = persisted.toSnapshot()
    XCTAssertEqual(snapshot.freeBoundsByAnnotationID.count, 1)
    XCTAssertEqual(snapshot.freeBoundsByAnnotationID[UUID(uuidString: validKey)!], CGRect(x: 0, y: 0, width: 10, height: 10))
  }

  // MARK: - Helpers

  private func writeSourceImage(named fileName: String) throws -> URL {
    let url = sourceDirectory.appendingPathComponent(fileName)
    try makeImageData(width: 24, height: 16).write(to: url, options: .atomic)
    return url
  }

  private func makeSessionData(combineSession: CombineSessionSnapshot?) throws -> AnnotationSessionData {
    AnnotationSessionData(
      originalImageData: try makeImageData(width: 24, height: 16),
      annotations: [],
      canvasEffects: AnnotationCanvasEffects(),
      selectedCanvasPresetId: nil,
      isSelectedCanvasPresetDirty: false,
      cropRect: nil,
      isCutoutApplied: false,
      cutoutImageData: nil,
      didCutoutAutoApplyCrop: false,
      cutoutAutoAppliedCropRect: nil,
      embeddedImageAssetsData: [:],
      combineSession: combineSession
    )
  }

  private func makeImage(width: Int, height: Int) throws -> NSImage {
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: width, height: height))
    return NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
  }

  private func makeImageData(width: Int, height: Int) throws -> Data {
    try XCTUnwrap(AnnotateExporter.imageData(from: makeImage(width: width, height: height), for: "png"))
  }

  private func sidecarDirectory(for sourceURL: URL) -> URL {
    let normalizedPath = AnnotationSessionStore.normalizedPath(for: sourceURL)
    return sessionsDirectory.appendingPathComponent(
      AnnotationSessionStore.pathHash(for: normalizedPath),
      isDirectory: true
    )
  }
}
