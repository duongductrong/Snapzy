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
  @ObservedObject private var annotateManager = AnnotateShortcutManager.shared

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

        SettingRow(icon: "keyboard", title: "Enable Shortcuts", description: "Capture from any app") {
          Toggle("", isOn: $shortcutsEnabled)
            .labelsHidden()
            .onChange(of: shortcutsEnabled) { newValue in
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

        Section("Annotation Tool Shortcuts") {
          Text("Single-key shortcuts for switching tools in the annotation editor.")
            .font(.caption)
            .foregroundColor(.secondary)

          ForEach(AnnotateShortcutManager.configurableTools, id: \.self) { tool in
            SingleKeyRecorderView(
              tool: tool,
              shortcut: bindingForTool(tool),
              onChanged: { annotateManager.setShortcut($0, for: tool) },
              conflictingTool: conflictForTool(tool),
              context: toolContext(for: tool)
            )
          }

          Text("Click to record. Press Backspace to clear. Esc to cancel.")
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

    // Reset annotation tool shortcuts
    annotateManager.resetToDefaults()
  }

  // MARK: - Annotation Tool Helpers

  private func bindingForTool(_ tool: AnnotationToolType) -> Binding<Character?> {
    Binding(
      get: { annotateManager.shortcut(for: tool) },
      set: { annotateManager.setShortcut($0, for: tool) }
    )
  }

  private func conflictForTool(_ tool: AnnotationToolType) -> AnnotationToolType? {
    guard let key = annotateManager.shortcut(for: tool) else { return nil }
    return annotateManager.conflictingTool(for: key, excluding: tool)
  }

  /// Recording annotation supports a subset of tools
  private static let recordingTools: Set<AnnotationToolType> = [
    .selection, .rectangle, .oval, .arrow, .line, .pencil, .highlighter,
  ]

  /// Screenshot annotation tools (all configurable except crop handled separately)
  private static let screenshotTools: Set<AnnotationToolType> = [
    .selection, .rectangle, .oval, .arrow, .line, .text,
    .highlighter, .blur, .counter, .pencil,
  ]

  private func toolContext(for tool: AnnotationToolType) -> AnnotationToolContext {
    let inScreenshot = Self.screenshotTools.contains(tool)
    let inRecording = Self.recordingTools.contains(tool)
    if inScreenshot && inRecording { return .both }
    if inRecording { return .recordingOnly }
    return .screenshotOnly
  }
}

#Preview {
  ShortcutsSettingsView()
    .frame(width: 600, height: 500)
}
