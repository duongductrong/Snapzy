//
//  AutomationSystemDefaultTests.swift
//  SnapzyTests
//
//  Milestone 6 phase 01: the after-capture matrix as default automations.
//  Parity: every matrix combination × capture type × runtime flag runs the
//  same effects, in the same order, as the legacy `executeActions`.
//

import XCTest
@testable import Snapzy

@MainActor
final class AutomationSystemDefaultTests: XCTestCase {
  private var directory: URL!
  private var screenshot: URL!
  private var recording: URL!
  private var suiteName: String!
  private var defaults: UserDefaults!

  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = FileManager.default.temporaryDirectory.appendingPathComponent("AutomationSystemDefaultTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    screenshot = directory.appendingPathComponent("Snapzy_shot.png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: screenshot)
    recording = directory.appendingPathComponent("Snapzy_rec.mp4")
    try Data([0, 1, 2, 3]).write(to: recording)
    suiteName = "AutomationSystemDefaultTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    defaults.removePersistentDomain(forName: suiteName)
    try super.tearDownWithError()
  }

  /// All 16 combinations of the four matrix cells.
  private static var allMatrices: [[AfterCaptureAction: Bool]] {
    (0..<16).map { bits in
      [
        .save: bits & 1 != 0,
        .copyFile: bits & 2 != 0,
        .showQuickAccess: bits & 4 != 0,
        .openAnnotate: bits & 8 != 0,
      ]
    }
  }

  /// What the legacy handler did, written out from `executeActions` before the
  /// switch: copy → Quick Access (unless skipped) → pin (screenshots, flag) →
  /// Annotate (screenshots only).
  private static func golden(
    _ type: CaptureType,
    _ matrix: [AfterCaptureAction: Bool],
    pin: Bool,
    skipQuickAccess: Bool
  ) -> [AutomationStepKind] {
    var effects: [AutomationStepKind] = []
    if matrix[.copyFile]! { effects.append(.copyFile) }
    if matrix[.showQuickAccess]!, !skipQuickAccess { effects.append(.showQuickAccess) }
    if type == .screenshot, pin { effects.append(.pin) }
    if type == .screenshot, matrix[.openAnnotate]! { effects.append(.openAnnotate) }
    return effects
  }

  // MARK: - Parity

  func testEveryMatrixCombinationRunsLegacyEffectsInOrder() async throws {
    for type in CaptureType.allCases {
      for matrix in Self.allMatrices {
        for pin in [false, true] {
          for skipQuickAccess in [false, true] {
            let environment = FakeAutomationEnvironment()
            let runner = AutomationRunner(environment: environment)
            let automation = AutomationSystemDefault.make(for: type, matrix: matrix)
            let file: URL = type == .screenshot ? screenshot : recording

            let result = await runner.runDefault(
              automation,
              type: type,
              files: [file],
              pinToScreen: pin,
              skipQuickAccess: skipQuickAccess
            )

            let label = "\(type) \(matrix.filter(\.value).keys.map(\.rawValue).sorted()) pin=\(pin) skip=\(skipQuickAccess)"
            let expected = Self.golden(type, matrix, pin: pin, skipQuickAccess: skipQuickAccess)
            XCTAssertEqual(environment.events, expected, label)
            XCTAssertEqual(
              AutomationSystemDefault.legacyEffects(type: type, matrix: matrix, pinToScreen: pin, skipQuickAccess: skipQuickAccess),
              expected,
              label
            )
            XCTAssertEqual(result?.outcome, .succeeded, label)
            // Every standard capture lands in History, as before.
            XCTAssertEqual(environment.history, [file], label)
            // Screenshots get the default canvas preset, recordings don't.
            XCTAssertEqual(environment.preparedScreenshots, type == .screenshot ? [file] : [], label)
            // Quiet: no HUD, no activity log entry, no notification.
            // (Step titles still flow; the HUD ignores a run it never started.)
            XCTAssertFalse(environment.runUpdates.contains { if case .started = $0 { true } else { false } }, label)
            XCTAssertTrue(environment.runRecords.isEmpty, label)
            XCTAssertTrue(environment.notifications.isEmpty, label)
            // Video copies go through the file-reference path, like `copyToClipboard(isVideo:)`.
            if matrix[.copyFile]! {
              XCTAssertEqual(type == .screenshot ? environment.copiedImages : environment.copiedMedia.map { [$0] }, [[file]], label)
            }
          }
        }
      }
    }
  }

  func testBatchScreenshotsCopyAllShowEachAndAnnotateFirst() async throws {
    let second = directory.appendingPathComponent("Snapzy_shot2.png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: second)
    let environment = FakeAutomationEnvironment()
    let runner = AutomationRunner(environment: environment)
    let matrix: [AfterCaptureAction: Bool] = [.save: true, .copyFile: true, .showQuickAccess: true, .openAnnotate: true]

    await runner.runDefault(AutomationSystemDefault.make(for: .screenshot, matrix: matrix), type: .screenshot, files: [screenshot, second])

    XCTAssertEqual(environment.copiedImages, [[screenshot, second]])
    XCTAssertEqual(environment.quickAccessShown, [screenshot, second])
    XCTAssertEqual(environment.annotated.map(\.0), [screenshot])
    XCTAssertEqual(environment.history, [screenshot, second])
  }

  func testCustomPipelineIsReportedAndLogged() async throws {
    let environment = FakeAutomationEnvironment()
    let runner = AutomationRunner(environment: environment)
    var automation = AutomationSystemDefault.make(for: .screenshot, matrix: AutomationSystemDefault.defaultMatrix(for: .screenshot))
    automation.steps.append(AutomationStep(.notify))
    XCTAssertTrue(automation.isCustomizedSystemDefault)

    await runner.runDefault(automation, type: .screenshot, files: [screenshot])

    XCTAssertEqual(environment.runRecords.count, 1)
    XCTAssertEqual(environment.runRecords.first?.invocation, AutomationInvocation.afterCapture.rawValue)
    XCTAssertFalse(environment.runUpdates.isEmpty)
    XCTAssertEqual(environment.notifications.count, 1)
  }

  func testUnreviewedImportedDefaultRunsItsSimpleForm() async throws {
    let environment = FakeAutomationEnvironment()
    let runner = AutomationRunner(environment: environment)
    var imported = AutomationSystemDefault.make(for: .screenshot, matrix: AutomationSystemDefault.defaultMatrix(for: .screenshot))
    imported.steps.append(AutomationStep(.webhook(AutomationWebhookConfig())))
    imported.needsReview = true

    await runner.runDefault(imported, type: .screenshot, files: [screenshot])

    XCTAssertEqual(environment.events, [.copyFile, .showQuickAccess])
    XCTAssertTrue(environment.sentRequests.isEmpty, "Unreviewed webhook never runs")
  }

  // MARK: - Projection

  func testProjectionRoundTripsEveryMatrix() {
    for type in CaptureType.allCases {
      for matrix in Self.allMatrices {
        var expected = matrix
        if type == .recording { expected[.openAnnotate] = false }
        let automation = AutomationSystemDefault.make(for: type, matrix: matrix)
        XCTAssertEqual(AutomationSystemDefault.project(automation, type: type), expected)
        XCTAssertFalse(automation.isCustomizedSystemDefault)
        XCTAssertTrue(automation.isSystemDefault)
        XCTAssertEqual(automation.systemCaptureType, type)
      }
    }
  }

  func testProjectionRejectsCustomPipelines() {
    let base = AutomationSystemDefault.make(for: .screenshot, matrix: AutomationSystemDefault.defaultMatrix(for: .screenshot))

    var extra = base
    extra.steps.append(AutomationStep(.upload(AutomationUploadConfig())))
    XCTAssertNil(AutomationSystemDefault.project(extra, type: .screenshot))

    var reordered = base
    reordered.steps.reverse()
    XCTAssertNil(AutomationSystemDefault.project(reordered, type: .screenshot))

    var disabled = base
    disabled.steps[0].isEnabled = false
    XCTAssertNil(AutomationSystemDefault.project(disabled, type: .screenshot))
    // Lenient: a disabled copy step reads as "copy off".
    XCTAssertEqual(AutomationSystemDefault.lenientMatrix(disabled, type: .screenshot)[.copyFile], false)
  }

  func testSettingACellOnASimplePipelineKeepsStepIDs() throws {
    let base = AutomationSystemDefault.make(for: .screenshot, matrix: AutomationSystemDefault.defaultMatrix(for: .screenshot))
    let copyID = try XCTUnwrap(base.steps.first { $0.action?.kind == .copyFile }?.id)

    let changed = AutomationSystemDefault.setting(.openAnnotate, to: true, in: base, type: .screenshot)

    XCTAssertEqual(changed.steps.compactMap(\.action?.kind), [.copyFile, .showQuickAccess, .openAnnotate])
    XCTAssertEqual(changed.steps.first?.id, copyID)
    let saveOff = AutomationSystemDefault.setting(.save, to: false, in: changed, type: .screenshot)
    XCTAssertEqual(saveOff.captureSpec?.saveToExportDirectory, false)
  }

  func testSettingACellOnACustomPipelineOnlyTouchesThatKind() {
    var custom = AutomationSystemDefault.make(for: .screenshot, matrix: AutomationSystemDefault.defaultMatrix(for: .screenshot))
    custom.steps.append(AutomationStep(.upload(AutomationUploadConfig())))

    let noQuickAccess = AutomationSystemDefault.setting(.showQuickAccess, to: false, in: custom, type: .screenshot)
    XCTAssertEqual(noQuickAccess.steps.compactMap(\.action?.kind), [.copyFile, .upload])

    let withAnnotate = AutomationSystemDefault.setting(.openAnnotate, to: true, in: noQuickAccess, type: .screenshot)
    XCTAssertEqual(withAnnotate.steps.compactMap(\.action?.kind), [.copyFile, .upload, .openAnnotate])

    let backQuickAccess = AutomationSystemDefault.setting(.showQuickAccess, to: true, in: withAnnotate, type: .screenshot)
    XCTAssertEqual(backQuickAccess.steps.compactMap(\.action?.kind), [.copyFile, .upload, .showQuickAccess, .openAnnotate])
  }

  func testRuntimeFlagsInsertPinBeforeAnnotateAndDropQuickAccess() {
    let matrix: [AfterCaptureAction: Bool] = [.save: true, .copyFile: true, .showQuickAccess: true, .openAnnotate: true]
    let steps = AutomationSystemDefault.make(for: .screenshot, matrix: matrix).steps

    let pinned = AutomationSystemDefault.runtimeSteps(steps, type: .screenshot, pinToScreen: true, skipQuickAccess: false)
    XCTAssertEqual(pinned.compactMap(\.action?.kind), [.copyFile, .showQuickAccess, .pin, .openAnnotate])

    let skipped = AutomationSystemDefault.runtimeSteps(steps, type: .screenshot, pinToScreen: false, skipQuickAccess: true)
    XCTAssertEqual(skipped.compactMap(\.action?.kind), [.copyFile, .openAnnotate])

    // Recordings never pin.
    let recordingSteps = AutomationSystemDefault.make(for: .recording, matrix: matrix).steps
    XCTAssertEqual(
      AutomationSystemDefault.runtimeSteps(recordingSteps, type: .recording, pinToScreen: true, skipQuickAccess: false).compactMap(\.action?.kind),
      [.copyFile, .showQuickAccess]
    )
  }

  func testNormalizedKeepsAnEmptyDefaultAndDropsTriggers() {
    let off: [AfterCaptureAction: Bool] = [.save: false, .copyFile: false, .showQuickAccess: false, .openAnnotate: false]
    var automation = AutomationSystemDefault.make(for: .screenshot, matrix: off)
    automation.triggers = [.menuBar, .quickAccessAction]
    automation.isEnabled = false
    automation.externalInvocation = true

    let normalized = automation.normalized()

    XCTAssertTrue(normalized.steps.isEmpty)
    XCTAssertTrue(normalized.triggers.isEmpty)
    XCTAssertTrue(normalized.isEnabled)
    XCTAssertFalse(normalized.externalInvocation)
  }

  // MARK: - Store migration

  func testFirstLaunchMigratesTheStoredMatrix() throws {
    let screenshotMatrix: [AfterCaptureAction: Bool] = [.save: false, .copyFile: true, .showQuickAccess: false, .openAnnotate: true]
    let store = AutomationStore(defaults: defaults, matrix: { type in
      type == .screenshot ? screenshotMatrix : AutomationSystemDefault.defaultMatrix(for: type)
    })

    let screenshotDefault = store.defaultAutomation(for: .screenshot)
    XCTAssertEqual(AutomationSystemDefault.project(screenshotDefault, type: .screenshot), screenshotMatrix)
    XCTAssertEqual(screenshotDefault.id, AutomationSystemDefault.id(for: .screenshot))
    XCTAssertEqual(store.systemAutomations.count, 2)
    // Not in the user list, not counted against the cap.
    XCTAssertFalse(store.automations.contains { $0.isSystemDefault })
    XCTAssertNotNil(defaults.data(forKey: PreferencesKeys.automationsSystemDefaults))

    // A later launch reads the stored automations, not the matrix.
    let reloaded = AutomationStore(defaults: defaults, matrix: { _ in
      [.save: true, .copyFile: false, .showQuickAccess: false, .openAnnotate: false]
    })
    XCTAssertEqual(reloaded.defaultAutomation(for: .screenshot), screenshotDefault)
  }

  func testMatrixChangesMirrorIntoTheLegacyKey() {
    let store = AutomationStore(defaults: defaults)
    var mirrored: [CaptureType: [AfterCaptureAction: Bool]] = [:]
    store.onSystemDefaultChanged = { mirrored[$0] = $1 }

    store.setDefaultMatrixAction(.showQuickAccess, for: .recording, enabled: false)

    XCTAssertEqual(mirrored[.recording]?[.showQuickAccess], false)
    XCTAssertEqual(store.defaultAutomation(for: .recording).steps.compactMap(\.action?.kind), [.copyFile])
  }

  func testPreferencesSetterWritesTheDefaultAutomation() {
    let preferences = PreferencesManager(defaults: defaults)
    let store = AutomationStore(defaults: defaults, matrix: { preferences.storedMatrix(for: $0) })
    store.onSystemDefaultChanged = { preferences.adoptDefaultAutomationMatrix($1, for: $0) }
    preferences.defaultAutomationWriter = { store.setDefaultMatrixAction($0, for: $1, enabled: $2) }

    preferences.setAction(.openAnnotate, for: .screenshot, enabled: true)

    XCTAssertTrue(store.defaultAutomation(for: .screenshot).contains(.openAnnotate))
    XCTAssertTrue(preferences.isActionEnabled(.openAnnotate, for: .screenshot))
    // Downgrade path: the legacy key a previous build reads holds the change.
    XCTAssertTrue(PreferencesManager(defaults: defaults).isActionEnabled(.openAnnotate, for: .screenshot))
  }

  func testEditorSaveOfACustomPipelineMirrorsLenientMatrix() {
    let preferences = PreferencesManager(defaults: defaults)
    let store = AutomationStore(defaults: defaults, matrix: { preferences.storedMatrix(for: $0) })
    store.onSystemDefaultChanged = { preferences.adoptDefaultAutomationMatrix($1, for: $0) }
    var custom = store.defaultAutomation(for: .screenshot)
    custom.steps = [AutomationStep(.upload(AutomationUploadConfig())), AutomationStep(.copyLink(AutomationLinkTemplate()))]

    store.update(custom)

    XCTAssertTrue(store.defaultAutomation(for: .screenshot).isCustomizedSystemDefault)
    XCTAssertFalse(preferences.isActionEnabled(.copyFile, for: .screenshot))
    XCTAssertFalse(preferences.isActionEnabled(.showQuickAccess, for: .screenshot))

    store.resetDefaultAutomation(for: .screenshot)
    XCTAssertFalse(store.defaultAutomation(for: .screenshot).isCustomizedSystemDefault)
    XCTAssertTrue(store.defaultAutomation(for: .screenshot).steps.isEmpty)
  }

  func testSystemDefaultsCannotBeAddedDuplicatedOrDeleted() {
    let store = AutomationStore(defaults: defaults)
    let system = store.defaultAutomation(for: .screenshot)

    XCTAssertFalse(store.add(system))
    XCTAssertNil(store.duplicate(id: system.id))
    store.delete(id: system.id)
    XCTAssertEqual(store.defaultAutomation(for: .screenshot), system)
  }

  func testReplaceAllRoutesSystemEntriesToTheDefaults() {
    let store = AutomationStore(defaults: defaults)
    var imported = store.defaultAutomation(for: .recording)
    imported.steps = []
    let user = Automation(name: "Mine", source: .input, steps: [AutomationStep(.copyFile)])

    store.replaceAll([imported, user])

    XCTAssertEqual(store.automations.map(\.name), ["Mine"])
    XCTAssertTrue(store.defaultAutomation(for: .recording).steps.isEmpty)
  }
}
