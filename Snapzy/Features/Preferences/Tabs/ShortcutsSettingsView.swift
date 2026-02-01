//
//  ShortcutsSettingsView.swift
//  Snapzy
//
//  Keyboard shortcuts configuration tab
//

import SwiftUI

struct ShortcutsSettingsView: View {
  @State private var fullscreenShortcut: ShortcutConfig
  @State private var areaShortcut: ShortcutConfig
  @State private var ocrShortcut: ShortcutConfig
  @State private var recordingShortcut: ShortcutConfig
  @State private var annotateShortcut: ShortcutConfig
  @State private var videoEditorShortcut: ShortcutConfig
  @State private var shortcutsEnabled: Bool
  @State private var showDisableConfirmation: Bool = false
  @State private var isConfirmedDisable: Bool = false

  private let manager = KeyboardShortcutManager.shared

  init() {
    _fullscreenShortcut = State(initialValue: KeyboardShortcutManager.shared.fullscreenShortcut)
    _areaShortcut = State(initialValue: KeyboardShortcutManager.shared.areaShortcut)
    _ocrShortcut = State(initialValue: KeyboardShortcutManager.shared.ocrShortcut)
    _recordingShortcut = State(initialValue: KeyboardShortcutManager.shared.recordingShortcut)
    _annotateShortcut = State(initialValue: KeyboardShortcutManager.shared.annotateShortcut)
    _videoEditorShortcut = State(initialValue: KeyboardShortcutManager.shared.videoEditorShortcut)
    _shortcutsEnabled = State(initialValue: KeyboardShortcutManager.shared.isEnabled)
  }

  var body: some View {
    Form {
      Section("Global Shortcuts") {
        Text("Use keyboard shortcuts to capture from anywhere.")
          .font(.caption)
          .foregroundColor(.secondary)

        settingRow(icon: "keyboard", title: "Enable Shortcuts", description: "Capture from any app") {
          Toggle("", isOn: $shortcutsEnabled)
            .labelsHidden()
            .onChange(of: shortcutsEnabled) { _, newValue in
              if newValue {
                manager.enable()
              } else {
                if isConfirmedDisable {
                  // User confirmed disable, proceed
                  isConfirmedDisable = false
                  manager.disable()
                } else {
                  // Revert toggle and show confirmation
                  shortcutsEnabled = true
                  showDisableConfirmation = true
                }
              }
            }
        }
        .alert("Disable Keyboard Shortcuts?", isPresented: $showDisableConfirmation) {
          Button("Cancel", role: .cancel) {}
          Button("Disable", role: .destructive) {
            isConfirmedDisable = true
            shortcutsEnabled = false
          }
        } message: {
          Text("You won't be able to capture screenshots or recordings using keyboard shortcuts from any app. You'll need to open Snapzy manually to use capture features.")
        }
      }

      if shortcutsEnabled {
        Section("Capture Shortcuts") {
          ShortcutRecorderView(
            label: "Capture Fullscreen",
            icon: "rectangle.dashed.and.paperclip",
            description: "Capture entire screen instantly",
            shortcut: $fullscreenShortcut,
            onShortcutChanged: { manager.setFullscreenShortcut($0) }
          )

          ShortcutRecorderView(
            label: "Capture Area",
            icon: "rectangle.dashed",
            description: "Select a region to capture",
            shortcut: $areaShortcut,
            onShortcutChanged: { manager.setAreaShortcut($0) }
          )

          ShortcutRecorderView(
            label: "Capture Text (OCR)",
            icon: "text.viewfinder",
            description: "Extract text from screen region",
            shortcut: $ocrShortcut,
            onShortcutChanged: { manager.setOCRShortcut($0) }
          )
        }

        Section("Recording Shortcuts") {
          ShortcutRecorderView(
            label: "Record Video",
            icon: "record.circle",
            description: "Start screen recording",
            shortcut: $recordingShortcut,
            onShortcutChanged: { manager.setRecordingShortcut($0) }
          )
        }

        Section("Tools Shortcuts") {
          ShortcutRecorderView(
            label: "Open Annotate",
            icon: "pencil.and.scribble",
            description: "Open image annotation editor",
            shortcut: $annotateShortcut,
            onShortcutChanged: { manager.setAnnotateShortcut($0) }
          )

          ShortcutRecorderView(
            label: "Open Video Editor",
            icon: "film",
            description: "Open video editing tools",
            shortcut: $videoEditorShortcut,
            onShortcutChanged: { manager.setVideoEditorShortcut($0) }
          )

          Text("Click a shortcut button to record new keys. Press Esc to cancel.")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 4)
        }
      }
    }
    .formStyle(.grouped)
    .safeAreaInset(edge: .bottom) {
      HStack {
        Spacer()
        Button("Reset to Defaults") {
          resetToDefaults()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding()
      }
    }
  }

  // MARK: - Setting Row Helper

  @ViewBuilder
  private func settingRow<Content: View>(
    icon: String,
    title: String,
    description: String?,
    @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundColor(.secondary)
        .frame(width: 28)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .fontWeight(.medium)
        if let description {
          Text(description)
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }

      Spacer()
      content()
    }
    .padding(.vertical, 4)
  }

  // MARK: - Actions

  private func resetToDefaults() {
    fullscreenShortcut = .defaultFullscreen
    areaShortcut = .defaultArea
    ocrShortcut = .defaultOCR
    recordingShortcut = .defaultRecording
    annotateShortcut = .defaultAnnotate
    videoEditorShortcut = .defaultVideoEditor

    manager.setFullscreenShortcut(.defaultFullscreen)
    manager.setAreaShortcut(.defaultArea)
    manager.setOCRShortcut(.defaultOCR)
    manager.setRecordingShortcut(.defaultRecording)
    manager.setAnnotateShortcut(.defaultAnnotate)
    manager.setVideoEditorShortcut(.defaultVideoEditor)
  }
}

#Preview {
  ShortcutsSettingsView()
    .frame(width: 600, height: 500)
}
