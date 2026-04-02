//
//  AnnotateBottomBarView.swift
//  Snapzy
//
//  Bottom bar with zoom, drag handle, and action buttons
//

import SwiftUI

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

  var body: some View {
    VStack(spacing: 0) {
      // Mockup preset bar (shown when mockup mode is active)
      if state.editorMode == .mockup {
        MockupPresetBarInline(state: state)
        Divider()
      }

      // Balanced left — center — right layout
      ZStack {
        // Center: Drag handle (absolute center)
        if state.hasImage {
          dragHandle
        }

        // Left + Right: overlay on top of center
        HStack(spacing: 0) {
          // Left section: zoom + mode toggle
          leftSection

          Spacer()

          // Right section: action buttons
          actionButtons
        }
      }
      .windowBottomBarPadding()

      // Cloud upload progress bar (always present to avoid layout shift)
      ProgressView(value: cloudUploadProgress)
        .progressViewStyle(.linear)
        .frame(height: 3)
        .opacity(isCloudUploading ? 1 : 0)
    }
    .alert("Cloud Not Configured", isPresented: $showCloudNotConfiguredAlert) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Please set up your cloud credentials in Preferences → Cloud before uploading.")
    }
    .alert("Overwrite Cloud File?", isPresented: $showOverwriteConfirmation) {
      Button("Overwrite") {
        handleCloudUpload()
      }
      .keyboardShortcut(.defaultAction)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This image was previously uploaded to cloud. Re-uploading will replace the existing file with your changes.")
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

  private var leftSection: some View {
    HStack(spacing: 10) {
      zoomPicker
      modeToggle
    }
  }

  // MARK: - Zoom Picker

  private var zoomPicker: some View {
    Menu {
      ForEach([25, 50, 75, 100, 125, 150, 200, 300, 400], id: \.self) { percent in
        Button("\(percent)%") {
          withAnimation(.easeOut(duration: 0.15)) {
            state.zoomLevel = CGFloat(percent) / 100
          }
        }
      }

      Divider()

      Button("Actual Size (⌘0)") {
        withAnimation(.easeOut(duration: 0.15)) {
          state.zoomLevel = 1.0
        }
      }
    } label: {
      HStack(spacing: 4) {
        Text("\(Int(state.zoomLevel * 100))%")
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
      Label("Annotate", systemImage: "pencil.and.outline")
        .tag(AnnotateState.EditorMode.annotate)
      Label("Mockup", systemImage: "cube.transparent")
        .tag(AnnotateState.EditorMode.mockup)
      Label("Preview", systemImage: "eye")
        .tag(AnnotateState.EditorMode.preview)
    }
    .pickerStyle(.segmented)
    .frame(width: 220)
  }

  // MARK: - Drag Handle (CleanShot-style)

  @State private var isDragHovering = false

  private var dragHandle: some View {
    AnnotateDragHandleView(state: state)
      .frame(width: 160, height: 32)
      .overlay(
        HStack(spacing: 6) {
          Image(systemName: "hand.draw")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(isDragHovering ? .primary : .secondary)

          Text("Drag to app")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(isDragHovering ? .primary : .secondary)
        }
        .allowsHitTesting(false)
      )
      .background(
        Capsule()
          .fill(isDragHovering ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06))
      )
      .overlay(
        Capsule()
          .strokeBorder(Color.primary.opacity(isDragHovering ? 0.2 : 0.1), lineWidth: 1)
      )
      .onHover { isDragHovering = $0 }
      .animation(.easeInOut(duration: 0.15), value: isDragHovering)
      .help("Drag this to another app to share the annotated image")
  }

  // MARK: - Action Buttons

  private var actionButtons: some View {
    let showCloudButton = preferencesManager.isActionEnabled(.uploadToCloud, for: .screenshot)
    let cloudUploadShortcut = annotateShortcutManager.isActionShortcutEnabled(for: .cloudUpload)
      ? annotateShortcutManager.cloudUploadShortcut.displayString : nil
    let togglePinShortcut = annotateShortcutManager.isActionShortcutEnabled(for: .togglePin)
      ? annotateShortcutManager.togglePinShortcut.displayString : nil
    let copyAndCloseShortcut = annotateShortcutManager.isActionShortcutEnabled(for: .copyAndClose)
      ? annotateShortcutManager.copyAndCloseShortcut.displayString : nil

    return HStack(spacing: 12) {
      BottomBarButton(icon: "square.and.arrow.up", tooltip: "Share") {
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
            ? "Uploaded to Cloud"
            : tooltipText(
              state.cloudKey != nil ? "Re-upload to Cloud" : "Upload to Cloud",
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
        tooltip: tooltipText(state.isPinned ? "Unpin window" : "Pin window", shortcut: togglePinShortcut)
      ) {
        pin()
      }

      BottomBarButton(icon: "doc.on.doc", tooltip: tooltipText("Copy to clipboard", shortcut: copyAndCloseShortcut)) {
        copyToClipboard()
      }

      BottomBarButton(icon: "trash", tooltip: "Delete") {
        confirmAndDeleteImage()
      }
      .disabled(state.sourceURL == nil)
      .opacity(state.sourceURL == nil ? 0.5 : 1)
    }
  }

  private func tooltipText(_ title: String, shortcut: String?) -> String {
    guard let shortcut else { return title }
    return "\(title) (\(shortcut))"
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
    alert.messageText = "Delete Screenshot"
    alert.informativeText = "This will move \"\(sourceURL.lastPathComponent)\" to Trash."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Delete")
    alert.addButton(withTitle: "Cancel")

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
      showCloudNotConfiguredAlert = true
      return
    }

    guard let sourceURL = state.sourceURL else { return }

    // Step 1: Render flattened image with annotations BEFORE uploading
    let renderedImage = AnnotateExporter.renderFinalImage(state: state)

    // Step 2: Save rendered image to disk (so the file includes annotations)
    if let renderedImage = renderedImage {
      AnnotateExporter.saveToFile(image: renderedImage, state: state)
    }

    isCloudUploading = true
    cloudUploadProgress = 0

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
            try? await CloudManager.shared.deleteByKey(key: oldKey)
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

        // Close window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
          NSApp.keyWindow?.close()
        }
      } catch {
        isCloudUploading = false
        cloudUploadProgress = 0
        cloudUploadError = error.localizedDescription
        print("[Snapzy:Cloud] Annotate upload failed: \(error.localizedDescription)")
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
