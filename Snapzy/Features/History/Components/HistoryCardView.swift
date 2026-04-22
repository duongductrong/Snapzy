//
//  HistoryCardView.swift
//  Snapzy
//
//  Refined preview card for the floating history panel
//

import SwiftUI

struct HistoryCardView: View {
  let record: CaptureHistoryRecord
  let isSelected: Bool
  let onTap: () -> Void

  @AppStorage(PreferencesKeys.historyBackgroundStyle) private var backgroundStyle: HistoryBackgroundStyle = .defaultStyle
  @Environment(\.colorScheme) private var colorScheme
  @State private var thumbnailImage: NSImage?
  @State private var isHovering = false
  @State private var fileExists = true

  var body: some View {
    VStack(spacing: 10) {
      preview

      if isSelected && fileExists {
        restoreButton
          .padding(.top, -2)
      }

      Text(relativeTimeString(from: record.capturedAt))
        .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
        .foregroundColor(timeLabelColor)
        .frame(maxWidth: .infinity, alignment: .center)
    }
    .contentShape(Rectangle())
    .scaleEffect(isSelected ? 1.02 : (isHovering ? 1.01 : 1))
    .animation(.spring(response: 0.24, dampingFraction: 0.88), value: isSelected)
    .animation(.easeOut(duration: 0.18), value: isHovering)
    .onHover { hovering in
      isHovering = hovering
    }
    .onTapGesture {
      onTap()
    }
    .simultaneousGesture(
      TapGesture(count: 2).onEnded {
        openDefaultEditor()
      }
    )
    .task(id: record.thumbnailPath ?? record.id.uuidString) {
      await loadThumbnail()
      checkFileExistence()
    }
  }

  private var preview: some View {
    GeometryReader { geometry in
      ZStack(alignment: .bottomTrailing) {
        cardShape
          .fill(cardBackground)

        if let image = thumbnailImage {
          Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: geometry.size.width, height: geometry.size.height)
        } else {
          Image(systemName: iconName)
            .font(.system(size: 30, weight: .medium))
            .foregroundColor(.secondary.opacity(0.55))
        }

        if !fileExists {
          Rectangle()
            .fill(Color.black.opacity(0.4))

          VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.system(size: 16))
            Text("File missing")
              .font(.caption2.weight(.semibold))
          }
          .foregroundColor(.white)
        }

        if let duration = record.formattedDuration, record.captureType != .screenshot {
          VStack {
            HStack {
              Text(duration)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.68))
                .foregroundColor(.white)
                .clipShape(Capsule())
              Spacer()
            }
            Spacer()
          }
          .padding(10)
        }

        typeBadge
          .padding(10)
      }
      .clipShape(cardShape)
      .overlay(cardShape.stroke(cardBorderColor, lineWidth: isSelected ? 3 : 1.2))
      .shadow(color: cardShadowColor, radius: isSelected ? 18 : 12, x: 0, y: isSelected ? 8 : 6)
    }
    .aspectRatio(16.0 / 10.0, contentMode: .fit)
  }

  private var restoreButton: some View {
    Button(action: openDefaultEditor) {
      Label(L10n.Common.restore, systemImage: "arrow.uturn.backward")
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
          Capsule()
            .fill(
              LinearGradient(
                colors: [
                  Color.accentColor.opacity(0.98),
                  Color.accentColor.opacity(0.82),
                ],
                startPoint: .top,
                endPoint: .bottom
              )
            )
        )
    }
    .buttonStyle(.plain)
  }

  private var cardShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: 18, style: .continuous)
  }

  private var cardBackground: some ShapeStyle {
    if backgroundStyle == .solid {
      return colorScheme == .dark
        ? AnyShapeStyle(Color.white.opacity(0.1))
        : AnyShapeStyle(Color.white.opacity(0.96))
    }

    return colorScheme == .dark
      ? AnyShapeStyle(Color.white.opacity(0.08))
      : AnyShapeStyle(Color.white.opacity(0.88))
  }

  private var cardBorderColor: Color {
    if isSelected {
      return Color.accentColor.opacity(0.95)
    }

    if isHovering {
      return colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.08)
    }

    if backgroundStyle == .solid {
      return colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)
    }

    return Color.clear
  }

  private var cardShadowColor: Color {
    if isSelected {
      return Color.black.opacity(colorScheme == .dark ? 0.28 : 0.12)
    }

    if isHovering {
      return Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08)
    }

    if backgroundStyle == .solid {
      return Color.black.opacity(colorScheme == .dark ? 0.16 : 0.07)
    }

    return Color.clear
  }

  private var timeLabelColor: Color {
    colorScheme == .dark ? .white.opacity(0.82) : .primary.opacity(0.7)
  }

  private var typeBadge: some View {
    Image(systemName: iconName)
      .font(.system(size: 11, weight: .semibold))
      .foregroundColor(.primary.opacity(0.78))
      .frame(width: 30, height: 30)
      .background(.regularMaterial)
      .clipShape(Circle())
      .overlay(
        Circle()
          .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.6), lineWidth: 1)
      )
  }

  private var iconName: String {
    record.captureType.systemIconName
  }

  private func loadThumbnail() async {
    let scopedAccess = SandboxFileAccessManager.shared.beginAccessingURL(record.fileURL)
    defer { scopedAccess.stop() }

    if let cachedURL = HistoryThumbnailGenerator.shared.thumbnailURL(for: record),
      let image = NSImage(contentsOf: cachedURL)
    {
      thumbnailImage = image
      return
    }

    if let url = await HistoryThumbnailGenerator.shared.generate(for: record),
      let image = NSImage(contentsOf: url)
    {
      thumbnailImage = image
    }
  }

  private func checkFileExistence() {
    let scopedAccess = SandboxFileAccessManager.shared.beginAccessingURL(record.fileURL)
    defer { scopedAccess.stop() }
    fileExists = FileManager.default.fileExists(atPath: record.filePath)
  }

  private func relativeTimeString(from date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: Date())
  }

  private func openDefaultEditor() {
    guard fileExists else { return }
    HistoryWindowController.shared.openItem(record)
  }
}
