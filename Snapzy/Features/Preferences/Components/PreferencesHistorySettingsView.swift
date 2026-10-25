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
          title: L10n.PreferencesHistory.floatingPanelTitle,
          description: L10n.PreferencesHistory.floatingPanelDescription
        ) {
          Toggle("", isOn: $manager.isEnabled)
            .labelsHidden()
        }

        SettingRow(
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
          title: L10n.PreferencesHistory.backgroundStyleTitle,
          description: L10n.PreferencesHistory.backgroundStyleDescription,
          alignment: .top
        ) {
          HistoryBackgroundStylePicker(selection: $historyBackgroundStyle, position: manager.position)
        }

        SettingRow(
          title: L10n.PreferencesHistory.panelSizeTitle,
          description: L10n.PreferencesHistory.panelSizeDescription
        ) {
          HStack(spacing: 8) {
            Text(L10n.PreferencesHistory.panelSizeSmall)
              .font(.caption)
              .foregroundColor(.secondary)
            Slider(value: $manager.panelScale.stepped(by: 0.05, in: HistoryFloatingLayout.scaleRange), in: HistoryFloatingLayout.scaleRange)
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
            ).stepped(by: 1, in: 3...20), in: 3...20)
            .frame(width: 120)
          }
          .frame(width: 220, alignment: .trailing)
        }
      }

      Section(L10n.PreferencesHistory.retentionSection) {
        SettingRow(
          title: L10n.PreferencesHistory.retentionDaysTitle,
          description: retentionDaysDescription,
          descriptionStyle: .subtitle
        ) {
          HStack(spacing: 8) {
            Text(historyRetentionDays == 0 ? "∞" : "\(historyRetentionDays)")
              .frame(width: 28, alignment: .trailing)
              .monospacedDigit()
              .foregroundColor(.secondary)
            Slider(value: Binding(
              get: { Double(historyRetentionDays) },
              set: { historyRetentionDays = Int($0) }
            ).stepped(by: 1, in: 0...90), in: 0...90)
            .frame(width: 120)
          }
          .frame(width: 220, alignment: .trailing)
        }

        SettingRow(
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
            ).stepped(by: 50, in: 0...1000), in: 0...1000)
            .frame(width: 120)
          }
          .frame(width: 220, alignment: .trailing)
        }
      }

      Section(L10n.PreferencesHistory.storageSection) {
        SettingRow(
          title: L10n.PreferencesHistory.captureStorageTitle,
          description: captureStorageSizeText,
          descriptionStyle: .subtitle
        ) {
          Button(L10n.PreferencesHistory.openCaptureStorageButton) {
            revealCaptureStorage()
          }
          .buttonStyle(.bordered)
          .controlSize(.regular)
        }

        SettingRow(
          title: L10n.PreferencesHistory.clearHistoryTitle,
          description: L10n.PreferencesHistory.clearHistoryDescription
        ) {
          Button(L10n.PreferencesHistory.clearHistoryButton) {
            clearHistoryWithConfirmation()
          }
          .buttonStyle(.bordered)
          .controlSize(.regular)
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
  let position: HistoryPanelPosition

  var body: some View {
    HStack(spacing: 10) {
      ForEach(HistoryBackgroundStyle.allCases) { style in
        PreferencesVisualOptionTile(
          title: style.displayName,
          isSelected: selection == style,
          action: { selection = style }
        ) {
          HistoryBackgroundStyleDesktopPreview(style: style, position: position)
        }
      }
    }
  }
}

/// The floating History panel drawn on a mini desktop at its configured edge, so the choice
/// shows what it changes: HUD lets the wallpaper read through, Solid covers it.
private struct HistoryBackgroundStyleDesktopPreview: View {
  @ObservedObject private var themeManager = ThemeManager.shared
  @Environment(\.colorScheme) private var colorScheme

  let style: HistoryBackgroundStyle
  let position: HistoryPanelPosition

  private static let panelSize = CGSize(width: 52, height: 24)
  private static let edgeGap: CGFloat = 3

  var body: some View {
    PreferencesMiniDesktop {
      VStack(spacing: 0) {
        if position == .bottomCenter { Spacer(minLength: 0) }
        panel
        if position != .bottomCenter { Spacer(minLength: 0) }
      }
      .padding(.top, PreferencesMiniDesktop<EmptyView>.menuBarHeight + Self.edgeGap)
      .padding(.bottom, Self.edgeGap)
    }
  }

  private var panel: some View {
    let shape = RoundedRectangle(cornerRadius: 4, style: .continuous) // radius-lint:allow — miniature History panel drawn at ~1:10 scale
    return VStack(spacing: 3) {
      HStack(spacing: 2) {
        Capsule().fill(Color.accentColor).frame(width: 7, height: 3)
        Capsule().fill(chromeFill).frame(width: 7, height: 3)
        Capsule().fill(chromeFill).frame(width: 7, height: 3)
        Spacer(minLength: 0)
        Circle().fill(chromeFill).frame(width: 3, height: 3)
      }
      HStack(spacing: 3) {
        ForEach(0..<4, id: \.self) { index in
          RoundedRectangle(cornerRadius: 1.5, style: .continuous) // radius-lint:allow — miniature capture card
            .fill(cardFill.opacity(index == 0 ? 1 : 0.7))
        }
      }
    }
    .padding(4)
    .frame(width: Self.panelSize.width, height: Self.panelSize.height)
    .background { panelFill.clipShape(shape) }
    .overlay { shape.strokeBorder(Color.white.opacity(style == .hud ? 0.22 : 0.1), lineWidth: 0.5) }
    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
  }

  /// HUD mirrors the real floating panel: forced-dark glass over the desktop.
  private var isDarkPanel: Bool {
    style == .hud || colorScheme == .dark
  }

  @ViewBuilder
  private var panelFill: some View {
    switch style {
    case .hud:
      Color.black.opacity(0.42)
    case .solid:
      Color(nsColor: WindowSurfacePalette.backgroundColor(for: themeManager.preferredAppearance))
    }
  }

  private var chromeFill: Color {
    isDarkPanel ? Color.white.opacity(0.22) : Color.black.opacity(0.12)
  }

  private var cardFill: Color {
    isDarkPanel ? Color.white.opacity(0.28) : Color.black.opacity(0.10)
  }
}

#Preview {
  HistorySettingsView()
    .frame(width: 600, height: 450)
}
