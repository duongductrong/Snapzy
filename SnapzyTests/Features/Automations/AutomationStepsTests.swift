//
//  AutomationStepsTests.swift
//  SnapzyTests
//
//  Milestone 3 steps through the runner with a fake environment: working
//  files, OCR / translate, link and text templates, save to folder, failure
//  policies, cancellation and the run record.
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class AutomationStepsTests: XCTestCase {
  private var environment: FakeAutomationEnvironment!
  private var runner: AutomationRunner!
  private var directory: URL!
  private var capture: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    environment = FakeAutomationEnvironment()
    runner = AutomationRunner(environment: environment, frontmostAppName: { "Safari" })
    directory = FileManager.default.temporaryDirectory.appendingPathComponent("AutomationStepsTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    capture = directory.appendingPathComponent("Snapzy_shot.png")
    try AutomationTestImages.png(width: 3000, height: 2000).write(to: capture)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    try super.tearDownWithError()
  }

  private func automation(_ steps: [AutomationStepAction], source: AutomationSource? = nil) -> Automation {
    Automation(
      name: "Test",
      source: source ?? .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: false)),
      steps: steps.map { AutomationStep($0) }
    )
  }

  // MARK: - Transforms

  func testResizeWritesWorkingFileAndKeepsOriginal() async throws {
    let originalData = try Data(contentsOf: capture)
    let result = try XCTUnwrapResult(await runner.run(
      automation([.resize(AutomationResizeConfig(maxDimension: 1600)), .copyImage]),
      files: [capture]
    ))

    let copied = try XCTUnwrap(environment.copiedImages.first?.first)
    XCTAssertNotEqual(copied, capture, "Steps after a transform get the working file")
    XCTAssertEqual(AutomationRunState.pixelSize(of: copied), CGSize(width: 1600, height: 1067))
    XCTAssertEqual(try Data(contentsOf: capture), originalData, "The capture is never modified")
    XCTAssertEqual(result.report.files, [capture])
    XCTAssertEqual(environment.history, [capture], "History records the original")
    XCTAssertTrue(FileManager.default.fileExists(atPath: copied.path), "A copied working file is kept for paste")
  }

  func testUnreferencedWorkingFilesAreDeleted() async throws {
    let result = try XCTUnwrapResult(await runner.run(
      automation([.resize(AutomationResizeConfig(maxDimension: 800)), .notify]),
      files: [capture]
    ))

    XCTAssertFalse(FileManager.default.fileExists(atPath: result.state.context.workingDirectory.path))
  }

  func testCanvasPresetStepReplacesDefaultPreset() async throws {
    _ = await runner.run(automation([.applyCanvasPreset(AutomationCanvasPresetConfig()), .copyImage]), files: [capture])

    XCTAssertTrue(environment.preparedScreenshots.isEmpty, "An explicit preset step skips the default preset")
    XCTAssertEqual(environment.canvasPresetCalls.map(\.1), [capture])
  }

  func testConvertWithMissingOptimizePresetFails() async throws {
    let result = try XCTUnwrapResult(await runner.run(
      automation([.convert(AutomationConvertConfig(optimizePresetID: UUID())), .copyImage]),
      files: [capture]
    ))

    XCTAssertTrue(result.isError)
    XCTAssertEqual(result.outcome, .failed)
    XCTAssertTrue(environment.copiedImages.isEmpty, "Stop policy ends the run")
  }

  func testConvertToGIFReplacesVideoWithGIF() async throws {
    let video = directory.appendingPathComponent("clip.mov")
    try Data([0, 1, 2]).write(to: video)

    let result = try XCTUnwrapResult(await runner.run(
      automation([.convertToGIF(AutomationGIFConfig()), .showQuickAccess]),
      input: AutomationInput(files: [video], isAlreadyInHistory: true),
      invocation: .cli
    ))

    XCTAssertEqual(environment.quickAccessShown.map(\.pathExtension), ["gif"])
    XCTAssertEqual(result.state.payload.files.first?.kind, .gif)
    XCTAssertEqual(result.state.payload.files.first?.original, video)
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: video.deletingPathExtension().appendingPathExtension("gif").path),
      "The GIF is written in the working directory, never next to the recording"
    )
  }

  // MARK: - Text

  func testTranslateSnipCopiesTranslation() async throws {
    let result = try XCTUnwrapResult(await runner.run(AutomationPreset.translateSnip.makeAutomation(), files: [capture]))

    XCTAssertEqual(environment.copiedTexts, ["translated:Hello world"])
    XCTAssertEqual(result.report.text, "translated:Hello world")
    XCTAssertEqual(environment.notifications.last?.body, L10n.Automations.resultTextCopied)
  }

  func testEmptyOCRFailsWithReason() async throws {
    environment.recognizedText = "   "

    let result = try XCTUnwrapResult(await runner.run(
      automation([.ocr(AutomationOCRConfig()), .copyText(AutomationTextTemplate())]),
      files: [capture]
    ))

    XCTAssertTrue(environment.copiedTexts.isEmpty)
    XCTAssertTrue(result.isError)
    XCTAssertEqual(environment.runRecords.first?.steps.first?.error, L10n.Automations.errorNoTextFound)
  }

  func testContinuePolicyMakesPartialOutcome() async throws {
    environment.translateShouldFail = true
    var automation = automation([.ocr(AutomationOCRConfig()), .translate(AutomationTranslateConfig()), .copyText(AutomationTextTemplate())])
    automation.steps[1].onFailure = .continue

    let result = try XCTUnwrapResult(await runner.run(automation, files: [capture]))

    XCTAssertEqual(environment.copiedTexts, ["Hello world"], "The untranslated text is still copied")
    XCTAssertEqual(result.outcome, .partial)
    XCTAssertEqual(environment.runRecords.first?.outcome, .partial)
  }

  // MARK: - Deliver

  func testLinkTemplates() async throws {
    for (style, expected) in [
      (AutomationLinkStyle.html, "<img src=\"https://cdn.example.com/Snapzy_shot.png\" alt=\"Snapzy_shot\">"),
      (.bbcode, "[img]https://cdn.example.com/Snapzy_shot.png[/img]"),
    ] {
      environment.copiedTexts = []
      _ = await runner.run(automation([.upload(AutomationUploadConfig()), .copyLink(AutomationLinkTemplate(style: style))]), files: [capture])
      XCTAssertEqual(environment.copiedTexts, [expected])
    }

    environment.copiedTexts = []
    _ = await runner.run(
      automation([.upload(AutomationUploadConfig()), .copyLink(AutomationLinkTemplate(style: .custom, custom: "<{link}> by {automation}"))]),
      files: [capture]
    )
    XCTAssertEqual(environment.copiedTexts, ["<https://cdn.example.com/Snapzy_shot.png> by Test"])
  }

  func testSaveToFolderCopiesWithTemplateAndRelativePath() async throws {
    let folder = directory.appendingPathComponent("docs", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let ref = AutomationFolderRef.bookmark(UUID())
    environment.folders[ref] = folder

    let result = try XCTUnwrapResult(await runner.run(
      automation([
        .saveToFolder(AutomationSaveToFolderConfig(folder: ref, nameTemplate: "img/{appName}")),
        .copyText(AutomationTextTemplate(template: "![{file.basename}]({saved.relativePath})")),
      ]),
      files: [capture]
    ))

    let saved = folder.appendingPathComponent("img/Safari.png")
    XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: capture.path), "Save copies, never moves")
    XCTAssertEqual(environment.copiedTexts, ["![Snapzy_shot](img/Safari.png)"])
    XCTAssertEqual(result.report.outputFiles, [saved])
    XCTAssertEqual(result.message, L10n.Automations.resultTextCopied, "The message follows the last delivery")

    // Second run: uniquified, not overwritten.
    let second = try XCTUnwrapResult(await runner.run(
      automation([.saveToFolder(AutomationSaveToFolderConfig(folder: ref, nameTemplate: "img/{appName}"))]),
      files: [capture]
    ))
    XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("img/Safari_2.png").path))
    XCTAssertEqual(second.message, L10n.Automations.resultSavedTo("Safari_2.png"))
  }

  func testOverwriteNeverReplacesTheCapture() async throws {
    let original = try Data(contentsOf: capture)
    let ref = AutomationFolderRef.exportDirectory
    environment.folders[ref] = directory

    _ = await runner.run(
      automation([
        .resize(AutomationResizeConfig(maxDimension: 100)),
        .saveToFolder(AutomationSaveToFolderConfig(folder: ref, conflict: .overwrite)),
      ]),
      files: [capture]
    )

    XCTAssertEqual(try Data(contentsOf: capture), original, "Overwrite falls back to keep-both for the capture itself")
    XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Snapzy_shot_2.png").path))
  }

  func testRelativeURLIsPercentEncoded() async throws {
    let ref = AutomationFolderRef.bookmark(UUID())
    environment.folders[ref] = directory
    runner = AutomationRunner(environment: environment, frontmostAppName: { "Google Chrome" })

    _ = await runner.run(
      automation([
        .saveToFolder(AutomationSaveToFolderConfig(folder: ref, nameTemplate: "{appName}")),
        .copyText(AutomationTextTemplate(template: AutomationPreset.docsShotMarkdown)),
      ]),
      files: [capture]
    )

    XCTAssertEqual(environment.copiedTexts, ["![Snapzy_shot](Google%20Chrome.png)"])
  }

  func testExternalRunsKeepReportedOutputFiles() async throws {
    let result = try XCTUnwrapResult(await runner.run(
      automation([.resize(AutomationResizeConfig(maxDimension: 100))]),
      input: AutomationInput(files: [capture], isAlreadyInHistory: false),
      invocation: .cli
    ))

    let output = try XCTUnwrap(result.report.outputFiles.first)
    XCTAssertNotEqual(output, capture)
    XCTAssertTrue(FileManager.default.fileExists(atPath: output.path), "CLI gets a path that still exists")
    try? FileManager.default.removeItem(at: result.state.context.workingDirectory)
  }

  func testSaveToMissingFolderFails() async throws {
    let result = try XCTUnwrapResult(await runner.run(
      automation([.saveToFolder(AutomationSaveToFolderConfig(folder: .bookmark(UUID())))]),
      files: [capture]
    ))

    XCTAssertTrue(result.isError)
    XCTAssertEqual(environment.runRecords.first?.steps.first?.error, L10n.Automations.errorFolderUnavailable)
  }

  func testRevealShowsSavedFileAndPinRetainsWorkingFile() async throws {
    let result = try XCTUnwrapResult(await runner.run(
      automation([.resize(AutomationResizeConfig(maxDimension: 500)), .pin, .reveal]),
      files: [capture]
    ))

    let pinned = try XCTUnwrap(environment.pinned.first)
    XCTAssertTrue(FileManager.default.fileExists(atPath: pinned.path), "A pinned working file outlives the run")
    XCTAssertEqual(environment.revealed, [[capture]], "Reveal shows the original, not the temporary working file")
    try? FileManager.default.removeItem(at: result.state.context.workingDirectory)
  }

  // MARK: - Run record, notification, cancel

  func testRunRecordAndNotificationContext() async throws {
    environment.uploadShouldFail = true

    _ = await runner.run(AutomationPreset.cloudShare.makeAutomation(), files: [capture])

    let record = try XCTUnwrap(environment.runRecords.first)
    XCTAssertEqual(record.outcome, .failed)
    XCTAssertEqual(record.steps.map(\.kind), ["copyImage", "upload"])
    XCTAssertEqual(record.steps.map(\.status), [.succeeded, .failed])
    XCTAssertEqual(record.inputFiles, [capture.path])
    let context = try XCTUnwrap(environment.notificationContexts.last ?? nil)
    XCTAssertEqual(context.outcome, .failed)
    XCTAssertEqual(context.inputFiles, [capture], "Retry re-runs on the capture")
    XCTAssertTrue(environment.runUpdates.contains(.finished(runID: record.id)))
  }

  func testCancelStopsRunWithoutFallback() async throws {
    environment.uploadDelayNanoseconds = 5_000_000_000
    let runID = UUID()

    async let pending = runner.run(
      automation([.upload(AutomationUploadConfig()), .copyLink(AutomationLinkTemplate()), .notify]),
      input: AutomationInput(files: [capture], isAlreadyInHistory: true),
      invocation: .cli,
      runID: runID
    )
    try await Task.sleep(nanoseconds: 100_000_000)
    runner.cancel(runID: runID)
    let result = try XCTUnwrapResult(await pending)

    XCTAssertEqual(result.outcome, .cancelled)
    XCTAssertTrue(environment.copiedImages.isEmpty, "No fallback copy after cancel")
    XCTAssertTrue(environment.notifications.isEmpty)
    XCTAssertEqual(environment.runRecords.first?.outcome, .cancelled)
  }
}

/// `XCTUnwrap` for an awaited optional result.
@MainActor
private func XCTUnwrapResult<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
  try XCTUnwrap(value, file: file, line: line)
}

enum AutomationTestImages {
  /// A solid PNG of the given pixel size.
  static func png(width: Int, height: Int) -> Data {
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: width,
      pixelsHigh: height,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    )!
    return rep.representation(using: .png, properties: [:])!
  }

  /// A JPEG carrying EXIF and GPS metadata.
  static func jpegWithGPS(width: Int, height: Int) -> Data {
    let image = NSBitmapImageRep(data: png(width: width, height: height))!.cgImage!
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil)!
    let properties: [CFString: Any] = [
      kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 10.77, kCGImagePropertyGPSLongitude: 106.7],
      kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "secret"],
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    CGImageDestinationFinalize(destination)
    return data as Data
  }
}
