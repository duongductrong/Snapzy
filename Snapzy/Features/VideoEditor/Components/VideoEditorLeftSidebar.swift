//
//  VideoEditorLeftSidebar.swift
//  Snapzy
//
//  Left sidebar panels for video editor background controls and zoom configuration
//

import SwiftUI

/// Left sidebar hosting the panel selected in the collapsed rail: background
/// and canvas settings, or zoom item configuration.
struct VideoEditorLeftSidebar: View {
  @ObservedObject var state: VideoEditorState
  let previewImage: NSImage?

  var body: some View {
    switch state.leftSidebarPanel {
    case .background:
      VideoBackgroundSidebarView(state: state)
        .frame(width: 240)
        .frame(maxHeight: .infinity)
    case .zoom:
      ZoomSettingsContent(state: state, previewImage: previewImage)
        .frame(width: 320)
        .frame(maxHeight: .infinity)
    case .cursor:
      VideoEditorCursorSettingsPanel(state: state)
        .frame(width: 240)
        .frame(maxHeight: .infinity)
    case .camera:
      VideoEditorCameraSettingsPanel(state: state)
        .frame(width: 240)
        .frame(maxHeight: .infinity)
    case .captions:
      VideoEditorCaptionsPanel(state: state)
        .frame(width: 240)
        .frame(maxHeight: .infinity)
    }
  }
}

struct ZoomSettingsContent: View {
  @ObservedObject var state: VideoEditorState
  let previewImage: NSImage?

  @State private var editingSegmentId: UUID?

  @State private var localZoomLevel: CGFloat = ZoomSegment.defaultZoomLevel
  @State private var localCenter: CGPoint = .init(x: 0.5, y: 0.5)
  @State private var localFollowSpeed: Double = AutoFocusSettings.defaultFollowSpeed
  @State private var localFocusMargin: CGFloat = AutoFocusSettings.defaultFocusMargin
  @State private var localTransitionDuration: TimeInterval = ZoomCalculator.defaultTransitionDuration
  @State private var motionBlurDragStart: VideoEditorMotionBlurSettings?

  @Namespace private var smartStyleNamespace
  @Namespace private var zoomModeNamespace
  @State private var hoveredSmartStyle: SmartAutoZoomStyle?
  @State private var hoveredMode: ZoomType?
  @State private var isHoveringSmartAction = false
  @State private var isHoveringEnableAction = false
  @State private var isHoveringDeleteAction = false

  private struct LocalStateSnapshot: Equatable {
    let id: UUID
    let zoomType: ZoomType
    let zoomLevel: CGFloat
    let zoomCenter: CGPoint
    let followSpeed: Double
    let focusMargin: CGFloat
    let transitionDuration: TimeInterval
  }

  private var selectedSegment: ZoomSegment? {
    state.selectedZoomSegment
  }

  private var localStateSnapshot: LocalStateSnapshot? {
    guard let segment = selectedSegment else { return nil }
    return LocalStateSnapshot(
      id: segment.id,
      zoomType: segment.zoomType,
      zoomLevel: segment.zoomLevel,
      zoomCenter: segment.zoomCenter,
      followSpeed: segment.followSpeed,
      focusMargin: segment.focusMargin,
      transitionDuration: state.zoomTransitionDuration
    )
  }

