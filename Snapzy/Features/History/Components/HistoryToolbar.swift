//
//  HistoryToolbar.swift
//  Snapzy
//
//  Top toolbar for the history browser
//

import SwiftUI

struct HistoryToolbar: View {
  @Binding var searchText: String
  let selectedCount: Int
  let canSelectAll: Bool
  let onSelectAll: () -> Void
  let onClearSelection: () -> Void
  let onDeleteSelection: () -> Void

  @AppStorage(PreferencesKeys.historyBackgroundStyle) private var backgroundStyle: HistoryBackgroundStyle = .defaultStyle
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    HStack(spacing: 12) {
      searchBar

      Spacer()

      if selectedCount > 0 {
        selectionControls
      }
    }
  }

  private var searchBar: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.secondary.opacity(0.9))

      TextField("Search by filename", text: $searchText)
        .textFieldStyle(.plain)
        .font(.system(size: 12, weight: .medium))

      if !searchText.isEmpty {
        Button(action: { searchText = "" }) {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary.opacity(0.8))
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .frame(width: 260)
    .background(chromeSurfaceFill, in: Capsule())
    .overlay(
      Capsule()
        .stroke(chromeSurfaceBorder, lineWidth: 1)
    )
    .shadow(color: chromeSurfaceShadow, radius: 7, x: 0, y: 3)
  }

  private var selectionControls: some View {
    HStack(spacing: 10) {
      Label(
        L10n.PreferencesHistory.selectedCaptures(selectedCount),
        systemImage: "checkmark.circle.fill"
      )
      .font(.system(size: 11, weight: .semibold))
      .foregroundColor(.primary.opacity(0.84))

      if canSelectAll {
        selectionButton(
          title: L10n.PreferencesHistory.selectAll,
          systemName: "checkmark.circle",
          action: onSelectAll
        )
      }

      selectionButton(
        title: L10n.PreferencesHistory.clearSelection,
        systemName: "xmark.circle",
        action: onClearSelection
      )

      selectionButton(
        title: L10n.Common.deleteAction,
        systemName: "trash",
        isDestructive: true,
        action: onDeleteSelection
      )
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .background(.ultraThinMaterial, in: Capsule())
    .background(selectionBarTint, in: Capsule())
    .overlay(
      Capsule()
        .stroke(selectionBarBorder, lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.32 : 0.14), radius: 18, x: 0, y: 8)
    .fixedSize(horizontal: true, vertical: false)
  }

  private func selectionButton(
    title: String,
    systemName: String,
    isDestructive: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(role: isDestructive ? .destructive : nil, action: action) {
      Label(title, systemImage: systemName)
        .font(.system(size: 11, weight: .semibold))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
    .buttonStyle(.plain)
    .foregroundColor(isDestructive ? .red : .primary.opacity(0.82))
  }

  private var chromeSurfaceFill: AnyShapeStyle {
    if backgroundStyle == .solid {
      return colorScheme == .dark
        ? AnyShapeStyle(Color.white.opacity(0.07))
        : AnyShapeStyle(Color.white.opacity(0.76))
    }

    return colorScheme == .dark
      ? AnyShapeStyle(Color.white.opacity(0.07))
      : AnyShapeStyle(Color.white.opacity(0.52))
  }

  private var chromeSurfaceBorder: Color {
    colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.64)
  }

  private var chromeSurfaceShadow: Color {
    Color.black.opacity(colorScheme == .dark ? 0.18 : 0.07)
  }

  private var selectionBarTint: Color {
    colorScheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.42)
  }

  private var selectionBarBorder: Color {
    colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.7)
  }
}
