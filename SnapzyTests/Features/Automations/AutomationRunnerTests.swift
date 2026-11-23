//
//  AutomationRunnerTests.swift
//  SnapzyTests
//
//  Step execution, upload fallback and pasteboard guarding with a fake
//  environment (no pasteboard, network or windows).
//

import XCTest
@testable import Snapzy

@MainActor
final class FakeAutomationEnvironment: AutomationRunEnvironment {
  struct UploadFailure: LocalizedError {
    var errorDescription: String? { "offline" }
  }

  var changeCount = 0
  var copiedImages: [[URL]] = []
  var copiedMedia: [URL] = []
  var preparedScreenshots: [URL] = []
  var copiedTexts: [String] = []
  var isCloudConfigured = true
  var uploadShouldFail = false
  var uploaded: [URL] = []
  var quickAccessShown: [URL] = []
  var cloudLinks: [UUID: URL] = [:]
  var annotated: [(URL, UUID?)] = []
  var history: [URL] = []
  var historyKinds: [AutomationFileKind] = []
  var notifications: [(title: String, body: String, isError: Bool)] = []
  var notificationContexts: [AutomationNotificationContext?] = []
  /// Simulates the user copying something while an upload runs.
  var copyDuringUpload = false
  var pinned: [URL] = []
  var revealed: [[URL]] = []
  var canvasPresetCalls: [(UUID?, URL)] = []
  var recognizedText = "Hello world"
  var translationPrefix = "translated:"
  var translateShouldFail = false
  var folders: [AutomationFolderRef: URL] = [:]
  var optimizePresets: [UUID: QuickAccessOptimizeSettings] = [:]
  var runUpdates: [AutomationRunUpdate] = []
  var runRecords: [AutomationRunRecord] = []
  /// Suspends `upload` until resumed, to test cancellation.
  var uploadDelayNanoseconds: UInt64 = 0

  func prepareScreenshot(_ url: URL) -> AnnotationSessionData? {
    preparedScreenshots.append(url)
    return nil
  }

  func copyMedia(_ url: URL) -> Int {
    copiedMedia.append(url)
    changeCount += 1
    return changeCount
  }

  func copyImages(_ urls: [URL]) -> Int {
    copiedImages.append(urls)
    changeCount += 1
    return changeCount
  }

  func copyText(_ text: String) -> Int {
    copiedTexts.append(text)
    changeCount += 1
    return changeCount
  }

  var pasteboardChangeCount: Int { changeCount }

  func upload(_ url: URL) async throws -> CloudUploadResult {
    if uploadDelayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: uploadDelayNanoseconds)
    }
    if copyDuringUpload { changeCount += 1 }
    if uploadShouldFail { throw UploadFailure() }
    uploaded.append(url)
    return CloudUploadResult(
      publicURL: URL(string: "https://cdn.example.com/\(url.lastPathComponent)")!,
      key: url.lastPathComponent,
      fileSize: 10,
      uploadedAt: Date()
    )
  }

  func showQuickAccess(_ url: URL, kind _: AutomationFileKind, sessionData _: AnnotationSessionData?) async -> UUID? {
    quickAccessShown.append(url)
    return UUID()
  }

  func setCloudLink(quickAccessItemID: UUID, result: CloudUploadResult) {
    cloudLinks[quickAccessItemID] = result.publicURL
  }

  func openAnnotate(_ url: URL, quickAccessItemID: UUID?, sessionData _: AnnotationSessionData?) {
    annotated.append((url, quickAccessItemID))
  }

  func recordHistory(_ url: URL, kind: AutomationFileKind) async {
    history.append(url)
    historyKinds.append(kind)
  }

  func notify(title: String, body: String, isError: Bool, context: AutomationNotificationContext?) async {
    notifications.append((title, body, isError))
    notificationContexts.append(context)
  }

  func pin(_ url: URL) async -> Bool {
    pinned.append(url)
    return true
  }

  func reveal(_ urls: [URL]) {
    revealed.append(urls)
  }

  /// Copies the source so a "rendered" working file exists.
  func applyCanvasPreset(_ presetID: UUID?, source: URL, destination: URL) throws -> AnnotationSessionData? {
    canvasPresetCalls.append((presetID, source))
    try FileManager.default.copyItem(at: source, to: destination)
    return nil
  }

  func optimizeSettings(presetID: UUID) -> QuickAccessOptimizeSettings? {
    optimizePresets[presetID]
  }

  func recognizeText(in _: URL, config _: AutomationOCRConfig) async throws -> String {
    recognizedText
  }

  func translate(_ text: String, targetLanguage _: String?) async throws -> String {
    if translateShouldFail { throw AutomationStepError.translationUnavailable("offline") }
    return translationPrefix + text
  }

  func convertToGIF(_ url: URL, config _: AutomationGIFConfig) async throws -> URL {
    let gif = url.deletingPathExtension().appendingPathExtension("gif")
    try Data("GIF89a".utf8).write(to: gif)
    return gif
  }

  func resolveFolder(_ ref: AutomationFolderRef) throws -> URL {
    guard let url = folders[ref] else { throw AutomationStepError.folderUnavailable }
    return url
  }

  func runDidUpdate(_ update: AutomationRunUpdate) {
    runUpdates.append(update)
  }

  func recordRun(_ record: AutomationRunRecord) {
    runRecords.append(record)
  }
}

