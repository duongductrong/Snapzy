//
//  PreferencesLanguageSettingRow.swift
//  Snapzy
//
//  App language picker for Settings > General.
//

import AppKit
import SwiftUI

struct PreferencesLanguageSettingRow: View {
  @ObservedObject private var languageManager = AppLanguageManager.shared
  @State private var isRelaunching = false
  @State private var pendingLanguageIdentifier: String?
  @State private var showRelaunchConfirmation = false

  var body: some View {
    SettingRow(
      icon: "globe",
      title: L10n.PreferencesGeneral.languageTitle,
      description: languageManager.requiresRelaunch
        ? L10n.PreferencesGeneral.languageRestartHint
        : L10n.PreferencesGeneral.languageDescription
    ) {
      Picker("", selection: languageSelection) {
        Text(L10n.PreferencesGeneral.languageSystem).tag("")

        ForEach(languageManager.availableOptions) { option in
          Text(verbatim: option.displayName)
            .tag(option.identifier)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .controlSize(.small)
      .disabled(isRelaunching)
    }
    .alert(L10n.PreferencesGeneral.languageRelaunchConfirmationTitle, isPresented: $showRelaunchConfirmation) {
      Button(L10n.Common.cancel, role: .cancel) {
        pendingLanguageIdentifier = nil
      }
      Button(L10n.PreferencesGeneral.languageRelaunchConfirmationAction) {
        applyPendingLanguageChange()
      }
      .disabled(isRelaunching)
    } message: {
      Text(L10n.PreferencesGeneral.languageRelaunchConfirmationMessage)
    }
  }

  private var languageSelection: Binding<String> {
    Binding(
      get: { languageManager.selectedLanguageIdentifier },
      set: { newIdentifier in
        guard !isRelaunching else { return }
        guard newIdentifier != languageManager.selectedLanguageIdentifier else { return }

        if !languageManager.requiresRelaunch(for: newIdentifier) {
          languageManager.selectLanguage(newIdentifier)
          return
        }

        pendingLanguageIdentifier = newIdentifier
        showRelaunchConfirmation = true
      }
    )
  }

  private func applyPendingLanguageChange() {
    guard let pendingLanguageIdentifier else { return }

    languageManager.selectLanguage(pendingLanguageIdentifier)
    self.pendingLanguageIdentifier = nil
    relaunchApplication()
  }

  private func relaunchApplication() {
    guard !isRelaunching else { return }
    isRelaunching = true

    Task {
      do {
        try await languageManager.relaunchApplication()
      } catch {
        isRelaunching = false
        presentRelaunchError(error)
      }
    }
  }

  private func presentRelaunchError(_ error: Error) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = L10n.PreferencesGeneral.languageRelaunchErrorTitle
    alert.informativeText = error.localizedDescription
    alert.addButton(withTitle: L10n.Common.ok)
    alert.runModal()
  }
}

#Preview {
  Form {
    Section(L10n.PreferencesGeneral.appearanceSection) {
      PreferencesLanguageSettingRow()
    }
  }
  .formStyle(.grouped)
  .frame(width: 640, height: 180)
}
