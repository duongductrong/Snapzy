//
//  AppDiscoveryTests.swift
//  SnapzyCLICoreTests
//
//  AppLocator path resolution and the AppLauncher connect/launch policy.
//

import Foundation
@testable import SnapzyCLIClient
@testable import SnapzyCLIProtocol
import XCTest

final class AppLocatorTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyCLIKitTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private func makeApp(_ name: String, bundleID: String) throws -> URL {
    let app = directory.appendingPathComponent(name, isDirectory: true)
    let helpers = app.appendingPathComponent("Contents/Helpers", isDirectory: true)
    try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
    let plist = try PropertyListSerialization.data(
      fromPropertyList: ["CFBundleIdentifier": bundleID],
      format: .xml,
      options: 0
    )
    try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
    FileManager.default.createFile(atPath: helpers.appendingPathComponent("snapzy").path, contents: Data())
    return app
  }

  func testEnclosingAppBundle() {
    XCTAssertEqual(
      AppLocator
        .enclosingAppBundle(forExecutableAt: URL(fileURLWithPath: "/Applications/Snapzy.app/Contents/Helpers/snapzy"))?
        .path,
      "/Applications/Snapzy.app",
      "must not depend on whether Snapzy is installed on the test machine"
    )
    XCTAssertNil(AppLocator.enclosingAppBundle(forExecutableAt: URL(fileURLWithPath: "/usr/local/bin/snapzy")))
    XCTAssertNil(AppLocator
      .enclosingAppBundle(forExecutableAt: URL(fileURLWithPath: "/Applications/Snapzy.app/Contents/MacOS/Snapzy")))
  }

  func testLocate_followsSymlinkToEnclosingApp() throws {
    let app = try makeApp("Snapzy.app", bundleID: "com.trongduong.snapzy.debug")
    let link = directory.appendingPathComponent("snapzy")
    try FileManager.default.createSymbolicLink(
      at: link,
      withDestinationURL: app.appendingPathComponent("Contents/Helpers/snapzy")
    )

    let location = try AppLocator.locate(environment: [:], executableURL: link) { _ in
      XCTFail("lookup should not run")
      return nil
    }

    XCTAssertEqual(location.bundleID, "com.trongduong.snapzy.debug")
    XCTAssertEqual(location.appURL.resolvingSymlinksInPath(), app.resolvingSymlinksInPath())
  }

  func testLocate_enclosingAppWinsOverEnvironment() throws {
    let enclosing = try makeApp("Enclosing.app", bundleID: "com.example.enclosing")
    let override = try makeApp("Override.app", bundleID: "com.example.override")

    let location = try AppLocator.locate(
      environment: [AppLocator.appPathEnvironmentKey: override.path],
      executableURL: enclosing.appendingPathComponent("Contents/Helpers/snapzy")
    ) { _ in nil }

    XCTAssertEqual(location.bundleID, "com.example.enclosing")
  }

  func testLocate_environmentOverrideOutsideAnApp() throws {
    let override = try makeApp("Override.app", bundleID: "com.example.override")

    let location = try AppLocator.locate(
      environment: [AppLocator.appPathEnvironmentKey: override.path],
      executableURL: URL(fileURLWithPath: "/tmp/.build/debug/snapzy-dev")
    ) { _ in
      XCTFail("lookup should not run")
      return nil
    }

    XCTAssertEqual(location.bundleID, "com.example.override")
  }

  func testLocate_fallsBackToInstalledApp() throws {
    let installed = try makeApp("Snapzy.app", bundleID: AppLocator.releaseBundleID)

    let location = try AppLocator.locate(
      environment: [:],
      executableURL: URL(fileURLWithPath: "/tmp/.build/debug/snapzy-dev")
    ) { bundleID in
      XCTAssertEqual(bundleID, AppLocator.releaseBundleID)
      return installed
    }

    XCTAssertEqual(location, AppLocation(appURL: installed, bundleID: AppLocator.releaseBundleID))
  }

  func testLocate_reportsMissingApp() {
    XCTAssertThrowsError(
      try AppLocator.locate(environment: [:], executableURL: URL(fileURLWithPath: "/tmp/snapzy-dev")) { _ in nil }
    ) { error in
      XCTAssertEqual((error as? CLIError)?.code, .appUnavailable)
    }
  }
}

