//
//  VideoEditorStudioAgentTests.swift
//  SnapzyTests
//
//  Studio layers, captions typography & local font resolution, timeline gap closing,
//  hostile-input safety, and opt-in SHA-256 verified SIL OFL 1.1 font downloads.
//

import CoreMedia
import Foundation
@testable import Snapzy
import XCTest

#if canImport(FoundationModels)
  import FoundationModels
#endif

private final class MockOFLFontURLProtocol: URLProtocol {
  nonisolated(unsafe) static var responder: ((URLRequest) throws -> (HTTPURLResponse, [Data]))?
  private static let lock = NSLock()
  private nonisolated(unsafe) static var recordedURLsStorage: [URL] = []

  static func reset() {
    lock.lock()
    responder = nil
    recordedURLsStorage = []
    lock.unlock()
  }

  static var recordedURLs: [URL] {
    lock.lock()
    defer { lock.unlock() }
    return recordedURLsStorage
  }

  override class func canInit(with _: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    if let url = request.url {
      Self.lock.lock()
      Self.recordedURLsStorage.append(url)
      Self.lock.unlock()
    }
    guard let handler = Self.responder else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    do {
      let (response, chunks) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      for chunk in chunks {
        client?.urlProtocol(self, didLoad: chunk)
      }
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

@MainActor
final class VideoEditorStudioAgentTests: XCTestCase {
  private var tempDirectory: URL!
  private var states: [VideoEditorState] = []
  private var registeredTestFontIds: [String] = []

  override func setUp() {
    super.setUp()
    MockOFLFontURLProtocol.reset()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_StudioAgent_\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDown() {
    for familyId in registeredTestFontIds {
      VideoEditorFontResolver.unregisterFamily(familyId)
    }
    registeredTestFontIds = []
    MockOFLFontURLProtocol.reset()
    try? FileManager.default.removeItem(at: tempDirectory)
    states = []
    super.tearDown()
  }

  /// Fixed ids, so values compare equal across calls.
  private let ids = [UUID(), UUID()]

  private func captions() -> VideoEditorCaptions {
    var value = VideoEditorCaptions(segments: [
      CaptionSegment(id: ids[0], sourceRange: 1 ... 3, text: "Hello there"),
      CaptionSegment(id: ids[1], sourceRange: 5 ... 7, text: "Second line"),
    ])
    value.settings.position = .top
    return value
  }

  // MARK: - Session

  func testEditStateKeepsStudioLayersAndOldManifestsStillDecode() throws {
    var cursor = VideoEditorCursorSettings.default
    cursor.scale = 1.5
    var camera = VideoEditorCameraSettings.default
    camera.shape = RecordingCameraShape.circle.rawValue
    let session = VideoEditorSessionData(
      sourceSnapshotURL: URL(fileURLWithPath: "/tmp/x.mov"),
      cursorSettings: cursor, cameraSettings: camera, captions: captions()
    )
    let data = try JSONEncoder().encode(PersistedVideoEditorEditState(sessionData: session))
    let decoded = try JSONDecoder().decode(PersistedVideoEditorEditState.self, from: data)
      .sessionData(sourceSnapshotURL: session.sourceSnapshotURL, recordingMetadata: nil)
    XCTAssertEqual(decoded.cursorSettings, cursor)
    XCTAssertEqual(decoded.cameraSettings, camera)
    XCTAssertEqual(decoded.captions, captions())

    // A manifest written before these fields existed.
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["cursorSettings"] = nil
    object["cameraSettings"] = nil
    object["captions"] = nil
    let old = try JSONDecoder().decode(
      PersistedVideoEditorEditState.self, from: JSONSerialization.data(withJSONObject: object)
    )
    XCTAssertNil(old.cursorSettings)
    XCTAssertNil(old.captions)
  }

  func testRestoredSessionBringsCaptionsBackAsTheCleanBaseline() async throws {
    let url = try await VideoEditorActivityFixture.makeVideoFile(in: tempDirectory, duration: 12, audio: true)
    let state = VideoEditorState(
      url: url,
      sessionData: VideoEditorSessionData(
        sourceSnapshotURL: url, clips: [TimelineClip(source: .primary, sourceDuration: 12)], captions: captions()
      )
    )
    states.append(state)
    await state.loadMetadata()
    XCTAssertEqual(state.captions, captions())
    XCTAssertFalse(state.hasUnsavedChanges)

    let snapshot = VideoEditorSessionData.snapshot(from: state, sourceSnapshotURL: url)
    XCTAssertEqual(snapshot.captions, captions())
    XCTAssertNil(snapshot.cursorSettings, "no editable cursor: nothing to save")
  }

  // MARK: - Agent tools

  private func makeToolbox() async throws -> (VideoEditorState, VideoEditorAgentToolbox) {
    let state = try await VideoEditorActivityFixture.makeState(in: tempDirectory, cursor: false)
    states.append(state)
    return (state, VideoEditorAgentToolbox(state: state))
  }

  private func call(_ toolbox: VideoEditorAgentToolbox, _ name: String, _ json: String = "{}") -> AgentToolResult {
    toolbox.execute(name: name, arguments: Data(json.utf8))
  }

  func testCursorAndCameraToolsExplainWhenTheRecordingCannotBeEdited() async throws {
    let (_, toolbox) = try await makeToolbox()
    XCTAssertTrue(call(toolbox, "set_cursor", #"{"visible": false}"#).text.contains("Studio"))
    XCTAssertTrue(call(toolbox, "set_camera", #"{"visible": false}"#).isError)
    let timeline = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(call(toolbox, "get_timeline").text.utf8)) as? [String: Any]
    )
    XCTAssertNil(timeline["cursor"])
    XCTAssertNil(timeline["captions"])
    let availableFonts = try XCTUnwrap(timeline["available_fonts"] as? [String])
    XCTAssertTrue(availableFonts.contains("system"))
  }

  func testEditCaptionChangesTextTimingTypographyAndClosesSlotGapsInOneUndoStep() async throws {
    let (state, toolbox) = try await makeToolbox()
    state.setCaptions(captions(), recordUndo: false)

    let timeline = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(call(toolbox, "get_timeline").text.utf8)) as? [String: Any]
    )
    let listed = try XCTUnwrap((timeline["captions"] as? [String: Any])?["items"] as? [[String: Any]])
    XCTAssertEqual(listed.map { $0["id"] as? String }, ["t1", "t2"])
    XCTAssertEqual(listed[1]["start"] as? Double ?? 0, 5, accuracy: 0.01)

    toolbox.beginRun()
    XCTAssertFalse(call(toolbox, "edit_caption", #"{"id": "t1", "text": "Hi", "end": 4}"#).isError)
    XCTAssertFalse(call(toolbox, "edit_caption", #"{"id": "t2", "text": ""}"#).isError)
    XCTAssertFalse(
      call(
        toolbox,
        "edit_caption",
        #"{"position": "bottom", "show_on_video": false, "font": "system", "font_weight": 800, "italic": true}"#
      ).isError
    )
    XCTAssertTrue(call(toolbox, "edit_caption", #"{"text": "no id"}"#).isError)

    // Trim `c1` non-destructively to leave dead-space slot padding, then collapse via `close_gaps`.
    XCTAssertFalse(call(toolbox, "trim_clip", #"{"clip": "c1", "start": 1.0, "end": 10.0}"#).isError)
    XCTAssertEqual(CMTimeGetSeconds(state.timelineDuration), 12.0, accuracy: 0.05)
    let closed = call(toolbox, "close_gaps", #"{"clip": "all"}"#)
    XCTAssertFalse(closed.isError, closed.text)
    XCTAssertEqual(CMTimeGetSeconds(state.timelineDuration), 9.0, accuracy: 0.05)
    toolbox.finishRun()

    XCTAssertEqual(state.captions.segments.map(\.text), ["Hi"])
    XCTAssertEqual(state.captions.segments[0].end, 4, accuracy: 0.01)
    XCTAssertEqual(state.captions.settings.position, .bottom)
    XCTAssertEqual(state.captions.settings.fontWeight, 800)
    XCTAssertTrue(state.captions.settings.isItalic)
    XCTAssertFalse(state.captions.settings.isEnabled)

    state.undo()
    XCTAssertEqual(state.captions, captions())
    XCTAssertEqual(CMTimeGetSeconds(state.timelineDuration), 12.0, accuracy: 0.05)
  }

  // MARK: - Hostile-Input & Explicit Destructive Target Guards

  func testDestructiveAndGlobalAgentToolsRequireExplicitIdOrAll() async throws {
    let (state, toolbox) = try await makeToolbox()
    state.setCaptions(captions(), recordUndo: false)
    _ = call(toolbox, "get_timeline")
    XCTAssertFalse(call(toolbox, "add_zoom", #"{"start": 1.0, "duration": 2.0}"#).isError)
    XCTAssertFalse(call(toolbox, "add_speed", #"{"start": 4.0, "end": 6.0, "rate": 2.0}"#).isError)
    XCTAssertFalse(call(toolbox, "trim_clip", #"{"clip": "c1", "start": 1.0, "end": 10.0}"#).isError)
    _ = call(toolbox, "get_timeline")

    // 1. remove_captions rejects empty/blank ids without removing captions.
    XCTAssertTrue(call(toolbox, "remove_captions", #"{"ids": []}"#).isError)
    XCTAssertTrue(call(toolbox, "remove_captions", #"{"ids": ["  "]}"#).isError)
    XCTAssertEqual(state.captions.segments.count, 2)

    // 2. remove_zoom and remove_speed reject empty/blank ids.
    XCTAssertTrue(call(toolbox, "remove_zoom", #"{"ids": []}"#).isError)
    XCTAssertTrue(call(toolbox, "remove_zoom", #"{"ids": [" "]}"#).isError)
    XCTAssertEqual(state.zoomSegments.count, 1)

    XCTAssertTrue(call(toolbox, "remove_speed", #"{"ids": []}"#).isError)
    XCTAssertTrue(call(toolbox, "remove_speed", #"{"ids": [""]}"#).isError)
    XCTAssertEqual(state.speedSegments.count, 1)

    // 3. close_gaps rejects missing/blank clip instead of silently collapsing all gaps.
    XCTAssertTrue(call(toolbox, "close_gaps", #"{}"#).isError)
    XCTAssertTrue(call(toolbox, "close_gaps", #"{"clip": " "}"#).isError)
    XCTAssertEqual(CMTimeGetSeconds(state.timelineDuration), 12.0, accuracy: 0.05)

    // 4. Apple Intelligence captions wrapper also requires explicit id on clear/remove.
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        let session = AgentSession(toolbox: toolbox, pacingEnabled: false, onToolCall: { _ in })
        let appleCaptions = VideoAppleCaptionsTool(bridge: VideoAppleToolBridge(session: session))
        let clearNoId = try await appleCaptions.call(
          arguments: VideoAppleCaptionsTool.Arguments(GeneratedContent(properties: ["action": "clear"]))
        )
        XCTAssertTrue(clearNoId.contains("\"ok\":false"), clearNoId)
        XCTAssertEqual(state.captions.segments.count, 2)
      }
    #endif

    // Explicit "all" succeeds cleanly across each tool.
    XCTAssertFalse(call(toolbox, "close_gaps", #"{"clip": "all"}"#).isError)
    XCTAssertEqual(CMTimeGetSeconds(state.timelineDuration), 9.0, accuracy: 0.05)

    XCTAssertFalse(call(toolbox, "remove_zoom", #"{"ids": ["all"]}"#).isError)
    XCTAssertTrue(state.zoomSegments.isEmpty)

    XCTAssertFalse(call(toolbox, "remove_speed", #"{"ids": ["all"]}"#).isError)
    XCTAssertTrue(state.speedSegments.isEmpty)

    XCTAssertFalse(call(toolbox, "remove_captions", #"{"ids": ["all"]}"#).isError)
    XCTAssertTrue(state.captions.segments.isEmpty)
  }

  func testAgentToolsClampIntMinAndIntMaxWithoutOverflow() async throws {
    let (state, toolbox) = try await makeToolbox()
    state.setCaptions(captions(), recordUndo: false)
    _ = call(toolbox, "get_timeline")

    // 1. Overflow-safe 1-based index helper never traps on Int.min or Int.max.
    XCTAssertEqual(VideoEditorAgentStudioTools.clampedZeroBasedIndex(Int.min, maxCount: 6), 0)
    XCTAssertEqual(VideoEditorAgentStudioTools.clampedZeroBasedIndex(Int.max, maxCount: 6), 5)

    // 2. edit_caption with Int.min and Int.max font_weight clamps safely to 400 and 900.
    XCTAssertFalse(call(toolbox, "edit_caption", "{\"font_weight\":\(Int.min)}").isError)
    XCTAssertEqual(state.captions.settings.fontWeight, 400)

    XCTAssertFalse(call(toolbox, "edit_caption", "{\"font_weight\":\(Int.max)}").isError)
    XCTAssertEqual(state.captions.settings.fontWeight, 900)

    // 3. move_clip with Int.min and Int.max rejects cleanly without arithmetic overflow.
    XCTAssertFalse(call(toolbox, "split", #"{"time": 4.0}"#).isError)
    _ = call(toolbox, "get_timeline")
    XCTAssertTrue(call(toolbox, "move_clip", "{\"clip\":\"c1\",\"position\":\(Int.min)}").isError)
    XCTAssertTrue(call(toolbox, "move_clip", "{\"clip\":\"c1\",\"position\":\(Int.max)}").isError)
  }

  func testAgentFontResolutionNeverTriggersNetworkDownload() async throws {
    let (state, toolbox) = try await makeToolbox()
    state.setCaptions(captions(), recordUndo: false)

    let unknownFont = call(toolbox, "edit_caption", #"{"font":"NonExistentFontFamily_999"}"#)
    XCTAssertTrue(unknownFont.isError)
    XCTAssertEqual(state.captions.settings.customFontId, VideoEditorFontResolver.defaultFamilyId)

    if let uninstalledCatalog = VideoEditorFontManager.curatedCatalog.first(where: {
      !VideoEditorFontManager.shared.downloadedCatalogIds.contains($0.id)
        && VideoEditorFontResolver.installedFamilyName(for: $0.displayName) == nil
    }) {
      let catalogAttempt = call(toolbox, "edit_caption", "{\"font\":\"\(uninstalledCatalog.id)\"}")
      XCTAssertTrue(catalogAttempt.isError)
      XCTAssertEqual(state.captions.settings.customFontId, VideoEditorFontResolver.defaultFamilyId)
    }

    // Installed system font family resolves locally without network access.
    if let installed = VideoEditorFontManager.shared.installedFamilies.first {
      let ok = call(toolbox, "edit_caption", "{\"font\":\"\(installed.familyName)\"}")
      XCTAssertFalse(ok.isError, ok.text)
      XCTAssertEqual(state.captions.settings.customFontId, installed.id)
    }
  }

  // MARK: - Opt-In SHA-256 Verified OFL Font Downloads

  func testOFLCatalogFontDownloadVerifiesSHA256Enforces5MBCapAndPersistsLicense() async throws {
    XCTAssertEqual(VideoEditorFontManager.curatedCatalog.count, 8)
    XCTAssertEqual(VideoEditorFontManager.maxDownloadAssetBytes, 5_242_880)
    let hexSet = CharacterSet(charactersIn: "0123456789abcdef")

    for family in VideoEditorFontManager.curatedCatalog {
      XCTAssertFalse(family.files.isEmpty, family.id)
      XCTAssertEqual(family.licenseAsset.fileName, "OFL.txt", family.id)
      for asset in family.files + [family.licenseAsset] {
        let url = try XCTUnwrap(asset.downloadURL, asset.relativePath)
        XCTAssertTrue(
          url.absoluteString.hasPrefix(VideoEditorFontManager.pinnedGoogleFontsBaseURL),
          "Unpinned font URL: \(url)"
        )
        XCTAssertEqual(asset.sha256.count, 64, asset.fileName)
        XCTAssertTrue(asset.sha256.unicodeScalars.allSatisfy { hexSet.contains($0) }, asset.fileName)
      }
    }

    let candidateFontPaths = [
      "/System/Library/Fonts/Keyboard.ttf",
      "/System/Library/Fonts/Monaco.ttf",
      "/System/Library/Fonts/Geneva.ttf",
      "/System/Library/Fonts/Apple Braille.ttf",
    ]
    let sampleFontURL = try XCTUnwrap(
      candidateFontPaths.map(URL.init(fileURLWithPath:)).first { FileManager.default.fileExists(atPath: $0.path) }
    )
    let validFontData = try Data(contentsOf: sampleFontURL)
    XCTAssertLessThan(validFontData.count, VideoEditorFontManager.maxDownloadAssetBytes)
    let validFontSHA = VideoEditorFontManager.sha256Hex(of: validFontData)

    let expectedLicenseText = """
    Copyright 2026 Test Foundry Project Authors
    This Font Software is licensed under the SIL Open Font License, Version 1.1.
    """
    let validLicenseData = Data(expectedLicenseText.utf8)
    let validLicenseSHA = VideoEditorFontManager.sha256Hex(of: validLicenseData)

    let testFamilyId = "test-ofl-\(UUID().uuidString.prefix(8).lowercased())"
    registeredTestFontIds.append(testFamilyId)
    let testFamily = VideoEditorCatalogFontFamily(
      id: testFamilyId,
      displayName: "Test OFL Family",
      categoryLabel: "Sans",
      files: [
        VideoEditorCatalogFontAsset(
          relativePath: "testfamily/TestFamily-Regular.ttf",
          fileName: "TestFamily-Regular.ttf",
          sha256: validFontSHA
        ),
      ],
      licenseAsset: VideoEditorCatalogFontAsset(
        relativePath: "testfamily/OFL.txt",
        fileName: "OFL.txt",
        sha256: validLicenseSHA
      )
    )

    let fontStorageDir = tempDirectory.appendingPathComponent("Fonts", isDirectory: true)
    let sessionConfig = URLSessionConfiguration.ephemeral
    sessionConfig.protocolClasses = [MockOFLFontURLProtocol.self]
    let manager = VideoEditorFontManager(
      storageRootURL: fontStorageDir,
      urlSessionConfiguration: sessionConfig
    )
    XCTAssertTrue(
      MockOFLFontURLProtocol.recordedURLs.isEmpty,
      "Initializing VideoEditorFontManager must never make network requests"
    )

    // Case A: Tampered payload fails SHA-256 check BEFORE writing to disk.
    MockOFLFontURLProtocol.responder = { request in
      let url = try XCTUnwrap(request.url)
      let response = try XCTUnwrap(
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)
      )
      return (response, [Data("tampered-font-binary".utf8)])
    }
    do {
      try await manager.downloadCatalogFont(testFamily)
      XCTFail("Expected checksumMismatch error")
    } catch let error as VideoEditorFontDownloadError {
      XCTAssertEqual(error, .checksumMismatch(fileName: "TestFamily-Regular.ttf"))
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: fontStorageDir.appendingPathComponent(testFamilyId).path))
    XCTAssertFalse(manager.downloadedCatalogIds.contains(testFamilyId))

    // Case B: Stream exceeding 5 MB (5_242_880 bytes) without Content-Length is aborted mid-stream.
    let oneMegabyte = Data(repeating: 0x41, count: 1_048_576)
    MockOFLFontURLProtocol.responder = { request in
      let url = try XCTUnwrap(request.url)
      let response = try XCTUnwrap(
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)
      )
      return (response, [oneMegabyte, oneMegabyte, oneMegabyte, oneMegabyte, oneMegabyte, Data([0x42])])
    }
    do {
      try await manager.downloadCatalogFont(testFamily)
      XCTFail("Expected fileTooLarge error")
    } catch let error as VideoEditorFontDownloadError {
      XCTAssertEqual(error, .fileTooLarge(maxBytes: VideoEditorFontManager.maxDownloadAssetBytes))
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: fontStorageDir.appendingPathComponent(testFamilyId).path))

    // Case C: HTTP 404 fails cleanly.
    MockOFLFontURLProtocol.responder = { request in
      let url = try XCTUnwrap(request.url)
      let response = try XCTUnwrap(
        HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)
      )
      return (response, [])
    }
    do {
      try await manager.downloadCatalogFont(testFamily)
      XCTFail("Expected httpStatus(404) error")
    } catch let error as VideoEditorFontDownloadError {
      XCTAssertEqual(error, .httpStatus(404))
    }

    // Case D: Valid SHA-256 font + OFL.txt succeeds, registers font, and persists OFL.txt.
    MockOFLFontURLProtocol.responder = { request in
      let url = try XCTUnwrap(request.url)
      let body = url.lastPathComponent == "OFL.txt" ? validLicenseData : validFontData
      let response = try XCTUnwrap(
        HTTPURLResponse(
          url: url,
          statusCode: 200,
          httpVersion: "HTTP/1.1",
          headerFields: ["Content-Length": "\(body.count)"]
        )
      )
      return (response, [body])
    }
    try await manager.downloadCatalogFont(testFamily)
    XCTAssertTrue(manager.downloadedCatalogIds.contains(testFamilyId))
    XCTAssertTrue(manager.isFontAvailable(testFamilyId))
    XCTAssertTrue(VideoEditorFontResolver.isFamilyRegistered(testFamilyId))
    XCTAssertEqual(manager.licenseText(for: testFamilyId), expectedLicenseText)
  }

  // MARK: - Mock planner

  func testMockPlansCursorVietnameseCaptionsAndCloseGaps() {
    let calls = VideoEditorAgentMockProvider.plan(for: "ẩn cursor, phóng to cursor 1.5x, thêm phụ đề tiếng Việt")
    XCTAssertEqual(calls.map(\.name), ["set_cursor", "set_cursor", "generate_captions"])
    XCTAssertTrue(calls[0].arguments.contains(#""visible":false"#))
    XCTAssertTrue(calls[1].arguments.contains(#""scale":1.5"#))
    XCTAssertTrue(calls[2].arguments.contains("vi-VN"))

    let gapCalls = VideoEditorAgentMockProvider.plan(for: "close all gaps")
    XCTAssertEqual(gapCalls.map(\.name), ["close_gaps"])
    XCTAssertTrue(gapCalls[0].arguments.contains(#""clip":"all""#))
  }
}
