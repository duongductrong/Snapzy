//
//  AutomationExternalSection.swift
//  Snapzy
//
//  Editor section "Run from other apps": the per-automation opt-in for the URL
//  scheme, command line and Shortcuts, plus ready-to-copy invocations.
//

import AppKit
import SwiftUI

struct AutomationExternalSection: View {
  @Binding var automation: Automation
  let isURLSchemeEnabled: Bool

  var body: some View {
    Section {
      Toggle(isOn: $automation.externalInvocation) {
        VStack(alignment: .leading, spacing: 2) {
          Text(L10n.Automations.externalToggle)
          Text(L10n.Automations.externalDescription)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      if automation.externalInvocation {
        if automation.runsWithoutInput {
          copyableRow(L10n.Automations.externalURLLabel, value: AutomationDisplay.runURL(for: automation))
        }
        copyableRow(L10n.Automations.externalCLILabel, value: AutomationDisplay.cliCommand(for: automation))

        // Second opt-in: a link or a shortcut must not run a script unless asked for.
        if automation.containsCodeSteps {
          Toggle(isOn: $automation.allowExternalCode) {
            VStack(alignment: .leading, spacing: 2) {
              Text(L10n.Automations.externalCodeToggle)
              Text(L10n.Automations.externalCodeDescription)
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }

        if !isURLSchemeEnabled, automation.runsWithoutInput {
          HStack(spacing: 6) {
            Label(L10n.Automations.externalURLSchemeOff, systemImage: "exclamationmark.triangle.fill")
              .font(.caption)
              .foregroundStyle(.orange)
            Button(L10n.Automations.openAdvancedSettings) {
              PreferencesNavigationState.shared.select(.advanced)
            }
            .buttonStyle(.link)
            .font(.caption)
          }
        }
      }
    } header: {
      Text(L10n.Automations.externalLabel)
    }
  }

  private func copyableRow(_ label: String, value: String) -> some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(label)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(value)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
          .lineLimit(2)
          .truncationMode(.middle)
      }
      Spacer(minLength: 0)
      Button {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
      } label: {
        Image(systemName: "doc.on.doc")
      }
      .buttonStyle(.borderless)
      .help(L10n.Automations.copyToClipboard)
      .accessibilityLabel(L10n.Automations.copyToClipboard)
    }
  }
}