final class AppLauncherTests: XCTestCase {
  private let location = AppLocation(
    appURL: URL(fileURLWithPath: "/Applications/Snapzy.app"),
    bundleID: "com.trongduong.snapzy"
  )

  private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _launches: [URL] = []
    private var _sleeps = 0

    var launches: [URL] {
      lock.withLock { _launches }
    }

    var sleeps: Int {
      lock.withLock { _sleeps }
    }

    func recordLaunch(_ url: URL) {
      lock.withLock { _launches.append(url) }
    }

    func recordSleep() {
      lock.withLock { _sleeps += 1 }
    }
  }

  private func launcher(
    running: Bool,
    allowsLaunch: Bool = true,
    launchTimeout: TimeInterval = 1,
    recorder: Recorder
  ) -> AppLauncher {
    AppLauncher(
      allowsLaunch: allowsLaunch,
      launchTimeout: launchTimeout,
      environment: AppLauncher.Environment(
        isAppRunning: { _ in running },
        launchApp: { recorder.recordLaunch($0) },
        sleep: { _ in recorder.recordSleep() }
      )
    )
  }

  /// Fails with `error` for the first `failures` attempts, then succeeds.
  private func attempts(failing failures: Int, with error: SocketConnectionError = .socketMissing) -> () throws -> Int {
    var count = 0
    return {
      count += 1
      if count <= failures { throw error }
      return count
    }
  }

  func testConnectsWithoutLaunchingWhenListening() async throws {
    let recorder = Recorder()

    let attempt = try await launcher(running: false, recorder: recorder).connect(
      to: location,
      attempt: attempts(failing: 0)
    )

    XCTAssertEqual(attempt, 1)
    XCTAssertTrue(recorder.launches.isEmpty)
  }

  func testLaunchesOnceThenPolls() async throws {
    let recorder = Recorder()

    let attempt = try await launcher(running: false, recorder: recorder)
      .connect(to: location, attempt: attempts(failing: 3, with: .connectionRefused))

    XCTAssertEqual(attempt, 4)
    XCTAssertEqual(recorder.launches, [location.appURL])
    XCTAssertEqual(recorder.sleeps, 3)
  }

  func testLaunchTimeout() async {
    let recorder = Recorder()

    do {
      _ = try await launcher(running: false, launchTimeout: 0.5, recorder: recorder)
        .connect(to: location, attempt: attempts(failing: .max))
      XCTFail("expected launch timeout")
    } catch {
      XCTAssertEqual((error as? CLIError)?.code, .launchTimeout)
      XCTAssertEqual(recorder.sleeps, 5)
    }
  }

  func testNoLaunchFailsFast() async {
    let recorder = Recorder()

    do {
      _ = try await launcher(running: false, allowsLaunch: false, recorder: recorder)
        .connect(to: location, attempt: attempts(failing: .max))
      XCTFail("expected app unavailable")
    } catch {
      XCTAssertEqual((error as? CLIError)?.code, .appUnavailable)
      XCTAssertTrue(recorder.launches.isEmpty)
      XCTAssertEqual(recorder.sleeps, 0)
    }
  }

  func testRunningAppWithoutSocketIsReportedAsDisabled() async {
    let recorder = Recorder()

    do {
      _ = try await launcher(running: true, recorder: recorder).connect(to: location, attempt: attempts(failing: .max))
      XCTFail("expected disabled")
    } catch {
      XCTAssertEqual((error as? CLIError)?.code, .disabled)
      XCTAssertTrue(recorder.launches.isEmpty)
    }
  }

  func testRunningAppThatComesUpDuringGracePeriodConnects() async throws {
    let recorder = Recorder()

    let attempt = try await launcher(running: true, recorder: recorder).connect(
      to: location,
      attempt: attempts(failing: 2)
    )

    XCTAssertEqual(attempt, 3)
    XCTAssertTrue(recorder.launches.isEmpty)
  }

  func testOtherSocketErrorsAreNotRetried() async {
    let recorder = Recorder()

    do {
      _ = try await launcher(running: false, recorder: recorder)
        .connect(to: location, attempt: attempts(failing: 1, with: .system(operation: "connect", errno: EACCES)))
      XCTFail("expected app unavailable")
    } catch {
      XCTAssertEqual((error as? CLIError)?.code, .appUnavailable)
      XCTAssertTrue(recorder.launches.isEmpty)
    }
  }
}
