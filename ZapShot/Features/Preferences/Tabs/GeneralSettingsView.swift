//
//  GeneralSettingsView.swift
//  ZapShot
//
//  General preferences tab with startup, sounds, export, and after-capture settings
//

import SwiftUI

struct GeneralSettingsView: View {
  @AppStorage(PreferencesKeys.playSounds) private var playSounds = true
  @AppStorage(PreferencesKeys.showMenuBarIcon) private var showMenuBarIcon = true
  @AppStorage(PreferencesKeys.exportLocation) private var exportLocation = ""
  @Environment(\.openWindow) private var openWindow

  @State private var startAtLogin = LoginItemManager.isEnabled

  var body: some View {
    Form {
      Section("Startup") {
        Toggle("Start at login", isOn: $startAtLogin)
          .onChange(of: startAtLogin) { _, newValue in
            LoginItemManager.setEnabled(newValue)
          }

        Toggle("Play sounds", isOn: $playSounds)
        Toggle("Show icon in menu bar", isOn: $showMenuBarIcon)
      }

      Section("Export") {
        HStack {
          Text("Save screenshots to:")
          Spacer()
          Text(exportLocationDisplay)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: 200)
          Button("Choose...") {
            chooseExportLocation()
          }
        }
      }

      Section("After Capture") {
        AfterCaptureMatrixView()
      }

      Section("Help") {
        Button("Restart Onboarding...") {
          restartOnboarding()
        }
        .foregroundColor(.accentColor)
      }
    }
    .formStyle(.grouped)
    .onAppear {
      startAtLogin = LoginItemManager.isEnabled
      initializeExportLocation()
    }
  }

  private var exportLocationDisplay: String {
    if exportLocation.isEmpty {
      return "Desktop/ZapShot"
    }
    return URL(fileURLWithPath: exportLocation).lastPathComponent
  }

  private func initializeExportLocation() {
    if exportLocation.isEmpty {
      guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
        // Fallback to home directory
        let home = FileManager.default.homeDirectoryForCurrentUser
        exportLocation = home.appendingPathComponent("ZapShot").path
        return
      }
      exportLocation = desktop.appendingPathComponent("ZapShot").path
    }
  }

  private func chooseExportLocation() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.message = "Choose where to save screenshots"

    if panel.runModal() == .OK, let url = panel.url {
      exportLocation = url.path
    }
  }

  private func restartOnboarding() {
    OnboardingFlowView.resetOnboarding()
    // Close settings window
    NSApp.keyWindow?.close()
    // Open onboarding window using SwiftUI environment
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      NSApp.activate(ignoringOtherApps: true)
      openWindow(id: "onboarding")
    }
  }
}

#Preview {
  GeneralSettingsView()
    .frame(width: 500, height: 400)
}
