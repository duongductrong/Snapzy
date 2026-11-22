//
//  AnnotateToolbarView.swift
//  Snapzy
//
//  Top toolbar with annotation tools and actions
//

import SwiftUI

private enum AnnotateToolbarActionRegistration: Equatable {
  case annotateDefault
  case crop
  case cutOut
}

/// Everything the toolbar displays, captured as plain values.
///
/// `AnnotateState` publishes far more often than the toolbar changes — during a live window
/// resize the canvas updates `fitScale`/`baseCanvasDisplaySize` every frame. Rendering from this
/// snapshot through `.equatable()` turns each of those publishes into one cheap comparison
/// instead of re-evaluating ~25 glass buttons.
nonisolated struct AnnotateToolbarSnapshot: Equatable {
  var selectedTool: AnnotationToolType
  var editorMode: AnnotateState.EditorMode
  var showSidebar: Bool
  var canApplyCutOut: Bool
  var canRotateImage: Bool
  var canUseBackgroundCutout: Bool
  var hasImage: Bool
  var isCutoutApplied: Bool
  var isCutoutProcessing: Bool
  var canUndo: Bool
  var canRedo: Bool
  var isCombineMode: Bool
  var isCropActive: Bool
  var isCutOutActive: Bool
  var cutOutMode: CutOutMode
  var hasCutOutPreview: Bool

  @MainActor
  init(_ state: AnnotateState) {
    selectedTool = state.selectedTool
    editorMode = state.editorMode
    showSidebar = state.showSidebar
    canApplyCutOut = state.canApplyCutOut
    canRotateImage = state.canRotateImage
    canUseBackgroundCutout = state.canUseBackgroundCutout
    hasImage = state.hasImage
    isCutoutApplied = state.isCutoutApplied
    isCutoutProcessing = state.isCutoutProcessing
    canUndo = state.canUndo
    canRedo = state.canRedo
    isCombineMode = state.isCombineMode
    isCropActive = state.isCropActive
    isCutOutActive = state.isCutOutActive
    cutOutMode = state.cutOutMode
    hasCutOutPreview = state.cutOutPreviewStrip != nil
  }
}

/// Top toolbar containing all annotation tools
struct AnnotateToolbarView: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    AnnotateToolbarContent(state: state, snapshot: AnnotateToolbarSnapshot(state))
      .equatable()
      .alert(
        L10n.AnnotateUI.backgroundCutoutTitle,
        isPresented: Binding(
          get: { state.cutoutErrorMessage != nil },
          set: { if !$0 { state.cutoutErrorMessage = nil } }
        )
      ) {
        Button(L10n.Common.ok, role: .cancel) {}
      } message: {
        Text(state.cutoutErrorMessage ?? L10n.AnnotateUI.unableToRemoveBackground)
      }
  }
}

