//
//  AutomationLauncherTests.swift
//  SnapzyTests
//
//  The launcher gate matrix, reference lookup and the capture / input paths,
//  with an isolated store, a fake environment and a fake capture starter.
//

import XCTest
@testable import Snapzy

@MainActor
private final class FakeCaptureStarter: AutomationCaptureStarting {
  var blocker: AutomationLaunchRejection?
  var started: [(AutomationCaptureMode, PostCaptureRouting)] = []
  /// Called with the routing right after the capture "starts".
  var onStart: ((PostCaptureRouting) -> Void)?

  func automationCaptureBlocker() -> AutomationLaunchRejection? { blocker }

  func startAutomationCapture(mode: AutomationCaptureMode, routing: PostCaptureRouting) {
    started.append((mode, routing))
    onStart?(routing)
  }
}

@MainActor
final class AutomationLauncherTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!
  private var store: AutomationStore!
  private var environment: FakeAutomationEnvironment!
  private var runner: AutomationRunner!
  private var starter: FakeCaptureStarter!
  private var urlSchemeEnabled = true
  private var launcher: AutomationLauncher!
  private var directory: URL!
  private var image: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    suiteName = "AutomationLauncherTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
    defaults.set(true, forKey: PreferencesKeys.automationsSeeded)
    store = AutomationStore(defaults: defaults)
    environment = FakeAutomationEnvironment()
    runner = AutomationRunner(environment: environment)
    starter = FakeCaptureStarter()
    urlSchemeEnabled = true
    launcher = AutomationLauncher(store: store, runner: runner, isURLSchemeEnabled: { [unowned self] in urlSchemeEnabled })
    launcher.captureStarter = starter

    directory = FileManager.default.temporaryDirectory.appendingPathComponent("AutomationLauncherTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    image = directory.appendingPathComponent("shot.png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: image)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    defaults.removePersistentDomain(forName: suiteName)
    try super.tearDownWithError()
  }

  @discardableResult
  private func add(
    _ name: String = "Quick",
    source: AutomationSource = .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: false)),
    steps: [AutomationStepAction] = [.copyImage],
    external: Bool = false,
    enabled: Bool = true
  ) -> Automation {
    let automation = Automation(
      name: name,
      isEnabled: enabled,
      source: source,
      steps: steps.map { AutomationStep($0) },
      externalInvocation: external
    )
    store.add(automation)
    return automation
  }

  private func rejection(_ outcome: AutomationLaunchOutcome) -> AutomationLaunchRejection? {
    if case .rejected(let rejection) = outcome { return rejection }
    return nil
  }

  // MARK: - Reference lookup

  func testResolveByIDNameAndAmbiguousName() {
    let first = add("Quick Copy")
    let second = add("Share")
    add("share ")

    XCTAssertEqual(try store.resolve(.id(first.id)).get().id, first.id)
    XCTAssertEqual(try store.resolve(AutomationRef("  quick copy ")).get().id, first.id)
    XCTAssertEqual(try store.resolve(AutomationRef(second.id.uuidString)).get().id, second.id)
    XCTAssertEqual(store.resolve(.name("missing")).failureValue, .notFound)
    guard case .ambiguousName(let ids)? = store.resolve(.name("SHARE")).failureValue else {
      return XCTFail("Expected an ambiguous name")
    }
    XCTAssertEqual(ids.count, 2)
    XCTAssertEqual(store.duplicateNameIDs(for: second).count, 1)
  }

  // MARK: - Gates

  func testExternalInvocationNeedsOptIn() async {
    let automation = add()

    for invocation in [AutomationInvocation.urlScheme, .cli, .appIntent] {
      let outcome = await launcher.launch(.id(automation.id), invocation: invocation)
      XCTAssertEqual(rejection(outcome), .externalNotAllowed, "\(invocation)")
    }
    XCTAssertTrue(starter.started.isEmpty)
  }

  func testURLSchemeToggleGatesURLRuns() async {
    let automation = add(external: true)
    urlSchemeEnabled = false

    let outcome = await launcher.launch(.id(automation.id), invocation: .urlScheme)

    XCTAssertEqual(rejection(outcome), .urlSchemeDisabled)
    XCTAssertTrue(starter.started.isEmpty)
  }

  func testDisabledNotFoundAndBlockedCapture() async {
    let disabled = add("Off", enabled: false)
    let disabledOutcome = await launcher.launch(.id(disabled.id), invocation: .hotkey)
    let missingOutcome = await launcher.launch(.name("nope"), invocation: .menuBar)
    XCTAssertEqual(rejection(disabledOutcome), .disabled)
    XCTAssertEqual(rejection(missingOutcome), .notFound)

    let automation = add()
    starter.blocker = .permissionRequired
    let blockedOutcome = await launcher.launch(.id(automation.id), invocation: .hotkey)
    XCTAssertEqual(rejection(blockedOutcome), .permissionRequired)
  }

  func testInputSourceNeedsFile() async {
    let automation = add("On file", source: .input, external: true)

    let outcome = await launcher.launch(.id(automation.id), invocation: .cli)

    XCTAssertEqual(rejection(outcome), .needsFile)
  }

  func testFileChecks() async throws {
    let automation = add(steps: [.openAnnotate], external: true)
    let missing = directory.appendingPathComponent("gone.png")
    let text = directory.appendingPathComponent("notes.txt")
    try Data("hi".utf8).write(to: text)
    let video = directory.appendingPathComponent("clip.mov")
    try Data([0]).write(to: video)

    func launch(_ file: URL) async -> AutomationLaunchRejection? {
      rejection(await launcher.launch(
        .id(automation.id),
        invocation: .cli,
        input: AutomationInput(files: [file], isAlreadyInHistory: false)
      ))
    }

    let missingRejection = await launch(missing)
    let textRejection = await launch(text)
    let videoRejection = await launch(video)
    XCTAssertEqual(missingRejection, .fileMissing("gone.png"))
    XCTAssertEqual(textRejection, .unsupportedFile("notes.txt"))
    XCTAssertEqual(videoRejection, .noStepAcceptsFile(.video))
  }

  // MARK: - Runs

  func testCLIInputRunCopiesWithoutCapture() async throws {
    let automation = add("Quick Copy", external: true)

    let outcome = await launcher.launch(
      .name("quick copy"),
      invocation: .cli,
      input: AutomationInput(files: [image], isAlreadyInHistory: false)
    )

    guard case .finished(let report) = outcome else { return XCTFail("Expected a finished run, got \(outcome)") }
    XCTAssertEqual(report.automationID, automation.id)
    XCTAssertEqual(environment.copiedImages, [[image]])
    XCTAssertTrue(starter.started.isEmpty, "No capture overlay for input runs")
  }

  func testCaptureRunWaitsForCompletion() async throws {
    let automation = add(source: .capture(AutomationCaptureSpec(mode: .fullscreen, saveToExportDirectory: false)), external: true)
    starter.onStart = { [runner, image] routing in
      guard case .automation(let runID) = routing else { return }
      Task { @MainActor in
        await runner!.complete(runID: runID, capturedURLs: [image!])
      }
    }

    let outcome = await launcher.launch(.id(automation.id), invocation: .cli)

    XCTAssertEqual(starter.started.map(\.0), [.fullscreen])
    guard case .finished(let report) = outcome else { return XCTFail("Expected a finished run, got \(outcome)") }
    XCTAssertEqual(report.files, [image])
  }

  func testCancelledCaptureReportsCancelled() async {
    let automation = add()
    starter.onStart = { [runner] routing in runner!.abandon(routing: routing) }

    let outcome = await launcher.launch(.id(automation.id), invocation: .hotkey)

    XCTAssertEqual(outcome, .cancelled)
  }

  // MARK: - Listings

  func testTriggerSlotsFilterByTriggerAndFileKind() {
    var annotate = add("Annotate", steps: [.openAnnotate])
    annotate.showsInHistory = true
    annotate.showsInMenuBar = true
    store.update(annotate)
    var copy = add("Copy", source: .input, steps: [.copyImage], external: true)
    copy.showsInHistory = true
    copy.showsInMenuBar = true  // dropped: input automations can't run from the menu bar
    store.update(copy)

    XCTAssertEqual(store.automations(for: .history, fileKind: .image).map(\.name), ["Annotate", "Copy"])
    XCTAssertEqual(store.automations(for: .history, fileKind: .video).map(\.name), ["Copy"])
    XCTAssertEqual(store.automations(for: .menuBar).map(\.name), ["Annotate"])
    XCTAssertEqual(store.automations(for: .external).map(\.name), ["Copy"])
    XCTAssertEqual(AutomationIntentSupport.entities(store: store).map(\.name), ["Copy"])
  }
}

private extension Result {
  var failureValue: Failure? {
    if case .failure(let error) = self { return error }
    return nil
  }
}
