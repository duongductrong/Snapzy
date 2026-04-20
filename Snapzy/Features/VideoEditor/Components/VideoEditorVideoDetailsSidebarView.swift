//
//  VideoDetailsSidebarView.swift
//  Snapzy
//
//  Video details sidebar with comprehensive metadata
//

import SwiftUI

struct VideoDetailsSidebarView: View {
  @ObservedObject var state: VideoEditorState

  private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
  }()

  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: Spacing.md) {
        HStack {
          Image(systemName: "info.circle.fill")
            .foregroundColor(ZoomColors.primary)
          Text(L10n.VideoEditor.videoDetails)
            .font(Typography.sectionHeader)
            .foregroundColor(SidebarColors.labelPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(SidebarColors.itemDefault)
        )

        // File Info Section
        SidebarSection(title: L10n.Common.file) {
          DetailRow(label: L10n.Common.name, value: state.filename)
          DetailRow(label: L10n.Common.path, value: state.sourceURL.deletingLastPathComponent().path)
          DetailRow(label: L10n.Common.size, value: state.fileSizeString)
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
          if let created = state.fileCreationDate {
            DetailRow(label: L10n.Common.created, value: dateFormatter.string(from: created))
          }
          if let modified = state.fileModificationDate {
            DetailRow(label: L10n.Common.modified, value: dateFormatter.string(from: modified))
          }
        }

        // Zoom Summary
        if !state.zoomSegments.isEmpty {
          SidebarSection(title: L10n.VideoEditor.zoomEffects) {
            DetailRow(label: L10n.VideoEditor.segments, value: "\(state.zoomSegments.count)")
            DetailRow(label: L10n.Common.enabled, value: "\(state.zoomSegments.filter { $0.isEnabled }.count)")
          }
        }

        if state.hasMouseTrackingData {
          SidebarSection(title: L10n.VideoEditor.smartCamera) {
            DetailRow(label: L10n.VideoEditor.mouseSamples, value: "\(state.recordingMetadata?.mouseSamples.count ?? 0)")
            DetailRow(label: L10n.VideoEditor.sampleRate, value: "\(state.recordingMetadata?.samplesPerSecond ?? 0) Hz")
            DetailRow(label: L10n.VideoEditor.coordSpace, value: state.recordingMetadata?.coordinateSpace.rawValue ?? "—")
            DetailRow(label: L10n.VideoEditor.autoSegments, value: "\(state.autoZoomSegmentCount)")
            DetailRow(label: L10n.Common.status, value: state.isAutoZoomActiveAtCurrentTime ? L10n.Common.active : L10n.Common.ready)
          }
        }

        Spacer(minLength: Spacing.lg)
      }
      .padding(Spacing.md)
    }
    .frame(maxHeight: .infinity)
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
    }
  }
}
