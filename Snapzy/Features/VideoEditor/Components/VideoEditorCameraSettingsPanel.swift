//
//  VideoEditorCameraSettingsPanel.swift
//  Snapzy
//
//  Left sidebar panel for the Studio camera layer: visibility, shape, size, position
//  (nine anchors), mirroring and a reset to the placement used while recording.
//

import SwiftUI

struct VideoEditorCameraSettingsPanel: View {
  @ObservedObject var state: VideoEditorState
  @State private var dragStart: VideoEditorCameraSettings?

  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: Spacing.md) {
        VideoSidebarSectionHeader(title: L10n.VideoEditor.cameraSection)
        if state.hasEditableCamera {
          controls
        } else {
          Text(L10n.VideoEditor.cameraUnavailableNotice)
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
    Toggle(L10n.VideoEditor.cameraShow, isOn: binding(\.isVisible))
      .font(Typography.labelSmall)
      .toggleStyle(.switch)
      .controlSize(.small)

    Group {
      Picker("", selection: binding(\.shape)) {
        ForEach(RecordingCameraShape.allCases) { shape in
          Image(systemName: shape.systemImage).tag(shape.rawValue)
            .help(shape.displayName)
        }
      }
      .labelsHidden()
      .pickerStyle(.segmented)

      VStack(alignment: .leading, spacing: 2) {
        HStack {
          Text(L10n.VideoEditor.cursorSize)
            .font(Typography.labelSmall)
            .foregroundColor(SidebarColors.labelSecondary)
          Spacer()
          Text(String(format: "%.0f%%", state.cameraSettings.size * 100))
            .font(Typography.labelSmall)
            .foregroundColor(SidebarColors.labelSecondary)
            .monospacedDigit()
        }
        Slider(value: binding(\.size), in: VideoEditorCameraSettings.sizeRange) { editing in
          if editing {
            dragStart = state.cameraSettings
          } else if let start = dragStart {
            dragStart = nil
            state.commitCameraSettings(from: start)
          }
        }
        .controlSize(.small)
      }

      VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(L10n.VideoEditor.cameraPosition)
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelSecondary)
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 6), count: 3), spacing: 6) {
          ForEach(Array(VideoEditorCameraSettings.anchors.enumerated()), id: \.offset) { _, anchor in
            anchorButton(anchor)
          }
        }
      }

      Toggle(L10n.VideoEditor.cameraMirror, isOn: binding(\.isMirrored))
        .font(Typography.labelSmall)
        .toggleStyle(.switch)
        .controlSize(.small)

      Button(L10n.VideoEditor.cameraResetToRecorded) {
        if let source = state.recordingMetadata?.cameraSource {
          state.setCameraSettings(.recorded(source))
        }
      }
      .controlSize(.small)
    }
    .disabled(!state.cameraSettings.isVisible)
  }

  private func anchorButton(_ anchor: CGPoint) -> some View {
    let center = state.cameraSettings.center
    let isSelected = abs(center.x - anchor.x) < 0.05 && abs(center.y - anchor.y) < 0.05
    return Button {
      var settings = state.cameraSettings
      settings.center = anchor
      state.setCameraSettings(settings)
    } label: {
      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .fill(isSelected ? Color.accentColor : SidebarColors.itemDefault)
        .frame(width: 28, height: 20)
    }
    .buttonStyle(.plain)
  }

  private func binding<Value>(_ keyPath: WritableKeyPath<VideoEditorCameraSettings, Value>) -> Binding<Value> {
    Binding(
      get: { state.cameraSettings[keyPath: keyPath] },
      set: { newValue in
        var settings = state.cameraSettings
        settings[keyPath: keyPath] = newValue
        state.setCameraSettings(settings, recordUndo: dragStart == nil)
      }
    )
  }
}
