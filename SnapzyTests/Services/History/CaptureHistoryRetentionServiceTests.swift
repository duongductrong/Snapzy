//
//  CaptureHistoryRetentionServiceTests.swift
//  SnapzyTests
//
//  Unit tests for retention service scheduling and sweep logic.
//  Verifies via synchronous DB reads to avoid observation timing issues.
//

import Foundation
import XCTest
@testable import Snapzy

@MainActor
final class CaptureHistoryRetentionServiceTests: XCTestCase {

  private var service: CaptureHistoryRetentionService!
  private var defaults: UserDefaults!
  private var defaultsSuiteName: String!
  private var tempDirectory: URL!
  private var annotationSessionStore: AnnotationSessionStore!
  private var videoEditorSessionStore: VideoEditorSessionStore!

  override func setUp() {
    super.setUp()
    service = CaptureHistoryRetentionService.shared
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_CaptureHistoryRetention_\(UUID().uuidString)", isDirectory: true)
    annotationSessionStore = AnnotationSessionStore(
      rootDirectory: tempDirectory.appendingPathComponent("AnnotationSessions", isDirectory: true)
    )
    videoEditorSessionStore = VideoEditorSessionStore(
      rootDirectory: tempDirectory.appendingPathComponent("VideoEditorSessions", isDirectory: true)
    )
    defaultsSuiteName = "SnapzyTests.CaptureHistoryRetentionServiceTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: defaultsSuiteName)
    defaults.removePersistentDomain(forName: defaultsSuiteName)
    defaults.set(true, forKey: PreferencesKeys.historyEnabled)
    defaults.set(0, forKey: PreferencesKeys.historyRetentionDays)
    defaults.set(0, forKey: PreferencesKeys.historyMaxCount)
    CaptureHistoryStore.shared.userDefaults = defaults
    service.userDefaults = defaults
    service.annotationSessionStore = annotationSessionStore
    service.videoEditorSessionStore = videoEditorSessionStore

    CaptureHistoryStore.shared.removeAll()
    CaptureHistoryStore.shared.refreshRecords()
  }

