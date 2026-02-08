//
//  GeneralSettingsView.swift
//  Snapzy
//
//  General preferences tab with startup, sounds, export, and after-capture settings
//

import SwiftUI
import Sparkle

struct GeneralSettingsView: View {
  @AppStorage(PreferencesKeys.playSounds) private var playSounds = true
  @AppStorage(PreferencesKeys.exportLocation) private var exportLocation = ""
  @AppStorage(PreferencesKeys.hideDesktopIcons) private var hideDesktopIcons = false
  @Environment(\.openWindow) private var openWindow
  @ObservedObject private var themeManager = ThemeManager.shared

  @State private var startAtLogin = LoginItemManager.isEnabled

  // Use shared updater manager
  private var updater: SPUUpdater {
    UpdaterManager.shared.updater
  }

  var body: some View {
    Form {
      Section("Startup") {
        settingRow(icon: "power.circle", title: "Start at login", description: "Launch Snapzy when you log in") {
          Toggle("", isOn: $startAtLogin)
            .labelsHidden()
            .onChange(of: startAtLogin) { _, newValue in
              LoginItemManager.setEnabled(newValue)
            }
        }

        settingRow(icon: "speaker.wave.2", title: "Play sounds", description: "Audio feedback for captures") {
          Toggle("", isOn: $playSounds)
            .labelsHidden()
        }
      }

      Section("Appearance") {
        AppearanceModePicker(selection: $themeManager.preferredAppearance)
          .frame(maxWidth: .infinity, alignment: .center)
      }

      Section("Storage") {
        settingRow(icon: "folder.fill", title: "Save location", description: exportLocationDisplay) {
          Button("Choose...") {
            chooseExportLocation()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      }

      Section("Capture") {
        settingRow(icon: "eye.slash", title: "Hide desktop icons", description: "Temporarily hide icons during capture") {
          Toggle("", isOn: $hideDesktopIcons)
            .labelsHidden()
        }
      }

      Section("Post-Capture Actions") {
        AfterCaptureMatrixView()
      }

      Section("Help") {
        settingRow(icon: "arrow.counterclockwise.circle", title: "Restart Onboarding", description: "Show the welcome tutorial again") {
          Button("Restart") {
            restartOnboarding()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      }

      Section("Software Updates") {
        settingRow(icon: "arrow.triangle.2.circlepath", title: "Check automatically", description: "Look for updates on launch") {
          Toggle("", isOn: Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.automaticallyChecksForUpdates = $0 }
          ))
          .labelsHidden()
        }

        settingRow(icon: "arrow.down.circle", title: "Download automatically", description: "Download updates in background") {
          Toggle("", isOn: Binding(
            get: { updater.automaticallyDownloadsUpdates },
            set: { updater.automaticallyDownloadsUpdates = $0 }
          ))
          .labelsHidden()
        }

        settingRow(icon: "clock", title: "Last checked", description: nil) {
          if let lastCheck = updater.lastUpdateCheckDate {
            Text(lastCheck, style: .relative)
              .font(.caption)
              .foregroundColor(.secondary)
          } else {
            Text("Never")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }
    }
    .formStyle(.grouped)
    .onAppear {
      startAtLogin = LoginItemManager.isEnabled
      initializeExportLocation()
    }
  }

  // MARK: - Setting Row Helper

  @ViewBuilder
  private func settingRow<Content: View>(
    icon: String,
    title: String,
    description: String?,
    @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundColor(.secondary)
        .frame(width: 28)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .fontWeight(.medium)
        if let description {
          Text(description)
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }

      Spacer()
      content()
    }
    .padding(.vertical, 4)
  }

  // MARK: - Helpers

  private var exportLocationDisplay: String {
    if exportLocation.isEmpty {
      return "Desktop/Snapzy"
    }
    return URL(fileURLWithPath: exportLocation).lastPathComponent
  }

  private func initializeExportLocation() {
    if exportLocation.isEmpty {
      guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
        let home = FileManager.default.homeDirectoryForCurrentUser
        exportLocation = home.appendingPathComponent("Snapzy").path
        return
      }
      exportLocation = desktop.appendingPathComponent("Snapzy").path
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
    NSApp.keyWindow?.close()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      NSApp.activate(ignoringOtherApps: true)
      // openWindow(id: "onboarding")
    }
  }
}

#Preview {
  GeneralSettingsView()
    .frame(width: 600, height: 500)
}
