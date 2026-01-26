//
//  VideoEditorRightSidebar.swift
//  ClaudeShot
//
//  Tabbed right sidebar for video editor with Zoom and Background settings
//  Uses vertical tab bar on right edge for better scalability
//

import SwiftUI

/// Tab selection for right sidebar
enum VideoEditorSidebarTab: String, CaseIterable {
  case background = "Background"
  case zoom = "Zoom"

  var icon: String {
    switch self {
    case .background: return "rectangle.on.rectangle"
    case .zoom: return "plus.magnifyingglass"
    }
  }
}

/// Tabbed right sidebar combining Zoom and Background settings
/// Layout: [Content Area] | [Vertical Tab Bar]
struct VideoEditorRightSidebar: View {
  @ObservedObject var state: VideoEditorState
  let previewImage: NSImage?

  @State private var selectedTab: VideoEditorSidebarTab = .background

  var body: some View {
    HStack(spacing: 0) {
      // Content area (left side)
      tabContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      Divider()

      // Vertical tab bar (right side)
      VerticalTabBar(
        selection: $selectedTab,
        tabs: VideoEditorSidebarTab.allCases
      ) { tab in
        (icon: tab.icon, title: tab.rawValue)
      }
    }
    .frame(width: 320)
    .frame(maxHeight: .infinity)
    .onChange(of: state.selectedZoomId) { _, newValue in
      // Auto-switch to zoom tab when a zoom is selected
      if newValue != nil {
        withAnimation(.easeInOut(duration: 0.15)) {
          selectedTab = .zoom
        }
      }
    }
  }

  // MARK: - Tab Content

  @ViewBuilder
  private var tabContent: some View {
    switch selectedTab {
    case .zoom:
      ZoomSettingsContent(state: state, previewImage: previewImage)
    case .background:
      VideoBackgroundSidebarView(state: state)
    }
  }
}

/// Zoom settings content (extracted from ZoomSettingsPopover for tab use)
struct ZoomSettingsContent: View {
  @ObservedObject var state: VideoEditorState
  let previewImage: NSImage?

  @State private var localZoomLevel: CGFloat = 2.0
  @State private var localCenter: CGPoint = CGPoint(x: 0.5, y: 0.5)

  private var selectedSegment: ZoomSegment? {
    state.selectedZoomSegment
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: 12) {
        if selectedSegment != nil {
          // Zoom level slider
          zoomLevelSection

          // Center picker
          centerPickerSection

          Divider()

          // Actions
          actionsSection
        } else {
          // Empty state
          emptyState
        }

        Spacer(minLength: 20)
      }
      .padding(12)
    }
    .frame(maxHeight: .infinity)
    .onAppear {
      syncLocalState()
    }
    .onChange(of: state.selectedZoomId) { _, _ in
      syncLocalState()
    }
  }

  // MARK: - Empty State

  private var emptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: "plus.magnifyingglass")
        .font(.system(size: 32))
        .foregroundColor(.secondary.opacity(0.5))

      Text("No Zoom Selected")
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(.secondary)

      Text("Press Z to add a zoom at the playhead, or click on a zoom segment in the timeline.")
        .font(.system(size: 11))
        .foregroundColor(.secondary.opacity(0.7))
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
  }

  // MARK: - Sections

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
      .onChange(of: localCenter) { _, newValue in
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