  override func tearDown() {
    service.stop()
    CaptureHistoryStore.shared.removeAll()
    CaptureHistoryStore.shared.refreshRecords()
    UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName)
    CaptureHistoryStore.shared.userDefaults = .standard
    service.userDefaults = .standard
    service.annotationSessionStore = .shared
    service.videoEditorSessionStore = .shared
    try? FileManager.default.removeItem(at: tempDirectory)
    annotationSessionStore = nil
    videoEditorSessionStore = nil
    tempDirectory = nil
    super.tearDown()
  }

  // MARK: - sweep

  func testSweep_skipsWhenHistoryDisabled() async {
    defaults.set(false, forKey: PreferencesKeys.historyEnabled)
    await service.sweep()
  }

  func testSweep_noOpWhenRetentionDaysZeroAndMaxCountZero() async {
    let record = makeRecord()
    CaptureHistoryStore.shared.add(record)
    CaptureHistoryStore.shared.refreshRecords()
    XCTAssertTrue(CaptureHistoryStore.shared.hasRecord(forFilePath: record.filePath))

    await service.sweep()
    XCTAssertTrue(CaptureHistoryStore.shared.hasRecord(forFilePath: record.filePath))
  }

  func testSweep_removesOldRecordsWhenRetentionDaysSet() async {
    defaults.set(7, forKey: PreferencesKeys.historyRetentionDays)
    let old = makeRecord(capturedAt: Date().addingTimeInterval(-86400 * 10))
    let recent = makeRecord(capturedAt: Date())
    CaptureHistoryStore.shared.add(old)
    CaptureHistoryStore.shared.add(recent)
    CaptureHistoryStore.shared.refreshRecords()

    await service.sweep()
    CaptureHistoryStore.shared.refreshRecords()
    XCTAssertFalse(CaptureHistoryStore.shared.hasRecord(forFilePath: old.filePath))
    XCTAssertTrue(CaptureHistoryStore.shared.hasRecord(forFilePath: recent.filePath))
  }

  func testSweep_trimsToMaxCount() async {
    defaults.set(2, forKey: PreferencesKeys.historyMaxCount)
    let r1 = makeRecord(capturedAt: Date().addingTimeInterval(-10))
    let r2 = makeRecord(capturedAt: Date().addingTimeInterval(-5))
    let r3 = makeRecord(capturedAt: Date())
    CaptureHistoryStore.shared.add(r1)
    CaptureHistoryStore.shared.add(r2)
    CaptureHistoryStore.shared.add(r3)
    CaptureHistoryStore.shared.refreshRecords()

    await service.sweep()
    CaptureHistoryStore.shared.refreshRecords()
    let ids = Set(CaptureHistoryStore.shared.records.map(\.id))
    XCTAssertEqual(ids.count, 2)
    XCTAssertTrue(ids.contains(r2.id))
    XCTAssertTrue(ids.contains(r3.id))
  }

  // MARK: - clearAllHistory

  func testClearAllHistory_removesAllRecordsAndThumbnails() {
    CaptureHistoryStore.shared.add(makeRecord())
    CaptureHistoryStore.shared.refreshRecords()

    service.clearAllHistory()
    CaptureHistoryStore.shared.refreshRecords()
    XCTAssertTrue(CaptureHistoryStore.shared.records.isEmpty)
  }

  func testClearAllHistory_removesAnnotationSidecars() throws {
    let sourceURL = try writeSourceFile(named: "capture.png")
    XCTAssertTrue(annotationSessionStore.persist(makeSessionData(), for: sourceURL))
    XCTAssertNotNil(annotationSessionStore.load(for: sourceURL))

    service.clearAllHistory()

    XCTAssertNil(annotationSessionStore.load(for: sourceURL))
  }

  func testClearAllHistory_removesVideoEditorSidecars() throws {
    let sourceURL = try writeSourceFile(named: "capture.mov")
    let masterURL = try writeSourceFile(named: "capture-master.mov")
    let sessionData = VideoEditorSessionData(sourceSnapshotURL: masterURL)
    XCTAssertTrue(videoEditorSessionStore.persist(sessionData, for: sourceURL))
    XCTAssertNotNil(videoEditorSessionStore.load(for: sourceURL))

    service.clearAllHistory()

    XCTAssertNil(videoEditorSessionStore.load(for: sourceURL))
  }

  func testSweep_cleansOrphanedAnnotationSidecars() async throws {
    let activeURL = try writeSourceFile(named: "active.png")
    let inactiveURL = try writeSourceFile(named: "inactive.png")
    let missingURL = try writeSourceFile(named: "missing.png")

    CaptureHistoryStore.shared.add(makeRecord(filePath: activeURL.path))
    CaptureHistoryStore.shared.refreshRecords()
    XCTAssertTrue(annotationSessionStore.persist(makeSessionData(), for: activeURL))
    XCTAssertTrue(annotationSessionStore.persist(makeSessionData(), for: inactiveURL))
    XCTAssertTrue(annotationSessionStore.persist(makeSessionData(), for: missingURL))
    try FileManager.default.removeItem(at: missingURL)

    await service.sweep()

    XCTAssertNotNil(annotationSessionStore.load(for: activeURL))
    XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarDirectory(for: inactiveURL).path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarDirectory(for: missingURL).path))
  }

  func testSweep_cleansOrphanedVideoEditorSidecars() async throws {
    let activeURL = try writeSourceFile(named: "active.mov")
    let inactiveURL = try writeSourceFile(named: "inactive.mov")
    let activeMasterURL = try writeSourceFile(named: "active-master.mov")
    let inactiveMasterURL = try writeSourceFile(named: "inactive-master.mov")

    CaptureHistoryStore.shared.add(makeRecord(filePath: activeURL.path))
    CaptureHistoryStore.shared.refreshRecords()
    XCTAssertTrue(
      videoEditorSessionStore.persist(
        VideoEditorSessionData(sourceSnapshotURL: activeMasterURL),
        for: activeURL
      )
    )
    XCTAssertTrue(
      videoEditorSessionStore.persist(
        VideoEditorSessionData(sourceSnapshotURL: inactiveMasterURL),
        for: inactiveURL
      )
    )

    await service.sweep()

    XCTAssertNotNil(videoEditorSessionStore.load(for: activeURL))
    XCTAssertFalse(FileManager.default.fileExists(atPath: videoSessionDirectory(for: inactiveURL).path))
  }

  // MARK: - start / stop

  func testStartStop_lifecycleDoesNotCrash() {
    service.start()
    service.stop()
    service.start()
    service.stop()
  }

  // MARK: - Helpers

  private func makeRecord(capturedAt: Date = Date()) -> CaptureHistoryRecord {
    let path = "/tmp/\(UUID().uuidString).png"
    return makeRecord(filePath: path, capturedAt: capturedAt)
  }

  private func makeRecord(filePath path: String, capturedAt: Date = Date()) -> CaptureHistoryRecord {
    return CaptureHistoryRecord(
      id: UUID(),
      filePath: path,
      fileName: (path as NSString).lastPathComponent,
      captureType: .screenshot,
      fileSize: 1024,
      capturedAt: capturedAt,
      width: 100,
      height: 100,
      duration: nil,
      thumbnailPath: nil,
      isDeleted: false
    )
  }

  private func makeSessionData() -> AnnotationSessionData {
    AnnotationSessionData(
      originalImageData: Data("original".utf8),
      annotations: [
        AnnotationItem(
          type: .text("History"),
          bounds: CGRect(x: 0, y: 0, width: 40, height: 16),
          properties: AnnotationProperties()
        )
      ],
      canvasEffects: AnnotationCanvasEffects(),
      cropRect: nil
    )
  }

  private func writeSourceFile(named fileName: String) throws -> URL {
    let directory = tempDirectory.appendingPathComponent("Sources", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(fileName)
    try Data("source-\(fileName)".utf8).write(to: url, options: .atomic)
    return url
  }

  private func sidecarDirectory(for sourceURL: URL) -> URL {
    let normalizedPath = AnnotationSessionStore.normalizedPath(for: sourceURL)
    return tempDirectory
      .appendingPathComponent("AnnotationSessions", isDirectory: true)
      .appendingPathComponent(AnnotationSessionStore.pathHash(for: normalizedPath), isDirectory: true)
  }

  private func videoSessionDirectory(for sourceURL: URL) -> URL {
    let normalizedPath = VideoEditorSessionStore.normalizedPath(for: sourceURL)
    return tempDirectory
      .appendingPathComponent("VideoEditorSessions", isDirectory: true)
      .appendingPathComponent(VideoEditorSessionStore.pathHash(for: normalizedPath), isDirectory: true)
  }
}
