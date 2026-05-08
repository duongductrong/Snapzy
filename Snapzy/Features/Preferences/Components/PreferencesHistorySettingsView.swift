//
//  PreferencesHistorySettingsView.swift
//  Snapzy
//
//  History settings tab for the floating panel and retention
//

import SwiftUI

struct HistorySettingsView: View {
  @ObservedObject private var manager = HistoryFloatingManager.shared
  @AppStorage(PreferencesKeys.historyRetentionDays) private var historyRetentionDays = 30
  @AppStorage(PreferencesKeys.historyMaxCount) private var historyMaxCount = 500
  @AppStorage(PreferencesKeys.historyBackgroundStyle) private var historyBackgroundStyle: HistoryBackgroundStyle = .defaultStyle
  @State private var captureStorageSizeText = L10n.PreferencesGeneral.calculating
  private let storageManager = CaptureStorageManager.shared

  var body: some View {
    Form {
      Section(L10n.PreferencesHistory.floatingPanelSection) {
        SettingRow(
          icon: "rectangle.stack.badge.person.crop",
          title: L10n.PreferencesHistory.floatingPanelTitle,
          description: L10n.PreferencesHistory.floatingPanelDescription
        ) {
          Toggle("", isOn: $manager.isEnabled)
            .labelsHidden()
        }

        SettingRow(
          icon: "arrow.up.and.down",
          title: L10n.PreferencesHistory.panelPositionTitle,
          description: L10n.PreferencesHistory.panelPositionDescription
        ) {
          Picker("", selection: $manager.position) {
            ForEach(HistoryPanelPosition.allCases, id: \.self) { position in
              Text(position.displayName).tag(position)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .fixedSize()
          .frame(width: 140, alignment: .trailing)
        }
      }

      Section(L10n.PreferencesHistory.displaySection) {
        SettingRow(
          icon: "line.3.horizontal.decrease.circle",
          title: L10n.PreferencesHistory.defaultFilterTitle,
          description: L10n.PreferencesHistory.defaultFilterDescription
        ) {
          Picker("", selection: $manager.defaultFilter) {
            Text(L10n.PreferencesHistory.defaultFilterAll).tag(Optional<CaptureHistoryType>.none)
            Text(L10n.PreferencesHistory.defaultFilterScreenshots).tag(Optional<CaptureHistoryType>.some(.screenshot))
            Text(L10n.PreferencesHistory.defaultFilterVideos).tag(Optional<CaptureHistoryType>.some(.video))
            Text(L10n.PreferencesHistory.defaultFilterGifs).tag(Optional<CaptureHistoryType>.some(.gif))
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .fixedSize()
          .frame(width: 140, alignment: .trailing)
        }

        SettingRow(
          icon: "macwindow",
          title: L10n.PreferencesHistory.backgroundStyleTitle,
          description: L10n.PreferencesHistory.backgroundStyleDescription
        ) {
          HistoryBackgroundStylePicker(selection: $historyBackgroundStyle)
            .frame(width: 190, alignment: .trailing)
        }

        SettingRow(
          icon: "arrow.up.left.and.arrow.down.right",
          title: L10n.PreferencesHistory.panelSizeTitle,
          description: L10n.PreferencesHistory.panelSizeDescription
        ) {
          HStack(spacing: 8) {
            Text(L10n.PreferencesHistory.panelSizeSmall)
              .font(.caption)
              .foregroundColor(.secondary)
            Slider(value: $manager.panelScale, in: HistoryFloatingLayout.scaleRange, step: 0.05)
              .frame(width: 120)
            Text(L10n.PreferencesHistory.panelSizeLarge)
              .font(.caption)
              .foregroundColor(.secondary)
            Text("\(Int(manager.panelScale * 100))%")
              .frame(width: 44, alignment: .trailing)
              .monospacedDigit()
              .foregroundColor(.secondary)
          }
          .frame(width: 220, alignment: .trailing)
        }

        SettingRow(
          icon: "number",
          title: L10n.PreferencesHistory.maxItemsTitle,
          description: L10n.PreferencesHistory.maxItemsDescription
        ) {
          HStack(spacing: 8) {
            Text("\(manager.maxDisplayedItems)")
              .frame(width: 28, alignment: .trailing)
              .monospacedDigit()
              .foregroundColor(.secondary)
            Slider(value: Binding(
              get: { Double(manager.maxDisplayedItems) },
              set: { manager.maxDisplayedItems = Int($0) }
            ), in: 3...20, step: 1)
            .frame(width: 120)
          }
          .frame(width: 220, alignment: .trailing)
        }
      }

      Section(L10n.PreferencesHistory.retentionSection) {
        SettingRow(
          icon: "clock.arrow.circlepath",
          title: L10n.PreferencesHistory.retentionDaysTitle,
          description: retentionDaysDescription
        ) {
          HStack(spacing: 8) {
            Text(historyRetentionDays == 0 ? "∞" : "\(historyRetentionDays)")
              .frame(width: 28, alignment: .trailing)
              .monospacedDigit()
              .foregroundColor(.secondary)
            Slider(value: Binding(
              get: { Double(historyRetentionDays) },
              set: { historyRetentionDays = Int($0) }
            ), in: 0...90, step: 1)
            .frame(width: 120)
          }
          .frame(width: 220, alignment: .trailing)
        }

        SettingRow(
          icon: "archivebox",
          title: L10n.PreferencesHistory.maxCountTitle,
          description: L10n.PreferencesHistory.maxCountDescription
        ) {
          HStack(spacing: 8) {
            Text(historyMaxCount == 0 ? "∞" : "\(historyMaxCount)")
              .frame(width: 36, alignment: .trailing)
              .monospacedDigit()
              .foregroundColor(.secondary)
            Slider(value: Binding(
              get: { Double(historyMaxCount) },
              set: { historyMaxCount = Int($0) }
            ), in: 0...1000, step: 50)
            .frame(width: 120)
          }
          .frame(width: 220, alignment: .trailing)
        }
      }

      Section(L10n.PreferencesHistory.storageSection) {
        SettingRow(
          icon: "externaldrive.fill",
          title: L10n.PreferencesHistory.captureStorageTitle,
          description: captureStorageSizeText
        ) {
          Button(L10n.PreferencesHistory.openCaptureStorageButton) {
            revealCaptureStorage()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }

        SettingRow(
          icon: "trash",
          title: L10n.PreferencesHistory.clearHistoryTitle,
          description: L10n.PreferencesHistory.clearHistoryDescription
        ) {
          Button(L10n.PreferencesHistory.clearHistoryButton) {
            clearHistoryWithConfirmation()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .tint(.red)
        }
      }
    }
    .formStyle(.grouped)
    .onAppear {
      updateCaptureStorageSize()
    }
  }

  private var retentionDaysDescription: String {
    if historyRetentionDays == 0 {
      return L10n.PreferencesHistory.keepForever
    }
    return L10n.PreferencesHistory.deleteAfterDays(historyRetentionDays)
  }

  private func clearHistoryWithConfirmation() {
    let alert = NSAlert()
    alert.messageText = L10n.PreferencesHistory.clearHistoryAlertTitle
    alert.informativeText = L10n.PreferencesHistory.clearHistoryAlertMessage
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.PreferencesHistory.clearHistoryConfirm)
    alert.addButton(withTitle: L10n.Common.cancel)

    guard alert.runModal() == .alertFirstButtonReturn else { return }
    HistoryWindowController.shared.deleteRecords(CaptureHistoryStore.shared.records, asksConfirmation: false)
    updateCaptureStorageSize()
  }

  private func updateCaptureStorageSize() {
    Task {
      let bytes = await storageManager.calculateCacheSize()
      captureStorageSizeText = CaptureStorageManager.formattedSize(bytes)
    }
  }

  private func revealCaptureStorage() {
    guard let url = storageManager.ensureCapturesDirectory() else { return }
    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
  }
}

private struct HistoryBackgroundStylePicker: View {
  @Binding var selection: HistoryBackgroundStyle

  var body: some View {
    HStack(spacing: 14) {
      ForEach(HistoryBackgroundStyle.allCases) { style in
        Button(action: { selection = style }) {
          VStack(spacing: 6) {
            HistoryBackgroundStyleThumbnail(style: style, isSelected: selection == style)

            Text(style.displayName)
              .font(.system(size: 10))
              .foregroundColor(selection == style ? .accentColor : .primary)
          }
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.vertical, 4)
  }
}

private struct HistoryBackgroundStyleThumbnail: View {
  @Environment(\.colorScheme) private var colorScheme

  let style: HistoryBackgroundStyle
  let isSelected: Bool

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(containerFill)

      HistoryBackdropView(style: style, cornerRadius: 6, compact: true)
        .padding(4)
    }
    .frame(width: 72, height: 52)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(isSelected ? Color.accentColor : borderColor, lineWidth: isSelected ? 3 : 1)
    )
    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
  }

  private var borderColor: Color {
    colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
  }

  private var containerFill: Color {
    colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02)
  }
}

#Preview {
  HistorySettingsView()
    .frame(width: 600, height: 450)
}
