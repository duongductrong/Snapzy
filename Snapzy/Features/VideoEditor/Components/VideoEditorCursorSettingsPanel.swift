//
//  VideoEditorCursorSettingsPanel.swift
//  Snapzy
//
//  Left sidebar panel for the Studio cursor layer. Recordings without captured cursor
//  data show why the controls are unavailable instead.
//

import SwiftUI

struct VideoEditorCursorSettingsPanel: View {
  @ObservedObject var state: VideoEditorState
  /// Settings before the current slider drag, committed as one undo step on release.
  @State private var dragStart: VideoEditorCursorSettings?

  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: Spacing.md) {
        VideoSidebarSectionHeader(title: L10n.VideoEditor.cursorSection)
        if state.hasEditableCursor {
          controls
        } else {
          Text(L10n.VideoEditor.cursorBakedNotice)
            .font(Typography.labelSmall)
            .foregroundColor(SidebarColors.labelSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: Spacing.lg)
      }
      .padding(Spacing.md)
    }
    .frame(maxHeight: .infinity)
  }

  @ViewBuilder
  private var controls: some View {
    toggle(L10n.VideoEditor.cursorShow, \.isVisible)

    Group {
      slider(L10n.VideoEditor.cursorSize, \.scale, range: VideoEditorCursorSettings.scaleRange) {
        String(format: "%.1f×", $0)
      }
      slider(L10n.VideoEditor.cursorSmoothing, \.smoothing, range: 0 ... 1) {
        String(format: "%.0f%%", $0 * 100)
      }

      Divider()

      toggle(L10n.VideoEditor.cursorHideWhenIdle, \.hideWhenIdle)
      if state.cursorSettings.hideWhenIdle {
        slider(L10n.VideoEditor.cursorIdleDelay, \.idleDelay, range: VideoEditorCursorSettings.idleDelayRange) {
          String(format: "%.1fs", $0)
        }
      }
      toggle(L10n.VideoEditor.cursorAlwaysArrow, \.alwaysUseArrow)

      Divider()

      VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(L10n.VideoEditor.cursorClickEffect)
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelSecondary)
        Picker("", selection: binding(\.clickEffect)) {
          Text(L10n.Common.none).tag(VideoEditorCursorClickEffect.none)
          Text(L10n.VideoEditor.cursorClickRipple).tag(VideoEditorCursorClickEffect.ripple)
          Text(L10n.VideoEditor.cursorClickRing).tag(VideoEditorCursorClickEffect.ring)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
      }
      if state.cursorSettings.clickEffect != .none {
        ColorPicker(L10n.VideoEditor.cursorClickColor, selection: clickColorBinding, supportsOpacity: true)
          .font(Typography.labelSmall)
      }
    }
    .disabled(!state.cursorSettings.isVisible)

    Divider()

    toggle(L10n.VideoEditor.cursorClickSound, \.clickSound)
    if state.cursorSettings.clickSound {
      slider(L10n.VideoEditor.cursorClickSoundVolume, \.clickSoundVolume, range: 0 ... 1) {
        String(format: "%.0f%%", $0 * 100)
      }
    }
  }

  // MARK: - Controls

  private func binding<Value>(_ keyPath: WritableKeyPath<VideoEditorCursorSettings, Value>) -> Binding<Value> {
    Binding(
      get: { state.cursorSettings[keyPath: keyPath] },
      set: { newValue in
        var settings = state.cursorSettings
        settings[keyPath: keyPath] = newValue
        state.setCursorSettings(settings, recordUndo: dragStart == nil)
      }
    )
  }

  private func toggle(_ title: String, _ keyPath: WritableKeyPath<VideoEditorCursorSettings, Bool>) -> some View {
    Toggle(title, isOn: binding(keyPath))
      .font(Typography.labelSmall)
      .toggleStyle(.switch)
      .controlSize(.small)
  }

  private func slider<Value: BinaryFloatingPoint>(
    _ title: String,
    _ keyPath: WritableKeyPath<VideoEditorCursorSettings, Value>,
    range: ClosedRange<Value>,
    format: @escaping (Double) -> String
  ) -> some View where Value.Stride: BinaryFloatingPoint {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(title)
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelSecondary)
        Spacer()
        Text(format(Double(state.cursorSettings[keyPath: keyPath])))
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelSecondary)
          .monospacedDigit()
      }
      Slider(value: binding(keyPath), in: range) { editing in
        if editing {
          dragStart = state.cursorSettings
        } else if let start = dragStart {
          dragStart = nil
          state.commitCursorSettings(from: start)
        }
      }
      .controlSize(.small)
    }
  }

  private var clickColorBinding: Binding<Color> {
    Binding(
      get: {
        let c = state.cursorSettings.clickColor
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
      },
      set: { color in
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return }
        var settings = state.cursorSettings
        settings.clickColor = VideoEditorRGBAColor(
          red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent, alpha: ns.alphaComponent
        )
        state.setCursorSettings(settings)
      }
    )
  }
}
