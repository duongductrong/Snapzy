//
//  AutomationDisplay.swift
//  Snapzy
//
//  Localized labels for automation model values. Storage keeps raw ids.
//

import Foundation

enum AutomationDisplay {
  static let inputSymbol = "doc.badge.gearshape"

  /// `snapzy://automation/run?id=<uuid>` for the "Run from other apps" section.
  static func runURL(for automation: Automation) -> String {
    "snapzy://automation/run?id=\(automation.id.uuidString)"
  }

  /// `snapzy automation run "<name>"`, quoting the name for a POSIX shell.
  static func cliCommand(for automation: Automation) -> String {
    let name = automation.displayName.replacingOccurrences(of: "'", with: "'\\''")
    return "snapzy automation run '\(name)'"
  }
}

extension AutomationCaptureMode {
  var displayName: String {
    switch self {
    case .area: L10n.Automations.modeArea
    case .fullscreen: L10n.Automations.modeFullscreen
    case .activeWindow: L10n.Automations.modeActiveWindow
    case .applicationWindow: L10n.Automations.modeApplicationWindow
    }
  }

  var symbol: String {
    switch self {
    case .area: "rectangle.dashed"
    case .fullscreen: "display"
    case .activeWindow: "macwindow"
    case .applicationWindow: "macwindow.on.rectangle"
    }
  }
}

extension AutomationStepKind {
  var displayName: String {
    switch self {
    case .copyImage: L10n.Automations.stepCopyImage
    case .uploadAndCopyLink: L10n.Automations.stepUploadCopyLink
    case .showQuickAccess: L10n.Automations.stepShowQuickAccess
    case .openAnnotate: L10n.Automations.stepOpenAnnotate
    case .notify: L10n.Automations.stepNotify
    }
  }

  var symbol: String {
    switch self {
    case .copyImage: "doc.on.clipboard"
    case .uploadAndCopyLink: "icloud.and.arrow.up"
    case .showQuickAccess: "square.stack.3d.up"
    case .openAnnotate: "pencil.and.scribble"
    case .notify: "bell"
    }
  }
}

extension AutomationLinkFormat {
  var displayName: String {
    switch self {
    case .url: L10n.Automations.linkFormatURL
    case .markdown: L10n.Automations.linkFormatMarkdown
    }
  }
}

extension Automation {
  /// One line for the settings list, e.g. "Area · Copy image, Upload and copy link".
  var summary: String {
    let mode: String = switch source {
    case .capture(let spec): spec.mode.displayName
    case .input: L10n.Automations.sourceInputShort
    case .unsupported: L10n.Automations.unsupported
    }
    let steps = activeActions.map { action -> String in
      if case .uploadAndCopyLink(let format) = action, format == .markdown {
        return "\(action.kind.displayName) (\(format.displayName))"
      }
      return action.kind.displayName
    }
    let stepsText = steps.isEmpty ? L10n.Automations.noSteps : steps.joined(separator: ", ")
    return "\(mode) · \(stepsText)"
  }

  var needsCloud: Bool {
    contains(.uploadAndCopyLink)
  }
}

extension AutomationLaunchRejection {
  /// Shown to the person who started the run (toast, Shortcuts error). Never
  /// lists other automations' names, so a URL caller can't probe for them.
  var localizedMessage: String {
    switch self {
    case .notFound: L10n.Automations.rejectionNotFound
    case .ambiguousName: L10n.Automations.rejectionAmbiguous
    case .disabled: L10n.Automations.rejectionDisabled
    case .externalNotAllowed: L10n.Automations.rejectionExternalNotAllowed
    case .urlSchemeDisabled: L10n.Automations.rejectionURLSchemeDisabled
    case .unsupportedSource: L10n.Automations.rejectionUnsupportedSource
    case .needsFile: L10n.Automations.rejectionNeedsFile
    case .unsupportedFile(let name): L10n.Automations.rejectionUnsupportedFile(name)
    case .noStepAcceptsFile: L10n.Automations.rejectionNoStepAcceptsFile
    case .fileMissing(let name): L10n.Automations.rejectionFileMissing(name)
    case .permissionRequired: L10n.Automations.rejectionPermissionRequired
    case .captureInProgress: L10n.Automations.rejectionCaptureInProgress
    }
  }
}