/// Toolbar body. Reads only from `snapshot`; `state` is used for actions and is deliberately not
/// observed, so this view re-renders only when the snapshot changes.
private struct AnnotateToolbarContent: View, Equatable {
  let state: AnnotateState
  let snapshot: AnnotateToolbarSnapshot
  @AppStorage(PreferencesKeys.backgroundCutoutAutoCropEnabled) private var backgroundCutoutAutoCropEnabled = true

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.state === rhs.state && lhs.snapshot == rhs.snapshot
  }

  var body: some View {
    HStack(spacing: WindowSpacingConfiguration.default.toolbarItemSpacing) {
      // Crop / sidebar / cut out / transform stay pinned on the left and the actions on the
      // right. Drawing tools that do not fit collapse, from the end, into a "More" menu.
      captureToolsGroup
        .fixedSize()
        .layoutPriority(1)

      ToolbarDivider()

      // Width tracking lives inside the row: resizing re-renders only the row, and only when
      // the number of visible tools actually changes.
      AnnotateToolbarCollapsibleRow(
        state: state,
        items: collapsibleItems,
        selectedTool: snapshot.selectedTool,
        leading: { annotationToolButton(for: .selection) },
        item: { collapsibleItemButton($0) },
        trailing: { undoRedoGroup }
      )

      registeredActionButtons
        .fixedSize()
        .layoutPriority(1)
    }
    .liquidGlassGroup(spacing: Spacing.xs)
    .windowTrafficLightsInset()
    .windowToolbarPadding()
    .animation(.easeInOut(duration: 0.16), value: activeActionRegistration)
  }

  // MARK: - Tool Groups

  private var captureToolsGroup: some View {
    HStack(spacing: 4) {
      ToolbarButton(
        icon: "crop",
        isSelected: snapshot.selectedTool == .crop,
        activeGlassTint: nil
      ) {
        state.beginCropInteraction()
      }
      .help(L10n.AnnotateUI.crop)

      ToolbarButton(
        icon: "sidebar.left",
        isSelected: snapshot.showSidebar,
        activeGlassTint: nil
      ) {
        state.toggleSidebarVisibility()
      }
      .help(L10n.AnnotateUI.toggleSidebar)

      ToolbarDivider()

      imageTransformButtonsGroup
    }
  }

  /// Cut out sits with rotate so Crop/Sidebar keep their established positions.
  private var imageTransformButtonsGroup: some View {
    HStack(spacing: 4) {
      ToolbarButton(
        icon: "scissors",
        isSelected: snapshot.selectedTool == .cutOut,
        activeGlassTint: nil
      ) {
        state.beginCutOutInteraction()
      }
      .help(L10n.AnnotateUI.cutOut)
      .disabled(!snapshot.canApplyCutOut)
      .opacity(snapshot.canApplyCutOut ? 1 : 0.4)

      transformMenuButton
    }
  }

  /// Rotate and flip are occasional whole-image actions, so they share one menu slot instead of
  /// four toolbar buttons. ⌘L / ⌘R rotate and ⌃⌘H / ⌃⌘V flip without opening the menu.
  private var transformMenuButton: some View {
    AnnotateImageTransformToolbarButton(state: state, isEnabled: snapshot.canRotateImage)
      .help(L10n.AnnotateUI.rotateAndFlip)
  }

  /// Tools after Selection, in the order they collapse from (last item first).
  private var collapsibleItems: [AnnotateToolbarCollapsibleItem] {
    snapshot.isCombineMode ? AnnotateToolbarCollapsibleItem.combineItems : AnnotateToolbarCollapsibleItem.standardItems
  }

  @ViewBuilder
  private func collapsibleItemButton(_ item: AnnotateToolbarCollapsibleItem) -> some View {
    switch item {
    case .tool(let tool):
      annotationToolButton(for: tool)
    case .backgroundCutout:
      backgroundCutoutButton
        .padding(.leading, AnnotateToolbarCollapseLayout.backgroundCutoutLeadingPadding)
    case .addImage:
      ToolbarButton(icon: "photo.badge.plus", isSelected: false) {
        AnnotateToolbarCollapsibleItem.postAddImage()
      }
      .help(L10n.Combine.pickerTitle)
    }
  }

  private var backgroundCutoutButton: some View {
    ToolbarButton(
      icon: snapshot.isCutoutProcessing ? "hourglass" : "wand.and.stars",
      isSelected: snapshot.isCutoutApplied,
      activeGlassTint: nil
    ) {
      state.toggleBackgroundCutout()
    }
    .disabled(!snapshot.canUseBackgroundCutout || !snapshot.hasImage || snapshot.isCutoutProcessing)
    .opacity((!snapshot.canUseBackgroundCutout || !snapshot.hasImage) ? 0.4 : 1)
    .help(
      snapshot.canUseBackgroundCutout
        ? (snapshot.isCutoutApplied
          ? L10n.AnnotateUI.backgroundRemovedClickToRestore
          : (backgroundCutoutAutoCropEnabled
            ? L10n.AnnotateUI.removeBackgroundAutoCropsWhenSafe
            : L10n.AnnotateUI.removeBackgroundAutoCropDisabledInSettings))
        : L10n.AnnotateUI.requiresMacOS14OrLater
    )
  }

  @ViewBuilder
  private func annotationToolButton(for tool: AnnotationToolType) -> some View {
    ToolbarButton(
      icon: tool.icon,
      isSelected: snapshot.selectedTool == tool,
      activeGlassTint: nil
    ) {
      state.activateTool(tool)
    }
    .help(tool.displayName)
    .disabled(snapshot.editorMode == .mockup && tool != .selection)
    .opacity(snapshot.editorMode == .mockup && tool != .selection ? 0.4 : 1)
  }

  private var undoRedoGroup: some View {
    HStack(spacing: 4) {
      ToolbarButton(icon: "arrow.uturn.backward", isSelected: false) {
        state.undo()
      }
      .help(L10n.Common.undo)
      .disabled(!snapshot.canUndo)

      ToolbarButton(icon: "arrow.uturn.forward", isSelected: false) {
        state.redo()
      }
      .help(L10n.Common.redo)
      .disabled(!snapshot.canRedo)
    }
  }

  private var activeActionRegistration: AnnotateToolbarActionRegistration {
    if snapshot.selectedTool == .crop && snapshot.isCropActive {
      return .crop
    }
    if snapshot.selectedTool == .cutOut && snapshot.isCutOutActive {
      return .cutOut
    }

    return .annotateDefault
  }

  @ViewBuilder
  private var registeredActionButtons: some View {
    switch activeActionRegistration {
    case .annotateDefault:
      annotateActionButtons
        .transition(.move(edge: .trailing))
    case .crop:
      cropActionButtons
        .transition(.move(edge: .trailing))
    case .cutOut:
      cutOutActionButtons
        .transition(.move(edge: .trailing))
    }
  }

  private var annotateActionButtons: some View {
    HStack(spacing: 8) {
      Button(L10n.Common.saveAs) {
        saveAs()
      }
      .buttonStyle(.liquidGlass(emphasis: .secondary, capsule: true))

      Button(L10n.Common.done) {
        done()
      }
      .buttonStyle(.liquidGlass(emphasis: .primary, capsule: true))
    }
  }

  private var cropActionButtons: some View {
    HStack(spacing: 8) {
      Button("\(L10n.Common.restore) \(L10n.Common.original)") {
        state.revertCropToOriginalBounds()
      }
      .buttonStyle(.liquidGlass(emphasis: .secondary, capsule: true))
      .help("\(L10n.Common.restore) \(L10n.Common.original)")

      Button(L10n.Common.cancel) {
        state.cancelCrop()
      }
      .buttonStyle(.liquidGlass(emphasis: .secondary, capsule: true))

      Button(L10n.Common.apply) {
        state.confirmCropInteraction()
      }
      .buttonStyle(.liquidGlass(emphasis: .primary, capsule: true))
    }
  }

  private var cutOutActionButtons: some View {
    HStack(spacing: 8) {
      Button(L10n.Common.cancel) {
        state.cancelCutOut()
      }
      .buttonStyle(.liquidGlass(emphasis: .secondary, capsule: true))

      Button(snapshot.cutOutMode == .remove ? L10n.AnnotateUI.cutOut : L10n.AnnotateUI.cutOutInsert) {
        state.commitCutOut()
      }
      .buttonStyle(.liquidGlass(emphasis: .primary, capsule: true))
      .disabled(!snapshot.hasCutOutPreview)
      .opacity(!snapshot.hasCutOutPreview ? 0.4 : 1)
    }
  }

  // MARK: - Actions

  private func saveAs() {
    if snapshot.isCombineMode {
      guard let window = NSApp.keyWindow else { return }
      NotificationCenter.default.post(name: .annotateSave, object: window)
    } else {
      AnnotateExporter.saveAs(state: state, closeWindow: true)
    }
  }

  private func done() {
    // Post save notification — controller handles silent save + cache + QA refresh + close
    guard let window = NSApp.keyWindow else { return }
    NotificationCenter.default.post(name: .annotateSave, object: window)
  }
}

