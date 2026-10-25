//
//  DoctorCommand.swift
//  SnapzyCLICore
//
//  Explains why `snapzy` can or cannot capture: which app it talks to,
//  whether it is on PATH, whether Snapzy is reachable, and the app's status.
//  Never launches Snapzy — a stopped app is reported, not fixed.
//

import ArgumentParser
import Foundation
import SnapzyCLIClient
import SnapzyCLIProtocol

struct DoctorCheck: Codable, Equatable {
  let name: String
  let ok: Bool
  let detail: String
  let hint: String?
  /// Set when this failure should decide the exit code; advisory checks
  /// (like PATH) can fail without failing `doctor`.
  let failureCode: CLIErrorCode?

  static func pass(_ name: String, _ detail: String) -> DoctorCheck {
    DoctorCheck(name: name, ok: true, detail: detail, hint: nil, failureCode: nil)
  }

  static func fail(_ name: String, _ detail: String, hint: String?, code: CLIErrorCode?) -> DoctorCheck {
    DoctorCheck(name: name, ok: false, detail: detail, hint: hint, failureCode: code)
  }
}

struct DoctorReport: Codable, Equatable, HumanReadable {
  let checks: [DoctorCheck]

  /// The first failure that carries a code, or nil when everything required passed.
  var failureCode: CLIErrorCode? {
    checks.first { !$0.ok && $0.failureCode != nil }?.failureCode
  }

  var humanDescription: String {
    checks.map { check in
      var line = "\(check.ok ? "✓" : "✗") \(check.name): \(check.detail)"
      if let hint = check.hint {
        line += "\n    hint: \(hint)"
      }
      return line
    }.joined(separator: "\n")
  }
}

struct DoctorCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "doctor",
    abstract: "Check that snapzy can reach Snapzy and capture."
  )

  @OptionGroup var global: GlobalOptions

  func run() async throws {
    var checks: [DoctorCheck] = []
    let executable = Bundle.main.executableURL?.resolvingSymlinksInPath()
    checks.append(.pass("cli", "\(CLIVersion.current) at \(executable?.path ?? "unknown")"))
    checks.append(Doctor.pathCheck(
      path: ProcessInfo.processInfo.environment["PATH"] ?? "",
      executable: executable,
      commandName: Doctor.commandName(for: executable),
      caskInstalled: Doctor.isCaskInstall(executable: executable)
    ))

    let location: AppLocation
    do {
      location = try AppLocator.locate()
      checks.append(.pass("app", "\(location.appURL.path) (\(location.bundleID))"))
    } catch let error as CLIError {
      checks.append(.fail("app", error.message, hint: error.hint, code: error.code))
      return try finish(checks)
    }

    // Never launch from doctor; say what could not be checked instead of
    // reporting success for a server that may not accept requests.
    let socketPath = SocketLocation.path(forAppBundleID: location.bundleID)
    guard AppLauncher.Environment.live.isAppRunning(location.bundleID) else {
      checks.append(.fail(
        "connection",
        "Snapzy is not running, so command line access, onboarding and permissions were not checked "
          + "(socket: \(socketPath))",
        hint: "Open Snapzy, then run `snapzy doctor` again",
        code: nil
      ))
      return try finish(checks)
    }

    var options = global.sessionOptions
    options.allowsLaunch = false
    let client: CLIClient
    do {
      client = try await CLISession.open(options)
    } catch let error as CLIError {
      checks.append(.fail("connection", error.message, hint: error.hint, code: error.code))
      return try finish(checks)
    }
    defer { client.close() }
    checks.append(.pass(
      "connection",
      "Snapzy \(client.hello.appVersion) on \(socketPath)"
    ))

    do {
      checks += try Doctor.statusChecks(client.call(.systemStatus, as: CLIStatus.self))
    } catch let error as CLIError {
      checks.append(.fail("status", error.message, hint: error.hint, code: error.code))
    }
    try finish(checks)
  }

  private func finish(_ checks: [DoctorCheck]) throws {
    let report = DoctorReport(checks: checks)
    try StandardStreams.write(global.renderer.render(report))
    if let code = report.failureCode {
      throw ExitCode(code.exitCode)
    }
  }
}

/// Pure pieces of `doctor`, kept separate for tests.
enum Doctor {
  /// `snapzy-debug` for the helper inside a Debug build, else `snapzy`.
  static func commandName(for executable: URL?) -> String {
    let bundleID = executable
      .flatMap(AppLocator.enclosingAppBundle(forExecutableAt:))
      .flatMap(AppLocator.bundleIdentifier(ofAppAt:))
    return CommandName.forAppBundleID(bundleID)
  }

