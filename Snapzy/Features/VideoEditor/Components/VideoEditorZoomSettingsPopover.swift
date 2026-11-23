//
//  VideoEditorZoomSettingsPopover.swift
//  Snapzy
//
//  Settings popover for editing selected zoom segment properties
//

import SwiftUI

/// Popover for editing zoom segment settings
struct ZoomSettingsPopover: View {
  @ObservedObject var state: VideoEditorState
  let previewImage: NSImage?

  @State private var editingSegmentId: UUID?

  @State private var localZoomLevel: CGFloat = 2.0
  @State private var localCenter: CGPoint = .init(x: 0.5, y: 0.5)

  private var selectedSegment: ZoomSegment? {
    state.selectedZoomSegment
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Header
      header

      Divider()

      // Zoom level slider
      zoomLevelSection

      // Center picker
      centerPickerSection

      Divider()

      // Actions
      actionsSection

      Spacer(minLength: 0)
    }
    .padding(12)
    .frame(width: 320, alignment: .topLeading)
    .frame(maxHeight: .infinity, alignment: .top)
    .onAppear {
      syncLocalState()
    }
    .onChange(of: state.selectedZoomId) { _ in
      endContinuousEdit()
      syncLocalState()
    }
    .onDisappear { endContinuousEdit() }
    .accessibilityIdentifier("video-editor.zoom-settings")
  }

  // MARK: - Sections

  private var header: some View {
    HStack(spacing: 6) {
      Text(L10n.VideoEditor.zoomSettings)
        .font(Typography.sectionHeader)
        .foregroundColor(SidebarColors.labelPrimary)

      Spacer()

      if let segment = selectedSegment {
        Text(segment.zoomType.displayName)
          .font(.system(size: 10, weight: .medium))
          .foregroundColor(SidebarColors.labelSecondary)
      }
    }
  }

  private var zoomLevelSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(L10n.VideoEditor.zoomLevel)
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(.secondary)

        Spacer()

        Text(String(format: "%.0f%%", localZoomLevel * 100))
          .font(.system(size: 11, weight: .semibold))
          .monospacedDigit()
      }

      HStack(spacing: 8) {
        Text("1x")
          .font(.system(size: 9))
          .foregroundColor(.secondary)

        Slider(
          value: $localZoomLevel.stepped(by: 0.1, in: ZoomSegment.minZoomLevel ... ZoomSegment.maxZoomLevel),
          in: ZoomSegment.minZoomLevel ... ZoomSegment.maxZoomLevel
        ) { isEditing in
          if isEditing {
            beginContinuousEdit()
          } else {
            applyZoomLevel()
            endContinuousEdit()
          }
        }
        .accessibilityIdentifier("video-editor.zoom-level")

        Text("4x")
          .font(.system(size: 9))
          .foregroundColor(.secondary)
      }

      // Quick presets
      HStack(spacing: 2) {
        ForEach([1.5, 2.0, 2.5, 3.0], id: \.self) { level in
          let isSelected = abs(localZoomLevel - level) < 0.05
          Button {
            localZoomLevel = level
            applyZoomLevel()
          } label: {
            Text("\(String(format: "%.1f", level))×")
              .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
              .monospacedDigit()
              .foregroundColor(isSelected ? SidebarColors.labelPrimary : SidebarColors.labelSecondary)
              .frame(maxWidth: .infinity)
              .frame(height: 20)
              .background {
                if isSelected {
                  Radius.controlRect(forHeight: 20)
                    .fill(Color.primary.opacity(0.11))
                    .overlay(
                      Radius.controlRect(forHeight: 20)
                        .strokeBorder(Color.primary.opacity(0.13), lineWidth: 0.5)
                    )
                }
              }
              .contentShape(Radius.controlRect(forHeight: 20))
          }
          .buttonStyle(.plain)
        }
      }
      .padding(2)
      .background(
        Radius.controlRect(forHeight: 24)
          .fill(Color.primary.opacity(0.05))
          .overlay(
            Radius.controlRect(forHeight: 24)
              .strokeBorder(Color.primary.opacity(0.075), lineWidth: 0.5)
          )
      )
    }
  }

  private var centerPickerSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(L10n.VideoEditor.zoomCenter)
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.secondary)

      ZoomCenterPicker(
        center: $localCenter,
        previewImage: previewImage,
        onEditingChanged: { editing in
          if editing {
            beginContinuousEdit()
          } else {
            endContinuousEdit()
          }
        },
        onCenterChanged: applyCenter
      )

      // Quick position presets
      HStack(spacing: 2) {
        ForEach(centerPresets, id: \.name) { preset in
          let isSelected = isNearPreset(localCenter, preset.point)
          Button {
            localCenter = preset.point
            applyCenter(preset.point)
          } label: {
            Image(systemName: preset.icon)
              .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
              .foregroundColor(isSelected ? SidebarColors.labelPrimary : SidebarColors.labelSecondary)
              .frame(maxWidth: .infinity)
              .frame(height: 22)
              .background {
                if isSelected {
                  Radius.controlRect(forHeight: 22)
                    .fill(Color.primary.opacity(0.11))
                    .overlay(
                      Radius.controlRect(forHeight: 22)
                        .strokeBorder(Color.primary.opacity(0.13), lineWidth: 0.5)
                    )
                }
              }
              .contentShape(Radius.controlRect(forHeight: 22))
          }
          .buttonStyle(.plain)
          .help(preset.name)
        }
      }
      .padding(2)
      .background(
        Radius.controlRect(forHeight: 26)
          .fill(Color.primary.opacity(0.05))
          .overlay(
            Radius.controlRect(forHeight: 26)
              .strokeBorder(Color.primary.opacity(0.075), lineWidth: 0.5)
          )
      )
    }
  }

  private var actionsSection: some View {
    HStack(spacing: 8) {
      // Enable/Disable toggle
      Button {
        if let id = state.selectedZoomId {
          state.toggleZoomEnabled(id: id)
        }
      } label: {
        HStack(spacing: 4) {
          Image(systemName: selectedSegment?.isEnabled == true ? "eye" : "eye.slash")
          Text(selectedSegment?.isEnabled == true ? L10n.Common.enabled : L10n.Common.disabled)
        }
        .font(.system(size: 10))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.1))
        .clipShape(Radius.controlRect(forHeight: 20))
      }
      .buttonStyle(.plain)

      Spacer()

      // Delete button
      Button(role: .destructive) {
        if let id = state.selectedZoomId {
          state.removeZoom(id: id)
        }
      } label: {
        Image(systemName: "trash")
          .font(.system(size: 10))
          .foregroundColor(.red)
          .padding(6)
          .background(Color.red.opacity(0.1))
          .clipShape(Radius.controlRect(forHeight: 24))
      }
      .buttonStyle(.plain)
    }
  }

  // MARK: - Center Presets

  private struct CenterPreset {
    let name: String
    let icon: String
    let point: CGPoint
  }

  private var centerPresets: [CenterPreset] {
    [
      CenterPreset(name: L10n.VideoEditor.topLeft, icon: "arrow.up.left", point: CGPoint(x: 0.25, y: 0.25)),
      CenterPreset(name: L10n.VideoEditor.topRight, icon: "arrow.up.right", point: CGPoint(x: 0.75, y: 0.25)),
      CenterPreset(name: L10n.VideoEditor.center, icon: "circle", point: CGPoint(x: 0.5, y: 0.5)),
      CenterPreset(name: L10n.VideoEditor.bottomLeft, icon: "arrow.down.left", point: CGPoint(x: 0.25, y: 0.75)),
      CenterPreset(name: L10n.VideoEditor.bottomRight, icon: "arrow.down.right", point: CGPoint(x: 0.75, y: 0.75)),
    ]
  }

  private func isNearPreset(_ point: CGPoint, _ preset: CGPoint) -> Bool {
    abs(point.x - preset.x) < 0.1 && abs(point.y - preset.y) < 0.1
  }

  // MARK: - Actions

  private func beginContinuousEdit() {
    guard editingSegmentId == nil, let id = state.selectedZoomId else { return }
    editingSegmentId = id
    state.beginZoomEdit(id: id)
  }

  private func endContinuousEdit() {
    guard let id = editingSegmentId else { return }
    state.endZoomEdit(id: id)
    editingSegmentId = nil
  }

  private func syncLocalState() {
    if let segment = selectedSegment {
      localZoomLevel = segment.zoomLevel
      localCenter = segment.zoomCenter
    }
  }

  private func applyZoomLevel() {
    guard let id = state.selectedZoomId else { return }
    state.updateZoom(id: id, zoomLevel: localZoomLevel)
  }

  private func applyCenter(_ center: CGPoint) {
    guard let id = state.selectedZoomId else { return }
    state.updateZoom(id: id, zoomCenter: center)
  }
}

// MARK: - Preview

#Preview {
  ZoomSettingsPopover(
    state: VideoEditorState(url: URL(fileURLWithPath: "/tmp/test.mov")),
    previewImage: nil
  )
  .background(Color(NSColor.windowBackgroundColor))
}
