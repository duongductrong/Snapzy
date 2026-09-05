//
//  HistoryCardView.swift
//  Snapzy
//
//  Refined preview card for the floating history panel
//

import SwiftUI

struct HistoryCardView: View, Equatable {
  let record: CaptureHistoryRecord
  let isSelected: Bool
  let onTap: () -> Void

  let backgroundStyle: HistoryBackgroundStyle

  static func == (lhs: HistoryCardView, rhs: HistoryCardView) -> Bool {
    lhs.record == rhs.record &&
    lhs.isSelected == rhs.isSelected &&
    lhs.backgroundStyle == rhs.backgroundStyle &&
    HistoryFloatingManager.shared.cloudUploadState(for: lhs.record) == HistoryFloatingManager.shared.cloudUploadState(for: rhs.record)
  }

  @ObservedObject private var manager = HistoryFloatingManager.shared
  @Environment(\.colorScheme) private var colorScheme
  @State private var thumbnailImage: NSImage?
  @State private var isHovering = false
  @State private var fileExists = true
  @State private var isVisible = false
  @State private var thumbnailReloadToken = 0

  var body: some View {
    VStack(spacing: 10) {
      preview

      if isSelected && fileExists {
        restoreButton
          .padding(.top, -2)
      }

      Text(relativeTimeString(from: record.capturedAt))
        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
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
    .onAppear {
      isVisible = true
      checkFileExistence()
    }
    .onDisappear {
      isVisible = false
    }
    .task(id: thumbnailTaskID, priority: .utility) {
      guard isVisible else { return }
      await loadThumbnail()
    }
    .onReceive(NotificationCenter.default.publisher(for: .captureHistoryFileDidChange)) { notification in
      guard matchesHistoryFileChange(notification) else { return }
      thumbnailImage = nil
      checkFileExistence()
      thumbnailReloadToken += 1
    }
  }

  private var preview: some View {
    GeometryReader { geometry in
      ZStack(alignment: .bottomTrailing) {
        cardShape
          .fill(cardBackground)

        if isVisible, let image = thumbnailImage {
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

        if let uploadState = manager.cloudUploadState(for: record) {
          HistoryCloudUploadOverlayView(state: uploadState)
        }
      }
      .clipShape(cardShape)
      .overlay(cardShape.stroke(cardBorderColor, lineWidth: isSelected ? 3 : 1.2))
      .shadow(color: cardShadowColor, radius: isSelected ? 18 : 3, x: 0, y: isSelected ? 8 : 2)
    }
    .aspectRatio(16.0 / 10.0, contentMode: .fit)
  }

  private var restoreButton: some View {
    Button(action: openDefaultEditor) {
      Label(L10n.Common.restore, systemImage: "arrow.uturn.backward")
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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

  @MainActor
  private func loadThumbnail() async {
    let image = await HistoryThumbnailGenerator.shared.loadThumbnailImage(for: record)
    guard !Task.isCancelled else { return }
    thumbnailImage = image
  }

  private var thumbnailTaskID: String {
    let id = record.thumbnailPath ?? record.id.uuidString
    return isVisible ? "\(id)-\(thumbnailReloadToken)" : "hidden-\(record.id.uuidString)"
  }

  private func matchesHistoryFileChange(_ notification: Notification) -> Bool {
    if let recordIDs = notification.userInfo?["recordIDs"] as? [UUID],
       recordIDs.contains(record.id) {
      return true
    }

    return (notification.userInfo?["filePath"] as? String) == record.filePath
  }

  private func checkFileExistence() {
    let url = record.fileURL
    let path = record.filePath
    Task.detached(priority: .utility) {
      let exists = await MainActor.run {
        SandboxFileAccessManager.shared.withScopedAccess(to: url) {
          FileManager.default.fileExists(atPath: path)
        }
      }
      await MainActor.run {
        self.fileExists = exists
      }
    }
  }

  private func relativeTimeString(from date: Date) -> String {
    HistoryFormatterCache.relativeFull.localizedString(for: date, relativeTo: Date())
  }

  private func openDefaultEditor() {
    guard fileExists else { return }
    HistoryWindowController.shared.openItem(record)
  }
}
