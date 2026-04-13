//
//  ShortcutOverlayView.swift
//  Snapzy
//
//  Full-screen shortcut list overlay with dimmed background.
//

import SwiftUI

struct ShortcutOverlayView: View {
  let sections: [ShortcutOverlaySection]
  let onClose: () -> Void
  let onOpenSettings: () -> Void

  var body: some View {
    ZStack {
      Color.black.opacity(0.42)
        .ignoresSafeArea()
        .onTapGesture(perform: onClose)

      VStack(spacing: 0) {
        header

        Divider()
          .opacity(0.22)

        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            ForEach(sections) { section in
              sectionView(section)
            }
          }
          .padding(20)
        }
        .frame(maxHeight: 520)

        Divider()
          .opacity(0.22)

        footer
      }
      .frame(width: 760)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(Color.primary.opacity(0.08), lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
      .padding(24)
      .onTapGesture {}  // Consume taps to prevent dismiss when interacting with card
    }
  }

  private var header: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text(L10n.ShortcutOverlay.title)
          .font(.system(size: 20, weight: .semibold))
        Text(L10n.ShortcutOverlay.subtitle)
          .font(.system(size: 12))
          .foregroundColor(.secondary)
      }

      Spacer()

      Button {
        onClose()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 18))
          .foregroundColor(.secondary.opacity(0.85))
      }
      .buttonStyle(.plain)
      .help(L10n.ShortcutOverlay.closeHelp)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
  }

  private var footer: some View {
    HStack {
      Button(L10n.ShortcutOverlay.customizeInSettings) {
        onOpenSettings()
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)

      Spacer()

      Button(L10n.Common.close) {
        onClose()
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
  }

  private func sectionView(_ section: ShortcutOverlaySection) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(section.title.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(.secondary)
        .tracking(1.1)

      VStack(spacing: 0) {
        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
          rowView(item)
          if index < section.items.count - 1 {
            Divider()
              .opacity(0.12)
              .padding(.leading, 34)
          }
        }
      }
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color.primary.opacity(0.035))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(Color.primary.opacity(0.06), lineWidth: 1)
      )
    }
  }

  private func rowView(_ item: ShortcutOverlayItem) -> some View {
    HStack(spacing: 10) {
      Image(systemName: item.icon)
        .font(.system(size: 14))
        .foregroundColor(.secondary)
        .frame(width: 18)

      VStack(alignment: .leading, spacing: 2) {
        Text(item.title)
          .font(.system(size: 13, weight: .medium))
        if let subtitle = item.subtitle {
          Text(subtitle)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
      }

      Spacer()

      if !item.isEnabled {
        Text(L10n.Common.off)
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Capsule().fill(Color.secondary.opacity(0.15)))
      }

      displayView(item.display)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .opacity(item.isEnabled ? 1 : 0.62)
  }

  @ViewBuilder
  private func displayView(_ display: ShortcutOverlayItem.ShortcutDisplay) -> some View {
    switch display {
    case .keycaps(let parts):
      KeyCapGroupView(parts: parts)
    case .text(let text):
      Text(text)
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.secondary.opacity(0.12))
        )
    }
  }
}

#Preview {
  ShortcutOverlayView(
    sections: ShortcutOverlayContentBuilder.buildSections(),
    onClose: {},
    onOpenSettings: {}
  )
}
