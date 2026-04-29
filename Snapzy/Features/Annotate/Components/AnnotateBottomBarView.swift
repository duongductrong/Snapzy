//
//  AnnotateBottomBarView.swift
//  Snapzy
//
//  Bottom bar with zoom, drag handle, and action buttons
//

import SwiftUI

private enum AnnotateBottomActionRegistration: Equatable {
  case annotateDefault
  case crop
}

private enum AnnotateBottomBarMeasuredSide: Hashable {
  case left
  case right
}

private struct AnnotateBottomBarWidthPreferenceKey: PreferenceKey {
  static let defaultValue: [AnnotateBottomBarMeasuredSide: CGFloat] = [:]

  static func reduce(
    value: inout [AnnotateBottomBarMeasuredSide: CGFloat],
    nextValue: () -> [AnnotateBottomBarMeasuredSide: CGFloat]
  ) {
    value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
  }
}

private extension View {
  func measuredBottomBarWidth(_ side: AnnotateBottomBarMeasuredSide) -> some View {
    background(
      GeometryReader { geometry in
        Color.clear.preference(
          key: AnnotateBottomBarWidthPreferenceKey.self,
          value: [side: geometry.size.width]
        )
      }
    )
  }
}

/// Bottom bar containing zoom controls and action buttons
struct AnnotateBottomBarView: View {
  @ObservedObject var state: AnnotateState
  @ObservedObject private var cloudManager = CloudManager.shared
  @ObservedObject private var preferencesManager = PreferencesManager.shared
  @ObservedObject private var annotateShortcutManager = AnnotateShortcutManager.shared

  @State private var isCloudUploading = false
  @State private var cloudUploadProgress: Double = 0
  @State private var cloudUploadError: String?
  @State private var showCloudNotConfiguredAlert = false
  @State private var showOverwriteConfirmation = false
  @State private var measuredLeftWidth: CGFloat = 0
  @State private var measuredRightWidth: CGFloat = 0

  private let centeredDragFullWidth: CGFloat = 160
  private let centeredDragCompactWidth: CGFloat = 44
  private let centeredDragHeight: CGFloat = 32
  private let centeredDragSideGap: CGFloat = 12

  var body: some View {
    VStack(spacing: 0) {
      // Mockup preset bar (shown when mockup mode is active)
      if state.editorMode == .mockup {
        MockupPresetBarInline(state: state)
        Divider()
      }

      bottomBarContent
      .windowBottomBarPadding()
      .animation(.easeInOut(duration: 0.16), value: activeActionRegistration)
      .onPreferenceChange(AnnotateBottomBarWidthPreferenceKey.self) { widths in
        measuredLeftWidth = widths[.left] ?? 0
        measuredRightWidth = widths[.right] ?? 0
      }

      // Cloud upload progress bar (always present to avoid layout shift)
      ProgressView(value: cloudUploadProgress)
        .progressViewStyle(.linear)
        .frame(height: 3)
        .opacity(isCloudUploading ? 1 : 0)
    }
    .alert(L10n.AnnotateUI.cloudNotConfiguredTitle, isPresented: $showCloudNotConfiguredAlert) {
      Button(L10n.Common.ok, role: .cancel) {}
    } message: {
      Text(L10n.AnnotateUI.cloudNotConfiguredMessage)
    }
    .alert(L10n.AnnotateUI.overwriteCloudFileTitle, isPresented: $showOverwriteConfirmation) {
      Button(L10n.Common.overwrite) {
        handleCloudUpload()
      }
      .keyboardShortcut(.defaultAction)
      Button(L10n.Common.cancel, role: .cancel) {}
    } message: {
      Text(L10n.AnnotateUI.overwriteCloudFileMessage)
    }
    .onReceive(NotificationCenter.default.publisher(for: .annotateCloudUpload)) { _ in
      // ⌘U shortcut: trigger cloud upload (with overwrite confirmation if needed)
      let showCloudButton = preferencesManager.isActionEnabled(.uploadToCloud, for: .screenshot)
      let needsReUpload = state.hasUnsavedChanges || state.isCloudStale
      let alreadyUploaded = state.cloudURL != nil && !needsReUpload
      guard showCloudButton, !isCloudUploading, !alreadyUploaded else { return }
      if state.cloudKey != nil && needsReUpload {
        showOverwriteConfirmation = true
      } else {
        handleCloudUpload()
      }
    }
  }

