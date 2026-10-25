//
//  SettingRow.swift
//  Snapzy
//
//  Reusable compact settings row: title with an info hint, and trailing content.
//

import SwiftUI

/// Where a row's description is shown.
enum SettingRowDescriptionStyle {
  /// Static explanation, revealed by hovering the ⓘ beside the title. Keeps rows single-line.
  case hint
  /// Live state the user should see at a glance (a path, a size, a sync status).
  case subtitle
}

struct SettingRow<Content: View>: View {
  let title: String
  let description: String?
  var descriptionStyle: SettingRowDescriptionStyle = .hint
  var tooltip: String? = nil
  /// `.top` for tall trailing content (thumbnail pickers): macOS pins the label to the top edge.
  var alignment: VerticalAlignment = .center
  @ViewBuilder let content: () -> Content

  @Environment(\.preferencesHighlightedSetting) private var highlightedSetting

  var body: some View {
    row
      // The title doubles as the anchor Preferences search scrolls to.
      .id(title)
      .background {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color.accentColor.opacity(highlightedSetting == title ? 0.16 : 0))
          .padding(.horizontal, -6)
          .padding(.vertical, -4)
          .animation(.easeInOut(duration: 0.35), value: highlightedSetting == title)
      }
  }

  private var row: some View {
    HStack(alignment: alignment, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        if let hintText {
          Text(title)
            .hint(hintText, variant: .icon(.info))
        } else {
          Text(title)
        }
        if descriptionStyle == .subtitle, let description {
          Text(description)
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }

      Spacer()
      content()
    }
  }

  private var hintText: String? {
    let hinted = descriptionStyle == .hint ? description : nil
    let parts = [hinted, tooltip].compactMap { $0 }.filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
  }
}

// MARK: - Search Highlight

private struct PreferencesHighlightedSettingKey: EnvironmentKey {
  static let defaultValue: String? = nil
}

extension EnvironmentValues {
  /// Title of the setting row flashing after a Preferences search jump.
  var preferencesHighlightedSetting: String? {
    get { self[PreferencesHighlightedSettingKey.self] }
    set { self[PreferencesHighlightedSettingKey.self] = newValue }
  }
}
