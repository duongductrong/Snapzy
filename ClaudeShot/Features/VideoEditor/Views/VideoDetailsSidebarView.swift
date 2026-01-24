//
//  VideoDetailsSidebarView.swift
//  ClaudeShot
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
      VStack(alignment: .leading, spacing: 16) {
        // Header
        HStack {
          Image(systemName: "info.circle.fill")
            .foregroundColor(ZoomColors.primary)
          Text("Video Details")
            .font(.system(size: 13, weight: .semibold))
        }

        Divider()

        // File Info Section
        SidebarSection(title: "File") {
          DetailRow(label: "Name", value: state.filename)
          DetailRow(label: "Path", value: state.sourceURL.deletingLastPathComponent().path)
          DetailRow(label: "Size", value: state.fileSizeString)
          DetailRow(label: "Format", value: state.fileExtension.uppercased())
        }

        // Video Info Section
        SidebarSection(title: "Video") {
          DetailRow(label: "Resolution", value: state.resolutionString)
          DetailRow(label: "Aspect Ratio", value: state.aspectRatioString)
          DetailRow(label: "Duration", value: state.formattedDuration)
        }

        // Dates Section
        SidebarSection(title: "Dates") {
          if let created = state.fileCreationDate {
            DetailRow(label: "Created", value: dateFormatter.string(from: created))
          }
          if let modified = state.fileModificationDate {
            DetailRow(label: "Modified", value: dateFormatter.string(from: modified))
          }
        }

        // Zoom Summary
        if !state.zoomSegments.isEmpty {
          SidebarSection(title: "Zoom Effects") {
            DetailRow(label: "Segments", value: "\(state.zoomSegments.count)")
            DetailRow(label: "Enabled", value: "\(state.zoomSegments.filter { $0.isEnabled }.count)")
          }
        }

        Spacer(minLength: 20)
      }
      .padding(12)
    }
    .frame(maxHeight: .infinity)
    .background(Color(NSColor.controlBackgroundColor))
  }
}

// MARK: - Components

private struct SidebarSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(.secondary)
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
        .font(.system(size: 11))
        .foregroundColor(.secondary)
      Spacer()
      Text(value)
        .font(.system(size: 11))
        .foregroundColor(.primary)
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }
}