  private var canSwitchSelectedSegmentToAuto: Bool {
    state.hasMouseTrackingData || selectedSegment?.isAutoMode == true
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: 10) {
        if state.hasMouseTrackingData {
          smartAutoZoomSection
        }

        motionBlurSection

        if let segment = selectedSegment {
          selectedSegmentCard(for: segment)
        } else {
          emptyState
        }

        Spacer(minLength: 16)
      }
      .padding(12)
    }
    .frame(maxHeight: .infinity)
    .onAppear {
      syncLocalState()
    }
    .onChange(of: state.selectedZoomId) { _ in
      endContinuousEdit()
    }
    .onChange(of: localStateSnapshot) { _ in
      syncLocalState()
    }
    .onDisappear { endContinuousEdit() }
    .accessibilityIdentifier("video-editor.zoom-settings")
  }

  // MARK: - Inspector Surface & Rail Primitives

  private func inspectorCard(@ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      content()
    }
    .padding(11)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Radius.rect(Radius.card)
        .fill(Color.primary.opacity(0.035))
        .overlay(
          Radius.rect(Radius.card)
            .strokeBorder(Color.primary.opacity(0.075), lineWidth: 0.5)
        )
    )
  }

  private var railBackground: some View {
    Radius.controlRect(forHeight: 26)
      .fill(Color.primary.opacity(0.05))
      .overlay(
        Radius.controlRect(forHeight: 26)
          .strokeBorder(Color.primary.opacity(0.075), lineWidth: 0.5)
      )
  }

  private var activeThumbShape: some View {
    Radius.controlRect(forHeight: 22)
      .fill(Color.primary.opacity(0.11))
      .overlay(
        Radius.controlRect(forHeight: 22)
          .strokeBorder(Color.primary.opacity(0.13), lineWidth: 0.5)
      )
  }

  // MARK: - Smart Auto-Zoom Section

  private var smartAutoZoomSection: some View {
    let hasZooms = !state.zoomSegments.isEmpty

    return inspectorCard {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(L10n.VideoEditor.smartAutoZoomTitle)
          .font(Typography.sectionHeader)
          .foregroundColor(SidebarColors.labelPrimary)

        Spacer()

        if hasZooms {
          Text("\(state.zoomSegments.count)")
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundColor(SidebarColors.labelSecondary)
            .contentTransition(.numericText())
        }
      }

      HStack(spacing: 2) {
        ForEach(SmartAutoZoomStyle.allCases, id: \.self) { style in
          smartStyleOption(style)
        }
      }
      .padding(2)
      .background(railBackground)

      Button {
        state.generateSmartAutoZoom(style: state.smartAutoZoomStyle)
      } label: {
        HStack(spacing: 6) {
          if state.isGeneratingSmartAutoZoom {
            ProgressView()
              .controlSize(.small)
              .scaleEffect(0.7)
          } else {
            Image(systemName: hasZooms ? "arrow.clockwise" : "viewfinder")
              .font(.system(size: 10.5, weight: .semibold))
          }

          Text(
            state.isGeneratingSmartAutoZoom
              ? L10n.VideoEditor.smartAutoZoomAnalyzing
              : (hasZooms
                  ? L10n.VideoEditor.smartAutoZoomRegenerate
                  : L10n.VideoEditor.smartAutoZoomGenerate)
          )
          .font(.system(size: 11, weight: .semibold))
          .lineLimit(1)
        }
        .foregroundColor(hasZooms ? SidebarColors.labelPrimary : LiquidGlassTokens.inkOnAccent)
        .frame(maxWidth: .infinity)
        .frame(height: 27)
        .background {
          if hasZooms {
            Radius.controlRect(forHeight: 27)
              .fill(Color.primary.opacity(isHoveringSmartAction ? 0.105 : 0.06))
              .overlay(
                Radius.controlRect(forHeight: 27)
                  .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5)
              )
          } else {
            Radius.controlRect(forHeight: 27)
              .fill(Color.accentColor.opacity(isHoveringSmartAction ? 0.90 : 1.0))
          }
        }
        .animation(.easeOut(duration: 0.12), value: isHoveringSmartAction)
        .contentShape(Radius.controlRect(forHeight: 27))
      }
      .buttonStyle(.plain)
      .onHover { isHoveringSmartAction = $0 }
      .disabled(state.isGeneratingSmartAutoZoom)
      .opacity(state.isGeneratingSmartAutoZoom ? 0.72 : 1.0)
      .accessibilityIdentifier("video-editor.smart-auto-zoom")

      Text(L10n.VideoEditor.smartAutoZoomDescription)
        .font(.system(size: 10))
        .foregroundColor(SidebarColors.labelTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func smartStyleOption(_ style: SmartAutoZoomStyle) -> some View {
    let isSelected = state.smartAutoZoomStyle == style
    let isHovered = hoveredSmartStyle == style
    let title: String = switch style {
    case .subtle: L10n.VideoEditor.smartAutoZoomSubtle
    case .balanced: L10n.VideoEditor.smartAutoZoomBalanced
    case .dynamic: L10n.VideoEditor.smartAutoZoomDynamic
    }

    return Button {
      withAnimation(LiquidGlassTokens.settleSpring) {
        state.smartAutoZoomStyle = style
      }
    } label: {
      Text(title)
        .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
        .foregroundColor(isSelected ? SidebarColors.labelPrimary : SidebarColors.labelSecondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .frame(height: 22)
        .background {
          if isSelected {
            activeThumbShape
              .matchedGeometryEffect(id: "smartStyleThumb", in: smartStyleNamespace)
          } else if isHovered {
            Radius.controlRect(forHeight: 22)
              .fill(Color.primary.opacity(0.05))
          }
        }
        .animation(.easeOut(duration: 0.10), value: isHovered)
        .contentShape(Radius.controlRect(forHeight: 22))
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      hoveredSmartStyle = hovering ? style : (hoveredSmartStyle == style ? nil : hoveredSmartStyle)
    }
  }

  // MARK: - Motion Blur Section

  private var motionBlurSection: some View {
    inspectorCard {
      HStack(alignment: .center, spacing: 8) {
        Text(L10n.VideoEditor.motionBlurTitle)
          .font(Typography.sectionHeader)
          .foregroundColor(SidebarColors.labelPrimary)

        Spacer()

        Toggle(
          "",
          isOn: Binding(
            get: { state.motionBlurSettings.isEnabled },
            set: { newValue in
              withAnimation(LiquidGlassTokens.settleSpring) {
                var updated = state.motionBlurSettings
                updated.isEnabled = newValue
                if newValue, updated.shutterStrength <= 0.01 {
                  updated.shutterStrength = VideoEditorMotionBlurSettings.defaultShutterStrength
                }
                state.setMotionBlurSettings(updated)
              }
            }
          )
        )
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
        .accessibilityIdentifier("video-editor.motion-blur-toggle")
      }

      if state.motionBlurSettings.isEnabled {
        VStack(alignment: .leading, spacing: 8) {
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(L10n.VideoEditor.motionBlurStrength)
                .font(Typography.labelMedium)
                .foregroundColor(SidebarColors.labelSecondary)

              Spacer()

              Text(state.motionBlurSettings.strengthDisplayValue)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            }

            Slider(
              value: Binding(
                get: { state.motionBlurSettings.shutterStrength },
                set: { newValue in
                  var updated = state.motionBlurSettings
                  updated.shutterStrength = VideoEditorMotionBlurSettings.clampStrength(newValue)
                  state.setMotionBlurSettings(updated, recordUndo: motionBlurDragStart == nil)
                }
              ),
              in: VideoEditorMotionBlurSettings.strengthRange
            ) { editing in
              if editing {
                motionBlurDragStart = state.motionBlurSettings
              } else if let start = motionBlurDragStart {
                motionBlurDragStart = nil
                state.commitMotionBlurSettings(from: start)
              }
            }
            .controlSize(.small)
            .accessibilityIdentifier("video-editor.motion-blur-strength")
          }

          if state.hasEditableCursor {
            HStack {
              Text(L10n.VideoEditor.motionBlurCursor)
                .font(Typography.labelMedium)
                .foregroundColor(SidebarColors.labelSecondary)

              Spacer()

              Toggle(
                "",
                isOn: Binding(
                  get: { state.motionBlurSettings.cursorBlurEnabled },
                  set: { newValue in
                    var updated = state.motionBlurSettings
                    updated.cursorBlurEnabled = newValue
                    state.setMotionBlurSettings(updated)
                  }
                )
              )
              .labelsHidden()
              .toggleStyle(.switch)
              .controlSize(.small)
            }
          }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }

      Text(L10n.VideoEditor.motionBlurDescription)
        .font(.system(size: 10))
        .foregroundColor(SidebarColors.labelTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - Selected Zoom Segment Card

  private func selectedSegmentCard(for segment: ZoomSegment) -> some View {
    inspectorCard {
      modeSection(for: segment)

      Divider()
        .opacity(0.6)

      zoomLevelSection

      transitionSmoothnessSection

      if segment.isAutoMode {
        followSpeedSection
        focusMarginSection
      } else {
        centerPickerSection
      }
    }
  }

  private func modeSection(for segment: ZoomSegment) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Text(L10n.VideoEditor.zoomItem)
          .font(Typography.sectionHeader)
          .foregroundColor(SidebarColors.labelPrimary)

        Spacer()

        Button {
          if let id = state.selectedZoomId {
            state.toggleZoomEnabled(id: id)
          }
        } label: {
          Image(systemName: segment.isEnabled ? "eye" : "eye.slash")
            .font(.system(size: 10.5, weight: .medium))
            .foregroundColor(segment.isEnabled ? SidebarColors.labelSecondary : SidebarColors.labelTertiary)
            .frame(width: 22, height: 22)
            .background(
              Radius.controlRect(forHeight: 22)
                .fill(isHoveringEnableAction ? SidebarColors.itemHover : .clear)
            )
            .animation(.easeOut(duration: 0.10), value: isHoveringEnableAction)
        }
        .buttonStyle(.plain)
        .onHover { isHoveringEnableAction = $0 }
        .help(segment.isEnabled ? L10n.VideoEditor.disableZoom : L10n.VideoEditor.enableZoom)

        Button(role: .destructive) {
          if let id = state.selectedZoomId {
            state.removeZoom(id: id)
          }
        } label: {
          Image(systemName: "trash")
            .font(.system(size: 10.5, weight: .medium))
            .foregroundColor(isHoveringDeleteAction ? .red : SidebarColors.labelSecondary)
            .frame(width: 22, height: 22)
            .background(
              Radius.controlRect(forHeight: 22)
                .fill(isHoveringDeleteAction ? Color.red.opacity(0.12) : .clear)
            )
            .animation(.easeOut(duration: 0.10), value: isHoveringDeleteAction)
        }
        .buttonStyle(.plain)
        .onHover { isHoveringDeleteAction = $0 }
        .help(L10n.VideoEditor.deleteZoom)
      }

      HStack(spacing: 2) {
        modeOption(
          type: .manual,
          title: L10n.VideoEditor.manual,
          icon: "hand.tap",
          isSelected: !segment.isAutoMode,
          isDisabled: false
        ) {
          applyZoomMode(.manual)
        }

        modeOption(
          type: .auto,
          title: L10n.VideoEditor.auto,
          icon: "scope",
          isSelected: segment.isAutoMode,
          isDisabled: !canSwitchSelectedSegmentToAuto
        ) {
          applyZoomMode(.auto)
        }
      }
      .padding(2)
      .background(railBackground)

      if segment.isAutoMode {
        if state.hasMouseTrackingData {
          Text(L10n.VideoEditor.followMouseActiveDescription)
            .font(.system(size: 10))
            .foregroundColor(SidebarColors.labelTertiary)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          availabilityWarning
        }
      } else if state.hasMouseTrackingData {
        Text(L10n.VideoEditor.manualModeDescription)
          .font(.system(size: 10))
          .foregroundColor(SidebarColors.labelTertiary)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        availabilityWarning
      }
    }
  }

  private func modeOption(
    type: ZoomType,
    title: String,
    icon: String,
    isSelected: Bool,
    isDisabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    let isHovered = hoveredMode == type && !isDisabled

    return Button {
      withAnimation(LiquidGlassTokens.settleSpring) {
        action()
      }
    } label: {
      HStack(spacing: 5) {
        Image(systemName: icon)
          .font(.system(size: 10, weight: .medium))

        Text(title)
          .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
          .lineLimit(1)
      }
      .foregroundColor(
        isDisabled
          ? SidebarColors.labelTertiary
          : (isSelected ? SidebarColors.labelPrimary : SidebarColors.labelSecondary)
      )
      .frame(maxWidth: .infinity)
      .frame(height: 22)
      .background {
        if isSelected {
          activeThumbShape
            .matchedGeometryEffect(id: "zoomModeThumb", in: zoomModeNamespace)
        } else if isHovered {
          Radius.controlRect(forHeight: 22)
            .fill(Color.primary.opacity(0.05))
        }
      }
      .animation(.easeOut(duration: 0.10), value: isHovered)
      .contentShape(Radius.controlRect(forHeight: 22))
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      hoveredMode = hovering ? type : (hoveredMode == type ? nil : hoveredMode)
    }
    .disabled(isDisabled)
    .opacity(isDisabled ? 0.45 : 1.0)
  }

  private var availabilityWarning: some View {
    VStack(alignment: .leading, spacing: 4) {
      Label(L10n.VideoEditor.mouseTrackingDataUnavailable, systemImage: "cursorarrow.slash")
        .font(.system(size: 10.5, weight: .medium))
        .foregroundColor(SidebarColors.labelSecondary)

      Text(L10n.VideoEditor.followMouseOnlyWorksWithSnapzy)
        .font(.system(size: 10))
        .foregroundColor(SidebarColors.labelTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Radius.rect(Radius.tile).fill(Color.primary.opacity(0.04)))
  }

  private var emptyState: some View {
    inspectorCard {
      VStack(spacing: 6) {
        Image(systemName: "plus.magnifyingglass")
          .font(.system(size: 18, weight: .regular))
          .foregroundColor(SidebarColors.labelTertiary)

        Text(L10n.VideoEditor.noZoomSelected)
          .font(.system(size: 11.5, weight: .medium))
          .foregroundColor(SidebarColors.labelSecondary)

        Text(L10n.VideoEditor.pressZToAddZoom)
          .font(.system(size: 10))
          .foregroundColor(SidebarColors.labelTertiary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 14)
    }
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

      Slider(
        value: $localFollowSpeed.stepped(by: 0.05, in: AutoFocusSettings.followSpeedRange),
        in: AutoFocusSettings.followSpeedRange
      ) { isEditing in
        if isEditing {
          beginContinuousEdit()
        } else {
          applyFollowSpeed()
          endContinuousEdit()
        }
      }
      .accessibilityIdentifier("video-editor.follow-speed")

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
          value: $localTransitionDuration.stepped(by: 0.05, in: ZoomCalculator.transitionDurationRange),
          in: ZoomCalculator.transitionDurationRange
        ) { isEditing in
          if !isEditing {
            applyTransitionDuration()
          }
        }

        Text(L10n.VideoEditor.smooth)
          .font(.system(size: 9))
          .foregroundColor(.secondary)
      }

      HStack(spacing: 2) {
        ForEach(transitionPresets, id: \.title) { preset in
          let isSelected = abs(localTransitionDuration - preset.value) < 0.02
          Button {
            localTransitionDuration = preset.value
            applyTransitionDuration()
          } label: {
            Text(preset.title)
              .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
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

      Slider(
        value: $localFocusMargin.stepped(by: 0.05, in: AutoFocusSettings.focusMarginRange),
        in: AutoFocusSettings.focusMarginRange
      ) { isEditing in
        if isEditing {
          beginContinuousEdit()
        } else {
          applyFocusMargin()
          endContinuousEdit()
        }
      }
      .accessibilityIdentifier("video-editor.focus-margin")

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
        previewImage: previewImage,
        onEditingChanged: { editing in
          if editing { beginContinuousEdit() } else { endContinuousEdit() }
        },
        onCenterChanged: applyCenter
      )

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
              .clipShape(Radius.controlRect(forHeight: 24))
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
