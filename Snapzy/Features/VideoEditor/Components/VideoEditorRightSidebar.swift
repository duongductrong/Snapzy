//
//  VideoEditorRightSidebar.swift
//  Snapzy
//
//  Tabbed right sidebar for video editor with Zoom and Background settings
//  Uses vertical tab bar on right edge for better scalability
//

import SwiftUI

/// Tab selection for right sidebar
enum VideoEditorSidebarTab: CaseIterable {
  case background
  case zoom

  var icon: String {
    switch self {
    case .background: return "rectangle.on.rectangle"
    case .zoom: return "plus.magnifyingglass"
    }
  }

  var title: String {
    switch self {
    case .background: return L10n.VideoEditor.backgroundTab
    case .zoom: return L10n.VideoEditor.zoomTab
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
      tabContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      Divider()

      VerticalTabBar(
        selection: $selectedTab,
        tabs: VideoEditorSidebarTab.allCases
      ) { tab in
        (icon: tab.icon, title: tab.title)
      }
    }
    .frame(width: 320)
    .frame(maxHeight: .infinity)
    .onChange(of: state.selectedZoomId) { newValue in
      if newValue != nil {
        withAnimation(.easeInOut(duration: 0.15)) {
          selectedTab = .zoom
        }
      }
    }
  }

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

struct ZoomSettingsContent: View {
  @ObservedObject var state: VideoEditorState
  let previewImage: NSImage?

  @State private var localZoomLevel: CGFloat = ZoomSegment.defaultZoomLevel
  @State private var localCenter: CGPoint = CGPoint(x: 0.5, y: 0.5)
  @State private var localFollowSpeed: Double = AutoFocusSettings.defaultFollowSpeed
  @State private var localFocusMargin: CGFloat = AutoFocusSettings.defaultFocusMargin
  @State private var localTransitionDuration: TimeInterval = ZoomCalculator.defaultTransitionDuration

  private var selectedSegment: ZoomSegment? {
    state.selectedZoomSegment
  }

  private var canSwitchSelectedSegmentToAuto: Bool {
    state.hasMouseTrackingData || selectedSegment?.isAutoMode == true
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: 16) {
        if let segment = selectedSegment {
          modeSection(for: segment)

          Divider()

          zoomLevelSection
          transitionSmoothnessSection

          if segment.isAutoMode {
            followSpeedSection
            focusMarginSection
          } else {
            centerPickerSection
          }

          Divider()

          actionsSection
        } else {
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
    .onChange(of: state.selectedZoomId) { _ in
      syncLocalState()
    }
    .onChange(of: state.zoomSegments) { _ in
      syncLocalState()
    }
    .onChange(of: state.zoomTransitionDuration) { _ in
      syncLocalState()
    }
  }

  private func modeSection(for segment: ZoomSegment) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label(L10n.VideoEditor.zoomItem, systemImage: "plus.magnifyingglass")
          .font(.system(size: 12, weight: .semibold))

        Spacer()

        Text(segment.isAutoMode ? L10n.VideoEditor.followMouse : L10n.VideoEditor.manual)
          .font(.system(size: 9, weight: .semibold))
          .padding(.horizontal, 6)
          .padding(.vertical, 3)
          .background((segment.isAutoMode ? Color.green : ZoomColors.primary).opacity(0.18))
          .foregroundColor(segment.isAutoMode ? .green : ZoomColors.primary)
          .cornerRadius(4)
      }

      HStack(spacing: 8) {
        modeButton(
          title: L10n.VideoEditor.manual,
          icon: "hand.tap",
          isSelected: !segment.isAutoMode,
          isDisabled: false
        ) {
          applyZoomMode(.manual)
        }

        modeButton(
          title: L10n.VideoEditor.auto,
          icon: "camera.metering.center.weighted",
          isSelected: segment.isAutoMode,
          isDisabled: !canSwitchSelectedSegmentToAuto
        ) {
          applyZoomMode(.auto)
        }
      }

