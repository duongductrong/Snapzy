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
private final class FakeAutomationEnvironment: AutomationRunEnvironment {
  struct UploadFailure: LocalizedError {
    var errorDescription: String? { "offline" }
  }

  var changeCount = 0
  var copiedImages: [[URL]] = []
  var copiedTexts: [String] = []
  var isCloudConfigured = true
  var uploadShouldFail = false
  var uploaded: [URL] = []
  var quickAccessShown: [URL] = []
  var cloudLinks: [UUID: URL] = [:]
  var annotated: [(URL, UUID?)] = []
  var history: [URL] = []
  var notifications: [(title: String, body: String, isError: Bool)] = []
  /// Simulates the user copying something while an upload runs.
  var copyDuringUpload = false

  func prepareScreenshot(_: URL) -> AnnotationSessionData? { nil }

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

  func showQuickAccess(_ url: URL, sessionData _: AnnotationSessionData?) async -> UUID? {
    quickAccessShown.append(url)
    return UUID()
  }

  func setCloudLink(quickAccessItemID: UUID, result: CloudUploadResult) {
    cloudLinks[quickAccessItemID] = result.publicURL
  }

  func openAnnotate(_ url: URL, quickAccessItemID: UUID?, sessionData _: AnnotationSessionData?) {
    annotated.append((url, quickAccessItemID))
  }

  func recordHistory(_ url: URL) async {
    history.append(url)
  }

  func notify(title: String, body: String, isError: Bool) async {
    notifications.append((title, body, isError))
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
