//
//  AutomationDisplay.swift
//  Snapzy
//
//  Localized labels for automation model values. Storage keeps raw ids.
//

import Foundation

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
    let mode = captureSpec?.mode.displayName ?? L10n.Automations.unsupported
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
