//
//  VideoEditorToolbarView.swift
//  Snapzy
//
//  Top toolbar for video editor with undo/redo, filename, and save actions
//

import SnapzyPluginAPI
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
  @ObservedObject private var pluginHost = PluginHostController.shared

  private var pluginCommandItems: [PluginCommandItem] {
    PluginCommandCatalog.commands(
      pluginHost.snapshots.flatMap(\.contributions),
      for: state.isGIF ? .gif : .video
    )
  }

  private var pluginLauncher: PluginInvocationLauncher {
    PluginInvocationLauncher(
      surface: .videoEditor,
      documentKind: state.isGIF ? .gif : .video,
      assetURL: state.sourceURL,
      document: nil,
      selection: [],
      options: .object([:])
    )
  }

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
      undoRedoGroup

      ToolbarDivider()

      if !state.isGIF {
        leftSidebarToggleButton

        ToolbarDivider()
      }

      fileActionsGroup
    }
    .padding(.leading, trafficLightsInsetWidth)
  }

  private var undoRedoGroup: some View {
    HStack(spacing: 4) {
      ToolbarButton(icon: "arrow.uturn.backward", isSelected: false) {
        state.undo()
      }
      .disabled(!state.canUndo)
      .opacity(state.canUndo ? 1 : 0.4)
      .keyboardShortcut("z", modifiers: [.command])
      .help(L10n.VideoEditor.undoShortcutHint)

      ToolbarButton(icon: "arrow.uturn.forward", isSelected: false) {
        state.redo()
      }
      .disabled(!state.canRedo)
      .opacity(state.canRedo ? 1 : 0.4)
      .keyboardShortcut("z", modifiers: [.command, .shift])
      .help(L10n.VideoEditor.redoShortcutHint)
    }
  }

  private var fileActionsGroup: some View {
    HStack(spacing: 4) {
      ToolbarButton(icon: "folder", isSelected: false) {
        state.openInFinder()
      }
      .help(L10n.Common.openInFinder)

      // Plugin commands for the open video/GIF.
      if !pluginCommandItems.isEmpty {
        Menu {
          ForEach(pluginCommandItems) { item in
            Button {
              pluginLauncher.launch(item)
            } label: {
              Label(item.title, systemImage: item.systemImage)
            }
            .disabled(item.disabledReason != nil)
          }
        } label: {
          Image(systemName: "puzzlepiece.extension")
            .frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Plugins")
      }

      ToolbarButton(
        icon: "info.circle",
        selectedIcon: "info.circle.fill",
        isSelected: state.isVideoInfoSidebarVisible,
        highlightColor: ZoomColors.primary
      ) {
        state.toggleVideoInfoSidebar()
      }
      .keyboardShortcut("i", modifiers: [])
      .help(state.isVideoInfoSidebarVisible ? L10n.VideoEditor.hideVideoInfoHint : L10n.VideoEditor.showVideoInfoHint)
      .popover(isPresented: $state.isVideoInfoSidebarVisible, arrowEdge: .bottom) {
        VideoDetailsSidebarView(state: state)
          .frame(width: 320)
          .frame(height: 380)
      }
    }
  }

  private var leftSidebarToggleButton: some View {
    ToolbarButton(
      icon: "rectangle.on.rectangle",
      isSelected: state.isLeftSidebarVisible,
      highlightColor: ZoomColors.primary
    ) {
      state.toggleLeftSidebar()
    }
    .keyboardShortcut("b", modifiers: [.command])
    .help(state.isLeftSidebarVisible ? L10n.VideoEditor.hideLeftSidebarHint : L10n.VideoEditor.showLeftSidebarHint)
  }

  private var rightSidebarToggleButton: some View {
    ToolbarButton(
      icon: "sidebar.right",
      isSelected: state.isRightSidebarVisible,
      highlightColor: ZoomColors.primary
    ) {
      state.toggleRightSidebar()
    }
    .keyboardShortcut("b", modifiers: [.command, .shift])
    .help(state.isRightSidebarVisible ? L10n.VideoEditor.hideRightSidebarHint : L10n.VideoEditor.showRightSidebarHint)
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
          .background(Color.primary.opacity(0.08))
          .clipShape(RoundedRectangle(cornerRadius: 6))
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

        ToolbarButton(
          icon: "pencil",
          isSelected: false
        ) {
          startRename()
        }
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
      if !state.isGIF {
        rightSidebarToggleButton
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
