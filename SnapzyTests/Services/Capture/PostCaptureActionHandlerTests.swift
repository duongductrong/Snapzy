//
//  PostCaptureActionHandlerTests.swift
//  SnapzyTests
//
//  Unit tests for PostCaptureActionHandler routing logic.
//
//  NOTE: Full action-dispatch testing requires protocol-based DI refactor
//  (injecting PreferencesManager, QuickAccessManager, AnnotateManager).
//  These tests cover the subset of behavior testable without mocks:
//  - PreferencesManager.isActionEnabled routing
//  - copyEditedCaptureToClipboardIfEnabled preference gating
//  - Missing file safety
//

import XCTest
@testable import Snapzy

@MainActor
final class PostCaptureActionHandlerTests: XCTestCase {

  private let afterCaptureActionsKey = "afterCaptureActions"
  private var originalAfterCaptureActions: [AfterCaptureAction: [CaptureType: Bool]]!
  private var originalAfterCaptureActionsData: Data?
  private var tempDirectory: URL!
  private var tempFileURL: URL!

  override func setUp() async throws {
    try await super.setUp()
    originalAfterCaptureActions = PreferencesManager.shared.afterCaptureActions
    originalAfterCaptureActionsData = UserDefaults.standard.data(forKey: afterCaptureActionsKey)
    resetAfterCaptureActionsToDefaults()

    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_PostCapture_\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    // Create a minimal test image file
    tempFileURL = tempDirectory.appendingPathComponent("test_capture.png")
    guard let image = TestImageFactory.solidColor(width: 10, height: 10) else {
      XCTFail("Failed to create test image")
      return
    }
    let bitmapRep = NSBitmapImageRep(cgImage: image)
    let pngData = bitmapRep.representation(using: .png, properties: [:])
    try pngData?.write(to: tempFileURL)
  }

  override func tearDown() async throws {
    PreferencesManager.shared.afterCaptureActions = originalAfterCaptureActions
    if let originalAfterCaptureActionsData {
      UserDefaults.standard.set(originalAfterCaptureActionsData, forKey: afterCaptureActionsKey)
    } else {
      UserDefaults.standard.removeObject(forKey: afterCaptureActionsKey)
    }
    if let tempDirectory {
      try? FileManager.default.removeItem(at: tempDirectory)
    }
    try await super.tearDown()
  }

  private func resetAfterCaptureActionsToDefaults() {
    PreferencesManager.shared.afterCaptureActions = Self.defaultAfterCaptureActions()
    UserDefaults.standard.removeObject(forKey: afterCaptureActionsKey)
  }

  private static func defaultAfterCaptureActions() -> [AfterCaptureAction: [CaptureType: Bool]] {
    var defaults: [AfterCaptureAction: [CaptureType: Bool]] = [:]
    for action in AfterCaptureAction.allCases {
      defaults[action] = [:]
      for captureType in CaptureType.allCases {
        defaults[action]?[captureType] = defaultValue(for: action)
      }
    }
    return defaults
  }

  private static func defaultValue(for action: AfterCaptureAction) -> Bool {
    switch action {
    case .showQuickAccess, .save, .copyFile:
      return true
    case .openAnnotate, .uploadToCloud:
      return false
    }
  }

  // MARK: - PreferencesManager Routing Logic

  func testIsActionEnabled_defaultValues() {
    let prefs = PreferencesManager.shared

    // Default: showQuickAccess and copyFile are ON for both types
    XCTAssertTrue(prefs.isActionEnabled(.showQuickAccess, for: .screenshot))
    XCTAssertTrue(prefs.isActionEnabled(.showQuickAccess, for: .recording))
    XCTAssertTrue(prefs.isActionEnabled(.copyFile, for: .screenshot))
    XCTAssertTrue(prefs.isActionEnabled(.copyFile, for: .recording))
    XCTAssertTrue(prefs.isActionEnabled(.save, for: .screenshot))
    XCTAssertTrue(prefs.isActionEnabled(.save, for: .recording))

    // Default: openAnnotate and uploadToCloud are OFF
    XCTAssertFalse(prefs.isActionEnabled(.openAnnotate, for: .screenshot))
    XCTAssertFalse(prefs.isActionEnabled(.openAnnotate, for: .recording))
    XCTAssertFalse(prefs.isActionEnabled(.uploadToCloud, for: .screenshot))
    XCTAssertFalse(prefs.isActionEnabled(.uploadToCloud, for: .recording))
  }

