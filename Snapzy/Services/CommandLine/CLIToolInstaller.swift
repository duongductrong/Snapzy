//
//  CLIToolInstaller.swift
//  Snapzy
//
//  Links the embedded `snapzy` tool (Contents/Helpers/snapzy) onto PATH at
//  /usr/local/bin/snapzy, asking for an administrator password only when
//  that directory is not writable. Only ever creates or removes a symlink,
//  and never replaces a file or another tool's link.
//

import Foundation

enum CLIToolInstaller {
  enum State: Equatable {
    case notInstalled
    /// The link points at this app's helper.
    case installed
    /// A symlink points somewhere else: another Snapzy copy, a missing app, or another tool.
    case pointsElsewhere(String)
    /// A regular file or directory occupies the link path.
    case blockedByFile
  }

  enum InstallError: LocalizedError, Equatable {
    case helperMissing
    case temporaryLocation
    case blockedByFile
    case occupiedByOtherTool(String)
    case cancelled
    case failed(String)

    var errorDescription: String? {
      switch self {
      case .helperMissing:
        "This copy of Snapzy does not include the snapzy command line tool."
      case .temporaryLocation:
        "Move Snapzy to the Applications folder first; it is running from a temporary location."
      case .blockedByFile:
        "\(CLIToolInstaller.linkPath) already exists and is not a symlink. Remove it, then try again."
      case .occupiedByOtherTool(let destination):
        "\(CLIToolInstaller.linkPath) already links to \(destination). Remove that link, then try again."
      case .cancelled:
        "Installation was cancelled."
      case .failed(let message):
        message
      }
    }
  }

  static let linkPath = "/usr/local/bin/snapzy"

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

  /// A link that may be replaced: it is dangling or points at a Snapzy helper.
  nonisolated static func isReplaceable(_ destination: String) -> Bool {
    let isSnapzyHelper = destination.range(
      of: #"/Snapzy[^/]*\.app/Contents/Helpers/snapzy$"#,
      options: .regularExpression
    ) != nil
    return isSnapzyHelper || !FileManager.default.fileExists(atPath: destination)
  }

  /// Linking a helper inside a DMG or an AppTranslocation copy breaks after
  /// eject or reboot.
  nonisolated static func isTemporaryLocation(_ appBundleURL: URL) -> Bool {
    let path = appBundleURL.path
    return path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
  }

  static func currentState() -> State {
    state(helperPath: helperURL().path)
  }

  static func install() async throws {
    let helper = helperURL().path
    guard !isTemporaryLocation(Bundle.main.bundleURL) else { throw InstallError.temporaryLocation }
    guard FileManager.default.isExecutableFile(atPath: helper) else { throw InstallError.helperMissing }
    switch state(helperPath: helper) {
    case .installed:
      return
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
