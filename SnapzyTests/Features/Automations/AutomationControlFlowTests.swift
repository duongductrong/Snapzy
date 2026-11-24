//
//  AutomationControlFlowTests.swift
//  SnapzyTests
//
//  Milestone 5: run context, condition / stop / run automation / ask steps,
//  path validation, trust propagation, picker keys, file triggers, recipes
//  and config round trips.
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class AutomationControlFlowTests: XCTestCase {
  private var environment: FakeAutomationEnvironment!
  private var runner: AutomationRunner!
  private var directory: URL!
  private var capture: URL!
  private var app = AutomationAppSnapshot(name: "Figma", bundleID: "com.figma.Desktop")

  private static let figma = "com.figma.Desktop"

  override func setUpWithError() throws {
    try super.setUpWithError()
    environment = FakeAutomationEnvironment()
    runner = AutomationRunner(environment: environment, frontmostApp: { [unowned self] in app })
    directory = FileManager.default.temporaryDirectory.appendingPathComponent("AutomationControlFlowTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    capture = directory.appendingPathComponent("shot.png")
    try Self.png(width: 40, height: 20).write(to: capture)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    try super.tearDownWithError()
  }

  private static func png(width: Int, height: Int) -> Data {
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0
    )!
    return rep.representation(using: .png, properties: [:])!
  }

  private func automation(
    name: String = "Test",
    mode: AutomationCaptureMode = .area,
    _ steps: [AutomationStepAction]
  ) -> Automation {
    Automation(
      name: name,
      source: .capture(AutomationCaptureSpec(mode: mode, saveToExportDirectory: false)),
      steps: steps.map { AutomationStep($0) }
    )
  }

  /// `XCTUnwrap` takes an autoclosure, which can't `await`.
  private func unwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    try XCTUnwrap(value, file: file, line: line)
  }

  private func text(_ value: String) -> AutomationStepAction {
    .copyText(AutomationTextTemplate(template: value))
  }

  private func appIs(_ bundleIDs: [String], otherwise: AutomationConditionConfig.Otherwise) -> AutomationStepAction {
    .condition(AutomationConditionConfig(predicates: [.frontmostApp(bundleIDs: bundleIDs, negate: false)], otherwise: otherwise))
  }

  private func store(_ automation: Automation) {
    environment.storedAutomations[automation.id] = automation
  }

  // MARK: - Context (phase 01)

  func testContextVariablesRender() async throws {
    let result = try unwrap(await runner.run(
      automation(mode: .activeWindow, [text("{app.name}|{app.bundleID}|{capture.mode}|{invocation}")]),
      files: [capture]
    ))
    XCTAssertEqual(environment.copiedTexts, ["Figma|com.figma.Desktop|activeWindow|hotkey"])
    XCTAssertEqual(result.state.context.bundleID, Self.figma)
  }

  func testCaptureContextWinsOverTriggerSnapshot() async {
    let routing = runner.begin(automation([text("{app.bundleID}|{window.title}")]))
    var context = CaptureContext(appName: "Sketch", windowTitle: "Board", bundleID: "com.bohemiancoding.sketch3")
    context.postCaptureRouting = routing
    runner.noteCaptureContext(context)
    guard case .automation(let runID) = routing else { return XCTFail("Expected automation routing") }

    await runner.complete(runID: runID, capturedURLs: [capture])

    XCTAssertEqual(environment.copiedTexts, ["com.bohemiancoding.sketch3|Board"])
  }

  func testSnapshotMergeKeepsTriggerFactsTheCaptureLacks() {
    let trigger = AutomationAppSnapshot(name: "Figma", bundleID: Self.figma, windowTitle: "Old")
    XCTAssertEqual(trigger.merged(with: AutomationAppSnapshot()), trigger)
    XCTAssertEqual(
      trigger.merged(with: AutomationAppSnapshot(name: nil, bundleID: "com.apple.Safari")),
      AutomationAppSnapshot(name: nil, bundleID: "com.apple.Safari", windowTitle: nil),
      "Another app's capture must not keep Figma's name or title"
    )
  }

  func testInputRunsHaveNoBundleID() async throws {
    let input = AutomationInput(files: [capture], isAlreadyInHistory: true)
    let result = try unwrap(await runner.run(automation([.copyImage]), input: input, invocation: .finder))
    XCTAssertNil(result.state.context.bundleID)
    XCTAssertNil(result.state.context.captureMode)
  }

  func testWindowTitleNamingToken() {
    let values = CaptureOutputNaming.tokenValues(
      kind: .screenshot,
      date: Date(),
      context: CaptureContext(appName: "Safari", windowTitle: "Docs/Guide")
    )
    XCTAssertEqual(values["{windowTitle}"], "Docs-Guide")
  }

  // MARK: - Predicates (phase 02)

  func testPredicateEvaluationTable() async throws {
    let result = try unwrap(await runner.run(automation(mode: .area, [.notify]), files: [capture]))
    var state = result.state
    state.payload.text = "Invoice 42"

    let cases: [(AutomationPredicate, Bool)] = [
      (.frontmostApp(bundleIDs: ["COM.FIGMA.DESKTOP"], negate: false), true),
      (.frontmostApp(bundleIDs: ["com.apple.Safari"], negate: false), false),
      (.frontmostApp(bundleIDs: ["com.apple.Safari"], negate: true), true),
      (.captureMode([.area, .fullscreen]), true),
      (.captureMode([.activeWindow]), false),
      (.invocation([.hotkey]), true),
      (.invocation([.cli]), false),
      (.fileKind([.image]), true),
      (.fileKind([.video, .gif]), false),
      (.pixelSize(dimension: .width, comparison: .greaterThan, value: 39), true),
      (.pixelSize(dimension: .height, comparison: .lessThan, value: 20), false),
      (.pixelSize(dimension: .longest, comparison: .greaterThan, value: 30), true),
      (.fileSize(comparison: .lessThan, bytes: 10_000_000), true),
      (.fileSize(comparison: .greaterThan, bytes: 10_000_000), false),
      (.hasText(contains: nil), true),
      (.hasText(contains: "invoice"), true),
      (.hasText(contains: "receipt"), false),
      (.unsupported(.object(["type": .string("from_the_future")])), false),
    ]
    for (predicate, expected) in cases {
      XCTAssertEqual(AutomationConditionEvaluator.evaluate(predicate, state: state), expected, "\(predicate)")
    }

    let both = AutomationConditionConfig(match: .all, predicates: [cases[0].0, cases[1].0])
    let either = AutomationConditionConfig(match: .any, predicates: [cases[0].0, cases[1].0])
    XCTAssertFalse(AutomationConditionEvaluator.evaluate(both, state: state))
    XCTAssertTrue(AutomationConditionEvaluator.evaluate(either, state: state))
    XCTAssertTrue(AutomationConditionEvaluator.evaluate(AutomationConditionConfig(), state: state), "No predicates holds")
  }

  // MARK: - Condition / stop

  /// `condition(app = Figma, else skip 2) · design · stop · default`
  private var designRouter: Automation {
    automation(mode: .activeWindow, [appIs([Self.figma], otherwise: .skip(2)), text("design"), .stop, text("default")])
  }

  func testDesignerRoutingTakesMatchingBranch() async throws {
    let result = try unwrap(await runner.run(designRouter, files: [capture]))
    XCTAssertEqual(environment.copiedTexts, ["design"])
    XCTAssertEqual(result.outcome, .succeeded)
    XCTAssertEqual(environment.runRecords.last?.steps.map(\.detail).first, L10n.Automations.logConditionMet)
  }

  func testDesignerRoutingSkipsToDefaultOtherwise() async throws {
    app = AutomationAppSnapshot(name: "Safari", bundleID: "com.apple.Safari")
    let result = try unwrap(await runner.run(designRouter, files: [capture]))
    XCTAssertEqual(environment.copiedTexts, ["default"])
    XCTAssertEqual(result.outcome, .succeeded)
    let steps = try XCTUnwrap(environment.runRecords.last?.steps)
    XCTAssertEqual(steps.map(\.status), [.succeeded, .skipped, .skipped, .succeeded])
    XCTAssertEqual(steps[1].detail, L10n.Automations.logSkippedByCondition)
  }

  func testConditionOtherwiseStopEndsRunSuccessfully() async throws {
    app = AutomationAppSnapshot(name: "Safari", bundleID: "com.apple.Safari")
    let result = try unwrap(await runner.run(
      automation([.copyImage, appIs([Self.figma], otherwise: .stop), text("never")]),
      files: [capture]
    ))
    XCTAssertTrue(environment.copiedTexts.isEmpty)
    XCTAssertEqual(result.outcome, .succeeded)
    XCTAssertEqual(result.message, L10n.Automations.resultImageCopied, "Outcome message comes from the last delivery")
  }

  // MARK: - Run automation

  func testRunAutomationRunsTargetStepsOnPayloadAndContinues() async throws {
    var target = automation(name: "Target", [text("child"), .stop, text("never")])
    target.source = .input
    store(target)
    let result = try unwrap(await runner.run(
      automation([.runAutomation(AutomationRunAutomationConfig(automationID: target.id)), text("parent")]),
      files: [capture]
    ))

    XCTAssertEqual(environment.copiedTexts, ["child", "parent"], "Stop in the target returns to the parent")
    XCTAssertEqual(result.outcome, .succeeded)
    let record = try XCTUnwrap(environment.runRecords.last?.steps.first)
    XCTAssertEqual(record.kind, AutomationStepKind.runAutomation.rawValue)
    XCTAssertEqual(record.detail, "Target")
    XCTAssertEqual(record.children?.map(\.kind), ["copyText", "stop"])
  }

  func testRunAutomationFailsForDisabledOrMissingTarget() async throws {
    var target = automation(name: "Off", [text("child")])
    target.isEnabled = false
    store(target)
    let result = try unwrap(await runner.run(
      automation([.runAutomation(AutomationRunAutomationConfig(automationID: target.id)), text("parent")]),
      files: [capture]
    ))
    XCTAssertTrue(environment.copiedTexts.isEmpty)
    XCTAssertEqual(result.outcome, .failed)
    XCTAssertTrue(result.isError)
  }

  func testRunAutomationCycleIsStoppedAtRunTime() async throws {
    var parent = automation(name: "A", [])
    var child = automation(name: "B", [])
    parent.steps = [AutomationStep(.runAutomation(AutomationRunAutomationConfig(automationID: child.id)))]
    child.steps = [AutomationStep(.runAutomation(AutomationRunAutomationConfig(automationID: parent.id)))]
    store(parent)
    store(child)

    let result = try unwrap(await runner.run(parent, files: [capture]))

    XCTAssertEqual(result.outcome, .failed)
    let nested = try XCTUnwrap(environment.runRecords.last?.steps.first?.children?.first)
    XCTAssertEqual(nested.error, L10n.Automations.errorRecursionLimit)
  }

  func testRunAutomationDepthLimit() async throws {
    // root → 1 → 2 → 3 → 4: the fourth level is refused.
    var chain = (1...4).map { automation(name: "L\($0)", [text("L\($0)")]) }
    for index in 0..<3 {
      chain[index].steps.append(AutomationStep(.runAutomation(AutomationRunAutomationConfig(automationID: chain[index + 1].id))))
    }
    chain.forEach(store)
    let root = automation(name: "Root", [.runAutomation(AutomationRunAutomationConfig(automationID: chain[0].id))])

    _ = await runner.run(root, files: [capture])

    XCTAssertEqual(environment.copiedTexts, ["L1", "L2", "L3"])
  }

  func testNestedAbortIsFailedNotPartial() async throws {
    environment.uploadShouldFail = true
    let target = automation(name: "Upload", [text("before"), .upload(AutomationUploadConfig())])
    store(target)
    let result = try unwrap(await runner.run(
      automation([.runAutomation(AutomationRunAutomationConfig(automationID: target.id))]),
      files: [capture]
    ))
    XCTAssertEqual(result.outcome, .failed)
    XCTAssertEqual(result.message, L10n.Automations.resultUploadFailed)
  }

  // MARK: - Ask

  private func askAutomation(_ choices: [AutomationAskChoice], then: [AutomationStepAction] = []) -> Automation {
    automation(name: "Share Menu", [.ask(AutomationAskConfig(choices: choices))] + then)
  }

  func testAskRunsChosenAutomationThenEndsRun() async throws {
    let quick = automation(name: "Quick", [text("quick")])
    let cloud = automation(name: "Cloud", [text("cloud")])
    store(quick)
    store(cloud)
    environment.pickAnswers = [.automation(cloud.id)]

    let result = try unwrap(await runner.run(
      askAutomation([.automation(quick.id), .automation(cloud.id), .continueRun], then: [text("after")]),
      files: [capture]
    ))

    XCTAssertEqual(environment.presentedPickers.first?.choices.map(\.title), ["Quick", "Cloud", L10n.Automations.askContinue])
    XCTAssertEqual(environment.presentedPickers.first?.title, "Share Menu")
    XCTAssertEqual(environment.copiedTexts, ["cloud"], "The parent stops after the chosen automation")
    XCTAssertEqual(result.outcome, .succeeded)
  }

  func testAskContinueGoesOnAndStopEnds() async throws {
    environment.pickAnswers = [.continueRun]
    _ = await runner.run(askAutomation([.continueRun, .stopRun], then: [text("after")]), files: [capture])
    XCTAssertEqual(environment.copiedTexts, ["after"])

    environment.copiedTexts = []
    environment.pickAnswers = [.stopRun]
    _ = await runner.run(askAutomation([.continueRun, .stopRun], then: [text("after")]), files: [capture])
    XCTAssertTrue(environment.copiedTexts.isEmpty)
  }

  func testAskCancelledEndsRunCancelledWithoutFallback() async throws {
    environment.pickAnswers = [nil]
    let result = try unwrap(await runner.run(askAutomation([.continueRun], then: [.copyImage]), files: [capture]))
    XCTAssertEqual(result.outcome, .cancelled)
    XCTAssertTrue(environment.copiedImages.isEmpty)
    XCTAssertTrue(environment.notifications.isEmpty)
  }

  func testAskCancelKeepsCaptureOnQuickAccess() async throws {
    environment.pickAnswers = [nil]
    _ = await runner.run(askAutomation([.continueRun]), files: [capture])
    XCTAssertEqual(environment.quickAccessShown, [capture])
  }

  func testAskHidesUnavailableTargetsAndFailsWhenNoneLeft() async throws {
    var off = automation(name: "Off", [text("x")])
    off.isEnabled = false
    store(off)
    let result = try unwrap(await runner.run(askAutomation([.automation(off.id), .automation(UUID())]), files: [capture]))
    XCTAssertTrue(environment.presentedPickers.isEmpty)
    XCTAssertEqual(result.outcome, .failed)
  }

  // MARK: - Validator

  func testValidatorChecksEveryPathAfterACondition() {
    // Skip path reaches Translate without OCR.
    let skipping = automation([appIs([Self.figma], otherwise: .skip(1)), .ocr(AutomationOCRConfig()), .translate(AutomationTranslateConfig())])
    let issues = AutomationChainValidator.validate(skipping, automationLookup: { _ in nil })
    XCTAssertEqual(issues.map(\.stepID), [skipping.steps[2].id])
    XCTAssertTrue(issues[0].blocksRun)

    // With "else stop" the only path that reaches Translate went through OCR.
    let stopping = automation([appIs([Self.figma], otherwise: .stop), .ocr(AutomationOCRConfig()), .translate(AutomationTranslateConfig())])
    XCTAssertTrue(AutomationChainValidator.validate(stopping, automationLookup: { _ in nil }).isEmpty)
  }

  func testValidatorFlagsSkipBeyondEndAndIncompleteCondition() {
    let chain = automation([appIs([], otherwise: .skip(5)), .copyImage])
    let reasons = AutomationChainValidator.validate(chain, automationLookup: { _ in nil }).map(\.reason)
    XCTAssertTrue(reasons.contains(.missingConfig(.condition)))
    XCTAssertTrue(reasons.contains(.missingConfig(.skipRange)))
    XCTAssertFalse(reasons.contains { if case .needs = $0 { true } else { false } })
  }

  func testIncompleteConditionBlocksRun() {
    let chain = automation([appIs([], otherwise: .stop), .copyImage])
    XCTAssertTrue(AutomationChainValidator.validate(chain, automationLookup: { _ in nil }).contains(where: \.blocksRun))
  }

  func testEditingInsideSkipRangeKeepsBranches() {
    var router = automation([appIs([Self.figma], otherwise: .skip(3)), text("a"), .notify, .stop, text("else")])
    router.removeStep(at: 2)
    XCTAssertEqual(router.steps[0].action, appIs([Self.figma], otherwise: .skip(2)))
    router.insertStep(AutomationStep(.copyImage), at: 1)
    XCTAssertEqual(router.steps[0].action, appIs([Self.figma], otherwise: .skip(3)))
    router.insertStep(AutomationStep(.copyImage), at: router.steps.count)
    XCTAssertEqual(router.steps[0].action, appIs([Self.figma], otherwise: .skip(3)), "After the range: unchanged")
  }

  func testValidatorStepsAfterStopAreUnreachable() {
    let chain = automation([.stop, .translate(AutomationTranslateConfig())])
    XCTAssertTrue(AutomationChainValidator.validate(chain, automationLookup: { _ in nil }).isEmpty)
  }

  func testValidatorDetectsCyclesAndMissingTargets() {
    var parent = automation(name: "A", [])
    var child = automation(name: "B", [])
    parent.steps = [AutomationStep(.runAutomation(AutomationRunAutomationConfig(automationID: child.id)))]
    child.steps = [AutomationStep(.runAutomation(AutomationRunAutomationConfig(automationID: parent.id)))]
    let lookup: (UUID) -> Automation? = { [parent, child] id in [parent, child].first { $0.id == id } }

    let issues = AutomationChainValidator.validate(parent, automationLookup: lookup)
    XCTAssertEqual(issues.map(\.reason), [.recursion])
    XCTAssertTrue(issues[0].blocksRun)

    let missing = automation([.runAutomation(AutomationRunAutomationConfig(automationID: UUID()))])
    XCTAssertEqual(AutomationChainValidator.validate(missing, automationLookup: { _ in nil }).map(\.reason), [.missingConfig(.automation)])
    let unset = automation([.runAutomation(AutomationRunAutomationConfig())])
    XCTAssertEqual(AutomationChainValidator.validate(unset, automationLookup: { _ in nil }).map(\.reason), [.missingConfig(.automation)])
    let empty = automation([.ask(AutomationAskConfig())])
    XCTAssertEqual(AutomationChainValidator.validate(empty, automationLookup: { _ in nil }).map(\.reason), [.missingConfig(.choices)])
  }

  func testValidatorFollowsTargetKinds() {
    // The target OCRs, so the parent can Translate afterwards.
    let ocr = automation(name: "OCR", [.ocr(AutomationOCRConfig())])
    let parent = automation([.runAutomation(AutomationRunAutomationConfig(automationID: ocr.id)), .translate(AutomationTranslateConfig())])
    XCTAssertTrue(AutomationChainValidator.validate(parent, automationLookup: { $0 == ocr.id ? ocr : nil }).isEmpty)

    // A target that needs text can't run on a fresh capture.
    let translate = automation(name: "Translate", [.translate(AutomationTranslateConfig())])
    let asking = automation([.ask(AutomationAskConfig(choices: [.automation(translate.id)]))])
    XCTAssertEqual(
      AutomationChainValidator.validate(asking, automationLookup: { $0 == translate.id ? translate : nil }).map(\.reason),
      [.targetCannotRun]
    )
  }

  // MARK: - Trust propagation

  func testEffectiveTrustIncludesReferencedAutomations() {
    let script = automation(name: "Script", [.runScript(AutomationRunScriptConfig(script: "echo hi"))])
    let parent = automation([.ask(AutomationAskConfig(choices: [.automation(script.id), .continueRun]))])
    let lookup: (UUID) -> Automation? = { $0 == script.id ? script : nil }
    XCTAssertEqual(parent.maxTrust, .local)
    XCTAssertEqual(parent.effectiveMaxTrust(lookup: lookup), .code)
    XCTAssertEqual(parent.reachableAutomations(lookup: lookup).map(\.id), [parent.id, script.id])
  }

  func testLauncherRefusesCodeReachedThroughRunAutomation() async throws {
    let suite = "AutomationControlFlowTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: PreferencesKeys.automationsSeeded)
    let store = AutomationStore(defaults: defaults)
    var script = automation(name: "Script", [.runScript(AutomationRunScriptConfig(script: "echo hi"))])
    script.source = .input
    store.add(script)
    var parent = automation(name: "Parent", [.runAutomation(AutomationRunAutomationConfig(automationID: script.id))])
    parent.source = .input
    store.add(parent)
    let launcher = AutomationLauncher(store: store, runner: runner, isURLSchemeEnabled: { true }, allowsCodeSteps: { false })

    let outcome = await launcher.launch(.id(parent.id), invocation: .menuBarDrop, input: AutomationInput(files: [capture], isAlreadyInHistory: false))

    XCTAssertEqual(outcome, .rejected(.codeStepsDisabled))
  }

  func testImportedControlStepsNeedReview() {
    let parent = automation([.runAutomation(AutomationRunAutomationConfig(automationID: UUID()))])
    XCTAssertTrue(parent.flaggedForReview(comparedTo: nil).needsReview)
  }

  // MARK: - Codable

  func testControlStepsRoundTripAndKeepUnknownPredicates() throws {
    let future = AutomationJSONValue.object(["type": .string("from_the_future"), "x": .number(1)])
    let original = automation([
      .condition(AutomationConditionConfig(
        match: .any,
        predicates: [
          .frontmostApp(bundleIDs: [Self.figma], negate: true),
          .captureMode([.area]),
          .invocation([.finder, .menuBarDrop]),
          .fileKind([.gif]),
          .pixelSize(dimension: .height, comparison: .lessThan, value: 100),
          .fileSize(comparison: .greaterThan, bytes: 42),
          .hasText(contains: "x"),
          .unsupported(future),
        ],
        otherwise: .skip(2)
      )),
      .stop,
      .runAutomation(AutomationRunAutomationConfig(automationID: UUID())),
      .ask(AutomationAskConfig(prompt: "Where?", choices: [.automation(UUID()), .continueRun, .stopRun])),
    ])
    var withFinder = original
    withFinder.showsInFinder = true

    let data = try JSONEncoder().encode(withFinder)
    let decoded = try JSONDecoder().decode(Automation.self, from: data)

    XCTAssertEqual(decoded, withFinder)
    XCTAssertTrue(decoded.showsInFinder)
  }

  func testOtherwiseTokens() {
    XCTAssertEqual(AutomationConditionConfig.Otherwise(token: "stop"), .stop)
    XCTAssertEqual(AutomationConditionConfig.Otherwise(token: "skip:3"), .skip(3))
    XCTAssertEqual(AutomationConditionConfig.Otherwise(token: "skip"), .skip(1))
    XCTAssertNil(AutomationConditionConfig.Otherwise(token: "skip:0"))
    XCTAssertNil(AutomationConditionConfig.Otherwise(token: "jump"))
  }

  func testConfigTOMLRoundTripWithoutJSONData() throws {
    let targetID = UUID()
    var source = automation(name: "Router", [
      .condition(AutomationConditionConfig(
        match: .any,
        predicates: [.frontmostApp(bundleIDs: [Self.figma], negate: false), .captureMode([.activeWindow])],
        otherwise: .skip(2)
      )),
      .copyImage,
      .stop,
      .runAutomation(AutomationRunAutomationConfig(automationID: targetID)),
      .ask(AutomationAskConfig(prompt: "Pick", choices: [.automation(targetID), .continueRun])),
    ])
    source.showsInFinder = true

    var writer = SimpleTOMLWriter()
    SnapzyConfigurationAutomationsCodec.write([source], to: &writer)
    // Hand-edited files may drop `data`: the keyed tables alone must carry everything.
    let keyed = writer.output.split(separator: "\n").filter { !$0.hasPrefix("data = ") }.joined(separator: "\n")
    XCTAssertTrue(keyed.contains(".predicates.01]"), keyed)
    let document = try SimpleTOMLParser.parse(keyed)
    let result = SnapzyConfigurationAutomationsCodec.parse(document, storedAutomation: { _ in source })

    XCTAssertTrue(result.warnings.isEmpty, "\(result.warnings)")
    let imported = try XCTUnwrap(result.automations?.first)
    XCTAssertEqual(imported.activeActions, source.activeActions)
    XCTAssertTrue(imported.showsInFinder)
  }

  func testTOMLResolvesTargetNamesWithinTheFile() throws {
    let aID = UUID(), bID = UUID()
    let toml = """
    [automations]

    [automations.\(aID.uuidString.lowercased())]
    name = "Parent"
    capture = "area"

    [automations.\(aID.uuidString.lowercased()).steps.01]
    kind = "run_automation"
    target = "child"

    [automations.\(bID.uuidString.lowercased())]
    name = "Child"
    capture = "input"

    [automations.\(bID.uuidString.lowercased()).steps.01]
    kind = "copy_image"
    """
    let result = SnapzyConfigurationAutomationsCodec.parse(try SimpleTOMLParser.parse(toml), storedAutomation: { _ in nil })
    let parent = try XCTUnwrap(result.automations?.first { $0.id == aID })
    XCTAssertEqual(parent.activeActions, [.runAutomation(AutomationRunAutomationConfig(automationID: bID))])
  }

  // MARK: - Picker model (phase 03)

  func testPickerModelKeys() {
    let choices = (1...3).map { AutomationPickerChoice(value: .automation(UUID()), title: "A\($0)", symbol: "bolt") }
    let model = AutomationPickerModel(title: "Pick", choices: choices)

    XCTAssertEqual(model.highlighted, 0)
    XCTAssertEqual(model.handle(.down), .consumed)
    XCTAssertEqual(model.handle(.down), .consumed)
    XCTAssertEqual(model.handle(.down), .consumed)
    XCTAssertEqual(model.highlighted, 2, "Clamped to the last row")
    XCTAssertEqual(model.handle(.returnKey), .finished(.picked(choices[2])))
    XCTAssertEqual(model.handle(.up), .consumed)
    XCTAssertEqual(model.handle(.digit(2)), .finished(.picked(choices[1])))
    XCTAssertEqual(model.handle(.digit(9)), .consumed, "No ninth row")
    XCTAssertEqual(model.handle(.escape), .finished(.cancelled))
    XCTAssertFalse(model.showsSearch)
  }

  func testPickerSearchFiltersAndDigitsTypeWhileSearching() {
    let choices = (1...12).map { AutomationPickerChoice(value: .automation(UUID()), title: "Item \($0)", symbol: "bolt") }
    let model = AutomationPickerModel(title: "Pick", choices: choices)
    XCTAssertTrue(model.showsSearch)

    model.query = "item 1"
    XCTAssertEqual(model.filtered.map(\.title), ["Item 1", "Item 10", "Item 11", "Item 12"])
    XCTAssertEqual(model.handle(.digit(1)), .ignored)
    XCTAssertEqual(model.handle(.returnKey), .finished(.picked(choices[0])))
  }

  // MARK: - File triggers (phase 04)

  func testSupportedFilesAndPasteboardParsing() throws {
    let video = directory.appendingPathComponent("clip.mov")
    let text = directory.appendingPathComponent("notes.txt")
    try Data().write(to: video)
    try Data().write(to: text)
    XCTAssertEqual(AutomationFileTriggers.supportedFiles([capture, text, video, capture]), [capture, video])

    let pasteboard = NSPasteboard(name: NSPasteboard.Name("AutomationControlFlowTests.\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    pasteboard.clearContents()
    pasteboard.writeObjects([capture as NSURL, text as NSURL, URL(string: "https://example.com/a.png")! as NSURL])
    XCTAssertEqual(AutomationFileTriggers.fileURLs(from: pasteboard).map(\.lastPathComponent), ["shot.png"])
  }

  func testEligibleAutomationsNeedFinderTriggerAndEveryKind() throws {
    let suite = "AutomationControlFlowTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: PreferencesKeys.automationsSeeded)
    let store = AutomationStore(defaults: defaults)

    var copy = automation(name: "Copy", [.copyImage])
    copy.showsInFinder = true
    var annotate = automation(name: "Annotate", [.openAnnotate])
    annotate.showsInFinder = true
    let hidden = automation(name: "Hidden", [.copyImage])
    [copy, annotate, hidden].forEach { store.add($0) }

    let video = directory.appendingPathComponent("clip.mov")
    XCTAssertEqual(AutomationFileTriggers.eligibleAutomations(for: [capture], store: store).map(\.name), ["Copy", "Annotate"])
    XCTAssertEqual(AutomationFileTriggers.eligibleAutomations(for: [capture, video], store: store).map(\.name), ["Copy"])
  }

  // MARK: - Recipes (phase 05)

  func testShareMenuAndDesignRouterRecipes() {
    let quick = AutomationPreset.quickCopy.makeAutomation()
    let cloud = AutomationPreset.cloudShare.makeAutomation()
    let ids: [AutomationPreset: UUID] = [.quickCopy: quick.id, .cloudShare: cloud.id]
    let shareMenu = AutomationPreset.shareMenu.makeAutomation(resolve: { ids[$0] })
    XCTAssertEqual(shareMenu.activeActions, [.ask(AutomationAskConfig(choices: [.automation(quick.id), .automation(cloud.id)]))])
    XCTAssertEqual(AutomationPreset.creationOrder.last, .shareMenu)

    let router = AutomationPreset.designRouter.makeAutomation()
    XCTAssertFalse(router.isEnabled, "Needs the design folder first")
    let issues = AutomationChainValidator.validate(router, automationLookup: { _ in nil })
    XCTAssertEqual(issues.map(\.reason), [.missingConfig(.folder)])
  }

  func testSeedingResolvesShareMenuChoices() {
    let suite = "AutomationControlFlowTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = AutomationStore(defaults: defaults)

    XCTAssertEqual(store.automations.map(\.presetID), AutomationPreset.allCases.map(\.rawValue))
    let shareMenu = store.automations.first { $0.presetID == AutomationPreset.shareMenu.rawValue }
    guard case .ask(let config)? = shareMenu?.activeActions.first else { return XCTFail("Expected an Ask step") }
    let expected = [AutomationPreset.quickCopy, .cloudShare, .docsShot].compactMap { preset in
      store.automations.first { $0.presetID == preset.rawValue }?.id
    }
    XCTAssertEqual(config.referencedAutomationIDs, expected)
  }
}
