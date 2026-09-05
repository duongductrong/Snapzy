//
//  HistoryExpandedCaptureCardView.swift
//  Snapzy
//
//  Rich card for the expanded floating history browser
//

import SwiftUI

struct HistoryExpandedCaptureCardView: View, Equatable {
  let record: CaptureHistoryRecord
  let isSelected: Bool
  let backgroundStyle: HistoryBackgroundStyle
  let onTap: () -> Void

  static func == (lhs: HistoryExpandedCaptureCardView, rhs: HistoryExpandedCaptureCardView) -> Bool {
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
    VStack(spacing: 8) {
      preview

      VStack(alignment: .leading, spacing: 6) {
        Text(displayTitle)
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.primary)
          .lineLimit(1)
          .truncationMode(.middle)

        Text(relativeTimeString(from: record.capturedAt))
          .font(.system(size: 9.5, weight: .medium))
          .foregroundColor(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(10)
    .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .stroke(cardBorderColor, lineWidth: isSelected ? 1.8 : 1)
    )
    .shadow(color: cardShadowColor, radius: isSelected ? 14 : 3, x: 0, y: isSelected ? 8 : 2)
    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .scaleEffect(isSelected ? 1.01 : (isHovering ? 1.005 : 1))
    .animation(.spring(response: 0.24, dampingFraction: 0.9), value: isSelected)
    .animation(.easeOut(duration: 0.16), value: isHovering)
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
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(previewBackground)

        if isVisible, let thumbnailImage {
          Image(nsImage: thumbnailImage)
            .resizable()
            .scaledToFill()
            .frame(width: geometry.size.width, height: geometry.size.height)
        } else {
          Image(systemName: record.captureType.systemIconName)
            .font(.system(size: 30, weight: .medium))
            .foregroundColor(.secondary.opacity(0.55))
        }

        if !fileExists {
          Rectangle()
            .fill(Color.black.opacity(0.44))

          VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.system(size: 16))
            Text("File missing")
              .font(.caption2.weight(.semibold))
          }
          .foregroundColor(.white)
        }

        if let duration = record.formattedDuration, record.captureType != .screenshot {
          Text(duration)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.7), in: Capsule())
            .foregroundColor(.white)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }

        HStack(spacing: 8) {
          typeBadge
        }
        .padding(8)

        if let uploadState = manager.cloudUploadState(for: record) {
          HistoryCloudUploadOverlayView(state: uploadState)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(previewBorderColor, lineWidth: 1)
      )
    }
    .aspectRatio(16 / 10, contentMode: .fit)
  }

  private var cardBackground: AnyShapeStyle {
    if backgroundStyle == .solid {
      return colorScheme == .dark
        ? AnyShapeStyle(Color.white.opacity(0.08))
        : AnyShapeStyle(Color.white.opacity(0.92))
    }

    return colorScheme == .dark
      ? AnyShapeStyle(Color.white.opacity(0.07))
      : AnyShapeStyle(Color.white.opacity(0.7))
  }

  private var cardBorderColor: Color {
    if isSelected {
      return Color.accentColor.opacity(0.9)
    }

    if isHovering {
      return colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
    }

    return colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.55)
  }

  private var cardShadowColor: Color {
    if isSelected {
      return Color.black.opacity(colorScheme == .dark ? 0.28 : 0.14)
    }

    return Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08)
  }

  private var previewBackground: Color {
    colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.9)
  }

  private var previewBorderColor: Color {
    return colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
  }

  private var typeBadge: some View {
    Image(systemName: record.captureType.systemIconName)
      .font(.system(size: 10, weight: .semibold))
      .foregroundColor(.primary.opacity(0.82))
      .frame(width: 24, height: 24)
      .background(.regularMaterial, in: Circle())
      .overlay(
        Circle()
          .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.55), lineWidth: 1)
      )
  }

  private func relativeTimeString(from date: Date) -> String {
    HistoryFormatterCache.relativeShort.localizedString(for: date, relativeTo: Date())
  }

  private var displayTitle: String {
    let title = record.fileURL.deletingPathExtension().lastPathComponent
    return title.isEmpty ? record.fileName : title
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

  private func openDefaultEditor() {
    guard fileExists else { return }
    HistoryWindowController.shared.openItem(record)
  }
}