// MARK: - Collapsible Tools

/// A toolbar slot that may collapse into the "More" menu when space runs out.
enum AnnotateToolbarCollapsibleItem: Hashable, Identifiable {
  case tool(AnnotationToolType)
  case backgroundCutout
  case addImage

  var id: Self { self }

  /// Built once: the row diffs these on every render, so avoid rebuilding them per frame.
  static let standardItems: [Self] = AnnotationToolType.drawableTools.map(Self.tool) + [.backgroundCutout]
  static let combineItems: [Self] = standardItems + [.addImage]

  static func postAddImage() {
    guard let window = NSApp.keyWindow else { return }
    NotificationCenter.default.post(name: .annotateAddImage, object: window)
  }
}

/// Width math for the collapsible row. Toolbar buttons have fixed sizes, so the visible count is
/// computed arithmetically instead of measuring each button (no layout feedback, no flicker).
enum AnnotateToolbarCollapseLayout {
  static let itemSpacing: CGFloat = 4
  static let backgroundCutoutLeadingPadding: CGFloat = 2

  private static let button = ControlMetrics.toolbarButton
  /// `ToolbarButton` with `showsMenuIndicator`: glyph (button - 4) + leading 2 + chevron + trailing 4.
  private static let overflowButton = (button - 4) + 2 + ToolbarButton.menuIndicatorWidth + 4
  /// Toolbar item spacing + divider (1 + 2×4 padding) + spacing + undo/redo pair.
  private static let trailingGroups: CGFloat = {
    let spacing = WindowSpacingConfiguration.default.toolbarItemSpacing
    return spacing + 9 + spacing + (button * 2 + itemSpacing)
  }()

