//
//  AnnotateBottomBarView.swift
//  ClaudeShot
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

      HStack(spacing: WindowSpacingConfiguration.default.bottomBarItemSpacing) {
        // Zoom picker
        zoomPicker

        Spacer()

        // Mode toggle (Annotate / Mockup / Preview)
        modeToggle

        Spacer()

        // Action buttons (hide in preview mode for cleaner view)
        if state.editorMode != .preview {
          actionButtons
        }
      }
      .windowBottomBarPadding()
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
  }

  // MARK: - Drag Handle

  private var dragHandle: some View {
    Text("Drag me")
      .font(.system(size: 12, weight: .medium))
      .foregroundColor(.secondary)
      .padding(.horizontal, 16)
      .padding(.vertical, 6)
      .background(Color.primary.opacity(0.05))
      .cornerRadius(6)
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

      BottomBarButton(icon: "doc.on.doc", tooltip: "Copy to clipboard") {
        copyToClipboard()
      }

      BottomBarButton(icon: "icloud.and.arrow.up", tooltip: "Upload") {
        upload()
      }
      .disabled(true)
      .opacity(0.5)
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

  private func copyToClipboard() {
    AnnotateExporter.copyToClipboard(state: state)
  }

  private func upload() {
    // Placeholder for future implementation
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
