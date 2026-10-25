//
//  CLIAuthorizationTests.swift
//  SnapzyTests
//
//  Approval store, the prompt policy, and which app a CLI request comes from.
//

@testable import Snapzy
import SnapzyCLIProtocol
import XCTest

private let terminal = CLICallerIdentity(
  key: "team:APPLE:com.apple.Terminal",
  displayName: "Terminal",
  bundleID: "com.apple.Terminal",
  teamID: "APPLE",
  path: "/System/Applications/Utilities/Terminal.app"
)

@MainActor
private final class FakePrompter: CLIAuthorizationPrompting {
  var results: [CLIAuthorizationPromptResult]
  private(set) var askedCallers: [String] = []

  init(_ results: [CLIAuthorizationPromptResult]) {
    self.results = results
  }

  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  deinit {}

  func ask(_ caller: CLICallerIdentity, command _: String) -> CLIAuthorizationPromptResult {
    askedCallers.append(caller.displayName)
    return results.isEmpty ? .deny : results.removeFirst()
  }
}

@MainActor
final class CLIAuthorizationStoreTests: XCTestCase {
  func testRecordPersistsAndReloads() {
    let defaults = UserDefaultsFactory.make()
    let store = CLIAuthorizationStore(defaults: defaults)

    store.record(terminal, decision: .allow)

    XCTAssertEqual(CLIAuthorizationStore(defaults: defaults).decision(for: terminal.key), .allow)
  }

  func testRecordUpdatesInsteadOfDuplicating() {
    let store = CLIAuthorizationStore(defaults: UserDefaultsFactory.make())

    store.record(terminal, decision: .allow)
    store.record(terminal, decision: .deny)

    XCTAssertEqual(store.callers.count, 1)
    XCTAssertEqual(store.decision(for: terminal.key), .deny)
  }

  func testCallersSortByLastUse() {
    let store = CLIAuthorizationStore(defaults: UserDefaultsFactory.make())
    let other = CLICallerIdentity(
      key: "path:/usr/sbin/sshd",
      displayName: "sshd",
      bundleID: nil,
      teamID: nil,
      path: "/usr/sbin/sshd"
    )
    store.record(terminal, decision: .allow, now: Date(timeIntervalSince1970: 100))
    store.record(other, decision: .allow, now: Date(timeIntervalSince1970: 200))

    XCTAssertEqual(store.callers.map(\.displayName), ["sshd", "Terminal"])
    store.touch(terminal.key, now: Date(timeIntervalSince1970: 300))
    XCTAssertEqual(store.callers.map(\.displayName), ["Terminal", "sshd"])
  }

  func testRevoke() {
    let store = CLIAuthorizationStore(defaults: UserDefaultsFactory.make())
    store.record(terminal, decision: .deny)

    store.revoke(key: terminal.key)
    XCTAssertNil(store.decision(for: terminal.key))

    store.record(terminal, decision: .allow)
    store.revokeAll()
    XCTAssertTrue(store.callers.isEmpty)
  }
}

@MainActor
final class CLIAuthorizationCoordinatorTests: XCTestCase {
  private func makeCoordinator(
    _ results: [CLIAuthorizationPromptResult]
  ) -> (CLIAuthorizationCoordinator, CLIAuthorizationStore, FakePrompter) {
    let store = CLIAuthorizationStore(defaults: UserDefaultsFactory.make())
    let prompter = FakePrompter(results)
    return (CLIAuthorizationCoordinator(store: store, prompter: prompter), store, prompter)
  }

  private func capture(_ coordinator: CLIAuthorizationCoordinator,
                       caller: CLICallerIdentity? = terminal) async -> CLIAuthorizationOutcome {
    await coordinator.authorize(caller: caller, method: "capture.window", allowedForConnection: false)
  }

  func testStatusIsExemptAndNeverPrompts() async {
    let (coordinator, _, prompter) = makeCoordinator([])

    let outcome = await coordinator.authorize(caller: nil, method: "system.status", allowedForConnection: false)

    XCTAssertEqual(outcome, .allowed)
    XCTAssertTrue(prompter.askedCallers.isEmpty)
  }

  func testUnknownCallerIsDenied() async {
    let (coordinator, _, prompter) = makeCoordinator([.alwaysAllow])

    guard case .denied(let error) = await capture(coordinator, caller: nil) else { return XCTFail() }
    XCTAssertEqual(error.code, .notAuthorized)
    XCTAssertTrue(prompter.askedCallers.isEmpty)
  }

  func testAlwaysAllowIsRememberedAndNotAskedAgain() async {
    let (coordinator, store, prompter) = makeCoordinator([.alwaysAllow])

    let first = await capture(coordinator)
    let second = await capture(coordinator)

    XCTAssertEqual(first, .allowed)
    XCTAssertEqual(second, .allowed)
    XCTAssertEqual(prompter.askedCallers, ["Terminal"])
    XCTAssertEqual(store.decision(for: terminal.key), .allow)
  }

