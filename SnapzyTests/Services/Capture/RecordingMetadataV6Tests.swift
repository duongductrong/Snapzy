//
//  RecordingMetadataV6Tests.swift
//  SnapzyTests
//
//  Metadata v6 (Studio fields) round-trips and the generalized sidecar store.
//

import CoreGraphics
import XCTest
@testable import Snapzy

@MainActor
final class RecordingMetadataV6Tests: XCTestCase {
  private var tempDirectory: URL!
  private var videoURLs: [URL] = []

  override func setUp() async throws {
    try await super.setUp()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_RecordingMetadataV6_\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    for url in videoURLs {
      try? RecordingMetadataStore.delete(for: url)
    }
    videoURLs.removeAll()
    if let tempDirectory {
      try? FileManager.default.removeItem(at: tempDirectory)
    }
    try await super.tearDown()
  }

  // MARK: - Codable

  func testV5PayloadDecodesWithBakedCursorAndNoStudioSources() throws {
    let json = """
    {"version":5,"coordinateSpace":"topLeftNormalized","captureSize":[640,360],
     "samplesPerSecond":60,"mouseSamples":[],"audioSourceTrackRoles":["microphone"]}
    """
    let decoded = try JSONDecoder().decode(RecordingMetadata.self, from: Data(json.utf8))

    XCTAssertEqual(decoded.version, 5)
    XCTAssertTrue(decoded.isCursorBaked)
    XCTAssertNil(decoded.cursorCapture)
    XCTAssertNil(decoded.cameraSource)
    XCTAssertEqual(decoded.audioSourceTrackRoles, [.microphone])
  }

  func testV5ToV6RoundTripKeepsFieldsAndOmitsDefaults() throws {
    let v5 = RecordingMetadata(
      version: 5,
      captureSize: CGSize(width: 640, height: 360),
      samplesPerSecond: 60,
      mouseSamples: [RecordedMouseSample(time: 0.5, normalizedX: 0.2, normalizedY: 0.3, isInsideCapture: true)]
    )
    var v6 = v5
    v6.version = RecordingMetadata.currentVersion

    let data = try JSONEncoder().encode(v6)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(RecordingMetadata.currentVersion, 6)
    XCTAssertNil(object["isCursorBaked"], "Default (baked) is not written")
    XCTAssertNil(object["cursorCapture"])
    XCTAssertNil(object["cameraSource"])

    let decoded = try JSONDecoder().decode(RecordingMetadata.self, from: data)
    XCTAssertEqual(decoded, v6)
    XCTAssertEqual(decoded.mouseSamples, v5.mouseSamples)
  }

  func testStudioFieldsRoundTrip() throws {
    let metadata = makeStudioMetadata(cameraFile: "camera.mov", cursorFolder: "cursor-folder")
    let data = try JSONEncoder().encode(metadata)
    let decoded = try JSONDecoder().decode(RecordingMetadata.self, from: data)

    XCTAssertEqual(decoded, metadata)
    XCTAssertFalse(decoded.isCursorBaked)
    XCTAssertEqual(decoded.cameraSource?.fileName, "camera.mov")
    XCTAssertEqual(decoded.cursorCapture?.imagesFolderName, "cursor-folder")
  }

  func testStoreSaveLoadUpgradesV5ToCurrentVersionKeepingStudioFields() throws {
    let videoURL = try makeVideoFile(named: "studio.mov")
    var metadata = makeStudioMetadata(cameraFile: "c.mov", cursorFolder: "f")
    metadata.version = 5

    try RecordingMetadataStore.save(metadata, for: videoURL)
    let loaded = try XCTUnwrap(RecordingMetadataStore.load(for: videoURL))

    XCTAssertEqual(loaded.version, RecordingMetadata.currentVersion)
    XCTAssertFalse(loaded.isCursorBaked)
    XCTAssertEqual(loaded.cameraSource, metadata.cameraSource)
    XCTAssertEqual(loaded.cursorCapture, metadata.cursorCapture)
  }

  // MARK: - Sidecar store

