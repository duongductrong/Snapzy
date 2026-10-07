//
//  HistoryExpandedCaptureCardView.swift
//  Snapzy
//
//  Rich card for the expanded floating history browser
//

import SwiftUI

enum HistoryExpandedCardEmphasisMode: Equatable {
  case selection
  case focus
}

struct HistoryExpandedCaptureCardView: View, Equatable {
  let record: CaptureHistoryRecord
  let isSelected: Bool
  let isFocused: Bool
  let emphasisMode: HistoryExpandedCardEmphasisMode
  let backgroundStyle: HistoryBackgroundStyle
  let onTap: () -> Void
  let reservedScrollAxis: QuickAccessDragScrollAxis?

  static func == (lhs: HistoryExpandedCaptureCardView, rhs: HistoryExpandedCaptureCardView) -> Bool {
    lhs.record == rhs.record &&
    lhs.isSelected == rhs.isSelected &&
    lhs.isFocused == rhs.isFocused &&
    lhs.emphasisMode == rhs.emphasisMode &&
    lhs.reservedScrollAxis == rhs.reservedScrollAxis &&
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
    .background(cardBackground, in: Radius.rect(Radius.card))
    .overlay(
      Radius.rect(Radius.card)
        .stroke(
          cardBorderColor,
          lineWidth: isSelected || isFocused
            ? HistoryCardEmphasis.activeBorderWidth
            : HistoryCardEmphasis.inactiveBorderWidth
        )
    )
    .overlay(historyDragInteractionBridge)
    .shadow(
      color: cardShadowColor,
      radius: isEmphasized
        ? HistoryCardEmphasis.activeShadowRadius
        : HistoryCardEmphasis.inactiveShadowRadius,
      x: 0,
      y: isEmphasized
        ? HistoryCardEmphasis.activeShadowYOffset
        : HistoryCardEmphasis.inactiveShadowYOffset
    )
    .contentShape(Radius.rect(Radius.card))
    .scaleEffect(
      isEmphasized
        ? HistoryCardEmphasis.activeScale
        : (isHovering ? HistoryCardEmphasis.expandedHoverScale : 1)
    )
    .offset(y: emphasisMode == .focus && isFocused ? HistoryCardEmphasis.focusedLiftOffset : 0)
    .animation(
      .spring(
        response: HistoryCardEmphasis.springResponse,
        dampingFraction: HistoryCardEmphasis.springDampingFraction
      ),
      value: isEmphasized
    )
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
        Radius.rect(Radius.tile)
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
            Text(L10n.PreferencesHistory.fileMissing)
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
      .clipShape(Radius.rect(Radius.tile))
      .overlay(
        Radius.rect(Radius.tile)
          .stroke(previewBorderColor, lineWidth: 1)
      )
    }
    .aspectRatio(16 / 10, contentMode: .fit)
  }

  private var historyDragInteractionBridge: some View {
    HistoryCardDragInteractionView(
      record: record,
      thumbnail: thumbnailImage,
      isEnabled: fileExists,
      reservedScrollAxis: reservedScrollAxis
    )
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
    if isSelected || isFocused {
      return Color.accentColor.opacity(0.95)
    }

    if isHovering {
      return colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
    }

    return colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.55)
  }

  private var cardShadowColor: Color {
    HistoryCardEmphasis.shadowColor(
      isActive: isEmphasized,
      isHovering: isHovering,
      backgroundStyle: backgroundStyle,
      colorScheme: colorScheme
    )
  }

  private var isEmphasized: Bool {
    switch emphasisMode {
    case .selection:
      return isSelected
    case .focus:
      return isFocused
    }
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
    let access = SandboxFileAccessManager.shared.beginAccessingURL(url)
    Task { @MainActor in
      let exists = await Task.detached(priority: .utility) {
        defer { access.stop() }
        return FileManager.default.fileExists(atPath: path)
      }.value
      guard !Task.isCancelled else { return }
      fileExists = exists
    }
  }

  private func openDefaultEditor() {
    guard fileExists else { return }
    HistoryWindowController.shared.openItem(record)
  }
}