@MainActor
final class AutomationRunnerTests: XCTestCase {
  private var environment: FakeAutomationEnvironment!
  private var runner: AutomationRunner!
  private var directory: URL!
  private var capture: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    environment = FakeAutomationEnvironment()
    runner = AutomationRunner(environment: environment)
    directory = FileManager.default.temporaryDirectory.appendingPathComponent("AutomationRunnerTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    capture = directory.appendingPathComponent("Snapzy_shot.png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: capture)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    try super.tearDownWithError()
  }

  private func automation(_ steps: [AutomationStepAction]) -> Automation {
    Automation(
      name: "Test",
      source: .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: false)),
      steps: steps.map { AutomationStep($0) }
    )
  }

  func testQuickCopyCopiesImageAndSkipsQuickAccess() async throws {
    let result = try await XCTUnwrapAsync(await runner.run(AutomationPreset.quickCopy.makeAutomation(), files: [capture]))

    XCTAssertEqual(environment.copiedImages, [[capture]])
    XCTAssertTrue(environment.quickAccessShown.isEmpty)
    XCTAssertEqual(environment.history, [capture])
    XCTAssertEqual(environment.notifications.map(\.body), [L10n.Automations.resultImageCopied])
    XCTAssertFalse(result.isError)
  }

  func testCloudShareCopiesLinkAfterImage() async throws {
    let result = try await XCTUnwrapAsync(await runner.run(automation([.copyImage, .uploadAndCopyLink(.markdown), .notify]), files: [capture]))

    XCTAssertEqual(environment.copiedImages.count, 1)
    XCTAssertEqual(environment.copiedTexts, ["![Snapzy_shot](https://cdn.example.com/Snapzy_shot.png)"])
    XCTAssertTrue(result.state.didCopyLink)
    XCTAssertEqual(environment.notifications.last?.body, L10n.Automations.resultLinkCopied)
  }

  func testUploadFailureFallsBackToImageAndQuickAccess() async throws {
    environment.uploadShouldFail = true

    let result = try await XCTUnwrapAsync(await runner.run(automation([.uploadAndCopyLink(.url), .openAnnotate]), files: [capture]))

    XCTAssertEqual(environment.copiedImages, [[capture]], "Image must be copied when the upload fails")
    XCTAssertEqual(environment.quickAccessShown, [capture], "A Quick Access card must be offered for retry")
    XCTAssertTrue(environment.annotated.isEmpty, "onFailure .stop ends the run")
    XCTAssertEqual(environment.history, [capture])
    XCTAssertEqual(environment.notifications.count, 1, "Failures notify even without a notify step")
    XCTAssertTrue(environment.notifications[0].isError)
    XCTAssertEqual(result.state.uploadFailure, .failed("offline"))
  }

  func testContinuePolicyRunsLaterSteps() async throws {
    environment.uploadShouldFail = true
    var automation = automation([.uploadAndCopyLink(.url), .openAnnotate])
    automation.steps[0].onFailure = .continue

    _ = await runner.run(automation, files: [capture])

    XCTAssertEqual(environment.annotated.count, 1)
    XCTAssertNotNil(environment.annotated.first?.1, "Annotate reuses the fallback Quick Access card")
  }

  func testCloudNotConfiguredReportsSetupMessage() async throws {
    environment.isCloudConfigured = false

    let result = try await XCTUnwrapAsync(await runner.run(automation([.copyImage, .uploadAndCopyLink(.url)]), files: [capture]))

    XCTAssertTrue(environment.uploaded.isEmpty)
    XCTAssertEqual(result.state.uploadFailure, .notConfigured)
    XCTAssertEqual(environment.notifications.last?.body, L10n.Automations.resultCloudNotConfigured)
  }

  func testLinkNotWrittenWhenPasteboardChangedDuringUpload() async throws {
    environment.copyDuringUpload = true

    let result = try await XCTUnwrapAsync(await runner.run(automation([.copyImage, .uploadAndCopyLink(.url), .notify]), files: [capture]))

    XCTAssertTrue(environment.copiedTexts.isEmpty)
    XCTAssertFalse(result.state.didCopyLink)
    XCTAssertEqual(environment.notifications.last?.body, L10n.Automations.resultLinkReady)
  }

  func testQuickAccessShownAfterUploadGetsCloudLink() async throws {
    _ = await runner.run(automation([.uploadAndCopyLink(.url), .showQuickAccess]), files: [capture])

    XCTAssertEqual(environment.cloudLinks.count, 1)
    XCTAssertEqual(environment.cloudLinks.values.first?.lastPathComponent, "Snapzy_shot.png")
  }

  func testDisabledAndUnsupportedStepsAreSkipped() async throws {
    var automation = automation([.copyImage, .showQuickAccess])
    automation.steps[0].isEnabled = false
    automation.steps.append(AutomationStep(id: UUID(), .notify))
    automation.steps[2].content = .unsupported(.object(["kind": .string("webhook")]))

    _ = await runner.run(automation, files: [capture])

    XCTAssertTrue(environment.copiedImages.isEmpty)
    XCTAssertEqual(environment.quickAccessShown, [capture])
    XCTAssertTrue(environment.notifications.isEmpty)
  }

  func testMissingFileSkipsRun() async {
    let missing = directory.appendingPathComponent("missing.png")
    let result = await runner.run(AutomationPreset.quickCopy.makeAutomation(), files: [missing])
    XCTAssertNil(result)
    XCTAssertTrue(environment.history.isEmpty)
  }

  func testBeginRegistersSaveChoiceUntilAbandoned() {
    var automation = AutomationPreset.quickCopy.makeAutomation()
    automation.source = .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: true))

    let routing = runner.begin(automation)
    XCTAssertEqual(runner.saveToExportOverride(for: routing), true)
    XCTAssertNil(runner.saveToExportOverride(for: .standard))

    runner.abandon(routing: routing)
    XCTAssertNil(runner.saveToExportOverride(for: routing))
  }

  func testCompleteRunsRegisteredAutomation() async {
    let routing = runner.begin(AutomationPreset.quickCopy.makeAutomation())
    guard case .automation(let runID) = routing else { return XCTFail("Expected automation routing") }

    await runner.complete(runID: runID, capturedURLs: [capture])

    XCTAssertEqual(environment.copiedImages, [[capture]])
    XCTAssertNil(runner.saveToExportOverride(for: routing), "A run is consumed once")
  }

  // MARK: - Milestone 2: input runs and awaitable capture runs

  func testInputRunSkipsCanvasPresetAndHistoryWhenAlreadyRecorded() async throws {
    let input = AutomationInput(files: [capture], isAlreadyInHistory: true)

    let result = try await XCTUnwrapAsync(
      await runner.run(AutomationPreset.quickCopy.makeAutomation(), input: input, invocation: .history)
    )

    XCTAssertTrue(environment.preparedScreenshots.isEmpty, "Input files are never re-processed")
    XCTAssertTrue(environment.history.isEmpty)
    XCTAssertEqual(environment.copiedImages, [[capture]])
    XCTAssertEqual(result.report.files, [capture])
  }

  func testInputRunRecordsHistoryByKindWhenNew() async throws {
    let video = directory.appendingPathComponent("clip.mov")
    try Data([0]).write(to: video)

    _ = await runner.run(
      automation([.copyImage, .openAnnotate]),
      input: AutomationInput(files: [video], isAlreadyInHistory: false),
      invocation: .cli
    )

    XCTAssertEqual(environment.copiedMedia, [video], "A video is copied as a file")
    XCTAssertTrue(environment.copiedImages.isEmpty)
    XCTAssertTrue(environment.annotated.isEmpty, "Annotate does not accept videos")
    XCTAssertEqual(environment.historyKinds, [.video])
  }

  func testQuickAccessInputReusesSourceCard() async throws {
    let cardID = UUID()
    let input = AutomationInput(files: [capture], isAlreadyInHistory: true, sourceQuickAccessItemID: cardID)

    let result = try await XCTUnwrapAsync(
      await runner.run(automation([.uploadAndCopyLink(.url), .showQuickAccess]), input: input, invocation: .quickAccess)
    )

    XCTAssertTrue(environment.quickAccessShown.isEmpty, "No second card for the same file")
    XCTAssertEqual(environment.cloudLinks[cardID]?.lastPathComponent, "Snapzy_shot.png")
    XCTAssertEqual(result.report.link, "https://cdn.example.com/Snapzy_shot.png")
  }

  func testAbandonReportsCancelled() {
    var outcomes: [AutomationLaunchOutcome] = []
    let routing = runner.begin(AutomationPreset.quickCopy.makeAutomation(), invocation: .cli) { outcomes.append($0) }

    runner.abandon(routing: routing)
    runner.abandon(routing: routing)

    XCTAssertEqual(outcomes, [.cancelled], "onFinish fires exactly once")
  }

  func testCompleteReportsFinishedRun() async {
    var outcomes: [AutomationLaunchOutcome] = []
    let automation = AutomationPreset.quickCopy.makeAutomation()
    let routing = runner.begin(automation, invocation: .urlScheme) { outcomes.append($0) }
    guard case .automation(let runID) = routing else { return XCTFail("Expected automation routing") }

    await runner.complete(runID: runID, capturedURLs: [capture])

    guard case .finished(let report)? = outcomes.first else { return XCTFail("Expected a finished outcome") }
    XCTAssertEqual(outcomes.count, 1)
    XCTAssertEqual(report.runID, runID)
    XCTAssertEqual(report.automationID, automation.id)
    XCTAssertEqual(report.message, L10n.Automations.resultImageCopied)
    XCTAssertEqual(environment.preparedScreenshots, [capture], "Captures still get the canvas preset")
  }

  func testStaleRegistrationsReportCancelledWhenPruned() {
    var clock = Date()
    runner = AutomationRunner(environment: environment, now: { clock })
    var outcomes: [AutomationLaunchOutcome] = []
    _ = runner.begin(AutomationPreset.quickCopy.makeAutomation()) { outcomes.append($0) }

    clock = clock.addingTimeInterval(31 * 60)
    _ = runner.begin(AutomationPreset.quickCopy.makeAutomation())

    XCTAssertEqual(outcomes, [.cancelled])
  }

  func testMarkdownLinkForVideoIsAPlainLink() {
    let text = CloudShareService.linkText(
      for: URL(string: "https://cdn.example.com/clip.mov")!,
      fileURL: URL(fileURLWithPath: "/tmp/clip.mov"),
      format: .markdown,
      isImage: false
    )
    XCTAssertEqual(text, "[clip](https://cdn.example.com/clip.mov)")
  }

  func testMarkdownLinkEscapesBracketsAndWrapsSpaces() {
    let text = CloudShareService.linkText(
      for: URL(string: "https://cdn.example.com/a%20(1).png")!,
      fileURL: URL(fileURLWithPath: "/tmp/shot [draft].png"),
      format: .markdown
    )
    XCTAssertEqual(text, "![shot \\[draft\\]](<https://cdn.example.com/a%20(1).png>)")
  }
}

/// `XCTUnwrap` for an optional produced by an awaited expression.
private func XCTUnwrapAsync<T>(
  _ expression: @autoclosure () async throws -> T?,
  file: StaticString = #filePath,
  line: UInt = #line
) async throws -> T {
  let value = try await expression()
  return try XCTUnwrap(value, file: file, line: line)
}
