//
//  CLIToolInstaller.swift
//  Snapzy
//
//  Links the embedded `snapzy` tool (Contents/Helpers/snapzy) onto PATH at
//  /usr/local/bin/snapzy (/usr/local/bin/snapzy-debug for Debug builds),
//  asking for an administrator password only when that directory is not
//  writable. Only ever creates or removes a symlink, and never replaces a
//  file, another tool's link, or a Debug link with a release one. A Homebrew
//  cask install leaves the link to Homebrew, so `brew reinstall` never meets a
//  link it did not make.
//

import Foundation
import SnapzyCLIProtocol

enum CLIToolInstaller {
  enum State: Equatable {
    case notInstalled
    /// The link points at this app's helper.
    case installed
    /// A symlink points somewhere else: another Snapzy copy, a missing app, or another tool.
    case pointsElsewhere(String)
    /// A regular file or directory occupies the link path.
    case blockedByFile
    /// The Homebrew cask's `binary` link (at the associated path) points at this helper.
    case managedByHomebrew(String)
    /// Installed by the Homebrew cask, which has not linked the helper yet
    /// (the cask predates the tool and Snapzy was updated in-app).
    case homebrewLinkMissing
  }

  enum InstallError: LocalizedError, Equatable {
    case helperMissing
    case temporaryLocation
    case blockedByFile
    case occupiedByOtherTool(String)
    case homebrewLinkMissing
    case cancelled
    case failed(String)

    var errorDescription: String? {
      switch self {
      case .helperMissing:
        L10n.CommandLine.errorHelperMissing
      case .temporaryLocation:
        L10n.CommandLine.errorTemporaryLocation
      case .blockedByFile:
        L10n.CommandLine.errorBlocked(CLIToolInstaller.linkPath)
      case .occupiedByOtherTool(let destination):
        L10n.CommandLine.errorOccupied(path: CLIToolInstaller.linkPath, destination: destination)
      case .homebrewLinkMissing:
        L10n.CommandLine.errorHomebrewLinkMissing(CLIToolInstaller.homebrewUpgradeCommand)
      case .cancelled:
        L10n.CommandLine.errorCancelled
      case .failed(let message):
        message
      }
    }
  }

  /// Debug builds (`com.trongduong.snapzy.debug`) link `snapzy-debug`, so a
  /// development copy and the installed app can both stay on PATH.
  static let isDebugBuild = CommandName.isDebugBundleID(Bundle.main.bundleIdentifier)
  static let linkPath = "/usr/local/bin/" + CommandName.forAppBundleID(Bundle.main.bundleIdentifier)
  static let homebrewUpgradeCommand = "brew reinstall --cask snapzy"

  static func helperURL(appBundleURL: URL = Bundle.main.bundleURL) -> URL {
    appBundleURL.appendingPathComponent("Contents/Helpers/snapzy")
  }

