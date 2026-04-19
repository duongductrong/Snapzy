//
//  VideoEditorToolbarView.swift
//  Snapzy
//
//  Top toolbar for video editor with undo/redo, filename, and save actions
//

import SwiftUI

private enum VideoEditorToolbarSection: Hashable {
  case left
  case right
}

private struct VideoEditorToolbarSectionWidthKey: PreferenceKey {
  static var defaultValue: [VideoEditorToolbarSection: CGFloat] = [:]

  static func reduce(
    value: inout [VideoEditorToolbarSection: CGFloat],
    nextValue: () -> [VideoEditorToolbarSection: CGFloat]
  ) {
    value.merge(nextValue(), uniquingKeysWith: { _, next in next })
  }
}

private extension View {
  func measureVideoEditorToolbarWidth(for section: VideoEditorToolbarSection) -> some View {
    background(
      GeometryReader { proxy in
        Color.clear.preference(
          key: VideoEditorToolbarSectionWidthKey.self,
          value: [section: proxy.size.width]
        )
      }
    )
  }
}

/// Top toolbar for video editor window
struct VideoEditorToolbarView: View {
  @ObservedObject var state: VideoEditorState

  @State private var editingFilename: String = ""
  @State private var renameError: String?
  @State private var leftSectionWidth: CGFloat = 0
  @State private var rightSectionWidth: CGFloat = 0

