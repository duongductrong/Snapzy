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
      ForEach([50, 75, 100, 150, 200], id: \.self) { percent in
        Button("\(percent)%") {
          state.zoomLevel = CGFloat(percent) / 100
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
    HStack(spacing: 12) {
      BottomBarButton(icon: "square.and.arrow.up", tooltip: "Share") {
        share()
      }

      BottomBarButton(icon: "pin", tooltip: "Pin window") {
        pin()
      }

      BottomBarButton(icon: "doc.on.doc", tooltip: "Copy to clipboard & close (⇧⌘C)") {
        copyToClipboardAndClose()
      }

      BottomBarButton(icon: "trash", tooltip: "Delete") {
        confirmAndDeleteImage()
      }
      .disabled(state.sourceURL == nil)
      .opacity(state.sourceURL == nil ? 0.5 : 1)
    }
  }

  // MARK: - Actions

  private func share() {
    guard let window = NSApp.keyWindow, let contentView = window.contentView else { return }
    AnnotateExporter.share(state: state, from: contentView)
  }

  private func pin() {
    if let window = NSApp.keyWindow {
      window.level = window.level == .floating ? .normal : .floating
    }
  }

  private func copyToClipboardAndClose() {
    AnnotateExporter.copyToClipboard(state: state)
    state.hasUnsavedChanges = false
    NSApp.keyWindow?.close()
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