  nonisolated static func state(linkPath: String = linkPath, helperPath: String) -> State {
    var info = stat()
    guard lstat(linkPath, &info) == 0 else { return .notInstalled }
    guard (info.st_mode & S_IFMT) == S_IFLNK else { return .blockedByFile }

    let destination = (try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath)) ?? ""
    // Relative targets are relative to the link's directory, not the working directory.
    let linkDirectory = URL(fileURLWithPath: (linkPath as NSString).deletingLastPathComponent, isDirectory: true)
    let resolvedDestination = URL(fileURLWithPath: destination, relativeTo: linkDirectory)
      .standardizedFileURL.resolvingSymlinksInPath().path
    let resolvedHelper = URL(fileURLWithPath: helperPath).resolvingSymlinksInPath().path
    return resolvedDestination == resolvedHelper ? .installed : .pointsElsewhere(destination)
  }

  /// A link that may be replaced: it is dangling or points at a Snapzy
  /// helper this build may take over. Debug builds replace only Debug links;
  /// release builds replace any Snapzy link, which reclaims a `snapzy` link
  /// left by a Debug build from before Debug had its own name.
  nonisolated static func isReplaceable(_ destination: String, isDebugBuild: Bool = isDebugBuild) -> Bool {
    let pattern = isDebugBuild
      ? #"/Snapzy Debug[^/]*\.app/Contents/Helpers/snapzy$"#
      : #"/Snapzy[^/]*\.app/Contents/Helpers/snapzy$"#
    let isSnapzyHelper = destination.range(of: pattern, options: .regularExpression) != nil
    return isSnapzyHelper || !FileManager.default.fileExists(atPath: destination)
  }

  /// Linking a helper inside a DMG or an AppTranslocation copy breaks after
  /// eject or reboot.
  nonisolated static func isTemporaryLocation(_ appBundleURL: URL) -> Bool {
    let path = appBundleURL.path
    return path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
  }

  /// Where `brew install --cask snapzy` links the helper, and where its cask lives.
  nonisolated static let homebrewLinkPaths = ["/opt/homebrew/bin/snapzy", "/usr/local/bin/snapzy"]
  nonisolated static let homebrewCaskroomPaths = ["/opt/homebrew/Caskroom/snapzy", "/usr/local/Caskroom/snapzy"]

  /// Whether this app came from the Homebrew cask. The cask installs exactly
  /// `Snapzy.app`, so other copies (`Snapzy Debug.app`) never count.
  nonisolated static func isCaskInstalled(
    appBundleURL: URL,
    caskroomPaths: [String] = homebrewCaskroomPaths
  ) -> Bool {
    appBundleURL.lastPathComponent == "Snapzy.app"
      && caskroomPaths.contains { FileManager.default.fileExists(atPath: $0) }
  }

  nonisolated static func state(
    helperPath: String,
    caskInstalled: Bool,
    linkPath: String = linkPath,
    homebrewLinkPaths: [String] = homebrewLinkPaths
  ) -> State {
    if caskInstalled,
       let brewLink = homebrewLinkPaths.first(where: { state(linkPath: $0, helperPath: helperPath) == .installed }) {
      return .managedByHomebrew(brewLink)
    }
    let linkState = state(linkPath: linkPath, helperPath: helperPath)
    // A link made before the cask took over keeps working until the cask's
    // preflight removes it; only offer Homebrew when nothing works yet.
    if caskInstalled, linkState != .installed {
      return .homebrewLinkMissing
    }
    return linkState
  }

  static func currentState() -> State {
    state(
      helperPath: helperURL().path,
      caskInstalled: isCaskInstalled(appBundleURL: Bundle.main.bundleURL)
    )
  }

  static func install() async throws {
    let helper = helperURL().path
    guard !isTemporaryLocation(Bundle.main.bundleURL) else { throw InstallError.temporaryLocation }
    guard FileManager.default.isExecutableFile(atPath: helper) else { throw InstallError.helperMissing }
    switch currentState() {
    case .installed, .managedByHomebrew:
      return
    case .homebrewLinkMissing:
      throw InstallError.homebrewLinkMissing
    case .blockedByFile:
      throw InstallError.blockedByFile
    case .pointsElsewhere(let destination) where !isReplaceable(destination):
      throw InstallError.occupiedByOtherTool(destination)
    case .notInstalled, .pointsElsewhere:
      break
    }

    let directory = (linkPath as NSString).deletingLastPathComponent
    let command = "mkdir -p \(shellQuoted(directory)) && ln -sfn \(shellQuoted(helper)) \(shellQuoted(linkPath))"
    try await run(command, asAdministrator: !FileManager.default.isWritableFile(atPath: directory))
    DiagnosticLogger.shared.log(.info, .cli, "snapzy command linked", context: ["link": linkPath])
  }

  /// Removes the link only if it points at this app's helper.
  static func uninstall() async throws {
    guard currentState() == .installed else { return }
    let directory = (linkPath as NSString).deletingLastPathComponent
    try await run(
      "rm -f \(shellQuoted(linkPath))",
      asAdministrator: !FileManager.default.isWritableFile(atPath: directory)
    )
    DiagnosticLogger.shared.log(.info, .cli, "snapzy command unlinked", context: ["link": linkPath])
  }

  /// Single-quotes for /bin/sh, so app paths with spaces ("Snapzy Debug.app") survive.
  nonisolated static func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  /// AppleScript string literal for `do shell script`.
  nonisolated static func appleScriptQuoted(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }

  /// Runs off the main actor: the password prompt and the shell must not
  /// block or re-enter the UI.
  private static func run(_ command: String, asAdministrator: Bool) async throws {
    let arguments = asAdministrator
      ? ["/usr/bin/osascript", "-e", "do shell script \(appleScriptQuoted(command)) with administrator privileges"]
      : ["/bin/sh", "-c", command]

    let (status, errorOutput) = try await Task.detached(priority: .userInitiated) {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: arguments[0])
      process.arguments = Array(arguments.dropFirst())
      let errorPipe = Pipe()
      process.standardError = errorPipe
      process.standardOutput = FileHandle.nullDevice
      do {
        try process.run()
      } catch {
        throw InstallError.failed(error.localizedDescription)
      }
      let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      return (process.terminationStatus, String(decoding: errorData, as: UTF8.self))
    }.value

    guard status != 0 else { return }
    // osascript reports a dismissed password prompt as error -128.
    if asAdministrator, errorOutput.contains("(-128)") {
      throw InstallError.cancelled
    }
    let message = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    throw InstallError.failed(message.isEmpty ? "The command failed." : message)
  }
}