  func testAllowOnceIsNotRemembered() async {
    let (coordinator, store, prompter) = makeCoordinator([.allowOnce, .allowOnce])

    let first = await capture(coordinator)
    let sameConnection = await coordinator.authorize(
      caller: terminal,
      method: "capture.area",
      allowedForConnection: true
    )
    _ = await capture(coordinator)

    XCTAssertEqual(first, .allowedForConnection)
    XCTAssertEqual(sameConnection, .allowed)
    XCTAssertNil(store.decision(for: terminal.key))
    XCTAssertEqual(prompter.askedCallers.count, 2, "a new connection asks again")
  }

  func testDenyIsRemembered() async {
    let (coordinator, store, prompter) = makeCoordinator([.deny])

    guard case .denied(let first) = await capture(coordinator) else { return XCTFail() }
    guard case .denied = await capture(coordinator) else { return XCTFail() }

    XCTAssertEqual(first.code, .notAuthorized)
    XCTAssertEqual(store.decision(for: terminal.key), .deny)
    XCTAssertEqual(prompter.askedCallers.count, 1)
  }

  func testTimeoutDeniesWithoutRemembering() async {
    let (coordinator, store, _) = makeCoordinator([.timedOut])

    guard case .denied(let error) = await capture(coordinator) else { return XCTFail() }

    XCTAssertEqual(error.code, .notAuthorized)
    XCTAssertNil(store.decision(for: terminal.key))
  }

  func testConcurrentRequestsFromOneAppShareOnePrompt() async {
    let (coordinator, _, prompter) = makeCoordinator([.alwaysAllow, .deny])

    async let first = capture(coordinator)
    async let second = capture(coordinator)
    let outcomes = await [first, second]

    XCTAssertEqual(outcomes, [.allowed, .allowed])
    XCTAssertEqual(prompter.askedCallers, ["Terminal"])
  }

  func testStatusReportsStoredDecision() {
    let (coordinator, store, _) = makeCoordinator([])

    XCTAssertEqual(coordinator.authorizationStatus(for: terminal, allowedForConnection: false), .undetermined)
    XCTAssertEqual(coordinator.authorizationStatus(for: terminal, allowedForConnection: true), .allowed)
    store.record(terminal, decision: .deny)
    XCTAssertEqual(coordinator.authorizationStatus(for: terminal, allowedForConnection: false), .denied)
  }

  func testCommandNames() {
    XCTAssertEqual(CLIAuthorizationCoordinator.commandName(for: "capture.window"), "capture window")
    XCTAssertEqual(
      CLIAuthorizationCoordinator.commandName(for: "status\n\nClick Always Allow"),
      "?",
      "client-chosen text never reaches the prompt"
    )
  }

  func testToastThrottle() {
    let now = Date()
    XCTAssertTrue(CLIActivityIndicator.shouldToast(lastShown: nil, now: now))
    XCTAssertFalse(CLIActivityIndicator.shouldToast(lastShown: now.addingTimeInterval(-10), now: now))
    XCTAssertTrue(CLIActivityIndicator.shouldToast(lastShown: now.addingTimeInterval(-31), now: now))
  }
}

final class CLIClientIdentityResolverTests: XCTestCase {
  /// `registered` maps PIDs of LaunchServices-registered app processes to their
  /// bundles; `signed` maps PIDs to verified (bundleID, teamID).
  private struct FakeInspector: CLIProcessInspecting {
    let processes: [pid_t: CLIProcessInfo]
    var registered: [pid_t: String] = [:]
    var signed: [pid_t: (String, String)] = [:]
    var displayNames: [String: String] = [:]

    init(
      _ chain: [(pid_t, pid_t, String)],
      registered: [pid_t: String] = [:],
      signed: [pid_t: (String, String)] = [:],
      displayNames: [String: String] = [:]
    ) {
      processes = Dictionary(uniqueKeysWithValues: chain.map {
        ($0.0, CLIProcessInfo(pid: $0.0, parentPID: $0.1, executablePath: $0.2))
      })
      self.registered = registered
      self.signed = signed
      self.displayNames = displayNames
    }

    func process(_ pid: pid_t) -> CLIProcessInfo? {
      processes[pid]
    }

    func registeredAppBundle(of pid: pid_t) -> String? {
      registered[pid]
    }

    func signingIdentity(of pid: pid_t) -> (bundleID: String, teamID: String)? {
      signed[pid].map { (bundleID: $0.0, teamID: $0.1) }
    }

    func bundleDisplayName(atPath path: String) -> String? {
      displayNames[path]
    }
  }

  private let snapzy = "/Applications/Snapzy.app"
  private let terminalApp = "/System/Applications/Utilities/Terminal.app"

