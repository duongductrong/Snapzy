//
//  CLIAuthorizationPromptController.swift
//  Snapzy
//
//  Asks the user whether an app may capture the screen through the `snapzy`
//  command. No button answers Return (the alert takes focus while the user
//  may be typing); Escape means Don't Allow. An unanswered prompt times out
//  before the CLI's default 30 s request timeout, so the CLI sees the reason.
//

import AppKit
import UniformTypeIdentifiers

@MainActor
final class CLIAuthorizationPromptController: CLIAuthorizationPrompting {
  static let timeout: TimeInterval = 25

  func ask(_ caller: CLICallerIdentity, command: String) -> CLIAuthorizationPromptResult {
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = L10n.CommandLine.promptTitle(caller.displayName)
    var message = L10n.CommandLine.promptMessage(command: command)
    if caller.isVerified {
      alert.icon = NSWorkspace.shared.icon(forFile: caller.path)
    } else {
      // An unsigned bundle can copy any app's name and icon; show where it really is.
      message += "\n\n" + L10n.CommandLine.promptUnverified(path: caller.path)
      alert.icon = NSWorkspace.shared.icon(for: .applicationBundle)
    }
    alert.informativeText = message

    alert.addButton(withTitle: L10n.CommandLine.promptDontAllow)
    alert.addButton(withTitle: L10n.CommandLine.promptAllowOnce)
    alert.addButton(withTitle: L10n.CommandLine.promptAlwaysAllow)
    alert.buttons[0].keyEquivalent = "\u{1b}"

    // Abort only this alert: another modal (an error alert in Settings) may
    // sit on top of it, and abortModal() ends whichever modal is frontmost.
    let deadline = Date().addingTimeInterval(Self.timeout)
    let alertWindow = alert.window
    let timer = Timer(timeInterval: 1, repeats: true) { _ in
      MainActor.assumeIsolated {
        if Date() >= deadline, NSApp.modalWindow === alertWindow {
          NSApp.abortModal()
        }
      }
    }
    RunLoop.main.add(timer, forMode: .modalPanel)
    defer { timer.invalidate() }

    DiagnosticLogger.shared.log(
      .info,
      .cli,
      "CLI authorization prompt shown",
      context: ["caller": caller.displayName, "verified": caller.isVerified ? "true" : "false"]
    )
    switch alert.runModal() {
    case .alertSecondButtonReturn: return .allowOnce
    case .alertThirdButtonReturn: return .alwaysAllow
    case .abort: return .timedOut
    default: return .deny
    }
  }
}