  /// Links this exact binary, so the hint is right for Debug builds and
  /// apps outside /Applications too.
  static func installHint(for executable: URL?, commandName: String = CommandName.release) -> String {
    let helper = executable?.path ?? "/Applications/Snapzy.app/Contents/Helpers/snapzy"
    let quoted = "'" + helper.replacingOccurrences(of: "'", with: "'\\''") + "'"
    return "sudo mkdir -p /usr/local/bin && sudo ln -sfn \(quoted) /usr/local/bin/\(commandName)"
  }

  static let homebrewHint = "Snapzy came from Homebrew, which links snapzy: run `brew reinstall --cask snapzy`"
  static let homebrewCaskroomPaths = ["/opt/homebrew/Caskroom/snapzy", "/usr/local/Caskroom/snapzy"]

  /// Whether this binary is inside the cask's `Snapzy.app` (not a Debug or
  /// renamed copy), so Homebrew should link it rather than `ln -s` by hand.
  static func isCaskInstall(
    executable: URL?,
    caskroomPaths: [String] = homebrewCaskroomPaths,
    fileManager: FileManager = .default
  ) -> Bool {
    guard let executable, executable.path.hasSuffix("/Snapzy.app/Contents/Helpers/snapzy") else { return false }
    return caskroomPaths.contains { fileManager.fileExists(atPath: $0) }
  }

  /// Whether `commandName` on PATH is this binary. Advisory: agents can always use the full path.
  static func pathCheck(
    path: String,
    executable: URL?,
    commandName: String = CommandName.release,
    caskInstalled: Bool = false,
    fileManager: FileManager = .default
  ) -> DoctorCheck {
    let found = path.split(separator: ":").lazy
      .map { URL(fileURLWithPath: String($0)).appendingPathComponent(commandName) }
      .first { candidate in
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory)
          && !isDirectory.boolValue
          && fileManager.isExecutableFile(atPath: candidate.path)
      }

    guard let found else {
      let hint = caskInstalled ? homebrewHint : installHint(for: executable, commandName: commandName)
      return .fail("path", "\(commandName) is not on PATH", hint: hint, code: nil)
    }
    let resolved = found.resolvingSymlinksInPath()
    guard let executable, resolved.path != executable.path else {
      return .pass("path", "\(found.path) → \(resolved.path)")
    }
    return .fail(
      "path",
      "\(found.path) runs \(resolved.path), not this \(commandName)",
      hint: "Point the link at the Snapzy.app you use: \(installHint(for: executable, commandName: commandName))",
      code: nil
    )
  }

  static func statusChecks(_ status: CLIStatus) -> [DoctorCheck] {
    var checks: [DoctorCheck] = []

    checks.append(status.cliEnabled
      ? .pass("command line access", "enabled")
      : .fail(
        "command line access",
        "disabled",
        hint: "Enable Settings → Command Line → Command line access",
        code: .disabled
      ))

    checks.append(status.onboardingCompleted
      ? .pass("onboarding", "completed")
      : .fail("onboarding", "not completed", hint: "Open Snapzy and finish setup", code: .onboardingIncomplete))

    switch status.screenRecordingPermission {
    case .granted:
      checks.append(.pass("screen recording", "granted"))
    case .denied:
      checks.append(.fail(
        "screen recording",
        "not granted",
        hint: "System Settings → Privacy & Security → Screen & System Audio Recording → enable Snapzy",
        code: .permissionDenied
      ))
    case .unavailable:
      checks.append(.fail(
        "screen recording",
        "granted but not usable yet",
        hint: "Relaunch Snapzy. If that does not help, remove Snapzy from System Settings → Privacy & Security → "
          + "Screen & System Audio Recording and add it again",
        code: .permissionDenied
      ))
    }

    switch status.authorization {
    case .allowed:
      checks.append(.pass("authorization", "this app is allowed"))
    case .undetermined:
      checks.append(.pass("authorization", "not asked yet; Snapzy asks on the first capture"))
    case .denied:
      checks.append(.fail(
        "authorization",
        "this app was denied",
        hint: "Remove it from Settings → Command Line → Allowed apps, then retry",
        code: .notAuthorized
      ))
    }
    return checks
  }
}
