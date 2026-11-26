//
//  VideoEditorToolbarView.swift
//  Snapzy
//
//  Top toolbar for video editor with undo/redo, filename, and save actions
//

import AppKit
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
  /// Not observed: the toolbar follows `aiChrome`, so typing in the prompt doesn't re-render it.
  private let agent: VideoEditorAgentController

  /// A run holds the timeline: everything but the AI toggle stands down.
  var isAuthoringLocked: Bool
  var aiChrome: VideoEditorAgentController.Chrome
  /// The toggle belongs to the sidebar; the dock has its own orb over the player.
  var aiLayout: VideoEditorAILayout
  private static let emptyProjectContext = VideoEditorProjectContext()

  @ObservedObject private var projectContext: VideoEditorProjectContext
  var onSaveProject: (() -> Void)?
  var onSaveProjectAs: (() -> Void)?
  var onOpenProjectOrVideo: (() -> Void)?

  init(
    state: VideoEditorState,
    isAuthoringLocked: Bool = false,
    aiChrome: VideoEditorAgentController.Chrome = .init(),
    aiLayout: VideoEditorAILayout = .defaultValue,
    projectContext: VideoEditorProjectContext? = nil,
    onSaveProject: (() -> Void)? = nil,
    onSaveProjectAs: (() -> Void)? = nil,
    onOpenProjectOrVideo: (() -> Void)? = nil
  ) {
    self.state = state
    self.isAuthoringLocked = isAuthoringLocked
    self.aiChrome = aiChrome
    self.aiLayout = aiLayout
    self.projectContext = projectContext ?? Self.emptyProjectContext
    self.onSaveProject = onSaveProject
    self.onSaveProjectAs = onSaveProjectAs
    self.onOpenProjectOrVideo = onOpenProjectOrVideo
    agent = state.agent
  }

  @ObservedObject private var shortcuts = VideoEditorShortcutManager.shared

  @State private var editingFilename: String = ""
  @State private var renameError: String?
  @State private var leftSectionWidth: CGFloat = 0
  @State private var rightSectionWidth: CGFloat = 0
  @State private var isProjectMenuOpen = false
  @State private var isSaveHovering = false
  @State private var isOpenHovering = false
  @State private var projectMenuButtonView = WeakToolbarNSViewBox()
  @FocusState private var isFilenameFieldFocused: Bool

  var body: some View {
    HStack(spacing: WindowSpacingConfiguration.default.toolbarItemSpacing) {
      leftSection
        .fixedSize(horizontal: true, vertical: false)
        .measureVideoEditorToolbarWidth(for: .left)
        .frame(width: reservedSideWidth, alignment: .leading)
        .disabled(isAuthoringLocked)
      centerSection
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, WindowSpacingConfiguration.default.toolbarItemSpacing)
        .disabled(isAuthoringLocked)
      rightSection
        .fixedSize(horizontal: true, vertical: false)
        .measureVideoEditorToolbarWidth(for: .right)
        .frame(width: reservedSideWidth, alignment: .trailing)
    }
    .windowToolbarPadding()
    .liquidGlassGroup(spacing: Spacing.xs)
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
      .keyboardShortcut("z", modifiers: [.command])
      .help(L10n.VideoEditor.undoShortcutHint)

      ToolbarButton(icon: "arrow.uturn.forward", isSelected: false) {
        state.redo()
      }
      .disabled(!state.canRedo)
      .keyboardShortcut("z", modifiers: [.command, .shift])
      .help(L10n.VideoEditor.redoShortcutHint)
    }
  }

  private var fileActionsGroup: some View {
    HStack(spacing: 4) {
      ToolbarButton(icon: "folder", isSelected: false) {
        if projectContext.hasProjectPackage {
          projectContext.revealInFinder()
        } else {
          state.openInFinder()
        }
      }
      .help(L10n.Common.openInFinder)

      ToolbarButton(
        icon: "info.circle",
        selectedIcon: "info.circle.fill",
        isSelected: state.isVideoInfoSidebarVisible,
        activeGlassTint: ZoomColors.primary
      ) {
        state.toggleVideoInfoSidebar()
      }
      .keyboardShortcut(aiChrome.allowsPlainKeyShortcuts ? KeyboardShortcut("i", modifiers: []) : nil)
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
      icon: "sidebar.left",
      isSelected: state.isLeftSidebarVisible,
      activeGlassTint: ZoomColors.primary
    ) {
      state.toggleLeftSidebar()
    }
    .keyboardShortcut("b", modifiers: [.command])
    .help(state.isLeftSidebarVisible ? L10n.VideoEditor.hideLeftSidebarHint : L10n.VideoEditor.showLeftSidebarHint)
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
          .liquidGlassChrome(
            shape: Radius.controlRect(forHeight: 24),
            isVisible: true,
            isActive: true
          )
          .focused($isFilenameFieldFocused)
          .onAppear {
            editingFilename = filenameWithoutExtension
            isFilenameFieldFocused = true
          }
          .onExitCommand(perform: cancelRename)
      } else {
        if projectContext.hasProjectPackage {
          Image(systemName: "shippingbox.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.accentColor)
        }

        Text(displayedTitle)
          .font(.system(size: 13, weight: .medium))
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(maxWidth: 300)

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
    .background {
      if state.isRenamingFile {
        Button(action: cancelRename) {
          EmptyView()
        }
        .keyboardShortcut(.cancelAction)
        .opacity(0)
        .frame(width: 0, height: 0)
      }
    }
  }

  // MARK: - Right Section

  /// Compact `.snapzy` project controls + AI assistant toggle.
  /// Both `.snapzy` pills share the exact `ControlMetrics.toolbarButton` (28pt) height and
  /// `Radius.controlRect` chrome so they align 1:1 with the toolbar icon buttons.
  private var rightSection: some View {
    HStack(spacing: WindowSpacingConfiguration.default.toolbarItemSpacing) {
      if !state.isGIF, onSaveProject != nil || onOpenProjectOrVideo != nil {
        projectControlsGroup
          .disabled(isAuthoringLocked || state.isExporting || projectContext.isSavingProject)
      }

      if aiLayout == .sidebar, !state.isGIF, !aiChrome.isPromptPresented, agent.isAvailable || aiChrome.isRunning {
        aiPanelToggleButton
      }
    }
  }

  private var projectControlsGroup: some View {
    HStack(spacing: 4) {
      if let onSaveProject {
        let isInPlaceLocked = state.sessionRestoreFailed && projectContext.hasProjectPackage
        let saveAction: () -> Void = {
          if isInPlaceLocked, let onSaveProjectAs {
            onSaveProjectAs()
          } else {
            onSaveProject()
          }
        }
        Button(action: saveAction) {
          HStack(spacing: 5) {
            Image(
              systemName: isInPlaceLocked
                ? "exclamationmark.triangle.fill"
                : (projectContext.showsJustSavedBadge ? "checkmark.circle.fill" : "square.and.arrow.down")
            )
            .font(.system(size: 11, weight: .semibold))
            .frame(width: 13, height: 13)
            .foregroundStyle(
              isInPlaceLocked
                ? Color.orange
                : (projectContext.showsJustSavedBadge ? Color.green : Color.primary)
            )

            Text(
              projectContext.showsJustSavedBadge
                ? L10n.VideoEditor.projectToolbarSaved
                : L10n.VideoEditor.projectToolbarSave
            )
            .font(.system(size: 11.5, weight: .medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)

            if state.hasUnsavedChanges, !projectContext.showsJustSavedBadge {
              Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
            }
          }
          .padding(.horizontal, 10)
          .frame(height: ControlMetrics.toolbarButton)
          .contentShape(Rectangle())
          .liquidGlassChrome(
            shape: Radius.controlRect(forHeight: ControlMetrics.toolbarButton),
            isVisible: true,
            isActive: (projectContext.hasProjectPackage && !state.hasUnsavedChanges) || isSaveHovering
          )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
          withAnimation(LiquidGlassTokens.hoverSpring) { isSaveHovering = hovering }
        }
        .help(
          isInPlaceLocked
            ? L10n.VideoEditor.projectRestoreFailedMessage
            : "\(L10n.VideoEditor.projectMenuSave) (⌘S)"
        )
      }

      Button {
        presentProjectMenu()
      } label: {
        HStack(spacing: 5) {
          Image(systemName: "shippingbox")
            .font(.system(size: 11, weight: .semibold))
            .frame(width: 13, height: 13)

          Text(L10n.VideoEditor.projectToolbarOpen)
            .font(.system(size: 11.5, weight: .medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)

          Image(systemName: "chevron.down")
            .font(.system(size: 8, weight: .bold))
            .opacity(0.62)
        }
        .padding(.horizontal, 10)
        .frame(height: ControlMetrics.toolbarButton)
        .contentShape(Rectangle())
        .liquidGlassChrome(
          shape: Radius.controlRect(forHeight: ControlMetrics.toolbarButton),
          isVisible: true,
          isActive: isProjectMenuOpen || isOpenHovering
        )
      }
      .buttonStyle(.plain)
      .onHover { hovering in
        withAnimation(LiquidGlassTokens.hoverSpring) { isOpenHovering = hovering }
      }
      .background(ToolbarMenuAnchorRepresentable(box: $projectMenuButtonView))
      .help("\(L10n.VideoEditor.projectMenuOpenOrVideo) (⌘O)")
    }
  }

  private func presentProjectMenu() {
    guard let view = projectMenuButtonView.view else { return }
    let menu = NSMenu()
    menu.autoenablesItems = false

    if let onOpenProjectOrVideo {
      let openItem = ClosureMenuItem(
        title: L10n.VideoEditor.projectMenuOpenOrVideo,
        keyEquivalent: "o"
      ) {
        onOpenProjectOrVideo()
      }
      openItem.keyEquivalentModifierMask = [.command]
      openItem.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)
      menu.addItem(openItem)
    }

    if onOpenProjectOrVideo != nil, onSaveProject != nil || onSaveProjectAs != nil {
      menu.addItem(.separator())
    }

    let isInPlaceLocked = state.sessionRestoreFailed && projectContext.hasProjectPackage
    if let onSaveProject, !isInPlaceLocked {
      let saveItem = ClosureMenuItem(
        title: L10n.VideoEditor.projectMenuSave,
        keyEquivalent: "s"
      ) {
        onSaveProject()
      }
      saveItem.keyEquivalentModifierMask = [.command]
      saveItem.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
      menu.addItem(saveItem)
    }

    if let onSaveProjectAs {
      let saveAsItem = ClosureMenuItem(
        title: L10n.VideoEditor.projectMenuSaveAs,
        keyEquivalent: "s"
      ) {
        onSaveProjectAs()
      }
      saveAsItem.keyEquivalentModifierMask = [.command, .shift]
      saveAsItem.image = NSImage(systemSymbolName: "plus.square.on.square", accessibilityDescription: nil)
      menu.addItem(saveAsItem)
    }

    isProjectMenuOpen = true
    let origin = NSPoint(x: 0, y: view.isFlipped ? view.bounds.height + 4 : -4)
    menu.popUp(positioning: nil, at: origin, in: view)
    isProjectMenuOpen = false
  }

  private var aiPanelToggleButton: some View {
    ToolbarButton(
      icon: AnnotateAgentGlyph.symbolName,
      isSelected: aiChrome.isPromptPresented,
      activeGlassTint: ZoomColors.primary,
      glyphGradient: TranslationCardMotion.rimHues
    ) {
      withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) { agent.togglePrompt() }
    }
    .overlay(alignment: .topTrailing) {
      // Working while the panel is hidden: a pulsing dot says a run is still going.
      if aiChrome.isRunning, !aiChrome.isPromptPresented {
        VideoEditorAIRunningDot()
          .offset(x: 1, y: -1)
          .allowsHitTesting(false)
      }
    }
    .help(shortcuts.helpText(L10n.VideoEditorAI.togglePanelHelp, for: .aiPrompt))
    .accessibilityLabel(L10n.VideoEditorAI.togglePanelHelp)
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

  private var displayedTitle: String {
    projectContext.packageDisplayName ?? state.filename
  }

  private var filenameWithoutExtension: String {
    if let stem = projectContext.packageStemName, !stem.isEmpty {
      return stem
    }
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

  private func cancelRename() {
    isFilenameFieldFocused = false
    state.isRenamingFile = false
    renameError = nil
  }

  private func commitRename() {
    do {
      if projectContext.hasProjectPackage, let onRenameProject = projectContext.onRenameProject {
        try onRenameProject(editingFilename)
      } else {
        try state.renameFile(to: editingFilename)
      }
      state.isRenamingFile = false
      renameError = nil
    } catch {
      renameError = error.localizedDescription
    }
  }
}

private struct WeakToolbarNSViewBox {
  weak var view: NSView?
}

private struct ToolbarMenuAnchorRepresentable: NSViewRepresentable {
  @Binding var box: WeakToolbarNSViewBox

  func makeNSView(context _: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      if box.view !== view {
        box.view = view
      }
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context _: Context) {
    if box.view !== nsView {
      DispatchQueue.main.async {
        if box.view !== nsView {
          box.view = nsView
        }
      }
    }
  }
}

private struct VideoEditorAIRunningDot: View {
  @State private var isPulsing = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Circle()
      .fill(Color.accentColor)
      .frame(width: 7, height: 7)
      .scaleEffect(isPulsing ? 1.25 : 0.85)
      .opacity(isPulsing ? 1 : 0.6)
      .onAppear {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { isPulsing = true }
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