  var body: some View {
    HStack(spacing: WindowSpacingConfiguration.default.toolbarItemSpacing) {
      leftSection
        .fixedSize(horizontal: true, vertical: false)
        .measureVideoEditorToolbarWidth(for: .left)
        .frame(width: reservedSideWidth, alignment: .leading)
      centerSection
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, WindowSpacingConfiguration.default.toolbarItemSpacing)
      rightSection
        .fixedSize(horizontal: true, vertical: false)
        .measureVideoEditorToolbarWidth(for: .right)
        .frame(width: reservedSideWidth, alignment: .trailing)
    }
    .windowToolbarPadding()
    .onPreferenceChange(VideoEditorToolbarSectionWidthKey.self) { widths in
      leftSectionWidth = widths[.left] ?? 0
      rightSectionWidth = widths[.right] ?? 0
    }
  }

  // MARK: - Left Section

  private var leftSection: some View {
    HStack(spacing: WindowSpacingConfiguration.default.toolbarItemSpacing) {
      // Undo button
      Button(action: { state.undo() }) {
        Image(systemName: "arrow.uturn.backward")
          .font(.system(size: 14))
          .frame(width: 28, height: 28)
          .background(Color.white.opacity(0.1))
          .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      .buttonStyle(.plain)
      .disabled(!state.canUndo)
      .opacity(state.canUndo ? 1 : 0.4)
      .keyboardShortcut("z", modifiers: [.command])
      .help(L10n.VideoEditor.undoShortcutHint)

      // Redo button
      Button(action: { state.redo() }) {
        Image(systemName: "arrow.uturn.forward")
          .font(.system(size: 14))
          .frame(width: 28, height: 28)
          .background(Color.white.opacity(0.1))
          .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      .buttonStyle(.plain)
      .disabled(!state.canRedo)
      .opacity(state.canRedo ? 1 : 0.4)
      .keyboardShortcut("z", modifiers: [.command, .shift])
      .help(L10n.VideoEditor.redoShortcutHint)

      Divider()
        .frame(height: 20)

      // Open in Folder button
      Button(action: { state.openInFinder() }) {
        Image(systemName: "folder")
          .font(.system(size: 14))
          .frame(width: 28, height: 28)
          .background(Color.white.opacity(0.1))
          .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      .buttonStyle(.plain)
      .help(L10n.Common.openInFinder)

      // Video Info button
      Button(action: { state.toggleVideoInfoSidebar() }) {
        Image(systemName: state.isVideoInfoSidebarVisible ? "info.circle.fill" : "info.circle")
          .font(.system(size: 14))
          .foregroundColor(state.isVideoInfoSidebarVisible ? ZoomColors.primary : .primary)
          .frame(width: 28, height: 28)
          .background(state.isVideoInfoSidebarVisible ? ZoomColors.primary.opacity(0.15) : Color.white.opacity(0.1))
          .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      .buttonStyle(.plain)
      .keyboardShortcut("i", modifiers: [])
      .help(state.isVideoInfoSidebarVisible ? L10n.VideoEditor.hideVideoInfoHint : L10n.VideoEditor.showVideoInfoHint)
    }
    .padding(.leading, trafficLightsInsetWidth)
  }

  // MARK: - Center Section

  private var centerSection: some View {
    HStack(spacing: 6) {
      if state.isRenamingFile {
        TextField(L10n.VideoEditor.filenamePlaceholder, text: $editingFilename, onCommit: commitRename)
          .textFieldStyle(.plain)
          .font(.system(size: 13, weight: .medium))
          .frame(width: 200)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(Color.white.opacity(0.1))
          .cornerRadius(6)
          .onAppear {
            editingFilename = filenameWithoutExtension
          }
          .onExitCommand {
            state.isRenamingFile = false
            renameError = nil
          }
      } else {
        Text(state.filename)
          .font(.system(size: 13, weight: .medium))
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(maxWidth: 320)

        Button(action: startRename) {
          Image(systemName: "pencil")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help(L10n.Common.renameFile)
      }

      if let error = renameError {
        Text(error)
          .font(.system(size: 10))
          .foregroundColor(.red)
          .lineLimit(1)
          .truncationMode(.tail)
      }
    }
    .frame(maxWidth: .infinity, alignment: .center)
  }

  // MARK: - Right Section

  private var rightSection: some View {
    HStack(spacing: WindowSpacingConfiguration.default.toolbarItemSpacing) {
      // Right sidebar toggle (video only — zoom/background don't apply to GIF)
      if !state.isGIF {
        Button(action: { state.toggleRightSidebar() }) {
          Image(systemName: "sidebar.right")
            .font(.system(size: 14))
            .foregroundColor(state.isRightSidebarVisible ? ZoomColors.primary : .primary)
            .frame(width: 28, height: 28)
            .background(state.isRightSidebarVisible ? ZoomColors.primary.opacity(0.15) : Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(".", modifiers: [.command])
        .help(state.isRightSidebarVisible ? L10n.VideoEditor.hideSidebarHint : L10n.VideoEditor.showSidebarHint)
      }

      // Unsaved changes indicator (video only)
      if !state.isGIF && state.hasUnsavedChanges {
        Divider()
          .frame(height: 20)

        HStack(spacing: 4) {
          Image(systemName: "circle.fill")
            .font(.system(size: 6))
            .foregroundColor(.orange)
          Text(L10n.Common.unsaved)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
      }
    }
  }

  // MARK: - Helpers

  private var reservedSideWidth: CGFloat {
    max(leftSectionWidth, rightSectionWidth)
  }

  private var trafficLightsInsetWidth: CGFloat {
    let trafficConfig = TrafficLightConfiguration.default
    return trafficConfig.horizontalOffset +
      (3 * 14) +
      (2 * trafficConfig.buttonSpacing) +
      WindowSpacingConfiguration.default.trafficLightsGap
  }

  private var filenameWithoutExtension: String {
    let filename = state.filename
    if let dotIndex = filename.lastIndex(of: ".") {
      return String(filename[..<dotIndex])
    }
    return filename
  }

  private func startRename() {
    editingFilename = filenameWithoutExtension
    renameError = nil
    state.isRenamingFile = true
  }

  private func commitRename() {
    do {
      try state.renameFile(to: editingFilename)
      state.isRenamingFile = false
      renameError = nil
    } catch {
      renameError = error.localizedDescription
    }
  }
}

// MARK: - Preview

#Preview {
  VideoEditorToolbarView(
    state: VideoEditorState(url: URL(fileURLWithPath: "/tmp/test-video.mov"))
  )
  .frame(width: 800)
  .background(Color(NSColor.windowBackgroundColor))
}
