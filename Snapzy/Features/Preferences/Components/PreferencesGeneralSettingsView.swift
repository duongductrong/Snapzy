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
  @State private var logSizeText = L10n.PreferencesGeneral.calculating
  @State private var cacheSizeText = L10n.PreferencesGeneral.calculating
  @State private var canClearCache = true
  @State private var isClearingCache = false
  private let fileAccessManager = SandboxFileAccessManager.shared
  private let storageManager = CaptureStorageManager.shared

  private var updater: SPUUpdater {
    UpdaterManager.shared.updater
  }

  var body: some View {
    Form {
      Section(L10n.PreferencesGeneral.startupSection) {
        SettingRow(icon: "power.circle", title: L10n.PreferencesGeneral.startAtLoginTitle, description: L10n.PreferencesGeneral.startAtLoginDescription) {
          Toggle("", isOn: $startAtLogin)
            .labelsHidden()
            .onChange(of: startAtLogin) { newValue in
              LoginItemManager.setEnabled(newValue)
            }
        }

        SettingRow(icon: "speaker.wave.2", title: L10n.PreferencesGeneral.playSoundsTitle, description: L10n.PreferencesGeneral.playSoundsDescription) {
          Toggle("", isOn: $playSounds)
            .labelsHidden()
        }
      }

      Section(L10n.PreferencesGeneral.appearanceSection) {
        SettingRow(icon: "circle.lefthalf.filled", title: L10n.PreferencesGeneral.themeTitle, description: L10n.PreferencesGeneral.themeDescription) {
          AppearanceModePicker(selection: $themeManager.preferredAppearance)
        }
      }

      Section(L10n.PreferencesGeneral.storageSection) {
        SettingRow(icon: "folder.fill", title: L10n.PreferencesGeneral.saveLocationTitle, description: exportLocationDisplay) {
          Button(L10n.PreferencesGeneral.chooseButton) {
            chooseExportLocation()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }

        SettingRow(icon: "externaldrive.fill", title: L10n.PreferencesGeneral.cacheTitle, description: cacheSizeText) {
          Button(isClearingCache ? L10n.PreferencesGeneral.clearingButton : L10n.PreferencesGeneral.clearButton) {
            clearCacheWithConfirmation()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(!canClearCache || isClearingCache)
        }
      }

      Section(L10n.PreferencesGeneral.updatesSection) {
        SettingRow(icon: "arrow.triangle.2.circlepath", title: L10n.PreferencesGeneral.checkAutomaticallyTitle, description: L10n.PreferencesGeneral.checkAutomaticallyDescription) {
          Toggle("", isOn: Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.automaticallyChecksForUpdates = $0 }
          ))
          .labelsHidden()
        }

        SettingRow(icon: "arrow.down.circle", title: L10n.PreferencesGeneral.downloadAutomaticallyTitle, description: L10n.PreferencesGeneral.downloadAutomaticallyDescription) {
          Toggle("", isOn: Binding(
            get: { updater.automaticallyDownloadsUpdates },
            set: { updater.automaticallyDownloadsUpdates = $0 }
          ))
          .labelsHidden()
        }

        SettingRow(icon: "clock", title: L10n.PreferencesGeneral.lastCheckedTitle, description: nil) {
          if let lastCheck = updater.lastUpdateCheckDate {
            Text(lastCheck, style: .relative)
              .font(.caption)
              .foregroundColor(.secondary)
          } else {
            Text(L10n.PreferencesGeneral.never)
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }

      Section(L10n.PreferencesGeneral.diagnosticsSection) {
        SettingRow(icon: "doc.text.magnifyingglass", title: L10n.PreferencesGeneral.crashLoggingTitle, description: L10n.PreferencesGeneral.crashLoggingDescription) {
          Toggle("", isOn: $diagnosticsEnabled)
            .labelsHidden()
        }

        SettingRow(icon: "folder", title: L10n.PreferencesGeneral.logFilesTitle, description: logSizeText) {
          Button(L10n.PreferencesGeneral.openFolderButton) {
            revealLogFolder()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      }

      Section(L10n.PreferencesGeneral.helpSection) {
        SettingRow(icon: "arrow.counterclockwise.circle", title: L10n.PreferencesGeneral.restartOnboardingTitle, description: L10n.PreferencesGeneral.restartOnboardingDescription) {
          Button(L10n.PreferencesGeneral.restartButton) {
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
      updateCacheSize()
    }
  }

  // MARK: - Helpers

  private var exportLocationDisplay: String {
    if exportLocation.isEmpty {
      return L10n.PreferencesGeneral.defaultSaveLocation
    }

    let folderName = URL(fileURLWithPath: exportLocation).lastPathComponent
    if fileAccessManager.hasPersistedExportPermission {
      return folderName
    }

    return L10n.PreferencesGeneral.accessNotGranted(folderName)
  }

  private func initializeExportLocation() {
    fileAccessManager.ensureExportLocationInitialized()
    exportLocation = fileAccessManager.exportLocationPath
  }

  private func chooseExportLocation() {
    if let url = fileAccessManager.chooseExportDirectory(
      message: L10n.PreferencesGeneral.chooseSaveLocationMessage,
      prompt: L10n.PreferencesGeneral.saveHereButton,
      directoryURL: fileAccessManager.resolvedExportDirectoryURL()
    ) {
      exportLocation = url.path
    }
  }

  // MARK: - Cache Management

  private func updateCacheSize() {
    Task {
      let bytes = await storageManager.calculateCacheSize()
      cacheSizeText = CaptureStorageManager.formattedSize(bytes)
      canClearCache = storageManager.isSafeToCleanup && bytes > 0
    }
  }

  private func clearCacheWithConfirmation() {
    let alert = NSAlert()
    alert.messageText = L10n.PreferencesGeneral.clearCacheAlertTitle
    alert.informativeText = L10n.PreferencesGeneral.clearCacheAlertMessage
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.PreferencesGeneral.clearCacheConfirm)
    alert.addButton(withTitle: L10n.Common.cancel)

    guard alert.runModal() == .alertFirstButtonReturn else { return }

    isClearingCache = true
    Task {
      do {
        try await storageManager.clearCache()
      } catch {
        let errorAlert = NSAlert()
        errorAlert.messageText = L10n.PreferencesGeneral.clearCacheErrorTitle
        errorAlert.informativeText = error.localizedDescription
        errorAlert.alertStyle = .informational
        errorAlert.addButton(withTitle: L10n.Common.ok)
        errorAlert.runModal()
      }
      isClearingCache = false
      updateCacheSize()
    }
  }

  // MARK: - Onboarding

  private func restartOnboarding() {
    OnboardingFlowView.resetOnboarding()
    NSApp.keyWindow?.close()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      NotificationCenter.default.post(name: .showOnboarding, object: nil)
    }
  }

  // MARK: - Diagnostics

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
      logSizeText = L10n.PreferencesGeneral.noLogs
      return
    }
    let totalBytes = files.compactMap { file -> Int? in
      let path = logDir.appendingPathComponent(file).path
      return (try? fm.attributesOfItem(atPath: path))?[.size] as? Int
    }.reduce(0, +)

    if totalBytes == 0 {
      logSizeText = L10n.PreferencesGeneral.noLogs
    } else {
      logSizeText = ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
    }
  }
}

#Preview {
  GeneralSettingsView()
    .frame(width: 600, height: 500)
}