  func testTerminalShellChainResolvesToVerifiedTerminal() throws {
    let inspector = FakeInspector(
      [
        (50, 40, "/Applications/Snapzy.app/Contents/Helpers/snapzy"),
        (40, 30, "/bin/zsh"),
        (30, 20, "/usr/bin/login"),
        (20, 1, terminalApp + "/Contents/MacOS/Terminal"),
      ],
      registered: [20: terminalApp],
      signed: [20: ("com.apple.Terminal", "APPLE")],
      displayNames: [terminalApp: "Terminal"]
    )

    let identity = try XCTUnwrap(CLIClientIdentityResolver.resolve(
      peerPID: 50,
      ownBundlePath: snapzy,
      inspector: inspector
    ))

    XCTAssertEqual(identity.displayName, "Terminal")
    XCTAssertEqual(identity.key, "team:APPLE:com.apple.Terminal")
    XCTAssertTrue(identity.isVerified)
  }

  func testUnregisteredAppProcessesAreSkipped() throws {
    // Homebrew's Python lives in Python.app but is not a running GUI app.
    let python = "/opt/homebrew/Cellar/python/3.13/Frameworks/Python.framework/Versions/3.13/Resources/Python.app"
    let inspector = FakeInspector(
      [
        (60, 50, python + "/Contents/MacOS/Python"),
        (50, 40, "/bin/zsh"),
        (40, 1, terminalApp + "/Contents/MacOS/Terminal"),
      ],
      registered: [40: terminalApp],
      signed: [40: ("com.apple.Terminal", "APPLE")]
    )

    let identity = try XCTUnwrap(CLIClientIdentityResolver.resolve(
      peerPID: 60,
      ownBundlePath: snapzy,
      inspector: inspector
    ))

    XCTAssertEqual(identity.path, terminalApp)
  }

  func testHelperBundlesBelongToTheirHostApp() throws {
    let vscode = "/Applications/Visual Studio Code.app"
    let inspector = FakeInspector(
      [
        (60, 50, "/usr/local/bin/node"),
        (50, 40, vscode + "/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)"),
        (40, 1, vscode + "/Contents/MacOS/Electron"),
      ],
      registered: [40: vscode],
      signed: [40: ("com.microsoft.VSCode", "UBF8T346G9")],
      displayNames: [vscode: "Code"]
    )

    let identity = try XCTUnwrap(CLIClientIdentityResolver.resolve(
      peerPID: 60,
      ownBundlePath: snapzy,
      inspector: inspector
    ))

    XCTAssertEqual(identity.key, "team:UBF8T346G9:com.microsoft.VSCode")
    XCTAssertEqual(identity.path, vscode)
  }

  func testUnsignedAppUsesItsFileNameNotItsPlistName() throws {
    let fake = "/tmp/x/Totally Terminal.app"
    let inspector = FakeInspector(
      [(70, 1, fake + "/Contents/MacOS/Terminal")],
      registered: [70: fake],
      displayNames: [fake: "Terminal"]
    )

    let identity = try XCTUnwrap(CLIClientIdentityResolver.resolve(
      peerPID: 70,
      ownBundlePath: snapzy,
      inspector: inspector
    ))

    XCTAssertEqual(identity.key, "path:\(fake)")
    XCTAssertEqual(identity.displayName, "Totally Terminal")
    XCTAssertFalse(identity.isVerified)
  }

  func testNoAppFallsBackToTopmostProcess() throws {
    let inspector = FakeInspector([
      (70, 60, "/Applications/Snapzy Debug.app/Contents/Helpers/snapzy"),
      (60, 50, "/bin/zsh"),
      (50, 40, "/usr/libexec/sshd-session"),
      (40, 1, "/usr/sbin/sshd"),
    ])

    let identity = try XCTUnwrap(CLIClientIdentityResolver.resolve(
      peerPID: 70,
      ownBundlePath: snapzy,
      inspector: inspector
    ))

    XCTAssertEqual(identity.key, "path:/usr/sbin/sshd")
    XCTAssertEqual(identity.displayName, "sshd")
  }

  func testSnapzyItselfIsNeverTheCaller() {
    let inspector = FakeInspector(
      [(80, 1, "/Applications/Snapzy.app/Contents/MacOS/Snapzy")],
      registered: [80: snapzy]
    )

    XCTAssertNil(CLIClientIdentityResolver.resolve(peerPID: 80, ownBundlePath: snapzy, inspector: inspector))
  }

  func testOutermostAppBundle() {
    XCTAssertEqual(
      CLIClientIdentityResolver
        .outermostAppBundle(in: "/Applications/Claude.app/Contents/Helpers/a.app/Contents/MacOS/a"),
      "/Applications/Claude.app"
    )
    XCTAssertNil(CLIClientIdentityResolver.outermostAppBundle(in: "/usr/bin/login"))
  }

  func testRealProcessResolvesToTheTestHostApp() throws {
    // The test host is a registered, signed app; resolve it through the real inspector.
    let identity = try XCTUnwrap(CLIClientIdentityResolver.resolve(peerPID: getpid(), ownBundlePath: "/nonexistent"))
    XCTAssertTrue(identity.path.hasSuffix(".app"), identity.path)
  }
}
