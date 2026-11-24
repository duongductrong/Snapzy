//
//  AutomationAIStepsTests.swift
//  SnapzyTests
//
//  Milestone 6 phase 04: Redact (renderer, on-device scan, handler, order
//  warning) and AI Describe (handler, trust, config round trip).
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class AutomationAIStepsTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = FileManager.default.temporaryDirectory.appendingPathComponent("AutomationAIStepsTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    try super.tearDownWithError()
  }

  /// White PNG with `text` drawn large in black.
  private func writeTextImage(_ text: String, name: String = "shot.png", size: CGSize = CGSize(width: 900, height: 200)) throws -> URL {
    let rep = try XCTUnwrap(NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: Int(size.width),
      pixelsHigh: Int(size.height),
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    (text as NSString).draw(
      at: NSPoint(x: 30, y: 70),
      withAttributes: [.font: NSFont.systemFont(ofSize: 44), .foregroundColor: NSColor.black]
    )
    NSGraphicsContext.restoreGraphicsState()
    let url = directory.appendingPathComponent(name)
    try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    return url
  }

  /// RGBA of the pixel at (x, y) with a bottom-left origin.
  private func pixel(_ url: URL, x: Int, y: Int) throws -> [UInt8] {
    let image = try XCTUnwrap(QuickAccessImageOptimizer.loadImage(at: url))
    let rep = NSBitmapImageRep(cgImage: image)
    let color = try XCTUnwrap(rep.colorAt(x: x, y: image.height - 1 - y)?.usingColorSpace(.deviceRGB))
    return [color.redComponent, color.greenComponent, color.blueComponent].map { UInt8(($0 * 255).rounded()) }
  }

  // MARK: - Renderer

  func testSolidRedactionCoversOnlyTheRegion() throws {
    let source = try writeTextImage("hello")
    let result = try AutomationImageTransforms.redact(
      source,
      regions: [CGRect(x: 0, y: 0, width: 100, height: 50)],
      style: .solid,
      into: directory,
      baseName: "out"
    )

    XCTAssertEqual(try pixel(result.url, x: 10, y: 10), [0, 0, 0])
    XCTAssertEqual(try pixel(result.url, x: 800, y: 180), [255, 255, 255])
    XCTAssertEqual(result.pixelWidth, 900)
    XCTAssertEqual(result.url.pathExtension, "png")
  }

  func testPixelateChangesTheRegion() throws {
    let source = try writeTextImage("jane.doe@example.com")
    let region = CGRect(x: 20, y: 50, width: 600, height: 100)
    let before = try Data(contentsOf: source)

    let result = try AutomationImageTransforms.redact(source, regions: [region], style: .pixelate, into: directory, baseName: "out")

    XCTAssertNotEqual(try Data(contentsOf: result.url), before)
    XCTAssertEqual(try Data(contentsOf: source), before, "The original is never modified")
  }

  // MARK: - Scanner (Vision, on device)

  func testScannerFindsAnEmailOffline() async throws {
    let source = try writeTextImage("Contact jane.doe@example.com today")

    let regions = try await AutomationSensitiveDataScanner.scan(source, config: AutomationRedactConfig(categories: [.emails]))

    XCTAssertFalse(regions.isEmpty)
    XCTAssertTrue(regions.allSatisfy { $0.category == .emails })
  }

  func testScannerHonoursCategories() async throws {
    let source = try writeTextImage("Contact jane.doe@example.com today")

    let regions = try await AutomationSensitiveDataScanner.scan(source, config: AutomationRedactConfig(categories: [.phoneNumbers]))

    XCTAssertTrue(regions.isEmpty)
  }

  // MARK: - Handler

  func testRedactStepReplacesTheFileAndLogsOnlyACount() async throws {
    let source = try writeTextImage("secret")
    let environment = FakeAutomationEnvironment()
    environment.redactionRegions = [
      AutomationRedactionRegion(category: .credentials, rect: CGRect(x: 0, y: 0, width: 50, height: 50)),
      AutomationRedactionRegion(category: .emails, rect: CGRect(x: 100, y: 0, width: 50, height: 50)),
    ]
    let runner = AutomationRunner(environment: environment)
    let automation = Automation(
      name: "Safe",
      source: .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: false)),
      steps: [AutomationStep(.redact(AutomationRedactConfig(style: .solid))), AutomationStep(.copyImage)]
    )

    let result = await runner.run(automation, files: [source])

    let copied = try XCTUnwrap(environment.copiedImages.first?.first)
    XCTAssertNotEqual(copied, source, "Later steps get the redacted copy")
    XCTAssertEqual(result?.outcome, .succeeded)
    let record = try XCTUnwrap(environment.runRecords.first?.steps.first)
    XCTAssertEqual(record.kind, AutomationStepKind.redact.rawValue)
    XCTAssertEqual(record.detail, L10n.Automations.logRedactedCount(2))
  }

  func testRedactWithNothingFoundKeepsTheFile() async throws {
    let source = try writeTextImage("nothing here")
    let environment = FakeAutomationEnvironment()
    let runner = AutomationRunner(environment: environment)
    let automation = Automation(
      name: "Safe",
      source: .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: false)),
      steps: [AutomationStep(.redact(AutomationRedactConfig())), AutomationStep(.copyImage)]
    )

    await runner.run(automation, files: [source])

    XCTAssertEqual(environment.copiedImages, [[source]])
    XCTAssertEqual(environment.redactionScans.count, 1)
  }

  func testSafeSharePresetRedactsBeforeUploading() async throws {
    let source = try writeTextImage("jane.doe@example.com")
    let environment = FakeAutomationEnvironment()
    environment.redactionRegions = [AutomationRedactionRegion(category: .emails, rect: CGRect(x: 0, y: 0, width: 400, height: 120))]
    let runner = AutomationRunner(environment: environment)

    await runner.run(AutomationPreset.safeShare.makeAutomation(), files: [source])

    let uploaded = try XCTUnwrap(environment.uploaded.first)
    XCTAssertNotEqual(uploaded, source, "The upload gets the redacted copy, never the original")
    XCTAssertEqual(environment.copiedTexts.count, 1)
  }

  // MARK: - Validator

  func testRedactAfterUploadIsAWarningNotABlocker() {
    let late = Automation(
      name: "Late",
      source: .input,
      steps: [AutomationStep(.upload(AutomationUploadConfig())), AutomationStep(.redact(AutomationRedactConfig()))]
    )
    let issues = AutomationChainValidator.validate(late, uploaderExists: { _ in true }, secretExists: { _ in true }, automationLookup: { _ in nil })
    XCTAssertEqual(issues.map(\.reason), [.redactAfterNetwork])
    XCTAssertFalse(issues[0].blocksRun)
    XCTAssertTrue(issues[0].isWarning)
    XCTAssertFalse(late.needsSetup)

    let early = Automation(
      name: "Early",
      source: .input,
      steps: [AutomationStep(.redact(AutomationRedactConfig())), AutomationStep(.upload(AutomationUploadConfig()))]
    )
    XCTAssertTrue(AutomationChainValidator.validate(early, uploaderExists: { _ in true }, secretExists: { _ in true }, automationLookup: { _ in nil }).isEmpty)
  }

  // MARK: - AI Describe

  func testAIDescribeHandsTextToLaterSteps() async throws {
    let source = try writeTextImage("hello")
    let environment = FakeAutomationEnvironment()
    let runner = AutomationRunner(environment: environment)
    let automation = Automation(
      name: "Alt text",
      source: .input,
      steps: [
        AutomationStep(.aiAnnotate(AutomationAIAnnotateConfig(prompt: "Alt text please"))),
        AutomationStep(.copyText(AutomationTextTemplate())),
      ]
    )

    await runner.run(automation, input: AutomationInput(files: [source], isAlreadyInHistory: true), invocation: .cli)

    XCTAssertEqual(environment.copiedTexts, [environment.describedText])
    XCTAssertEqual(environment.describeCalls.first?.1.prompt, "Alt text please")
    XCTAssertEqual(environment.describeCalls.first?.2, false, "A CLI run can't ask for consent")
  }

  func testAIDescribeIsNetworkAndNeedsReviewOnImport() {
    let action = AutomationStepAction.aiAnnotate(AutomationAIAnnotateConfig())
    XCTAssertEqual(AutomationTrust.tier(of: action), .network)
    XCTAssertTrue(AutomationTrust.needsReviewWhenImported(action))
    XCTAssertEqual(AutomationTrust.tier(of: .redact(AutomationRedactConfig())), .local)
    XCTAssertFalse(AutomationTrust.needsReviewWhenImported(.redact(AutomationRedactConfig())))
  }

  func testDescribeToolboxKeepsTheResult() async {
    let toolbox = AutomationDescribeToolbox()
    let bad = await toolbox.execute(name: AutomationDescribeToolbox.toolName, argumentsJSON: #"{"text":"  "}"#)
    XCTAssertTrue(bad.isError)
    _ = await toolbox.execute(name: AutomationDescribeToolbox.toolName, argumentsJSON: #"{"text":"A dialog"}"#)
    XCTAssertEqual(toolbox.result, "A dialog")
  }

  // MARK: - Persistence

  func testConfigsRoundTripThroughJSONAndTOML() throws {
    let endpointID = UUID()
    let steps = [
      AutomationStep(.redact(AutomationRedactConfig(categories: [.faces, .emails], style: .blur))),
      AutomationStep(.aiAnnotate(AutomationAIAnnotateConfig(prompt: "Summarize", provider: .endpoint(endpointID)))),
    ]
    let automation = Automation(name: "AI", source: .input, steps: steps)

    let json = try JSONDecoder().decode(Automation.self, from: JSONEncoder().encode(automation))
    XCTAssertEqual(json.steps.compactMap(\.action), steps.compactMap(\.action))
    // Categories are kept in catalog order.
    if case .redact(let config)? = json.steps.first?.action {
      XCTAssertEqual(config.categories, [.emails, .faces])
    }

    var writer = SimpleTOMLWriter()
    SnapzyConfigurationAutomationsCodec.write([automation], to: &writer)
    let parsed = SnapzyConfigurationAutomationsCodec.parse(try SimpleTOMLParser.parse(writer.output), storedAutomation: { _ in nil })
    XCTAssertEqual(parsed.automations?.first?.steps.compactMap(\.action), steps.compactMap(\.action))
  }

  func testUnknownRedactCategoryIsDropped() throws {
    let data = Data(#"{"categories":["emails","retinas"],"style":"solid"}"#.utf8)
    let config = try JSONDecoder().decode(AutomationRedactConfig.self, from: data)
    XCTAssertEqual(config.categories, [.emails])
    XCTAssertEqual(config.style, .solid)
  }
}
