//
//  VideoEditorVideoDetailsSidebarView.swift
//  Snapzy
//
//  Video details sidebar with comprehensive metadata
//

import SwiftUI

struct VideoDetailsSidebarView: View {
  @ObservedObject var state: VideoEditorState

  /// Shared: a `DateFormatter` per view init is expensive, and this struct is rebuilt on
  /// every editor state change while the popover is open.
  private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
  }()

  private var dateFormatter: DateFormatter { Self.dateFormatter }

  /// File-system reads (sandbox access + `attributesOfItem`) happen once when the details
  /// open, not on every body evaluation.
  private struct FileFacts: Equatable {
    var size = "—"
    var created: Date?
    var modified: Date?
  }

  @State private var fileFacts = FileFacts()

  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: Spacing.md) {
        HStack {
          Image(systemName: "info.circle.fill")
            .foregroundColor(ZoomColors.primary)
          Text(L10n.VideoEditor.videoDetails)
            .font(Typography.sectionHeader)
            .foregroundColor(SidebarColors.labelPrimary)

          Spacer()

          Button {
            state.isVideoInfoSidebarVisible = false
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 10, weight: .semibold))
              .foregroundColor(SidebarColors.labelSecondary)
              .frame(width: 16, height: 16)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }

        Divider()

        // File Info Section
        SidebarSection(title: L10n.Common.file) {
          DetailRow(label: L10n.Common.name, value: state.filename)
          DetailRow(label: L10n.Common.path, value: state.sourceURL.deletingLastPathComponent().path)
          DetailRow(label: L10n.Common.size, value: fileFacts.size)
          DetailRow(label: L10n.Common.format, value: state.fileExtension.uppercased())
        }

        // Video Info Section
        SidebarSection(title: L10n.Common.video) {
          DetailRow(label: L10n.Common.resolution, value: state.resolutionString)
          DetailRow(label: L10n.VideoEditor.aspectRatio, value: state.aspectRatioString)
          DetailRow(label: L10n.Common.duration, value: state.formattedDuration)
        }

        // Dates Section
        SidebarSection(title: L10n.Common.dates) {
          if let created = fileFacts.created {
            DetailRow(label: L10n.Common.created, value: dateFormatter.string(from: created))
          }
          if let modified = fileFacts.modified {
            DetailRow(label: L10n.Common.modified, value: dateFormatter.string(from: modified))
          }
        }

        // Zoom Summary
        if !state.zoomSegments.isEmpty {
          SidebarSection(title: L10n.VideoEditor.zoomEffects) {
            DetailRow(label: L10n.VideoEditor.segments, value: "\(state.zoomSegments.count)")
            DetailRow(label: L10n.Common.enabled, value: "\(state.zoomSegments.filter(\.isEnabled).count)")
          }
        }

        if state.hasMouseTrackingData {
          SidebarSection(title: L10n.VideoEditor.smartCamera) {
            DetailRow(
              label: L10n.VideoEditor.mouseSamples,
              value: "\(state.recordingMetadata?.mouseSamples.count ?? 0)"
            )
            DetailRow(label: L10n.VideoEditor.sampleRate, value: "\(state.recordingMetadata?.samplesPerSecond ?? 0) Hz")
            DetailRow(
              label: L10n.VideoEditor.coordSpace,
              value: state.recordingMetadata?.coordinateSpace.rawValue ?? "—"
            )
            DetailRow(label: L10n.VideoEditor.autoSegments, value: "\(state.autoZoomSegmentCount)")
            DetailRow(
              label: L10n.Common.status,
              value: state.isAutoZoomActiveAtCurrentTime ? L10n.Common.active : L10n.Common.ready
            )
          }
        }

        Spacer(minLength: Spacing.lg)
      }
      .padding(Spacing.md)
    }
    .frame(maxHeight: .infinity)
    // Re-read when the file can have changed: a new source, or a save that replaced it.
    .onAppear { refreshFileFacts() }
    .onChange(of: state.sourceURL) { _ in refreshFileFacts() }
    .onChange(of: state.hasUnsavedChanges) { _ in refreshFileFacts() }
  }

  private func refreshFileFacts() {
    let facts = FileFacts(
      size: state.fileSizeString,
      created: state.fileCreationDate,
      modified: state.fileModificationDate
    )
    if fileFacts != facts { fileFacts = facts }
  }
}

// MARK: - Components

private struct SidebarSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(title)
        .font(Typography.labelSmall)
        .foregroundColor(SidebarColors.labelSecondary)
        .textCase(.uppercase)
      content
    }
  }
}

private struct DetailRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack {
      Text(label)
        .font(Typography.labelMedium)
        .foregroundColor(SidebarColors.labelSecondary)
      Spacer()
      Text(value)
        .font(Typography.labelMedium)
        .foregroundColor(SidebarColors.labelPrimary)
        .lineLimit(1)
        .truncationMode(.middle)
        .help(value)
    }
  }
}
