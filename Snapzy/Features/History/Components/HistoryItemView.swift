//
//  HistoryItemView.swift
//  Snapzy
//
//  Individual cell in the capture history grid
//

import SwiftUI

struct HistoryItemView: View {
  let record: CaptureHistoryRecord
  let isSelected: Bool
  let onSelect: () -> Void

  @State private var thumbnailImage: NSImage?
  @State private var isHovering = false
  @State private var fileExists: Bool = true

  var body: some View {
    VStack(spacing: 6) {
      // Thumbnail
      GeometryReader { geometry in
        ZStack {
          RoundedRectangle(cornerRadius: 8)
            .fill(Color.secondary.opacity(0.1))

          if let image = thumbnailImage {
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
      .task(id: record.thumbnailPath ?? record.id.uuidString) {
        await loadThumbnail()
        checkFileExistence()
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

  private func loadThumbnail() async {
    // Check cache first (with sandbox access)
    let scopedAccess = SandboxFileAccessManager.shared.beginAccessingURL(record.fileURL)
    defer { scopedAccess.stop() }

    if let cachedURL = HistoryThumbnailGenerator.shared.thumbnailURL(for: record),
      let image = NSImage(contentsOf: cachedURL) {
      thumbnailImage = image
      return
    }

    // Generate lazily
    if let url = await HistoryThumbnailGenerator.shared.generate(for: record),
      let image = NSImage(contentsOf: url) {
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
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
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
    // Move file to trash if it exists
    if fileExists {
      try? NSWorkspace.shared.recycle([record.fileURL])
    }
    // Remove from history
    CaptureHistoryStore.shared.remove(id: record.id)
    // Clean up thumbnail
    HistoryThumbnailGenerator.shared.deleteThumbnail(for: record.id)
  }
}
