//
//  HistoryItemView.swift
//  Snapzy
//
//  Individual cell in the capture history grid
//

import SwiftUI

struct HistoryItemView: View, Equatable {
  let record: CaptureHistoryRecord
  let isSelected: Bool
  let onSelect: () -> Void

  static func == (lhs: HistoryItemView, rhs: HistoryItemView) -> Bool {
    lhs.record == rhs.record &&
    lhs.isSelected == rhs.isSelected &&
    HistoryFloatingManager.shared.cloudUploadState(for: lhs.record) == HistoryFloatingManager.shared.cloudUploadState(for: rhs.record)
  }

  @ObservedObject private var manager = HistoryFloatingManager.shared
  @State private var thumbnailImage: NSImage?
  @State private var isHovering = false
  @State private var fileExists: Bool = true
  @State private var isVisible = false
  @State private var thumbnailReloadToken = 0

  var body: some View {
    VStack(spacing: 6) {
      // Thumbnail
      GeometryReader { geometry in
        ZStack {
          RoundedRectangle(cornerRadius: 8)
            .fill(Color.secondary.opacity(0.1))

          if isVisible, let image = thumbnailImage {
            Image(nsImage: image)
              .resizable()
              .scaledToFill()
              .frame(width: geometry.size.width, height: geometry.size.height)
          } else {
            Image(systemName: iconName)
              .font(.system(size: 32))
              .foregroundColor(.secondary)
          }

          // Missing file overlay
          if !fileExists {
            Rectangle()
              .fill(Color.black.opacity(0.5))
            VStack(spacing: 4) {
              Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 16))
              Text("File missing")
                .font(.caption)
            }
            .foregroundColor(.white)
          }

          // Hover overlay with actions
          if isHovering {
            Rectangle()
              .fill(Color.black.opacity(0.4))

            HStack(spacing: 12) {
              Button(action: { copyFile() }) {
                Image(systemName: "doc.on.doc")
                  .font(.system(size: 14, weight: .medium))
              }
              .buttonStyle(PlainButtonStyle())
              .foregroundColor(.white)

              Button(action: { openInFinder() }) {
                Image(systemName: "folder")
                  .font(.system(size: 14, weight: .medium))
              }
              .buttonStyle(PlainButtonStyle())
              .foregroundColor(.white)

              Button(action: { deleteRecord() }) {
                Image(systemName: "trash")
                  .font(.system(size: 14, weight: .medium))
              }
              .buttonStyle(PlainButtonStyle())
              .foregroundColor(.white)
            }
          }

          // Duration badge for videos
          if let duration = record.formattedDuration, record.captureType != .screenshot {
            VStack {
              Spacer()
              HStack {
                Spacer()
                Text(duration)
                  .font(.caption2)
                  .fontWeight(.medium)
                  .padding(.horizontal, 6)
                  .padding(.vertical, 2)
                  .background(Color.black.opacity(0.7))
                  .foregroundColor(.white)
                  .clipShape(Capsule())
                  .padding(4)
              }
            }
          }

          if let uploadState = manager.cloudUploadState(for: record) {
            HistoryCloudUploadOverlayView(state: uploadState)
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .aspectRatio(1.0, contentMode: .fit)
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
      )
      .onHover { hovering in
        withAnimation(.easeInOut(duration: 0.1)) {
          isHovering = hovering
        }
      }
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
      // Filename
      Text(record.fileName)
        .font(.caption)
        .lineLimit(1)
        .truncationMode(.middle)
        .frame(maxWidth: .infinity, alignment: .leading)

      // Metadata
      HStack {
        Text(relativeTimeString(from: record.capturedAt))
          .font(.caption2)
          .foregroundColor(.secondary)
        Spacer()
        Text(record.formattedFileSize)
          .font(.caption2)
          .foregroundColor(.secondary)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      onSelect()
    }
    .simultaneousGesture(
      TapGesture(count: 2).onEnded {
        openDefaultEditor()
      }
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
    HistoryFormatterCache.relativeShort.localizedString(for: date, relativeTo: Date())
  }

  private func openDefaultEditor() {
    guard fileExists else { return }
    HistoryWindowController.shared.openItem(record)
  }

  private func copyFile() {
    HistoryWindowController.shared.copyToClipboard([record])
  }

  private func openInFinder() {
    NSWorkspace.shared.activateFileViewerSelecting([record.fileURL])
  }

  private func deleteRecord() {
    HistoryWindowController.shared.deleteRecords([record], asksConfirmation: false)
  }
}
