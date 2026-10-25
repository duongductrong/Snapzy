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

  var body: some View {
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