      if segment.isAutoMode {
        if state.hasMouseTrackingData {
          Text(L10n.VideoEditor.followMouseActiveDescription)
            .font(.system(size: 10))
            .foregroundColor(.secondary.opacity(0.8))
            .fixedSize(horizontal: false, vertical: true)
        } else {
          availabilityWarning
        }
      } else if state.hasMouseTrackingData {
        Text(L10n.VideoEditor.manualModeDescription)
          .font(.system(size: 10))
          .foregroundColor(.secondary.opacity(0.8))
          .fixedSize(horizontal: false, vertical: true)
      } else {
        availabilityWarning
      }
    }
  }

  private func modeButton(
    title: String,
    icon: String,
    isSelected: Bool,
    isDisabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: 10, weight: .semibold))

        Text(title)
          .font(.system(size: 11, weight: .medium))
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 7)
      .background(
        isSelected
          ? ZoomColors.primary.opacity(0.22)
          : Color.white.opacity(0.08)
      )
      .foregroundColor(isDisabled ? .secondary : .primary)
      .cornerRadius(8)
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(isSelected ? ZoomColors.primary.opacity(0.45) : Color.clear, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
    .opacity(isDisabled ? 0.45 : 1.0)
  }

  private var availabilityWarning: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(L10n.VideoEditor.mouseTrackingDataUnavailable, systemImage: "cursorarrow.slash")
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.secondary)

      Text(L10n.VideoEditor.followMouseOnlyWorksWithSnapzy)
        .font(.system(size: 10))
        .foregroundColor(.secondary.opacity(0.8))
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white.opacity(0.06))
    .cornerRadius(8)
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: "plus.magnifyingglass")
        .font(.system(size: 32))
        .foregroundColor(.secondary.opacity(0.5))

      Text(L10n.VideoEditor.noZoomSelected)
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(.secondary)

      Text(L10n.VideoEditor.pressZToAddZoom)
        .font(.system(size: 11))
        .foregroundColor(.secondary.opacity(0.7))
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
  }

  private var zoomLevelSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(L10n.VideoEditor.zoomLevel)
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(.secondary)

        Spacer()

        Text(zoomDisplayValue(for: localZoomLevel))
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
                abs(localZoomLevel - level) < 0.05
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

  private var followSpeedSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(L10n.VideoEditor.followSpeed)
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(.secondary)

        Spacer()

        Text("\(Int((localFollowSpeed * 100).rounded()))%")
          .font(.system(size: 11, weight: .semibold))
          .monospacedDigit()
      }

      Slider(value: $localFollowSpeed, in: AutoFocusSettings.followSpeedRange, step: 0.05) { isEditing in
        if !isEditing {
          applyFollowSpeed()
        }
      }

      Text(L10n.VideoEditor.followSpeedDescription)
        .font(.system(size: 10))
        .foregroundColor(.secondary.opacity(0.8))
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private struct TransitionPreset {
    let title: String
    let value: TimeInterval
  }

  private var transitionPresets: [TransitionPreset] {
    [
      TransitionPreset(title: L10n.VideoEditor.fast, value: ZoomCalculator.fastTransitionDuration),
      TransitionPreset(title: L10n.VideoEditor.balanced, value: ZoomCalculator.balancedTransitionDuration),
      TransitionPreset(title: L10n.VideoEditor.smooth, value: ZoomCalculator.smoothTransitionDuration),
    ]
  }

  private var transitionSmoothnessSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(L10n.VideoEditor.transitionSmoothness)
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(.secondary)

        Spacer()

        Text(transitionDisplayValue(for: localTransitionDuration))
          .font(.system(size: 11, weight: .semibold))
          .monospacedDigit()
      }

      HStack(spacing: 8) {
        Text(L10n.VideoEditor.fast)
          .font(.system(size: 9))
          .foregroundColor(.secondary)

        Slider(
          value: $localTransitionDuration,
          in: ZoomCalculator.transitionDurationRange,
          step: 0.05
        ) { isEditing in
          if !isEditing {
            applyTransitionDuration()
          }
        }

        Text(L10n.VideoEditor.smooth)
          .font(.system(size: 9))
          .foregroundColor(.secondary)
      }

      HStack(spacing: 4) {
        ForEach(transitionPresets, id: \.title) { preset in
          Button {
            localTransitionDuration = preset.value
            applyTransitionDuration()
          } label: {
            Text(preset.title)
              .font(.system(size: 9, weight: .medium))
              .padding(.horizontal, 6)
              .padding(.vertical, 3)
              .background(
                abs(localTransitionDuration - preset.value) < 0.02
                  ? ZoomColors.primary.opacity(0.3)
                  : Color.white.opacity(0.1)
              )
              .cornerRadius(4)
          }
          .buttonStyle(.plain)
        }
      }

      Text(L10n.VideoEditor.transitionAppliesDescription)
        .font(.system(size: 10))
        .foregroundColor(.secondary.opacity(0.8))
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var focusMarginSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(L10n.VideoEditor.focusMargin)
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(.secondary)

        Spacer()

        Text("\(Int((localFocusMargin * 100).rounded()))%")
          .font(.system(size: 11, weight: .semibold))
          .monospacedDigit()
      }

      Slider(value: $localFocusMargin, in: AutoFocusSettings.focusMarginRange, step: 0.05) { isEditing in
        if !isEditing {
          applyFocusMargin()
        }
      }

      Text(L10n.VideoEditor.focusMarginDescription)
        .font(.system(size: 10))
        .foregroundColor(.secondary.opacity(0.8))
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var centerPickerSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(L10n.VideoEditor.zoomCenter)
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.secondary)

      ZoomCenterPicker(
        center: $localCenter,
        previewImage: previewImage
      )
      .onChange(of: localCenter) { newValue in
        applyCenter(newValue)
      }

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

      Text(L10n.VideoEditor.manualCameraControlOnlyInManualMode)
        .font(.system(size: 10))
        .foregroundColor(.secondary.opacity(0.8))
    }
  }

  private var actionsSection: some View {
    HStack(spacing: 8) {
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
        .cornerRadius(4)
      }
      .buttonStyle(.plain)

      Spacer()

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

  private func syncLocalState() {
    localTransitionDuration = state.zoomTransitionDuration

    guard let segment = selectedSegment else { return }
    localZoomLevel = segment.zoomLevel
    localCenter = segment.zoomCenter
    localFollowSpeed = segment.followSpeed
    localFocusMargin = segment.focusMargin
  }

  private func applyZoomMode(_ zoomType: ZoomType) {
    guard let id = state.selectedZoomId else { return }
    state.setZoomMode(id: id, zoomType: zoomType)
  }

  private func applyZoomLevel() {
    guard let id = state.selectedZoomId else { return }
    state.updateZoom(id: id, zoomLevel: localZoomLevel)
  }

  private func applyFollowSpeed() {
    guard let id = state.selectedZoomId else { return }
    state.updateZoom(id: id, followSpeed: localFollowSpeed)
  }

  private func applyFocusMargin() {
    guard let id = state.selectedZoomId else { return }
    state.updateZoom(id: id, focusMargin: localFocusMargin)
  }

  private func applyCenter(_ center: CGPoint) {
    guard let id = state.selectedZoomId else { return }
    state.updateZoom(id: id, zoomCenter: center)
  }

  private func applyTransitionDuration() {
    state.zoomTransitionDuration = localTransitionDuration
  }

  private func zoomDisplayValue(for level: CGFloat) -> String {
    if level == floor(level) {
      return String(format: "%.0fx", level)
    }
    return String(format: "%.1fx", level)
  }

  private func transitionDisplayValue(for duration: TimeInterval) -> String {
    "\(Int((duration * 1000).rounded())) ms"
  }
}
