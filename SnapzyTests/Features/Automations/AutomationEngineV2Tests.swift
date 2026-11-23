//
//  AutomationEngineV2Tests.swift
//  SnapzyTests
//
//  Chain validation, template variables, image transforms on real files,
//  the folder bookmark store and the activity log.
//

import ImageIO
import XCTest
@testable import Snapzy

@MainActor
final class AutomationEngineV2Tests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = FileManager.default.temporaryDirectory.appendingPathComponent("AutomationEngineV2Tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    try super.tearDownWithError()
  }

  // MARK: - Validator

  private func automation(_ steps: [AutomationStepAction], source: AutomationSource = .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: false))) -> Automation {
    Automation(name: "V", source: source, steps: steps.map { AutomationStep($0) })
  }

  func testTranslateBeforeOCRIsRejected() {
    let invalid = automation([.translate(AutomationTranslateConfig()), .ocr(AutomationOCRConfig()), .copyText(AutomationTextTemplate())])
    let issues = AutomationChainValidator.validate(invalid)

    XCTAssertEqual(issues.map(\.stepID), [invalid.steps[0].id])
    XCTAssertEqual(issues.first?.reason, .needs([.text]))
    XCTAssertTrue(issues.first?.blocksRun ?? false)
  }

  func testOCRTranslateCopyTextIsValid() {
    let valid = automation([.ocr(AutomationOCRConfig()), .translate(AutomationTranslateConfig()), .copyText(AutomationTextTemplate())])
    XCTAssertTrue(AutomationChainValidator.validate(valid).isEmpty)
  }

  func testValidatorMatrix() {
    let gifRecording = AutomationSource.capture(AutomationCaptureSpec(mode: .recordingArea, saveToExportDirectory: false, recordingOutput: .gif))
    let videoRecording = AutomationSource.capture(AutomationCaptureSpec(mode: .recordingArea, saveToExportDirectory: false))

    XCTAssertTrue(AutomationChainValidator.validate(automation([.upload, .copyLink(AutomationLinkTemplate())], source: gifRecording)).isEmpty)
    XCTAssertEqual(
      AutomationChainValidator.validate(automation([.copyLink(AutomationLinkTemplate())])).first?.reason,
      .needs([.link]),
      "Copy link needs an upload first"
    )
    XCTAssertEqual(
      AutomationChainValidator.validate(automation([.resize(AutomationResizeConfig())], source: videoRecording)).first?.reason,
      .needs([.image])
    )
    XCTAssertTrue(
      AutomationChainValidator.validate(automation([.convertToGIF(AutomationGIFConfig()), .upload], source: videoRecording)).isEmpty
    )
    XCTAssertEqual(
      AutomationChainValidator.validate(automation([.convertToGIF(AutomationGIFConfig()), .convertToGIF(AutomationGIFConfig())], source: videoRecording))
        .first?.reason,
      .needs([.video]),
      "After Convert to GIF there is no video left"
    )
    XCTAssertTrue(
      AutomationChainValidator.validate(automation([.copyText(AutomationTextTemplate(template: "{file.path}"))])).isEmpty,
      "A template without {text} needs no OCR"
    )
  }

  func testMissingConfigIsNotBlocking() {
    let needsFolder = automation([.saveToFolder(AutomationSaveToFolderConfig())])
    let issues = AutomationChainValidator.validate(needsFolder)

    XCTAssertEqual(issues.map(\.reason), [.missingConfig(.folder)])
    XCTAssertFalse(issues[0].blocksRun)
    XCTAssertTrue(needsFolder.needsSetup)
    XCTAssertTrue(AutomationPreset.docsShot.makeAutomation().needsSetup)
    XCTAssertFalse(AutomationPreset.docsShot.makeAutomation().isEnabled)
  }

  func testDisabledStepsAreIgnored() {
    var chain = automation([.translate(AutomationTranslateConfig()), .copyImage])
    chain.steps[0].isEnabled = false
    XCTAssertTrue(AutomationChainValidator.validate(chain).isEmpty)
  }

  // MARK: - Variables

  func testVariablesRenderTable() {
    let variables = AutomationVariables(values: [
      "{link}": "https://x.test/a b.png",
      "{file.basename}": "shot [1]",
      "{text}": "a \"quoted\" <b>",
    ])
    let cases: [(String, AutomationEscape, String)] = [
      ("{link}", .none, "https://x.test/a b.png"),
      ("![{file.basename}]({link})", .markdown, "![shot \\[1\\]](https://x.test/a b.png)"),
      ("<p>{text}</p>", .html, "<p>a &quot;quoted&quot; &lt;b&gt;</p>"),
      ("{\"t\": \"{text}\"}", .json, "{\"t\": \"a \\\"quoted\\\" <b>\"}"),
      ("q={file.basename}", .url, "q=shot%20%5B1%5D"),
      ("{unknown} {link", .none, "{unknown} {link"),
      ("", .none, ""),
    ]
    for (template, escape, expected) in cases {
      XCTAssertEqual(variables.render(template, escape: escape), expected, template)
    }
  }

  func testVariablesFromRunContext() {
    let context = AutomationRunContext(
      runID: UUID(),
      automationID: UUID(),
      automationName: "Docs Shot",
      invocation: .hotkey,
      startedAt: Date(timeIntervalSince1970: 0),
      appName: "Safari",
      windowTitle: "Docs/Guide",
      workingDirectory: directory
    )
    var payload = AutomationPayload(files: [AutomationFile(url: URL(fileURLWithPath: "/tmp/shot.webp"), kind: .image)])
    payload.savedFile = URL(fileURLWithPath: "/repo/docs/img/a.webp")
    payload.savedFolder = URL(fileURLWithPath: "/repo/docs")
    let variables = AutomationVariables(context: context, payload: payload, pixelSize: CGSize(width: 10, height: 20))

    XCTAssertEqual(variables.render("{appName}|{automation}|{file.ext}|{width}x{height}"), "Safari|Docs Shot|webp|10x20")
    XCTAssertEqual(variables.render("{saved.relativePath}"), "img/a.webp")
    XCTAssertEqual(variables.render("{window.title}"), "Docs-Guide", "A slash in a title never creates folders")
  }

  // MARK: - Image transforms

  private func write(_ data: Data, _ name: String) throws -> URL {
    let url = directory.appendingPathComponent(name)
    try data.write(to: url)
    return url
  }

  func testResizeToMaxDimensionWithoutUpscaling() throws {
    let source = try write(AutomationTestImages.png(width: 3000, height: 2000), "big.png")
    let result = try AutomationImageTransforms.resize(source, config: AutomationResizeConfig(maxDimension: 1600), into: directory, baseName: "out")

    XCTAssertEqual(result.pixelWidth, 1600)
    XCTAssertEqual(result.pixelHeight, 1067)
    XCTAssertEqual(result.url.pathExtension, "png")

    let small = try write(AutomationTestImages.png(width: 300, height: 200), "small.png")
    let unchanged = try AutomationImageTransforms.resize(small, config: AutomationResizeConfig(maxDimension: 1600), into: directory, baseName: "small-out")
    XCTAssertEqual(unchanged.pixelWidth, 300, "Never upscales")
  }

  func testConvertToWebP() throws {
    let source = try write(AutomationTestImages.png(width: 400, height: 300), "c.png")
    let result = try AutomationImageTransforms.convert(
      source,
      settings: AutomationConvertConfig(format: .webp, quality: 85).optimizeSettings,
      into: directory,
      baseName: "c"
    )

    XCTAssertEqual(result.url.pathExtension, "webp")
    XCTAssertFalse(result.fellBackToPNG)
    XCTAssertGreaterThan((try? Data(contentsOf: result.url).count) ?? 0, 0)
  }

  func testStripMetadataRemovesGPSAndEXIF() throws {
    let source = try write(AutomationTestImages.jpegWithGPS(width: 200, height: 100), "gps.jpg")
    XCTAssertNotNil(properties(source)[kCGImagePropertyGPSDictionary], "Fixture has GPS")

    let result = try AutomationImageTransforms.stripMetadata(source, into: directory, baseName: "clean")

    let stripped = properties(result.url)
    XCTAssertNil(stripped[kCGImagePropertyGPSDictionary])
    XCTAssertNil((stripped[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment])
    XCTAssertEqual(result.url.pathExtension, "jpg")
  }

  private func properties(_ url: URL) -> [CFString: Any] {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [:] }
    return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
  }

  // MARK: - Folder store

  func testFolderStoreRegistersResolvesAndReportsMissing() throws {
    let defaults = UserDefaults(suiteName: "AutomationEngineV2Tests.\(UUID().uuidString)")!
    let exportFolder = directory.appendingPathComponent("export", isDirectory: true)
    let store = AutomationFolderAccessStore(defaults: defaults, exportDirectory: { exportFolder })
    let folder = directory.appendingPathComponent("docs", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let id = store.register(folder)
    XCTAssertEqual(store.register(folder), id, "Same folder keeps its id")
    XCTAssertEqual(store.resolve(.bookmark(id))?.standardizedFileURL.path, folder.standardizedFileURL.path)
    XCTAssertEqual(store.resolve(.exportDirectory), exportFolder)

    let reloaded = AutomationFolderAccessStore(defaults: defaults, exportDirectory: { nil })
    XCTAssertEqual(reloaded.path(for: .bookmark(id)), folder.standardizedFileURL.path, "Persists across instances")

    try FileManager.default.removeItem(at: folder)
    XCTAssertNil(reloaded.resolve(.bookmark(id)), "A deleted folder is unavailable")
    XCTAssertNil(reloaded.resolve(.bookmark(UUID())))
  }

  // MARK: - Run log

  private func record(_ index: Int, text: String? = nil) -> AutomationRunRecord {
    AutomationRunRecord(
      id: UUID(),
      automationID: UUID(),
      automationName: "Run \(index)",
      invocation: "hotkey",
      startedAt: Date(timeIntervalSince1970: TimeInterval(index)),
      durationMs: index,
      outcome: .succeeded,
      steps: [.init(kind: "copyImage", durationMs: 1, status: .succeeded, error: nil)],
      inputFiles: ["/tmp/\(index).png"],
      text: text
    )
  }

  func testRunLogRingBufferTruncationAndPersistence() throws {
    let file = directory.appendingPathComponent("runs.json")
    let defaults = UserDefaults(suiteName: "AutomationEngineV2Tests.\(UUID().uuidString)")!
    let log = AutomationRunLog(fileURL: file, defaults: defaults, writeDelayNanoseconds: 0)

    for index in 0..<(AutomationRunLog.capacity + 5) {
      log.append(record(index))
    }
    log.append(record(999, text: String(repeating: "x", count: 500)))
    log.flush()

    XCTAssertEqual(log.records.count, AutomationRunLog.capacity)
    XCTAssertEqual(log.records.first?.automationName, "Run 999", "Newest first")
    XCTAssertEqual(log.records.first?.text?.count, AutomationRunRecord.maxTextLength + 1, "Text truncated with an ellipsis")

    let reloaded = AutomationRunLog(fileURL: file, defaults: defaults)
    XCTAssertEqual(reloaded.records, log.records)

    defaults.set(false, forKey: PreferencesKeys.automationsActivityLogEnabled)
    reloaded.append(record(1000))
    XCTAssertEqual(reloaded.records.first?.automationName, "Run 999", "Disabled log records nothing")
  }

  // MARK: - Notification routing

  func testNotificationPayloadAndRetryRouting() throws {
    let file = try write(AutomationTestImages.png(width: 10, height: 10), "r.png")
    let id = UUID()
    let payload = try XCTUnwrap(AutomationNotificationRouter.payload(for: AutomationNotificationContext(
      outcome: .failed,
      automationID: id,
      inputFiles: [file],
      link: nil,
      savedFile: nil
    )))
    XCTAssertEqual(payload.category, AutomationNotificationRouter.Category.failed)

    var retried: [(UUID, [URL])] = []
    AutomationNotificationRouter.handle(
      action: AutomationNotificationRouter.Action.retry,
      userInfo: payload.userInfo,
      retry: { retried.append(($0, $1)) }
    )
    XCTAssertEqual(retried.first?.0, id)
    XCTAssertEqual(retried.first?.1, [file])

    let success = AutomationNotificationRouter.payload(for: AutomationNotificationContext(
      outcome: .succeeded,
      automationID: id,
      inputFiles: [file],
      link: URL(string: "https://x.test/a.png"),
      savedFile: nil
    ))
    XCTAssertEqual(success?.category, AutomationNotificationRouter.Category.succeededLink)
    XCTAssertNil(AutomationNotificationRouter.payload(for: AutomationNotificationContext(
      outcome: .succeeded,
      automationID: id,
      inputFiles: [file],
      link: nil,
      savedFile: nil
    )), "Nothing to act on: no buttons")
  }
}