  static func visibleCount(items: [AnnotateToolbarCollapsibleItem], availableWidth: CGFloat) -> Int {
    func rowWidth(_ count: Int, withOverflow: Bool) -> CGFloat {
      // Selection button is always shown.
      var width = button + trailingGroups
      for item in items.prefix(count) {
        width += itemSpacing + button
        if item == .backgroundCutout { width += backgroundCutoutLeadingPadding }
      }
      if withOverflow { width += itemSpacing + overflowButton }
      return width
    }

    if rowWidth(items.count, withOverflow: false) <= availableWidth {
      return items.count
    }
    var count = items.count - 1
    while count > 0 && rowWidth(count, withOverflow: true) > availableWidth {
      count -= 1
    }
    return count
  }
}

/// The collapsible middle section of the toolbar. It owns the width tracking: geometry changes
/// on every resize frame, but state is written only when the visible-tool count crosses a
/// threshold, so the parent toolbar never re-renders during a resize and this row re-renders
/// only a handful of times across the whole drag.
private struct AnnotateToolbarCollapsibleRow<Leading: View, Item: View, Trailing: View>: View {
  let state: AnnotateState
  let items: [AnnotateToolbarCollapsibleItem]
  let selectedTool: AnnotationToolType
  @ViewBuilder let leading: () -> Leading
  @ViewBuilder let item: (AnnotateToolbarCollapsibleItem) -> Item
  @ViewBuilder let trailing: () -> Trailing

  /// Latest measured width. A reference box, so writing it on every frame invalidates nothing.
  @State private var widthBox = WidthBox()
  /// `nil` until first measured: everything is shown.
  @State private var visibleCount: Int?

  var body: some View {
    let count = min(visibleCount ?? items.count, items.count)
    let visible = items.prefix(count)
    let overflow = Array(items.dropFirst(count))

    Color.clear
      .frame(maxWidth: .infinity)
      .frame(height: ControlMetrics.toolbarButton)
      .background(
        GeometryReader { proxy in
          Color.clear
            .onAppear { widthDidChange(proxy.size.width) }
            .onChange(of: proxy.size.width) { widthDidChange($0) }
        }
      )
      // Overlay so the row's content never feeds back into the measured width.
      .overlay(alignment: .leading) {
        HStack(spacing: WindowSpacingConfiguration.default.toolbarItemSpacing) {
          HStack(spacing: AnnotateToolbarCollapseLayout.itemSpacing) {
            leading()

            ForEach(visible) { entry in
              item(entry)
            }

            if !overflow.isEmpty {
              AnnotateToolbarOverflowButton(state: state, items: overflow, selectedTool: selectedTool)
                .help(L10n.Common.more)
            }
          }

          ToolbarDivider()

          trailing()
        }
        .fixedSize()
      }
      // Combine mode adds/removes an item: re-derive the count from the last width.
      .onChange(of: items) { _ in updateVisibleCount() }
  }

