//
//  HistoryContextMenu.swift
//  Snapzy
//
//  Context menu for history items
//

import SnapzyPluginAPI
import SwiftUI

struct HistoryContextMenu: View {
  let record: CaptureHistoryRecord
  @ObservedObject private var manager = HistoryFloatingManager.shared
  @ObservedObject private var pluginHost = PluginHostController.shared

  var body: some View {
    Button("Open in Finder") {
      NSWorkspace.shared.activateFileViewerSelecting([record.fileURL])
    }

    Button("Copy") {
      HistoryWindowController.shared.copyToClipboard([record])
    }

    Button("Edit") {
      HistoryWindowController.shared.openItem(record)
    }

    if CloudManager.shared.isConfigured {
      Button {
        manager.uploadToCloud(record)
      } label: {
        Label(uploadMenuTitle, systemImage: uploadMenuIcon)
      }
      .disabled(manager.cloudUploadState(for: record) != nil)
    }

    PluginCommandMenu(items: pluginCommandItems) { item in
      pluginLauncher.launch(item)
    }

    Divider()

    Button("Delete") {
      HistoryWindowController.shared.deleteRecords([record], asksConfirmation: false)
    }
  }

  private var pluginCommandItems: [PluginCommandItem] {
    let kind: SnapzyDocumentKind = switch record.captureType {
    case .video: .video
    case .gif: .gif
    case .screenshot: .screenshot
    }
    return PluginCommandCatalog.commands(
      pluginHost.snapshots.flatMap(\.contributions),
      for: kind
    )
  }

  private var pluginLauncher: PluginInvocationLauncher {
    let kind: SnapzyDocumentKind = switch record.captureType {
    case .video: .video
    case .gif: .gif
    case .screenshot: .screenshot
    }
    return PluginInvocationLauncher(
      surface: .history,
      documentKind: kind,
      assetURL: record.fileURL,
      document: nil,
      selection: [],
      options: .object([:])
    )
  }

  private var uploadMenuTitle: String {
    switch manager.cloudUploadState(for: record) {
    case .uploading:
      return L10n.PreferencesHistory.uploadingToCloud
    case .completed:
      return L10n.PreferencesHistory.uploadedToCloud
    case nil:
      return L10n.PreferencesHistory.uploadToCloud
    }
  }

  private var uploadMenuIcon: String {
    switch manager.cloudUploadState(for: record) {
    case .uploading:
      return "icloud.and.arrow.up"
    case .completed:
      return "checkmark.icloud"
    case nil:
      return "icloud.and.arrow.up"
    }
  }
}

struct HistoryCloudUploadOverlayView: View {
  let state: HistoryCloudUploadState
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      Rectangle()
        .fill(Color.black.opacity(0.52))

      VStack(spacing: 8) {
        icon

        Text(title)
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
      }
      .padding(.horizontal, 10)
    }
    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
  }

  @ViewBuilder
  private var icon: some View {
    switch state {
    case .uploading:
      ProgressView()
        .progressViewStyle(.circular)
        .controlSize(.small)
        .tint(.white)
    case .completed:
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 26, weight: .semibold))
        .foregroundStyle(.white, Color.green)
    }
  }

  private var title: String {
    switch state {
    case .uploading:
      return L10n.PreferencesHistory.uploadingToCloud
    case .completed:
      return L10n.PreferencesHistory.uploadedToCloud
    }
  }
}
