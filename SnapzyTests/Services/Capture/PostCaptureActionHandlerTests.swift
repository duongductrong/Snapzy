//
//  PostCaptureActionHandlerTests.swift
//  SnapzyTests
//
//  Unit tests for PostCaptureActionHandler routing logic.
//

import AppKit
import ImageIO
import SwiftUI
import XCTest
@testable import Snapzy

@MainActor
final class PostCaptureActionHandlerTests: XCTestCase {

  private var defaults: UserDefaults!
  private var preferences: PreferencesManager!
  private var tempDirectory: URL!
  private var tempFileURL: URL!
  private var canvasPresetStore: AnnotateCanvasPresetStore!
  private var screenshotPresetAutoApplier: ScreenshotPresetAutoApplier!

  override func setUp() async throws {
    try await super.setUp()
    defaults = UserDefaultsFactory.make()
    preferences = PreferencesManager(defaults: defaults)
    canvasPresetStore = AnnotateCanvasPresetStore(defaults: defaults)
    screenshotPresetAutoApplier = ScreenshotPresetAutoApplier(presetStore: canvasPresetStore)
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
    if let tempDirectory {
      try? FileManager.default.removeItem(at: tempDirectory)
    }
    try await super.tearDown()
  }

  private func resetAfterCaptureActionsToDefaults() {
    preferences.afterCaptureActions = Self.defaultAfterCaptureActions()
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
    case .openAnnotate:
      return false
    }
  }

  /// Milestone 6: standard captures run the default automation the matrix
  /// describes. These tests predate the switch, so they double as parity
  /// tests of the automation path against the legacy behavior.
  private func makeHandler(quickAccess: QuickAccessManaging) -> PostCaptureActionHandler {
    let preferences = preferences!
    return PostCaptureActionHandler(
      preferences: preferences,
      quickAccess: quickAccess,
      fileAccess: SandboxFileAccessManager.shared,
      screenshotPresetAutoApplier: screenshotPresetAutoApplier,
      defaultAutomation: { AutomationSystemDefault.make(for: $0, matrix: preferences.storedMatrix(for: $0)) }
    )
  }

  /// The pre-milestone-6 matrix handler, for side-by-side parity checks.
  private func makeLegacyHandler(quickAccess: QuickAccessManaging) -> PostCaptureActionHandler {
    PostCaptureActionHandler(
      preferences: preferences,
      quickAccess: quickAccess,
      fileAccess: SandboxFileAccessManager.shared,
      screenshotPresetAutoApplier: screenshotPresetAutoApplier
    )
  }

  private func writeTestImage(to url: URL, width: Int = 100, height: Int = 100) throws {
    guard let image = TestImageFactory.solidColor(width: width, height: height) else {
      XCTFail("Failed to create test image")
      return
    }
    let bitmapRep = NSBitmapImageRep(cgImage: image)
    let pngData = bitmapRep.representation(using: .png, properties: [:])
    try pngData?.write(to: url)
  }

  private func imagePixelSize(at url: URL) -> CGSize? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
          let width = properties[kCGImagePropertyPixelWidth as String] as? CGFloat,
          let height = properties[kCGImagePropertyPixelHeight as String] as? CGFloat else {
      return nil
    }
    return CGSize(width: width, height: height)
  }

  private func saveDefaultPreset(
    padding: CGFloat = 10,
    backgroundStyle: Snapzy.BackgroundStyle = .solidColor(SwiftUI.Color.red)
  ) -> AnnotateCanvasPreset {
    let preset = AnnotateCanvasPreset(
      name: "Default Share",
      payload: AnnotateCanvasPresetPayload(
        backgroundStyle: CodableBackgroundStyle(from: backgroundStyle)!,
        padding: padding,
        shadowIntensity: 0,
        cornerRadius: 0
      )
    )
    canvasPresetStore.savePresets([preset])
    canvasPresetStore.saveDefaultPresetId(preset.id)
    return preset
  }

  // MARK: - PreferencesManager Routing Logic

  func testIsActionEnabled_defaultValues() {
    // Default: showQuickAccess and copyFile are ON for both types
    XCTAssertTrue(preferences.isActionEnabled(.showQuickAccess, for: .screenshot))
    XCTAssertTrue(preferences.isActionEnabled(.showQuickAccess, for: .recording))
    XCTAssertTrue(preferences.isActionEnabled(.copyFile, for: .screenshot))
    XCTAssertTrue(preferences.isActionEnabled(.copyFile, for: .recording))
    XCTAssertTrue(preferences.isActionEnabled(.save, for: .screenshot))
    XCTAssertTrue(preferences.isActionEnabled(.save, for: .recording))

    // Default: openAnnotate is OFF
    XCTAssertFalse(preferences.isActionEnabled(.openAnnotate, for: .screenshot))
    XCTAssertFalse(preferences.isActionEnabled(.openAnnotate, for: .recording))
  }

  func testSetAndCheckActionEnabled() {
    // Disable quickAccess for screenshots
    preferences.setAction(.showQuickAccess, for: .screenshot, enabled: false)
    XCTAssertFalse(preferences.isActionEnabled(.showQuickAccess, for: .screenshot))

    // Re-enable
    preferences.setAction(.showQuickAccess, for: .screenshot, enabled: true)
    XCTAssertTrue(preferences.isActionEnabled(.showQuickAccess, for: .screenshot))
  }

  // MARK: - Missing File Safety

  func testHandleScreenshotCapture_missingFile_doesNotAddToQuickAccess() async {
    let fakeQuickAccess = FakeQuickAccessManager()
    let handler = makeHandler(quickAccess: fakeQuickAccess)
    let nonexistentURL = tempDirectory.appendingPathComponent("does_not_exist.png")

    await handler.handleScreenshotCapture(url: nonexistentURL)

    XCTAssertEqual(fakeQuickAccess.addedScreenshots.count, 0)
  }

  func testHandleVideoCapture_missingFile_doesNotAddToQuickAccess() async {
    let fakeQuickAccess = FakeQuickAccessManager()
    let handler = makeHandler(quickAccess: fakeQuickAccess)
    let nonexistentURL = tempDirectory.appendingPathComponent("does_not_exist.mov")

    await handler.handleVideoCapture(url: nonexistentURL)

    XCTAssertEqual(fakeQuickAccess.addedVideos.count, 0)
  }

  func testHandleScreenshotCaptures_multipleFiles_addsAllToQuickAccess() async throws {
    preferences.setAction(.copyFile, for: .screenshot, enabled: false)
    let secondURL = tempDirectory.appendingPathComponent("test_capture_2.png")
    try FileManager.default.copyItem(at: tempFileURL, to: secondURL)
    let fakeQuickAccess = FakeQuickAccessManager()
    let handler = makeHandler(quickAccess: fakeQuickAccess)

    await handler.handleScreenshotCaptures(urls: [tempFileURL, secondURL])

    XCTAssertEqual(fakeQuickAccess.addedScreenshots, [tempFileURL, secondURL])
  }

  func testHandleScreenshotCaptures_filtersMissingFiles() async throws {
    preferences.setAction(.copyFile, for: .screenshot, enabled: false)
    let missingURL = tempDirectory.appendingPathComponent("missing.png")
    let fakeQuickAccess = FakeQuickAccessManager()
    let handler = makeHandler(quickAccess: fakeQuickAccess)

    await handler.handleScreenshotCaptures(urls: [missingURL, tempFileURL])

    XCTAssertEqual(fakeQuickAccess.addedScreenshots, [tempFileURL])
  }

  func testHandleScreenshotCapture_copiesToClipboardBeforeQuickAccess() async throws {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString("stale clipboard value", forType: .string)

    let expectedURL = try XCTUnwrap(tempFileURL)
    let fakeQuickAccess = FakeQuickAccessManager()
    fakeQuickAccess.onAddScreenshot = { url in
      XCTAssertEqual(url, expectedURL)
      let item = NSPasteboard.general.pasteboardItems?.first
      XCTAssertTrue(item?.types.contains(.fileURL) ?? false)
      XCTAssertTrue(item?.types.contains(.png) ?? false)
      XCTAssertEqual(
        (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.first?.standardizedFileURL,
        expectedURL.standardizedFileURL
      )
    }
    let handler = makeHandler(quickAccess: fakeQuickAccess)

    await handler.handleScreenshotCapture(url: tempFileURL)

    XCTAssertEqual(fakeQuickAccess.addedScreenshots, [tempFileURL])
  }

  func testHandleVideoCapture_copiesMediaFileToClipboardBeforeQuickAccess() async throws {
    let videoURL = tempDirectory.appendingPathComponent("test_recording.mp4")
    try Data([0, 1, 2, 3]).write(to: videoURL)

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString("stale clipboard value", forType: .string)

    let fakeQuickAccess = FakeQuickAccessManager()
    fakeQuickAccess.onAddVideo = { url in
      XCTAssertEqual(url, videoURL)
      let item = NSPasteboard.general.pasteboardItems?.first
      XCTAssertTrue(item?.types.contains(.fileURL) ?? false)
      XCTAssertTrue(item?.types.contains(.URL) ?? false)
      XCTAssertTrue(item?.types.contains(.string) ?? false)
      XCTAssertEqual(item?.string(forType: .URL), videoURL.absoluteString)
      XCTAssertEqual(item?.string(forType: .string), videoURL.path)
      XCTAssertEqual(
        (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.first?.standardizedFileURL,
        videoURL.standardizedFileURL
      )
    }
    let handler = makeHandler(quickAccess: fakeQuickAccess)

    await handler.handleVideoCapture(url: videoURL)

    XCTAssertEqual(fakeQuickAccess.addedVideos, [videoURL])
  }

  func testScreenshotPresetAutoApplier_noDefaultPreset_preservesOriginalFile() throws {
    let beforeData = try Data(contentsOf: tempFileURL)

    let sessionData = screenshotPresetAutoApplier.applyDefaultPresetIfNeeded(to: tempFileURL)

    XCTAssertNil(sessionData)
    XCTAssertEqual(try Data(contentsOf: tempFileURL), beforeData)
  }

  func testScreenshotPresetAutoApplier_validPresetRendersFileAndReturnsEditableSession() throws {
    let preset = saveDefaultPreset(padding: 12)
    let beforeSize = try XCTUnwrap(imagePixelSize(at: tempFileURL))
    let beforeData = try Data(contentsOf: tempFileURL)

    let sessionData = try XCTUnwrap(
      screenshotPresetAutoApplier.applyDefaultPresetIfNeeded(to: tempFileURL)
    )
    let afterSize = try XCTUnwrap(imagePixelSize(at: tempFileURL))

    XCTAssertGreaterThan(afterSize.width, beforeSize.width)
    XCTAssertGreaterThan(afterSize.height, beforeSize.height)
    XCTAssertEqual(sessionData.originalImageData, beforeData)
    XCTAssertEqual(sessionData.selectedCanvasPresetId, preset.id)
    XCTAssertEqual(sessionData.canvasEffects.padding, 12)
    XCTAssertEqual(sessionData.annotations.count, 0)
  }

  func testScreenshotPresetAutoApplier_stalePresetClearsDefaultAndPreservesFile() throws {
    defaults.set(UUID().uuidString, forKey: PreferencesKeys.annotateDefaultCanvasPresetId)
    let beforeData = try Data(contentsOf: tempFileURL)

    let sessionData = screenshotPresetAutoApplier.applyDefaultPresetIfNeeded(to: tempFileURL)

    XCTAssertNil(sessionData)
    XCTAssertNil(defaults.string(forKey: PreferencesKeys.annotateDefaultCanvasPresetId))
    XCTAssertEqual(try Data(contentsOf: tempFileURL), beforeData)
  }

  func testHandleScreenshotCapture_appliesPresetBeforeQuickAccessReceivesURL() async throws {
    preferences.setAction(.copyFile, for: .screenshot, enabled: false)
    _ = saveDefaultPreset(padding: 12)
    let beforeSize = try XCTUnwrap(imagePixelSize(at: tempFileURL))
    let fakeQuickAccess = FakeQuickAccessManager()
    let handler = makeHandler(quickAccess: fakeQuickAccess)

    await handler.handleScreenshotCapture(url: tempFileURL)
    let afterSize = try XCTUnwrap(imagePixelSize(at: tempFileURL))

    XCTAssertEqual(fakeQuickAccess.addedScreenshots, [tempFileURL])
    XCTAssertGreaterThan(afterSize.width, beforeSize.width)
    XCTAssertGreaterThan(afterSize.height, beforeSize.height)
  }

  func testHandleScreenshotCapture_cachesAutoAppliedPresetSessionForQuickAccessItem() async throws {
    preferences.setAction(.copyFile, for: .screenshot, enabled: false)
    let preset = saveDefaultPreset(padding: 12)
    let beforeData = try Data(contentsOf: tempFileURL)
    let fakeQuickAccess = FakeQuickAccessManager()
    let handler = makeHandler(quickAccess: fakeQuickAccess)

    await handler.handleScreenshotCapture(url: tempFileURL)

    let item = try XCTUnwrap(fakeQuickAccess.createdScreenshotItems.first)
    let sessionData = try XCTUnwrap(AnnotateManager.shared.getSessionData(for: item.id))
    XCTAssertEqual(sessionData.originalImageData, beforeData)
    XCTAssertEqual(sessionData.selectedCanvasPresetId, preset.id)
    XCTAssertEqual(sessionData.canvasEffects.padding, 12)

    AnnotateManager.shared.clearSessionData(for: item.id)
  }

  func testHandleScreenshotCapture_pinToScreenPinsCreatedQuickAccessItem() async throws {
    preferences.setAction(.copyFile, for: .screenshot, enabled: false)
    let fakeQuickAccess = FakeQuickAccessManager()
    let handler = makeHandler(quickAccess: fakeQuickAccess)

    let returnedItem = await handler.handleScreenshotCapture(url: tempFileURL, pinToScreen: true)

    let item = try XCTUnwrap(fakeQuickAccess.createdScreenshotItems.first)
    XCTAssertEqual(returnedItem?.id, item.id)
    XCTAssertEqual(fakeQuickAccess.addedScreenshots, [tempFileURL])
    XCTAssertEqual(fakeQuickAccess.pinnedScreenshotIDs, [item.id])
    XCTAssertTrue(fakeQuickAccess.pinnedScreenshotURLs.isEmpty)
  }

  func testHandleScreenshotCapture_pinToScreenPinsURLWhenQuickAccessActionDisabled() async throws {
    preferences.setAction(.showQuickAccess, for: .screenshot, enabled: false)
    preferences.setAction(.copyFile, for: .screenshot, enabled: false)
    let fakeQuickAccess = FakeQuickAccessManager()
    let handler = makeHandler(quickAccess: fakeQuickAccess)

    let returnedItem = await handler.handleScreenshotCapture(url: tempFileURL, pinToScreen: true)

    XCTAssertNotNil(returnedItem)
    XCTAssertTrue(fakeQuickAccess.addedScreenshots.isEmpty)
    XCTAssertTrue(fakeQuickAccess.pinnedScreenshotIDs.isEmpty)
    XCTAssertEqual(fakeQuickAccess.pinnedScreenshotURLs, [tempFileURL])
  }

  // MARK: - Legacy parity (milestone 6)

  /// Every matrix combination without Annotate (it opens a window) × pin flag:
  /// the automation path makes the same Quick Access / pin calls as the legacy one.
  func testDefaultAutomationMatchesLegacyQuickAccessAndPinEffects() async throws {
    for bits in 0..<4 {
      for pin in [false, true] {
        preferences.setAction(.copyFile, for: .screenshot, enabled: bits & 1 != 0)
        preferences.setAction(.showQuickAccess, for: .screenshot, enabled: bits & 2 != 0)
        preferences.setAction(.openAnnotate, for: .screenshot, enabled: false)

        let legacyQuickAccess = FakeQuickAccessManager()
        let legacyItem = await makeLegacyHandler(quickAccess: legacyQuickAccess)
          .handleScreenshotCapture(url: tempFileURL, pinToScreen: pin)
        let legacyClipboard = NSPasteboard.general.changeCount
        let newQuickAccess = FakeQuickAccessManager()
        let newItem = await makeHandler(quickAccess: newQuickAccess)
          .handleScreenshotCapture(url: tempFileURL, pinToScreen: pin)
        let label = "copy=\(bits & 1 != 0) qa=\(bits & 2 != 0) pin=\(pin)"

        XCTAssertEqual(newQuickAccess.addedScreenshots, legacyQuickAccess.addedScreenshots, label)
        XCTAssertEqual(newQuickAccess.pinnedScreenshotIDs.count, legacyQuickAccess.pinnedScreenshotIDs.count, label)
        XCTAssertEqual(newQuickAccess.pinnedScreenshotURLs, legacyQuickAccess.pinnedScreenshotURLs, label)
        XCTAssertEqual(newItem == nil, legacyItem == nil, label)
        // Copy on → the automation path wrote the pasteboard again.
        XCTAssertEqual(NSPasteboard.general.changeCount != legacyClipboard, bits & 1 != 0, label)
      }
    }
  }

  func testDefaultAutomationMatchesLegacyForRecordingsWithSkipQuickAccess() async throws {
    let videoURL = tempDirectory.appendingPathComponent("parity.mp4")
    try Data([0, 1, 2, 3]).write(to: videoURL)
    for bits in 0..<4 {
      for skip in [false, true] {
        preferences.setAction(.copyFile, for: .recording, enabled: bits & 1 != 0)
        preferences.setAction(.showQuickAccess, for: .recording, enabled: bits & 2 != 0)

        let legacyQuickAccess = FakeQuickAccessManager()
        await makeLegacyHandler(quickAccess: legacyQuickAccess).handleVideoCapture(url: videoURL, skipQuickAccess: skip)
        let newQuickAccess = FakeQuickAccessManager()
        await makeHandler(quickAccess: newQuickAccess).handleVideoCapture(url: videoURL, skipQuickAccess: skip)

        XCTAssertEqual(newQuickAccess.addedVideos, legacyQuickAccess.addedVideos, "bits=\(bits) skip=\(skip)")
      }
    }
  }

  // MARK: - AfterCaptureAction Properties

  func testAfterCaptureAction_allCases() {
    let allCases = AfterCaptureAction.allCases
    XCTAssertEqual(allCases.count, 4)
    XCTAssertTrue(allCases.contains(.showQuickAccess))
    XCTAssertTrue(allCases.contains(.copyFile))
    XCTAssertTrue(allCases.contains(.save))
    XCTAssertTrue(allCases.contains(.openAnnotate))
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
