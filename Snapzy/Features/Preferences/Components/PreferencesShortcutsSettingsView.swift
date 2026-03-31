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
  @State private var objectCutoutShortcut: ShortcutConfig
  @State private var ocrShortcut: ShortcutConfig
  @State private var recordingShortcut: ShortcutConfig
  @State private var annotateShortcut: ShortcutConfig
  @State private var videoEditorShortcut: ShortcutConfig
  @State private var cloudUploadsShortcut: ShortcutConfig
  @State private var copyAndCloseShortcut: ShortcutConfig
  @State private var togglePinShortcut: ShortcutConfig
  @State private var cloudUploadShortcut: ShortcutConfig
  @State private var shortcutsEnabled: Bool
  @State private var showDisableConfirmation: Bool = false
  @State private var isConfirmedDisable: Bool = false
  @State private var hasSystemConflict: Bool = false
  @State private var isRefreshingConflict: Bool = false

  private let manager = KeyboardShortcutManager.shared
  @ObservedObject private var annotateManager = AnnotateShortcutManager.shared

  init() {
    _fullscreenShortcut = State(initialValue: KeyboardShortcutManager.shared.fullscreenShortcut)
    _areaShortcut = State(initialValue: KeyboardShortcutManager.shared.areaShortcut)
    _objectCutoutShortcut = State(initialValue: KeyboardShortcutManager.shared.objectCutoutShortcut)
    _ocrShortcut = State(initialValue: KeyboardShortcutManager.shared.ocrShortcut)
    _recordingShortcut = State(initialValue: KeyboardShortcutManager.shared.recordingShortcut)
    _annotateShortcut = State(initialValue: KeyboardShortcutManager.shared.annotateShortcut)
    _videoEditorShortcut = State(initialValue: KeyboardShortcutManager.shared.videoEditorShortcut)
    _cloudUploadsShortcut = State(initialValue: KeyboardShortcutManager.shared.cloudUploadsShortcut)
    _copyAndCloseShortcut = State(initialValue: AnnotateShortcutManager.shared.copyAndCloseShortcut)
    _togglePinShortcut = State(initialValue: AnnotateShortcutManager.shared.togglePinShortcut)
    _cloudUploadShortcut = State(initialValue: AnnotateShortcutManager.shared.cloudUploadShortcut)
    _shortcutsEnabled = State(initialValue: KeyboardShortcutManager.shared.isEnabled)
    _hasSystemConflict = State(
      initialValue: SystemScreenshotShortcutManager.shared.hasConflictingSystemShortcuts()
    )
  }

  var body: some View {
    Form {
      // System shortcut conflict status
      if shortcutsEnabled {
        if hasSystemConflict {
          Section {
            VStack(alignment: .leading, spacing: 12) {
              // Header
              HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                  .font(.system(size: 18))
                  .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 2) {
                  Text("macOS screenshot shortcuts are still active")
                    .font(.system(size: 13, weight: .semibold))
                  Text("Snapzy shortcuts will not work until you disable the macOS defaults.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                }
              }

              // Step-by-step guide
              VStack(alignment: .leading, spacing: 6) {
                Text("HOW TO DISABLE")
                  .font(.system(size: 10, weight: .semibold))
                  .foregroundColor(.secondary)
                  .tracking(0.8)

                PreferencesGuideStep(
                  step: "1",
                  text: "Open **System Settings → Keyboard → Keyboard Shortcuts**"
                )
                PreferencesGuideStep(
                  step: "2",
                  text: "Select **Screenshots** from the sidebar"
                )
                PreferencesGuideStep(
                  step: "3",
                  text: "Uncheck **⌘⇧3**, **⌘⇧4**, and **⌘⇧5**"
                )
              }
              .padding(10)
              .background(
                RoundedRectangle(cornerRadius: 8)
                  .fill(Color.orange.opacity(0.06))
              )

              // Action buttons
              HStack(spacing: 8) {
                Button {
                  SystemScreenshotShortcutManager.shared.openSystemScreenshotSettings()
                } label: {
                  HStack {
                    Image(systemName: "gear")
                      .font(.system(size: 12))
                    Text("Open Keyboard Shortcuts Settings")
                      .font(.system(size: 12, weight: .medium))
                  }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                  refreshSystemConflict()
                } label: {
                  HStack(spacing: 4) {
                    Image(
                      systemName: isRefreshingConflict
                        ? "arrow.triangle.2.circlepath" : "arrow.clockwise"
                    )
                    .font(.system(size: 12))
                    .rotationEffect(.degrees(isRefreshingConflict ? 360 : 0))
                    .animation(
                      isRefreshingConflict
                        ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                        : .default,
                      value: isRefreshingConflict
                    )
                    Text("Refresh")
                      .font(.system(size: 12, weight: .medium))
                  }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
              }
            }
            .padding(.vertical, 4)
          } header: {
            Label("Action Required", systemImage: "exclamationmark.circle.fill")
              .foregroundColor(.orange)
          }
        } else {
          // Success badge — no conflicts
          Section {
            HStack(spacing: 10) {
              Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(.green)

              VStack(alignment: .leading, spacing: 2) {
                Text("No conflicts detected")
                  .font(.system(size: 13, weight: .semibold))
                Text("macOS default screenshot shortcuts are disabled. Snapzy shortcuts will work correctly.")
                  .font(.system(size: 11))
                  .foregroundColor(.secondary)
              }

              Spacer()

              Button {
                refreshSystemConflict()
              } label: {
                Image(
                  systemName: isRefreshingConflict
                    ? "arrow.triangle.2.circlepath" : "arrow.clockwise"
                )
                .font(.system(size: 12))
                .rotationEffect(.degrees(isRefreshingConflict ? 360 : 0))
                .animation(
                  isRefreshingConflict
                    ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                    : .default,
                  value: isRefreshingConflict
                )
              }
              .buttonStyle(.borderless)
            }
            .padding(.vertical, 4)
          } header: {
            Label("System Shortcuts", systemImage: "checkmark.seal.fill")
              .foregroundColor(.green)
          }
        }
      }

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
                // Re-check system conflicts when enabling
                hasSystemConflict =
                  SystemScreenshotShortcutManager.shared.hasConflictingSystemShortcuts()
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
            label: "Capture Object (Transparent)",
            icon: "person.crop.rectangle",
            description: "Select an area and remove background automatically",
            shortcut: $objectCutoutShortcut,
            onShortcutChanged: { manager.setObjectCutoutShortcut($0) }
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

          ShortcutRecorderView(
            label: "Cloud Uploads",
            icon: "icloud.and.arrow.up",
            description: "Open cloud upload history",
            shortcut: $cloudUploadsShortcut,
            onShortcutChanged: { manager.setCloudUploadsShortcut($0) }
          )

          Text("Click a shortcut button to record new keys. Press Esc to cancel.")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 4)
        }

        Section("Annotate Editor Actions") {
          Text("Shortcuts for common actions inside the annotation editor.")
            .font(.caption)
            .foregroundColor(.secondary)

          ShortcutRecorderView(
            label: "Copy & Close",
            icon: "doc.on.doc",
            description: "Copy annotated image to clipboard and close",
            shortcut: $copyAndCloseShortcut,
            onShortcutChanged: { annotateManager.setCopyAndCloseShortcut($0) }
          )

          ShortcutRecorderView(
            label: "Toggle Pin",
            icon: "pin",
            description: "Pin or unpin the annotation window",
            shortcut: $togglePinShortcut,
            onShortcutChanged: { annotateManager.setTogglePinShortcut($0) }
          )

          ShortcutRecorderView(
            label: "Cloud Upload",
            icon: "icloud.and.arrow.up",
            description: "Upload annotated image to cloud",
            shortcut: $cloudUploadShortcut,
            onShortcutChanged: { annotateManager.setCloudUploadShortcut($0) }
          )
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

        Section("Annotate Editor Reference") {
          Text("Standard macOS shortcuts used in the annotation editor.")
            .font(.caption)
            .foregroundColor(.secondary)

          ReadOnlyShortcutRow(icon: "square.and.arrow.down", label: "Save (Done)", shortcut: "⌘ S")
          ReadOnlyShortcutRow(icon: "square.and.arrow.down.on.square", label: "Save As…", shortcut: "⌘ ⇧ S")
          ReadOnlyShortcutRow(icon: "arrow.uturn.backward", label: "Undo", shortcut: "⌘ Z")
          ReadOnlyShortcutRow(icon: "arrow.uturn.forward", label: "Redo", shortcut: "⌘ ⇧ Z")
          ReadOnlyShortcutRow(icon: "trash", label: "Delete Annotation", shortcut: "⌫")
          ReadOnlyShortcutRow(icon: "escape", label: "Cancel / Deselect", shortcut: "⎋")
          ReadOnlyShortcutRow(icon: "return", label: "Confirm Crop", shortcut: "↩")
          ReadOnlyShortcutRow(icon: "arrow.up.arrow.down.arrow.left.arrow.right", label: "Nudge Annotation", shortcut: "← → ↑ ↓")
          ReadOnlyShortcutRow(icon: "arrow.up.arrow.down.arrow.left.arrow.right", label: "Nudge 10px", shortcut: "⇧ ← → ↑ ↓")
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
    objectCutoutShortcut = .defaultObjectCutout
    ocrShortcut = .defaultOCR
    recordingShortcut = .defaultRecording
    annotateShortcut = .defaultAnnotate
    videoEditorShortcut = .defaultVideoEditor
    cloudUploadsShortcut = .defaultCloudUploads
    copyAndCloseShortcut = AnnotateShortcutManager.defaultCopyAndClose
    togglePinShortcut = AnnotateShortcutManager.defaultTogglePin
    cloudUploadShortcut = AnnotateShortcutManager.defaultCloudUpload

    manager.setFullscreenShortcut(.defaultFullscreen)
    manager.setAreaShortcut(.defaultArea)
    manager.setObjectCutoutShortcut(.defaultObjectCutout)
    manager.setOCRShortcut(.defaultOCR)
    manager.setRecordingShortcut(.defaultRecording)
    manager.setAnnotateShortcut(.defaultAnnotate)
    manager.setVideoEditorShortcut(.defaultVideoEditor)
    manager.setCloudUploadsShortcut(.defaultCloudUploads)

    // Reset annotation tool + action shortcuts
    annotateManager.resetToDefaults()
  }

  /// Re-check system shortcut conflict status with spinner animation
  private func refreshSystemConflict() {
    isRefreshingConflict = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      withAnimation(.easeInOut(duration: 0.3)) {
        hasSystemConflict = SystemScreenshotShortcutManager.shared.hasConflictingSystemShortcuts()
      }
      isRefreshingConflict = false
    }
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

// MARK: - Guide Step Component

private struct PreferencesGuideStep: View {
  let step: String
  let text: String

  var body: some View {
    HStack(spacing: 8) {
      Text(step)
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .foregroundColor(.orange)
        .frame(width: 18, height: 18)
        .background(
          Circle()
            .fill(Color.orange.opacity(0.15))
        )

      Text(.init(text))  // Supports **bold** markdown
        .font(.system(size: 12))
        .foregroundColor(.primary)
    }
  }
}

#Preview {
  ShortcutsSettingsView()
    .frame(width: 600, height: 500)
}

// MARK: - Read-Only Shortcut Row

private struct ReadOnlyShortcutRow: View {
  let icon: String
  let label: String
  let shortcut: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.title3)
        .foregroundColor(.secondary)
        .frame(width: 24)

      Text(label)
        .frame(minWidth: 100, alignment: .leading)

      Spacer()

      Text(shortcut)
        .font(.system(.body, design: .monospaced))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(Color.gray.opacity(0.1))
        )
    }
    .padding(.vertical, 2)
  }
}
