//
//  GeneralSettingsView.swift
//  Snapzy
//
//  General preferences tab with startup, appearance, storage, updates, and help
//

import SwiftUI
import Sparkle

struct GeneralSettingsView: View {
  @AppStorage(PreferencesKeys.playSounds) private var playSounds = true
  @AppStorage(PreferencesKeys.exportLocation) private var exportLocation = ""
  @AppStorage(PreferencesKeys.diagnosticsEnabled) private var diagnosticsEnabled = true
  @Environment(\.openWindow) private var openWindow
  @ObservedObject private var themeManager = ThemeManager.shared

  @State private var startAtLogin = LoginItemManager.isEnabled
  @State private var logSizeText = "Calculating..."

  private var updater: SPUUpdater {
    UpdaterManager.shared.updater
  }

  var body: some View {
    Form {
      Section("Startup") {
        SettingRow(icon: "power.circle", title: "Start at login", description: "Launch Snapzy when you log in") {
          Toggle("", isOn: $startAtLogin)
            .labelsHidden()
            .onChange(of: startAtLogin) { newValue in
              LoginItemManager.setEnabled(newValue)
            }
        }

        SettingRow(icon: "speaker.wave.2", title: "Play sounds", description: "Audio feedback for captures") {
          Toggle("", isOn: $playSounds)
            .labelsHidden()
        }
      }

      Section("Appearance") {
        SettingRow(icon: "circle.lefthalf.filled", title: "Theme", description: "Choose your preferred appearance") {
          AppearanceModePicker(selection: $themeManager.preferredAppearance)
        }
      }

      Section("Storage") {
        SettingRow(icon: "folder.fill", title: "Save location", description: exportLocationDisplay) {
          Button("Choose...") {
            chooseExportLocation()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      }

      Section("Software Updates") {
        SettingRow(icon: "arrow.triangle.2.circlepath", title: "Check automatically", description: "Look for updates on launch") {
          Toggle("", isOn: Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.automaticallyChecksForUpdates = $0 }
          ))
          .labelsHidden()
        }

        SettingRow(icon: "arrow.down.circle", title: "Download automatically", description: "Download updates in background") {
          Toggle("", isOn: Binding(
            get: { updater.automaticallyDownloadsUpdates },
            set: { updater.automaticallyDownloadsUpdates = $0 }
          ))
          .labelsHidden()
        }

        SettingRow(icon: "clock", title: "Last checked", description: nil) {
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

      Section("Diagnostics") {
        SettingRow(icon: "doc.text.magnifyingglass", title: "Crash Logging", description: "Collect diagnostic logs to help us fix bugs") {
          Toggle("", isOn: $diagnosticsEnabled)
            .labelsHidden()
        }

        SettingRow(icon: "folder", title: "Log Files", description: logSizeText) {
          Button("Open Folder") {
            revealLogFolder()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      }

      Section("Help") {
        SettingRow(icon: "arrow.counterclockwise.circle", title: "Restart Onboarding", description: "Show the welcome tutorial again") {
          Button("Restart") {
            restartOnboarding()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      }
    }
    .formStyle(.grouped)
    .onAppear {
      startAtLogin = LoginItemManager.isEnabled
      initializeExportLocation()
      updateLogSize()
    }
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
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      NotificationCenter.default.post(name: .showOnboarding, object: nil)
    }
  }

  private func revealLogFolder() {
    let logDir = DiagnosticLogger.shared.logDirectoryURL
    let fm = FileManager.default
    if !fm.fileExists(atPath: logDir.path) {
      try? fm.createDirectory(at: logDir, withIntermediateDirectories: true)
    }
    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: logDir.path)
  }

  private func updateLogSize() {
    let logDir = DiagnosticLogger.shared.logDirectoryURL
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(atPath: logDir.path) else {
      logSizeText = "No logs"
      return
    }
    let totalBytes = files.compactMap { file -> Int? in
      let path = logDir.appendingPathComponent(file).path
      return (try? fm.attributesOfItem(atPath: path))?[.size] as? Int
    }.reduce(0, +)

    if totalBytes == 0 {
      logSizeText = "No logs"
    } else if totalBytes < 1024 {
      logSizeText = "\(totalBytes) B"
    } else {
      logSizeText = String(format: "%.1f KB", Double(totalBytes) / 1024.0)
    }
  }
}

#Preview {
  GeneralSettingsView()
    .frame(width: 600, height: 500)
}