  // MARK: - Left Section

  private var bottomBarContent: some View {
    GeometryReader { geometry in
      let dragWidth = centeredDragWidth(for: geometry.size.width)

      ZStack {
        HStack(spacing: 0) {
          // Left section: zoom + mode toggle
          leftSection
            .fixedSize(horizontal: true, vertical: false)
            .measuredBottomBarWidth(.left)

          Spacer(minLength: 0)

          // Right section: registered action surface
          registeredActionSurface
            .fixedSize(horizontal: true, vertical: false)
            .measuredBottomBarWidth(.right)
        }

        // Center: Drag handle pinned to true bar center. If the bar gets too
        // tight, it compacts before hiding so side controls stay clickable.
        if state.hasImage && activeActionRegistration == .annotateDefault && dragWidth > 0 {
          dragHandle(
            width: dragWidth,
            isCompact: dragWidth < centeredDragFullWidth
          )
          .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
      }
    }
    .frame(height: centeredDragHeight)
  }

  private var leftSection: some View {
    HStack(spacing: 10) {
      zoomPicker
      modeToggle
    }
  }

  private func centeredDragWidth(for contentWidth: CGFloat) -> CGFloat {
    guard contentWidth > 0 else { return centeredDragFullWidth }

    let halfWidth = contentWidth / 2
    let leftClearance = halfWidth - measuredLeftWidth - centeredDragSideGap
    let rightClearance = halfWidth - measuredRightWidth - centeredDragSideGap
    let availableCenteredWidth = max(0, min(leftClearance, rightClearance) * 2)

    if availableCenteredWidth >= centeredDragFullWidth {
      return centeredDragFullWidth
    }

    if availableCenteredWidth >= centeredDragCompactWidth {
      return centeredDragCompactWidth
    }

    return 0
  }

  // MARK: - Zoom Picker

  private var zoomPicker: some View {
    Menu {
      ForEach(state.zoomMenuPresetPercents, id: \.self) { percent in
        Button("\(percent)%") {
          withAnimation(.easeOut(duration: 0.15)) {
            state.zoomLevel = state.zoomLevel(forDisplayedPercent: percent)
          }
        }
      }

      Divider()

      Button("1:1") {
        withAnimation(.easeOut(duration: 0.15)) {
          state.zoomLevel = state.actualPixelZoomLevel
        }
      }

      Button(L10n.AnnotateUI.fitWithShortcut("⌘0")) {
        withAnimation(.easeOut(duration: 0.15)) {
          state.zoomLevel = 1.0
        }
      }
    } label: {
      HStack(spacing: 4) {
        Text("\(state.currentDisplayedZoomPercent)%")
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(.primary)
        Image(systemName: "chevron.down")
          .font(.system(size: 8))
          .foregroundColor(.secondary)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(Color.primary.opacity(0.1))
      .cornerRadius(6)
    }
    .menuStyle(.borderlessButton)
    .fixedSize(horizontal: true, vertical: false)
  }

  // MARK: - Mode Toggle

  /// Check if any mockup transforms have been applied
  private var hasMockupTransforms: Bool {
    state.mockupRotationX != 0 ||
    state.mockupRotationY != 0 ||
    state.mockupRotationZ != 0
  }

  private var modeToggle: some View {
    Picker("", selection: $state.editorMode) {
      Label(L10n.AnnotateUI.modeAnnotate, systemImage: "pencil.and.outline")
        .tag(AnnotateState.EditorMode.annotate)
      Label(L10n.AnnotateUI.modeMockup, systemImage: "cube.transparent")
        .tag(AnnotateState.EditorMode.mockup)
      Label(L10n.AnnotateUI.modePreview, systemImage: "eye")
        .tag(AnnotateState.EditorMode.preview)
    }
    .pickerStyle(.segmented)
    .frame(width: 220)
  }

  // MARK: - Drag Handle (CleanShot-style)

  @State private var isDragHovering = false

  private func dragHandle(width: CGFloat, isCompact: Bool) -> some View {
    let dragState = state.dragToAppPreparationState

    return AnnotateDragHandleView(state: state)
      .frame(width: width, height: centeredDragHeight)
      .overlay(
        HStack(spacing: isCompact ? 0 : 6) {
          if dragState == .preparing {
            ProgressView()
              .controlSize(.small)
              .scaleEffect(0.7)
              .tint(isDragHovering ? .primary : .secondary)
          } else {
            Image(systemName: "hand.draw")
              .font(.system(size: 13, weight: .medium))
              .foregroundColor(isDragHovering ? .primary : .secondary)
          }

          if !isCompact {
            Text(L10n.AnnotateUI.dragToApp)
              .font(.system(size: 12, weight: .medium))
              .foregroundColor(dragLabelColor(for: dragState))
          }
        }
        .allowsHitTesting(false)
      )
      .background(
        Capsule()
          .fill(dragBackgroundColor(for: dragState))
      )
      .overlay(
        Capsule()
          .strokeBorder(dragBorderColor(for: dragState), lineWidth: 1)
      )
      .onHover { isDragHovering = $0 }
      .animation(.easeInOut(duration: 0.15), value: isDragHovering)
      .animation(.easeInOut(duration: 0.15), value: dragState)
      .help(L10n.AnnotateUI.dragToAppHelp)
  }

  private func dragLabelColor(for state: AnnotateState.DragToAppPreparationState) -> Color {
    switch state {
    case .ready:
      return isDragHovering ? .primary : .secondary
    case .preparing:
      return .primary
    case .unavailable:
      return .secondary.opacity(0.6)
    }
  }

  private func dragBackgroundColor(for state: AnnotateState.DragToAppPreparationState) -> Color {
    switch state {
    case .ready:
      return isDragHovering ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06)
    case .preparing:
      return Color.accentColor.opacity(isDragHovering ? 0.12 : 0.08)
    case .unavailable:
      return Color.primary.opacity(0.04)
    }
  }

  private func dragBorderColor(for state: AnnotateState.DragToAppPreparationState) -> Color {
    switch state {
    case .ready:
      return Color.primary.opacity(isDragHovering ? 0.2 : 0.1)
    case .preparing:
      return Color.accentColor.opacity(isDragHovering ? 0.35 : 0.22)
    case .unavailable:
      return Color.primary.opacity(0.08)
    }
  }

  // MARK: - Action Buttons

  private var activeActionRegistration: AnnotateBottomActionRegistration {
    // Specialized tools can register a replacement for the default Annotate actions here.
    if state.selectedTool == .crop && state.isCropActive {
      return .crop
    }

    return .annotateDefault
  }

  @ViewBuilder
  private var registeredActionSurface: some View {
    switch activeActionRegistration {
    case .annotateDefault:
      annotateActionButtons
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    case .crop:
      CropToolbarView(state: state)
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }
  }

  private var annotateActionButtons: some View {
    let showCloudButton = preferencesManager.isActionEnabled(.uploadToCloud, for: .screenshot)
    let cloudUploadShortcut = annotateShortcutManager.isActionShortcutEnabled(for: .cloudUpload)
      ? annotateShortcutManager.cloudUploadShortcut.displayString : nil
    let togglePinShortcut = annotateShortcutManager.isActionShortcutEnabled(for: .togglePin)
      ? annotateShortcutManager.togglePinShortcut.displayString : nil
    let copyAndCloseShortcut = annotateShortcutManager.isActionShortcutEnabled(for: .copyAndClose)
      ? annotateShortcutManager.copyAndCloseShortcut.displayString : nil

    return HStack(spacing: 12) {
      BottomBarButton(
        icon: "plus.rectangle.on.rectangle",
        tooltip: L10n.AnnotateUI.newWindow
      ) {
        AnnotateManager.shared.openEmptyAnnotation()
      }

      BottomBarButton(icon: "square.and.arrow.up", tooltip: L10n.Common.share) {
        share()
      }

      // Cloud upload button
      if showCloudButton {
        // needsReUpload: true when image changed in current session OR was changed since last upload
        let needsReUpload = state.hasUnsavedChanges || state.isCloudStale
        let alreadyUploaded = state.cloudURL != nil && !needsReUpload
        BottomBarButton(
          icon: alreadyUploaded ? "checkmark.icloud" : "icloud.and.arrow.up",
          tooltip: alreadyUploaded
            ? L10n.AnnotateUI.uploadedToCloud
            : tooltipText(
              state.cloudKey != nil ? L10n.AnnotateUI.reuploadToCloud : L10n.AnnotateUI.uploadToCloud,
              shortcut: cloudUploadShortcut
            )
        ) {
          if state.cloudKey != nil && needsReUpload {
            showOverwriteConfirmation = true
          } else {
            handleCloudUpload()
          }
        }
        .disabled(isCloudUploading || alreadyUploaded)
        .opacity(alreadyUploaded ? 0.6 : 1)
      }

      BottomBarButton(
        icon: state.isPinned ? "pin.fill" : "pin",
        tooltip: tooltipText(
          state.isPinned ? L10n.AnnotateUI.unpinWindow : L10n.AnnotateUI.pinWindow,
          shortcut: togglePinShortcut
        )
      ) {
        pin()
      }

      BottomBarButton(
        icon: "doc.on.doc",
        tooltip: tooltipText(L10n.AnnotateUI.copyToClipboard, shortcut: copyAndCloseShortcut)
      ) {
        copyToClipboard()
      }

      BottomBarButton(icon: "trash", tooltip: L10n.Common.deleteAction) {
        confirmAndDeleteImage()
      }
      .disabled(state.sourceURL == nil)
      .opacity(state.sourceURL == nil ? 0.5 : 1)
    }
  }

  private func tooltipText(_ title: String, shortcut: String?) -> String {
    guard let shortcut else { return title }
    return L10n.Common.withShortcut(title, shortcut)
  }

  // MARK: - Actions

  private func share() {
    guard let window = NSApp.keyWindow, let contentView = window.contentView else { return }
    AnnotateExporter.share(state: state, from: contentView)
  }

  private func pin() {
    if let window = NSApp.keyWindow {
      let newPinned = !state.isPinned
      window.level = newPinned ? .floating : .normal
      state.isPinned = newPinned
    }
  }

  private func copyToClipboard() {
    guard let window = NSApp.keyWindow else { return }
    // Post notification so the controller handles save + cache + copy
    NotificationCenter.default.post(name: .annotateCopyAndClose, object: window)
  }

  private func confirmAndDeleteImage() {
    guard let sourceURL = state.sourceURL,
          let window = NSApp.keyWindow else { return }

    let alert = NSAlert()
    alert.messageText = L10n.AnnotateUI.deleteScreenshotTitle
    alert.informativeText = L10n.AnnotateUI.deleteScreenshotMessage(sourceURL.lastPathComponent)
    alert.alertStyle = .warning
    alert.addButton(withTitle: L10n.Common.deleteAction)
    alert.addButton(withTitle: L10n.Common.cancel)

    alert.beginSheetModal(for: window) { [state] response in
      guard response == .alertFirstButtonReturn else { return }

      // Remove QuickAccess card if it exists
      if let itemId = state.quickAccessItemId {
        QuickAccessManager.shared.removeItem(id: itemId)
      }

      // Trash the file
      let fileAccessManager = SandboxFileAccessManager.shared
      let fileAccess = fileAccessManager.beginAccessingURL(sourceURL)
      let directoryAccess = fileAccessManager.beginAccessingURL(sourceURL.deletingLastPathComponent())
      defer {
        fileAccess.stop()
        directoryAccess.stop()
      }

      try? FileManager.default.trashItem(at: sourceURL, resultingItemURL: nil)

      // Close the annotate window (captured before alert)
      state.hasUnsavedChanges = false
      window.close()
    }
  }

  // MARK: - Cloud Upload

  private func handleCloudUpload() {
    guard cloudManager.isConfigured else {
      DiagnosticLogger.shared.log(.warning, .cloud, "Annotate cloud upload skipped; cloud not configured")
      showCloudNotConfiguredAlert = true
      return
    }

    guard let sourceURL = state.sourceURL else {
      DiagnosticLogger.shared.log(.warning, .cloud, "Annotate cloud upload skipped; source URL missing")
      return
    }

    // Step 1: Render flattened image with annotations BEFORE uploading
    let renderedImage = AnnotateExporter.renderFinalImage(state: state)

    // Step 2: Save rendered image to disk (so the file includes annotations)
    if let renderedImage = renderedImage {
      AnnotateExporter.saveToFile(image: renderedImage, state: state)
    }

    isCloudUploading = true
    cloudUploadProgress = 0
    DiagnosticLogger.shared.log(
      .info,
      .cloud,
      "Annotate cloud upload started",
      context: ["fileName": sourceURL.lastPathComponent, "hasOldCloudKey": state.cloudKey == nil ? "false" : "true"]
    )

    // Animate to 80% quickly to show activity
    withAnimation(.easeOut(duration: 0.4)) {
      cloudUploadProgress = 0.8
    }

    let uploadStartTime = Date()
    let oldCloudKey = state.cloudKey  // Save old key for cleanup after successful upload

    Task {
      do {
        let fileAccess = SandboxFileAccessManager.shared.beginAccessingURL(sourceURL)
        defer { fileAccess.stop() }

        // Always upload with a fresh key (new URL avoids CDN cache issues)
        let result = try await cloudManager.upload(fileURL: sourceURL)

        // Delete the old cloud file in background (no garbage)
        if let oldKey = oldCloudKey {
          Task.detached(priority: .utility) {
            do {
              try await CloudManager.shared.deleteByKey(key: oldKey)
            } catch {
              DiagnosticLogger.shared.logError(.cloud, error, "Annotate old cloud object cleanup failed")
            }
          }
        }

        // Store cloud URL and key on state
        state.cloudURL = result.publicURL
        state.cloudKey = result.key

        // Auto-copy cloud link
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result.publicURL.absoluteString, forType: .string)

        // Ensure minimum visual duration (~600ms total)
        let elapsed = Date().timeIntervalSince(uploadStartTime)
        let remainingDelay = max(0, 0.6 - elapsed)

        withAnimation(.easeIn(duration: 0.15)) {
          cloudUploadProgress = 1.0
        }

        if remainingDelay > 0 {
          try? await Task.sleep(nanoseconds: UInt64(remainingDelay * 1_000_000_000))
        }

        isCloudUploading = false
        SoundManager.play("Pop")

        // Update QuickAccess thumbnail and mark as saved
        state.markAsSaved()
        state.isCloudStale = false
        if let itemId = state.quickAccessItemId {
          if let renderedImage = renderedImage {
            QuickAccessManager.shared.updateItemThumbnail(id: itemId, image: renderedImage)
          }
          // Set cloud URL AFTER thumbnail update to ensure isCloudStale = false
          QuickAccessManager.shared.setCloudURL(id: itemId, url: result.publicURL, key: result.key)
        }
        DiagnosticLogger.shared.log(
          .info,
          .cloud,
          "Annotate cloud upload completed",
          context: ["fileName": sourceURL.lastPathComponent]
        )

        // Close window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
          NSApp.keyWindow?.close()
        }
      } catch {
        isCloudUploading = false
        cloudUploadProgress = 0
        cloudUploadError = error.localizedDescription
        DiagnosticLogger.shared.logError(
          .cloud,
          error,
          "Annotate cloud upload failed",
          context: ["fileName": sourceURL.lastPathComponent]
        )
      }
    }
  }
}

// MARK: - Bottom Bar Button

struct BottomBarButton: View {
  let icon: String
  let tooltip: String
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 14))
        .foregroundColor(.primary)
        .frame(width: 28, height: 28)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(isHovering ? Color.primary.opacity(0.15) : Color.clear)
        )
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .help(tooltip)
  }
}
