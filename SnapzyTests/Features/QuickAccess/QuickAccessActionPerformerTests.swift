//
//  QuickAccessActionPerformerTests.swift
//  SnapzyTests
//
//  Milestone 6 phase 02: Quick Access copy / upload run the automation step
//  handlers (fake environment: no pasteboard, network or windows).
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class QuickAccessActionPerformerTests: XCTestCase {
  private var directory: URL!
  private var environment: FakeAutomationEnvironment!
  private var replacedKeys: [String?] = []
  private var performer: QuickAccessActionPerformer!

  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = FileManager.default.temporaryDirectory.appendingPathComponent("QuickAccessActionPerformerTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    environment = FakeAutomationEnvironment()
    replacedKeys = []
    performer = QuickAccessActionPerformer(environment: { [unowned self] key in
      replacedKeys.append(key)
      return environment
    })
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    try super.tearDownWithError()
  }

  private func item(_ name: String, duration: TimeInterval? = nil) throws -> QuickAccessItem {
    let url = directory.appendingPathComponent(name)
    try Data([0, 1, 2, 3]).write(to: url)
    let thumbnail = NSImage(size: NSSize(width: 1, height: 1))
    if let duration {
      return QuickAccessItem(url: url, thumbnail: thumbnail, duration: duration)
    }
    return QuickAccessItem(url: url, thumbnail: thumbnail)
  }

  func testCopyScreenshotCopiesImage() async throws {
    let screenshot = try item("shot.png")

    await performer.copy(screenshot)

    XCTAssertEqual(environment.copiedImages, [[screenshot.url]])
    XCTAssertTrue(environment.copiedMedia.isEmpty)
  }

  func testCopyVideoCopiesFileReference() async throws {
    let video = try item("clip.mp4", duration: 3)

    await performer.copy(video)

    XCTAssertEqual(environment.copiedMedia, [video.url])
    XCTAssertTrue(environment.copiedImages.isEmpty)
  }

  func testCopyUploadedItemCopiesItsLink() async throws {
    var uploaded = try item("shot.png")
    uploaded.cloudURL = URL(string: "https://cdn.example.com/shot.png")

    await performer.copy(uploaded)

    XCTAssertEqual(environment.copiedTexts, ["https://cdn.example.com/shot.png"])
    XCTAssertTrue(environment.copiedImages.isEmpty)
  }

  func testUploadSetsCardLinkCopiesURLAndReplacesOldObject() async throws {
    var card = try item("shot.png")
    card.cloudKey = "old-key"

    let result = try await performer.upload(card)

    XCTAssertEqual(environment.uploaded, [card.url])
    XCTAssertEqual(environment.copiedTexts, [result.publicURL.absoluteString])
    XCTAssertEqual(environment.cloudLinks[card.id], result.publicURL)
    XCTAssertEqual(replacedKeys, ["old-key"])
  }

  func testUploadWithoutCloudThrowsAndCopiesNothing() async throws {
    environment.isCloudConfigured = false
    let card = try item("shot.png")

    do {
      try await performer.upload(card)
      XCTFail("Expected an error")
    } catch {
      XCTAssertEqual(error as? AutomationStepError, .cloudNotConfigured)
    }
    XCTAssertTrue(environment.copiedTexts.isEmpty)
  }
}
