//
//  ZoomSettingsPopover.swift
//  Snapzy
//
//  Settings popover for editing selected zoom segment properties
//

import SwiftUI

/// Popover for editing zoom segment settings
struct ZoomSettingsPopover: View {
  @ObservedObject var state: VideoEditorState
  let previewImage: NSImage?

  @State private var localZoomLevel: CGFloat = 2.0
  @State private var localCenter: CGPoint = CGPoint(x: 0.5, y: 0.5)

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
      syncLocalState()
    }
  }

  // MARK: - Sections

  private var header: some View {
    HStack {
      Image(systemName: "plus.magnifyingglass")
        .foregroundColor(ZoomColors.primary)

      Text("Zoom Settings")
        .font(.system(size: 12, weight: .semibold))

      Spacer()

      if let segment = selectedSegment {
        Text(segment.zoomType.displayName)
          .font(.system(size: 9, weight: .medium))
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(ZoomColors.primary.opacity(0.2))
          .cornerRadius(4)
      }
    }
  }

  private var zoomLevelSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Zoom Level")
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
          value: $localZoomLevel,
          in: ZoomSegment.minZoomLevel...ZoomSegment.maxZoomLevel,
          step: 0.1
        ) { isEditing in
          if !isEditing {
            applyZoomLevel()
          }
        }

        Text("4x")
          .font(.system(size: 9))
          .foregroundColor(.secondary)
      }

      // Quick presets
      HStack(spacing: 4) {
        ForEach([1.5, 2.0, 2.5, 3.0], id: \.self) { level in
          Button {
            localZoomLevel = level
            applyZoomLevel()
          } label: {
            Text("\(String(format: "%.1f", level))x")
              .font(.system(size: 9, weight: .medium))
              .padding(.horizontal, 6)
              .padding(.vertical, 3)
              .background(
                localZoomLevel == level
                  ? ZoomColors.primary.opacity(0.3)
                  : Color.white.opacity(0.1)
              )
              .cornerRadius(4)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var centerPickerSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Zoom Center")
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.secondary)

      ZoomCenterPicker(
        center: $localCenter,
        previewImage: previewImage
      )
      .onChange(of: localCenter) { newValue in
        applyCenter(newValue)
      }

      // Quick position presets
      HStack(spacing: 4) {
        ForEach(centerPresets, id: \.name) { preset in
          Button {
            localCenter = preset.point
            applyCenter(preset.point)
          } label: {
            Image(systemName: preset.icon)
              .font(.system(size: 10))
              .frame(width: 24, height: 24)
              .background(
                isNearPreset(localCenter, preset.point)
                  ? ZoomColors.primary.opacity(0.3)
                  : Color.white.opacity(0.1)
              )
              .cornerRadius(4)
          }
          .buttonStyle(.plain)
          .help(preset.name)
        }
      }
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
          Text(selectedSegment?.isEnabled == true ? "Enabled" : "Disabled")
        }
        .font(.system(size: 10))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.1))
        .cornerRadius(4)
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
          .cornerRadius(4)
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
      CenterPreset(name: "Top Left", icon: "arrow.up.left", point: CGPoint(x: 0.25, y: 0.25)),
      CenterPreset(name: "Top Right", icon: "arrow.up.right", point: CGPoint(x: 0.75, y: 0.25)),
      CenterPreset(name: "Center", icon: "circle", point: CGPoint(x: 0.5, y: 0.5)),
      CenterPreset(name: "Bottom Left", icon: "arrow.down.left", point: CGPoint(x: 0.25, y: 0.75)),
      CenterPreset(name: "Bottom Right", icon: "arrow.down.right", point: CGPoint(x: 0.75, y: 0.75)),
    ]
  }

  private func isNearPreset(_ point: CGPoint, _ preset: CGPoint) -> Bool {
    abs(point.x - preset.x) < 0.1 && abs(point.y - preset.y) < 0.1
  }

  // MARK: - Actions

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
    state: {
      let state = VideoEditorState(url: URL(fileURLWithPath: "/tmp/test.mov"))
      return state
    }(),
    previewImage: nil
  )
  .background(Color(NSColor.windowBackgroundColor))
}