  private func widthDidChange(_ width: CGFloat) {
    widthBox.value = width
    updateVisibleCount()
  }

  private func updateVisibleCount() {
    let newCount = AnnotateToolbarCollapseLayout.visibleCount(items: items, availableWidth: widthBox.value)
    guard newCount != visibleCount else { return }
    // Snap rather than animate: an animated change would run glass morphing mid-resize.
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      visibleCount = newCount
    }
  }

  private final class WidthBox {
    var value: CGFloat = .greatestFiniteMagnitude
  }
}

/// "More" pull-down holding collapsed tools. When the active tool lives in the menu, the button
/// takes that tool's glyph and selected state so the current tool stays visible.
private struct AnnotateToolbarOverflowButton: View {
  /// Not observed: the glyph depends only on `selectedTool`, and the menu reads live state when
  /// it opens.
  let state: AnnotateState
  let items: [AnnotateToolbarCollapsibleItem]
  let selectedTool: AnnotationToolType

  @State private var anchor = MenuAnchor()
  @State private var isMenuOpen = false

  private var collapsedSelectedTool: AnnotationToolType? {
    items.lazy.compactMap { item -> AnnotationToolType? in
      if case .tool(let tool) = item, tool == selectedTool { return tool }
      return nil
    }.first
  }

  var body: some View {
    ToolbarButton(
      icon: collapsedSelectedTool?.icon ?? "ellipsis",
      isSelected: collapsedSelectedTool != nil || isMenuOpen,
      activeGlassTint: nil,
      showsMenuIndicator: true
    ) {
      presentMenu()
    }
    .background(MenuAnchorView(anchor: anchor))
  }

  private func presentMenu() {
    guard let view = anchor.view else { return }
    let menu = NSMenu()
    menu.autoenablesItems = false

    for item in items {
      if item == .backgroundCutout || item == .addImage {
        menu.addItem(.separator())
      }
      menu.addItem(menuItem(for: item))
    }

    isMenuOpen = true
    let origin = NSPoint(x: 0, y: view.isFlipped ? view.bounds.height + 4 : -4)
    menu.popUp(positioning: nil, at: origin, in: view)
    isMenuOpen = false
  }

  private func menuItem(for item: AnnotateToolbarCollapsibleItem) -> NSMenuItem {
    switch item {
    case .tool(let tool):
      let shortcuts = AnnotateShortcutManager.shared
      let key = shortcuts.isShortcutEnabled(for: tool) ? shortcuts.shortcut(for: tool).map(String.init) ?? "" : ""
      let menuItem = ClosureMenuItem(title: tool.displayName, keyEquivalent: key) { [weak state] in
        state?.activateTool(tool)
      }
      menuItem.keyEquivalentModifierMask = []
      menuItem.image = NSImage(systemSymbolName: tool.icon, accessibilityDescription: nil)
      menuItem.state = state.selectedTool == tool ? .on : .off
      menuItem.isEnabled = !(state.editorMode == .mockup && tool != .selection)
      return menuItem

    case .backgroundCutout:
      let menuItem = ClosureMenuItem(
        title: L10n.PreferencesCapture.removeBackground,
        keyEquivalent: ""
      ) { [weak state] in
        state?.toggleBackgroundCutout()
      }
      menuItem.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)
      menuItem.state = state.isCutoutApplied ? .on : .off
      menuItem.isEnabled = state.canUseBackgroundCutout && state.hasImage && !state.isCutoutProcessing
      return menuItem

    case .addImage:
      let menuItem = ClosureMenuItem(title: L10n.Combine.pickerTitle, keyEquivalent: "") {
        AnnotateToolbarCollapsibleItem.postAddImage()
      }
      menuItem.image = NSImage(systemSymbolName: "photo.badge.plus", accessibilityDescription: nil)
      return menuItem
    }
  }
}