  func testStoreSidecarUsesKindFoldersAndDeleteRemovesEveryKind() throws {
    let videoURL = try makeVideoFile(named: "sidecars.mov")
    let audioURL = try RecordingMetadataStore.storeSidecar(from: try makeFile("a.mov"), kind: .audio)
    let cameraURL = try RecordingMetadataStore.storeSidecar(from: try makeFile("c.mov"), kind: .camera)
    let cursorURL = try RecordingMetadataStore.storeSidecar(from: try makeFolder("cursor"), kind: .cursorImages)

    XCTAssertEqual(audioURL.deletingLastPathComponent().lastPathComponent, "AudioSources")
    XCTAssertEqual(cameraURL.deletingLastPathComponent().lastPathComponent, "CameraSources")
    XCTAssertEqual(cursorURL.deletingLastPathComponent().lastPathComponent, "CursorImages")
    XCTAssertEqual(cameraURL.pathExtension, "mov")
    XCTAssertEqual(cursorURL.pathExtension, "", "Folders keep no extension")
    XCTAssertEqual(
      try RecordingMetadataStore.sidecarURL(named: cameraURL.lastPathComponent, kind: .camera)?.standardizedFileURL,
      cameraURL.standardizedFileURL
    )

    var metadata = makeStudioMetadata(
      cameraFile: cameraURL.lastPathComponent,
      cursorFolder: cursorURL.lastPathComponent
    )
    metadata.audioSourceURL = audioURL
    try RecordingMetadataStore.save(metadata, for: videoURL)

    try RecordingMetadataStore.delete(for: videoURL)

    for url in [audioURL, cameraURL, cursorURL] {
      XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), url.lastPathComponent)
    }
  }

  func testDeleteNeverRemovesSidecarReferencesOutsideTheStore() throws {
    let videoURL = try makeVideoFile(named: "escape.mov")
    let outsideFile = try makeFile("outside.mov")
    var metadata = makeStudioMetadata(cameraFile: "../AudioSources/x.mov", cursorFolder: "..")
    metadata.audioSourceURL = outsideFile
    try RecordingMetadataStore.save(metadata, for: videoURL)

    try RecordingMetadataStore.delete(for: videoURL)

    XCTAssertTrue(FileManager.default.fileExists(atPath: outsideFile.path))
    XCTAssertNil(try RecordingMetadataStore.sidecarURL(named: "../x", kind: .camera))
    XCTAssertNil(try RecordingMetadataStore.sidecarURL(named: "..", kind: .cursorImages))
  }

  func testOrphanCleanupRemovesCameraSidecarAfterGracePeriod() throws {
    let videoURL = try makeVideoFile(named: "orphan.mov")
    let cameraURL = try RecordingMetadataStore.storeSidecar(from: try makeFile("cam.mov"), kind: .camera)
    try RecordingMetadataStore.save(
      makeStudioMetadata(cameraFile: cameraURL.lastPathComponent, cursorFolder: nil),
      for: videoURL
    )
    try FileManager.default.removeItem(at: videoURL)

    let now = Date()
    try RecordingMetadataStore.performOrphanCleanup(now: now)
    XCTAssertTrue(FileManager.default.fileExists(atPath: cameraURL.path), "Grace period keeps it first")

    try RecordingMetadataStore.performOrphanCleanup(now: now.addingTimeInterval(25 * 60 * 60))
    XCTAssertFalse(FileManager.default.fileExists(atPath: cameraURL.path))
  }

  // MARK: - Helpers

  private func makeStudioMetadata(cameraFile: String?, cursorFolder: String?) -> RecordingMetadata {
    RecordingMetadata(
      captureSize: CGSize(width: 1280, height: 720),
      samplesPerSecond: 60,
      mouseSamples: [],
      cursorCapture: RecordingCursorCapture(imagesFolderName: cursorFolder),
      isCursorBaked: false,
      cameraSource: cameraFile.map { RecordingCameraSource(fileName: $0) }
    )
  }

  private func makeVideoFile(named name: String) throws -> URL {
    let url = try makeFile(name)
    videoURLs.append(url)
    return url
  }

  private func makeFile(_ name: String) throws -> URL {
    let url = tempDirectory.appendingPathComponent(name)
    try Data("payload-\(name)".utf8).write(to: url)
    return url
  }

  private func makeFolder(_ name: String) throws -> URL {
    let url = tempDirectory.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try Data("png".utf8).write(to: url.appendingPathComponent("0.png"))
    return url
  }
}
