//
//  AgentRemoteConsent.swift
//  Snapzy
//
//  The one-time "send this off the Mac?" question for off-device providers. The
//  user agrees once per destination and surface: a surface that sends different
//  data (video frames and transcript rather than a screenshot) passes a `scope`,
//  so agreeing for Annotate does not cover it.
//

import AppKit
import Foundation

@MainActor
struct AgentRemoteConsent {
  let defaults: UserDefaults
  /// Appended to the destination id (`#video`). `nil` = the id as is (Annotate).
  var scope: String? = nil

  func key(for destination: AgentRemoteDestination) -> String {
    scope.map { "\(destination.id)#\($0)" } ?? destination.id
  }

  func has(_ destination: AgentRemoteDestination) -> Bool {
    defaults.stringArray(forKey: PreferencesKeys.annotateAgentConsentedProviders)?.contains(key(for: destination)) ?? false
  }

  func record(_ destination: AgentRemoteDestination) {
    var ids = defaults.stringArray(forKey: PreferencesKeys.annotateAgentConsentedProviders) ?? []
    let key = key(for: destination)
    guard !ids.contains(key) else { return }
    ids.append(key)
    defaults.set(ids, forKey: PreferencesKeys.annotateAgentConsentedProviders)
  }

  /// Sheet on the key window (app-modal when there is none). `true` = send.
  /// The words are the caller's: what leaves the Mac differs per surface.
  static func ask(
    _ destination: AgentRemoteDestination,
    title: String,
    endpointMessage: String,
    cliMessage: String
  ) async -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = title
    // Agent CLIs also run with the user's own MCP servers and hooks: say so up front.
    switch destination.kind {
    case .agentCLI:
      alert.informativeText = cliMessage
    case .endpoint:
      alert.informativeText = endpointMessage
    }
    alert.addButton(withTitle: L10n.AnnotateAI.consentSend)
    alert.addButton(withTitle: L10n.Common.cancel)
    guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
      return alert.runModal() == .alertFirstButtonReturn
    }
    return await withCheckedContinuation { continuation in
      alert.beginSheetModal(for: window) { response in
        continuation.resume(returning: response == .alertFirstButtonReturn)
      }
    }
  }
}