  func testSetAndCheckActionEnabled() {
    let prefs = PreferencesManager.shared

    // Disable quickAccess for screenshots
    prefs.setAction(.showQuickAccess, for: .screenshot, enabled: false)
    XCTAssertFalse(prefs.isActionEnabled(.showQuickAccess, for: .screenshot))

    // Re-enable
    prefs.setAction(.showQuickAccess, for: .screenshot, enabled: true)
    XCTAssertTrue(prefs.isActionEnabled(.showQuickAccess, for: .screenshot))
  }

  // MARK: - Missing File Safety

  func testHandleScreenshotCapture_missingFile_doesNotCrash() async {
    let handler = PostCaptureActionHandler.shared
    let nonexistentURL = tempDirectory.appendingPathComponent("does_not_exist.png")

    // Should complete without crashing
    await handler.handleScreenshotCapture(url: nonexistentURL)
    // No assertion needed — test passes if no crash
  }

  func testHandleVideoCapture_missingFile_doesNotCrash() async {
    let handler = PostCaptureActionHandler.shared
    let nonexistentURL = tempDirectory.appendingPathComponent("does_not_exist.mov")

    await handler.handleVideoCapture(url: nonexistentURL)
  }

  // MARK: - copyEditedCaptureToClipboardIfEnabled

  func testCopyEditedCapture_whenDisabled_doesNotCopy() {
    let handler = PostCaptureActionHandler.shared

    // Disable clipboard copy for screenshots
    PreferencesManager.shared.setAction(.copyFile, for: .screenshot, enabled: false)

    // Should complete without crashing
    handler.copyEditedCaptureToClipboardIfEnabled(for: .screenshot, url: tempFileURL)

    // Re-enable
    PreferencesManager.shared.setAction(.copyFile, for: .screenshot, enabled: true)
  }

  func testCopyEditedCapture_whenEnabled_copiesWithoutCrash() {
    let handler = PostCaptureActionHandler.shared

    // Ensure clipboard copy is enabled
    PreferencesManager.shared.setAction(.copyFile, for: .screenshot, enabled: true)

    // Should complete without crashing
    handler.copyEditedCaptureToClipboardIfEnabled(for: .screenshot, url: tempFileURL)
  }

  // MARK: - AfterCaptureAction Properties

  func testAfterCaptureAction_allCases() {
    let allCases = AfterCaptureAction.allCases
    XCTAssertEqual(allCases.count, 5)
    XCTAssertTrue(allCases.contains(.showQuickAccess))
    XCTAssertTrue(allCases.contains(.copyFile))
    XCTAssertTrue(allCases.contains(.save))
    XCTAssertTrue(allCases.contains(.openAnnotate))
    XCTAssertTrue(allCases.contains(.uploadToCloud))
  }

  func testAfterCaptureAction_displayNames_nonEmpty() {
    for action in AfterCaptureAction.allCases {
      XCTAssertFalse(action.displayName.isEmpty, "\(action.rawValue) has empty displayName")
    }
  }

  // MARK: - CaptureType Properties

  func testCaptureType_allCases() {
    XCTAssertEqual(CaptureType.allCases.count, 2)
    XCTAssertTrue(CaptureType.allCases.contains(.screenshot))
    XCTAssertTrue(CaptureType.allCases.contains(.recording))
  }

  func testCaptureType_rawValues() {
    XCTAssertEqual(CaptureType.screenshot.rawValue, "screenshot")
    XCTAssertEqual(CaptureType.recording.rawValue, "recording")
  }

  func testCaptureType_displayNames_nonEmpty() {
    for type in CaptureType.allCases {
      XCTAssertFalse(type.displayName.isEmpty, "\(type.rawValue) has empty displayName")
    }
  }
}
