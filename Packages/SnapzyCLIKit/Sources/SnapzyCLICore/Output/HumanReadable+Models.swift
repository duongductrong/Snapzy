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

extension CLIMeasureResult: HumanReadable {
  /// One line per measurement: `span @120,80  240 × 32 pt  (480 × 64 px)`.
  public var humanDescription: String {
    guard !measurements.isEmpty else { return "No measurements." }
    return measurements.map { measurement in
      let label = switch measurement {
      case .span(let at, _, _, _):
        "span @\(at)"
      case .box(let input, _, let points, _):
        "box \(input) → \(points.rect)"
      }
      return "\(label)  \(Self.size(measurement.points)) pt  (\(Self.size(measurement.pixels)) px)"
    }.joined(separator: "\n")
  }

  /// `240 × 32`, or the one measured axis.
  static func size(_ extent: CLIMeasureExtent) -> String {
    [extent.width, extent.height].compactMap { $0.map(CLIMeasureNumber.text) }.joined(separator: " × ")
  }
}

extension CLIRecordingInfo: HumanReadable {
  /// `snapzy-cli-20261123-101500-a1b2c3  recording  00:12  0,0,1512,982  display 1`.
  public var humanDescription: String {
    var line = "\(id)  \(state.rawValue)  \(Self.clock(elapsedSeconds))  \(rect)"
    if let window {
      line += "  \(window.app.name)\(window.title.map { $0.isEmpty ? "" : " — \($0)" } ?? "")"
    } else if let displayID {
      line += "  display \(displayID)"
    }
    if let output {
      line += "  → \(output.path)"
    }
    return line
  }

  static func clock(_ seconds: Int) -> String {
    String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }
}

extension CLIRecordingStatus: HumanReadable {
  public var humanDescription: String {
    if let recording {
      return recording.humanDescription
    }
    return interactiveRecordingActive
      ? "No snapzy recording. Snapzy is recording from its own toolbar."
      : "No snapzy recording."
  }
}

extension CLIRecordingResult: HumanReadable {
  public var humanDescription: String {
    let size = ByteCountFormatter.string(fromByteCount: Int64(file.bytes), countStyle: .file)
    return "\(file.path)  \(file.width)x\(file.height)  \(RecordingDuration.text(file.durationSeconds))  \(size)"
  }
}

extension CLIAutomationList: HumanReadable {
  /// `3F2A…  Cloud Share  area → copyImage, uploadAndCopyLink`, flagged when it cannot run.
  public var humanDescription: String {
    guard !automations.isEmpty else { return "No automations." }
    return automations.map { automation in
      var line = "\(automation.id)  \(automation.name)  \(automation.source)"
      if !automation.steps.isEmpty {
        line += " → \(automation.steps.joined(separator: ", "))"
      }
      if !automation.enabled {
        line += "  disabled"
      }
      if !automation.external {
        line += "  not allowed from the command line"
      }
      return line
    }.joined(separator: "\n")
  }
}

extension CLIAutomationRunResult: HumanReadable {
  /// `Link copied: https://…` (or Snapzy's summary), then one file path per line.
  public var humanDescription: String {
    guard state == .finished else { return "Cancelled." }
    let summary = message.isEmpty ? (isError ? "Failed" : "Done") : message
    var lines = [link.map { "\(summary): \($0)" } ?? summary]
    if let text, !text.isEmpty { lines.append(text) }
    lines += files
    return lines.joined(separator: "\n")
  }
}
