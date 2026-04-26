//
//  PreferencesHistorySettingsView.swift
//  Snapzy
//
//  History settings tab for the floating panel and retention
//

import SwiftUI

struct HistorySettingsView: View {
  @ObservedObject private var themeManager = ThemeManager.shared
  @ObservedObject private var manager = HistoryFloatingManager.shared
  @AppStorage(PreferencesKeys.historyRetentionDays) private var historyRetentionDays = 30
  @AppStorage(PreferencesKeys.historyMaxCount) private var historyMaxCount = 500
  @AppStorage(PreferencesKeys.historyBackgroundStyle) private var historyBackgroundStyle: HistoryBackgroundStyle = .defaultStyle
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ZStack {
      HistoryBackdropView(style: historyBackgroundStyle)
        .ignoresSafeArea()

      ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 16) {
          settingsSection(L10n.PreferencesHistory.floatingPanelSection) {
            settingsRow(
              icon: "rectangle.stack.badge.person.crop",
              title: L10n.PreferencesHistory.floatingPanelTitle,
              description: L10n.PreferencesHistory.floatingPanelDescription
            ) {
              Toggle("", isOn: $manager.isEnabled)
                .labelsHidden()
            }

            rowDivider

            settingsRow(
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

          settingsSection(L10n.PreferencesHistory.displaySection) {
            settingsRow(
              icon: "line.3.horizontal.decrease.circle",
              title: L10n.PreferencesHistory.defaultFilterTitle,
              description: L10n.PreferencesHistory.defaultFilterDescription
            ) {
              Picker("", selection: $manager.defaultFilter) {
                Text("All").tag(Optional<CaptureHistoryType>.none)
                Text("Screenshots").tag(Optional<CaptureHistoryType>.some(.screenshot))
                Text("Videos").tag(Optional<CaptureHistoryType>.some(.video))
                Text("GIFs").tag(Optional<CaptureHistoryType>.some(.gif))
              }
              .labelsHidden()
              .pickerStyle(.menu)
              .fixedSize()
              .frame(width: 140, alignment: .trailing)
            }

            rowDivider

            settingsRow(
              icon: "macwindow",
              title: L10n.PreferencesHistory.backgroundStyleTitle,
              description: L10n.PreferencesHistory.backgroundStyleDescription
            ) {
              HistoryBackgroundStylePicker(selection: $historyBackgroundStyle)
                .frame(width: 220, alignment: .trailing)
            }

            rowDivider

            settingsRow(
              icon: "arrow.up.left.and.arrow.down.right",
              title: L10n.PreferencesHistory.panelSizeTitle,
              description: L10n.PreferencesHistory.panelSizeDescription
            ) {
              HStack(spacing: 8) {
                Text(verbatim: "S")
                  .font(.caption)
                  .foregroundColor(.secondary)
                Slider(value: $manager.panelScale, in: HistoryFloatingLayout.scaleRange, step: 0.05)
                  .frame(width: 120)
                Text(verbatim: "L")
                  .font(.caption)
                  .foregroundColor(.secondary)
                Text("\(Int(manager.panelScale * 100))%")
                  .frame(width: 44, alignment: .trailing)
                  .monospacedDigit()
                  .foregroundColor(.secondary)
              }
              .frame(width: 220, alignment: .trailing)
            }

            rowDivider

            settingsRow(
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

          settingsSection(L10n.PreferencesHistory.retentionSection) {
            settingsRow(
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

            rowDivider

            settingsRow(
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

          settingsSection(L10n.PreferencesHistory.storageSection) {
            settingsRow(
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
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
      }
    }
    .preferredColorScheme(themeManager.systemAppearance)
  }

  private func settingsSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.secondary)
        .textCase(.uppercase)
        .padding(.horizontal, 4)

      VStack(spacing: 0) {
        content()
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 6)
      .background(sectionFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .stroke(sectionBorder, lineWidth: 1)
      )
      .shadow(color: sectionShadow, radius: 10, x: 0, y: 6)
    }
  }

  private func settingsRow<Content: View>(
    icon: String,
    title: String,
    description: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(spacing: 13) {
      Image(systemName: icon)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.primary.opacity(0.78))
        .frame(width: 30, height: 30)
        .background(.regularMaterial, in: Circle())
        .overlay(
          Circle()
            .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.55), lineWidth: 1)
        )

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.primary)

        Text(description)
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(.secondary)
          .lineLimit(2)
      }

      Spacer(minLength: 12)

      content()
    }
    .padding(.vertical, 9)
  }

  private var rowDivider: some View {
    Divider()
      .padding(.leading, 43)
  }

  private var sectionFill: AnyShapeStyle {
    if historyBackgroundStyle == .solid {
      return colorScheme == .dark
        ? AnyShapeStyle(Color.white.opacity(0.08))
        : AnyShapeStyle(Color.white.opacity(0.9))
    }

    return colorScheme == .dark
      ? AnyShapeStyle(Color.white.opacity(0.07))
      : AnyShapeStyle(Color.white.opacity(0.64))
  }

  private var sectionBorder: Color {
    colorScheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.62)
  }

  private var sectionShadow: Color {
    Color.black.opacity(colorScheme == .dark ? 0.18 : 0.07)
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
    CaptureHistoryStore.shared.removeAll()
  }
}

private struct HistoryBackgroundStylePicker: View {
  @Binding var selection: HistoryBackgroundStyle

  var body: some View {
    HStack(spacing: 12) {
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
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(containerFill)

      HistoryBackdropView(style: style, cornerRadius: 9, compact: true)
        .padding(5)
    }
    .frame(width: 82, height: 62)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(isSelected ? Color.accentColor : borderColor, lineWidth: isSelected ? 2 : 1)
    )
    .shadow(color: Color.black.opacity(isSelected ? 0.12 : 0.06), radius: isSelected ? 8 : 4, x: 0, y: 2)
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
