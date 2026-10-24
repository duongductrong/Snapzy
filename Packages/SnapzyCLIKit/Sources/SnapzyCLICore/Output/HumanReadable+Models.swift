//
//  HumanReadable+Models.swift
//  SnapzyCLICore
//
//  Terminal formatting for wire models. Agents read JSON; these strings are
//  for people and are not a stable contract.
//

import Foundation
import SnapzyCLIProtocol

extension CLIStatus: HumanReadable {
  public var humanDescription: String {
    [
      "Snapzy \(appVersion)",
      "Command line access: \(cliEnabled ? "enabled" : "disabled")",
      "Onboarding: \(onboardingCompleted ? "completed" : "not completed")",
      "Screen Recording: \(screenRecordingPermission.rawValue)",
      "This app: \(authorization.rawValue)",
    ].joined(separator: "\n")
  }
}

extension CLIDisplayList: HumanReadable {
  public var humanDescription: String {
    guard !displays.isEmpty else { return "No displays." }
    return displays.map { display in
      var line = "\(display.id)  \(display.name)  \(display.frame)  @\(Self.scaleLabel(display.scale))x"
      if display.isMain {
        line += "  main"
      }
      return line
    }.joined(separator: "\n")
  }

  static func scaleLabel(_ scale: Double) -> String {
    scale.rounded() == scale ? String(Int(scale)) : String(format: "%.2f", scale)
  }
}

extension CLIWindowList: HumanReadable {
  public var humanDescription: String {
    guard !windows.isEmpty else { return "No windows." }
    return windows.map { window in
      let title = window.title.map { $0.isEmpty ? "" : " — \($0)" } ?? ""
      var line = "\(window.id)  \(window.app.name)\(title)  \(window.frame)"
      if !window.isOnScreen {
        line += "  off-screen"
      }
      if window.isActive {
        line += "  active"
      }
      return line
    }.joined(separator: "\n")
  }
}

extension CLIAppList: HumanReadable {
  public var humanDescription: String {
    guard !apps.isEmpty else { return "No apps with windows." }
    return apps.map { app in
      let bundle = app.bundleID.map { " (\($0))" } ?? ""
      let windows = app.windowCount == 1 ? "1 window" : "\(app.windowCount) windows"
      return "\(app.name)\(bundle)  pid \(app.pid)  \(windows)\(app.isActive ? "  active" : "")"
    }.joined(separator: "\n")
  }
}

extension CLICaptureResult: HumanReadable {
  public var humanDescription: String {
    files.map { file in
      let size = ByteCountFormatter.string(fromByteCount: Int64(file.bytes), countStyle: .file)
      return "\(file.path)  \(file.width)x\(file.height) @\(CLIDisplayList.scaleLabel(file.scale))x  \(size)"
    }.joined(separator: "\n")
  }
}
