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
  @AppStorage(PreferencesKeys.showMenuBarIcon) private var showMenuBarIcon = true
  @AppStorage(PreferencesKeys.exportLocation) private var exportLocation = ""
  @Environment(\.openWindow) private var openWindow
  @ObservedObject private var themeManager = ThemeManager.shared

  @State private var startAtLogin = LoginItemManager.isEnabled
  private let fileAccessManager = SandboxFileAccessManager.shared

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

        SettingRow(icon: "menubar.rectangle", title: L10n.PreferencesGeneral.menuBarIconTitle, description: L10n.PreferencesGeneral.menuBarIconDescription) {
          Toggle("", isOn: $showMenuBarIcon)
            .labelsHidden()
            .onChange(of: showMenuBarIcon) { newValue in
              AppStatusBarController.shared.setMenuBarIconVisible(newValue)
            }
        }
      }

      Section(L10n.PreferencesGeneral.appearanceSection) {
        PreferencesLanguageSettingRow()

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
      }

      Section(L10n.PreferencesGeneral.updatesSection) {
        SettingRow(icon: "arrow.triangle.2.circlepath", title: L10n.PreferencesGeneral.checkAutomaticallyTitle, description: L10n.PreferencesGeneral.checkAutomaticallyDescription) {
          Toggle("", isOn: Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: {
              updater.automaticallyChecksForUpdates = $0
              SnapzyConfigurationSyncCoordinator.shared.scheduleSync(reason: .explicitChange)
            }
          ))
          .labelsHidden()
        }

        SettingRow(icon: "arrow.down.circle", title: L10n.PreferencesGeneral.downloadAutomaticallyTitle, description: L10n.PreferencesGeneral.downloadAutomaticallyDescription) {
          Toggle("", isOn: Binding(
            get: { updater.automaticallyDownloadsUpdates },
            set: {
              updater.automaticallyDownloadsUpdates = $0
              SnapzyConfigurationSyncCoordinator.shared.scheduleSync(reason: .explicitChange)
            }
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

      Section(L10n.PreferencesGeneral.helpSection) {
        SettingRow(icon: "arrow.counterclockwise.circle", title: L10n.PreferencesGeneral.restartOnboardingTitle, description: L10n.PreferencesGeneral.restartOnboardingDescription) {
          Button(L10n.PreferencesGeneral.restartButton) {
            restartOnboarding()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }

        SettingRow(
          icon: "exclamationmark.bubble",
          title: L10n.PreferencesGeneral.reportIssueTitle,
          description: L10n.PreferencesGeneral.reportIssueDescription(bugReportDisplayAddress)
        ) {
          Button(L10n.PreferencesGeneral.openReportPageButton) {
            openBugReportPage()
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

  // MARK: - Onboarding

  private func restartOnboarding() {
    OnboardingFlowView.resetOnboarding()
    NSApp.keyWindow?.close()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      NotificationCenter.default.post(name: .showOnboarding, object: nil)
    }
  }

  // MARK: - Help

  private var bugReportDisplayAddress: String {
    CrashReportService.bugReportURL.absoluteString.replacingOccurrences(of: "https://", with: "")
  }

  private func openBugReportPage() {
    NSWorkspace.shared.open(CrashReportService.bugReportURL)
  }
}

#Preview {
  GeneralSettingsView()
    .frame(width: 600, height: 500)
}
