//
//  ShortcutsSettingsView.swift
//  Snapzy
//
//  Keyboard shortcuts configuration tab
//

import AppKit
import SwiftUI

struct ShortcutsSettingsView: View {
  @State private var fullscreenShortcut: ShortcutConfig
  @State private var areaShortcut: ShortcutConfig
  @State private var areaApplicationCaptureShortcut: Character
  @State private var scrollingCaptureShortcut: ShortcutConfig
  @State private var objectCutoutShortcut: ShortcutConfig
  @State private var ocrShortcut: ShortcutConfig
  @State private var recordingShortcut: ShortcutConfig
  @State private var annotateShortcut: ShortcutConfig
  @State private var videoEditorShortcut: ShortcutConfig
  @State private var cloudUploadsShortcut: ShortcutConfig
  @State private var shortcutListShortcut: ShortcutConfig
  @State private var historyShortcut: ShortcutConfig
  @State private var copyAndCloseShortcut: ShortcutConfig
  @State private var togglePinShortcut: ShortcutConfig
  @State private var cloudUploadShortcut: ShortcutConfig
  @State private var globalShortcutEnabled: [GlobalShortcutKind: Bool]
  @State private var annotateActionEnabled: [AnnotateActionShortcutKind: Bool]
  @State private var globalValidationIssues: [GlobalShortcutKind: ShortcutValidationIssue] = [:]
  @State private var annotateActionValidationIssues: [AnnotateActionShortcutKind: ShortcutValidationIssue] = [:]
  @State private var annotateToolValidationIssues: [AnnotationToolType: ShortcutValidationIssue] = [:]
  @State private var shortcutsEnabled: Bool
  @State private var showDisableConfirmation: Bool = false
  @State private var isConfirmedDisable: Bool = false
  @State private var hasSystemConflict: Bool = false
  @State private var isRefreshingConflict: Bool = false

  private let manager = KeyboardShortcutManager.shared
  private let validator = ShortcutValidationService.shared
  @ObservedObject private var annotateManager = AnnotateShortcutManager.shared

  init() {
    _fullscreenShortcut = State(initialValue: KeyboardShortcutManager.shared.fullscreenShortcut)
    _areaShortcut = State(initialValue: KeyboardShortcutManager.shared.areaShortcut)
    _areaApplicationCaptureShortcut = State(
      initialValue: CaptureOverlayShortcutSettings.applicationCaptureShortcut
    )
    _scrollingCaptureShortcut = State(initialValue: KeyboardShortcutManager.shared.scrollingCaptureShortcut)
    _objectCutoutShortcut = State(initialValue: KeyboardShortcutManager.shared.objectCutoutShortcut)
    _ocrShortcut = State(initialValue: KeyboardShortcutManager.shared.ocrShortcut)
    _recordingShortcut = State(initialValue: KeyboardShortcutManager.shared.recordingShortcut)
    _annotateShortcut = State(initialValue: KeyboardShortcutManager.shared.annotateShortcut)
    _videoEditorShortcut = State(initialValue: KeyboardShortcutManager.shared.videoEditorShortcut)
    _cloudUploadsShortcut = State(initialValue: KeyboardShortcutManager.shared.cloudUploadsShortcut)
    _shortcutListShortcut = State(initialValue: KeyboardShortcutManager.shared.shortcutListShortcut)
    _historyShortcut = State(initialValue: KeyboardShortcutManager.shared.historyShortcut)
    _copyAndCloseShortcut = State(initialValue: AnnotateShortcutManager.shared.copyAndCloseShortcut)
    _togglePinShortcut = State(initialValue: AnnotateShortcutManager.shared.togglePinShortcut)
    _cloudUploadShortcut = State(initialValue: AnnotateShortcutManager.shared.cloudUploadShortcut)
    _globalShortcutEnabled = State(
      initialValue: Dictionary(
        uniqueKeysWithValues: GlobalShortcutKind.allCases.map {
          ($0, KeyboardShortcutManager.shared.isShortcutEnabled(for: $0))
        }
      )
    )
    _annotateActionEnabled = State(
      initialValue: Dictionary(
        uniqueKeysWithValues: AnnotateActionShortcutKind.allCases.map {
          ($0, AnnotateShortcutManager.shared.isActionShortcutEnabled(for: $0))
        }
      )
    )
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
                  Text(L10n.PreferencesShortcuts.systemConflictTitle)
                    .font(.system(size: 13, weight: .semibold))
                  Text(L10n.PreferencesShortcuts.systemConflictDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                }
              }

              // Step-by-step guide
              VStack(alignment: .leading, spacing: 6) {
                Text(L10n.PreferencesShortcuts.howToDisable)
                  .font(.system(size: 10, weight: .semibold))
                  .foregroundColor(.secondary)
                  .tracking(0.8)

                PreferencesGuideStep(
                  step: "1",
                  text: L10n.Onboarding.guideStep1
                )
                PreferencesGuideStep(
                  step: "2",
                  text: L10n.Onboarding.guideStep2
                )
                PreferencesGuideStep(
                  step: "3",
                  text: L10n.Onboarding.guideStep3
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
                    Text(L10n.PreferencesShortcuts.openKeyboardShortcutsSettings)
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
                    Text(L10n.Common.refresh)
                      .font(.system(size: 12, weight: .medium))
                  }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
              }
            }
            .padding(.vertical, 4)
          } header: {
            Label(L10n.PreferencesShortcuts.actionRequired, systemImage: "exclamationmark.circle.fill")
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
                Text(L10n.PreferencesShortcuts.noConflictsDetected)
                  .font(.system(size: 13, weight: .semibold))
                Text(L10n.PreferencesShortcuts.noConflictsDescription)
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
            Label(L10n.PreferencesShortcuts.systemShortcuts, systemImage: "checkmark.seal.fill")
              .foregroundColor(.green)
          }
        }
      }

      Section(L10n.PreferencesShortcuts.globalSection) {
        Text(L10n.PreferencesShortcuts.globalSectionDescription)
          .font(.caption)
          .foregroundColor(.secondary)

        SettingRow(icon: "keyboard", title: L10n.PreferencesShortcuts.enableShortcutsTitle, description: L10n.PreferencesShortcuts.enableShortcutsDescription) {
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
        .alert(L10n.PreferencesShortcuts.disableShortcutsTitle, isPresented: $showDisableConfirmation) {
          Button(L10n.Common.cancel, role: .cancel) {}
          Button(L10n.Common.disable, role: .destructive) {
            isConfirmedDisable = true
            shortcutsEnabled = false
          }
        } message: {
          Text(L10n.PreferencesShortcuts.disableShortcutsMessage)
        }
      }

      if shortcutsEnabled {
        Section(L10n.PreferencesShortcuts.captureSection) {
          ShortcutRecorderView(
            label: L10n.Actions.captureFullscreen,
            icon: "rectangle.dashed.and.paperclip",
            description: L10n.PreferencesShortcuts.captureFullscreenDescription,
            shortcut: $fullscreenShortcut,
            isEnabled: globalEnabledBinding(for: .fullscreen),
            validationIssue: globalValidationIssues[.fullscreen],
            onShortcutChanged: { handleGlobalShortcutChange($0, for: .fullscreen) }
          )

          VStack(alignment: .leading, spacing: 4) {
            ShortcutRecorderView(
              label: L10n.Actions.captureArea,
              icon: "rectangle.dashed",
              description: L10n.PreferencesShortcuts.captureAreaDescription,
              shortcut: $areaShortcut,
              isEnabled: globalEnabledBinding(for: .area),
              validationIssue: globalValidationIssues[.area],
              onShortcutChanged: { handleGlobalShortcutChange($0, for: .area) }
            )

            CaptureOverlayShortcutRecorderRow(
              label: L10n.PreferencesShortcuts.applicationCaptureTitle,
              description: L10n.PreferencesShortcuts.applicationCaptureDescription,
              shortcut: $areaApplicationCaptureShortcut,
              isEnabled: globalEnabledBinding(for: .area)
            ) { newShortcut in
              areaApplicationCaptureShortcut = newShortcut
              CaptureOverlayShortcutSettings.setApplicationCaptureShortcut(newShortcut)
            }
          }
          .padding(.vertical, 2)

          ShortcutRecorderView(
            label: GlobalShortcutKind.scrollingCapture.displayName,
            icon: "arrow.up.and.down",
            description: "Guided session for long screenshots",
            shortcut: $scrollingCaptureShortcut,
            isEnabled: globalEnabledBinding(for: .scrollingCapture),
            validationIssue: globalValidationIssues[.scrollingCapture],
            onShortcutChanged: { handleGlobalShortcutChange($0, for: .scrollingCapture) }
          )

          ShortcutRecorderView(
            label: GlobalShortcutKind.objectCutout.displayName,
            icon: "person.crop.rectangle",
            description: "Select an area, isolate the subject, and optionally auto-crop",
            shortcut: $objectCutoutShortcut,
            isEnabled: globalEnabledBinding(for: .objectCutout),
            validationIssue: globalValidationIssues[.objectCutout],
            onShortcutChanged: { handleGlobalShortcutChange($0, for: .objectCutout) }
          )

          ShortcutRecorderView(
            label: L10n.Actions.captureTextOCR,
            icon: "text.viewfinder",
            description: L10n.PreferencesShortcuts.captureTextDescription,
            shortcut: $ocrShortcut,
            isEnabled: globalEnabledBinding(for: .ocr),
            validationIssue: globalValidationIssues[.ocr],
            onShortcutChanged: { handleGlobalShortcutChange($0, for: .ocr) }
          )
        }

        Section(L10n.PreferencesShortcuts.recordingSection) {
          ShortcutRecorderView(
            label: L10n.Actions.recordVideo,
            icon: "record.circle",
            description: L10n.PreferencesShortcuts.recordVideoDescription,
            shortcut: $recordingShortcut,
            isEnabled: globalEnabledBinding(for: .recording),
            validationIssue: globalValidationIssues[.recording],
            onShortcutChanged: { handleGlobalShortcutChange($0, for: .recording) }
          )
        }

        Section(L10n.PreferencesShortcuts.toolsSection) {
          ShortcutRecorderView(
            label: L10n.Actions.openAnnotate,
            icon: "pencil.and.scribble",
            description: L10n.PreferencesShortcuts.openAnnotateDescription,
            shortcut: $annotateShortcut,
            isEnabled: globalEnabledBinding(for: .annotate),
            validationIssue: globalValidationIssues[.annotate],
            onShortcutChanged: { handleGlobalShortcutChange($0, for: .annotate) }
          )

          ShortcutRecorderView(
            label: L10n.Actions.openVideoEditor,
            icon: "film",
            description: L10n.PreferencesShortcuts.openVideoEditorDescription,
            shortcut: $videoEditorShortcut,
            isEnabled: globalEnabledBinding(for: .videoEditor),
            validationIssue: globalValidationIssues[.videoEditor],
            onShortcutChanged: { handleGlobalShortcutChange($0, for: .videoEditor) }
          )

          ShortcutRecorderView(
            label: L10n.Actions.cloudUploads,
            icon: "icloud.and.arrow.up",
            description: L10n.PreferencesShortcuts.cloudUploadsDescription,
            shortcut: $cloudUploadsShortcut,
            isEnabled: globalEnabledBinding(for: .cloudUploads),
            validationIssue: globalValidationIssues[.cloudUploads],
            onShortcutChanged: { handleGlobalShortcutChange($0, for: .cloudUploads) }
          )

          ShortcutRecorderView(
            label: L10n.Actions.showShortcutList,
            icon: "list.bullet.rectangle",
            description: L10n.PreferencesShortcuts.shortcutListDescription,
            shortcut: $shortcutListShortcut,
            isEnabled: globalEnabledBinding(for: .shortcutList),
            validationIssue: globalValidationIssues[.shortcutList],
            onShortcutChanged: { handleGlobalShortcutChange($0, for: .shortcutList) }
          )

          ShortcutRecorderView(
            label: L10n.Actions.openHistory,
            icon: "clock.arrow.circlepath",
            description: "Open the capture history browser",
            shortcut: $historyShortcut,
            isEnabled: globalEnabledBinding(for: .history),
            validationIssue: globalValidationIssues[.history],
            onShortcutChanged: { handleGlobalShortcutChange($0, for: .history) }
          )

          Text(L10n.PreferencesShortcuts.recorderHint)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 4)
        }

        Section(L10n.ShortcutOverlay.annotateActions) {
          Text(L10n.PreferencesShortcuts.annotateActionsDescription)
            .font(.caption)
            .foregroundColor(.secondary)

          ShortcutRecorderView(
            label: L10n.ShortcutOverlay.copyAndClose,
            icon: "doc.on.doc",
            description: L10n.PreferencesShortcuts.copyAndCloseDescription,
            shortcut: $copyAndCloseShortcut,
            isEnabled: annotateActionEnabledBinding(for: .copyAndClose),
            validationIssue: annotateActionValidationIssues[.copyAndClose],
            onShortcutChanged: { handleAnnotateActionShortcutChange($0, for: .copyAndClose) }
          )

          ShortcutRecorderView(
            label: L10n.ShortcutOverlay.togglePin,
            icon: "pin",
            description: L10n.PreferencesShortcuts.togglePinDescription,
            shortcut: $togglePinShortcut,
            isEnabled: annotateActionEnabledBinding(for: .togglePin),
            validationIssue: annotateActionValidationIssues[.togglePin],
            onShortcutChanged: { handleAnnotateActionShortcutChange($0, for: .togglePin) }
          )

          ShortcutRecorderView(
            label: L10n.ShortcutOverlay.cloudUpload,
            icon: "icloud.and.arrow.up",
            description: L10n.PreferencesShortcuts.cloudUploadDescription,
            shortcut: $cloudUploadShortcut,
            isEnabled: annotateActionEnabledBinding(for: .cloudUpload),
            validationIssue: annotateActionValidationIssues[.cloudUpload],
            onShortcutChanged: { handleAnnotateActionShortcutChange($0, for: .cloudUpload) }
          )
        }

        Section(L10n.ShortcutOverlay.annotateToolKeys) {
          Text(L10n.PreferencesShortcuts.annotationToolDescription)
            .font(.caption)
            .foregroundColor(.secondary)

          ForEach(AnnotateShortcutManager.configurableTools, id: \.self) { tool in
            SingleKeyRecorderView(
              tool: tool,
              shortcut: bindingForTool(tool),
              isEnabled: toolEnabledBinding(for: tool),
              validationIssue: annotateToolValidationIssues[tool],
              onChanged: { handleAnnotateToolShortcutChange($0, for: tool) },
              conflictingTool: conflictForTool(tool),
              context: toolContext(for: tool)
            )
          }

          Text(L10n.PreferencesShortcuts.singleKeyHint)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 4)
        }

        Section(L10n.ShortcutOverlay.annotateReference) {
          Text(L10n.PreferencesShortcuts.referenceDescription)
            .font(.caption)
            .foregroundColor(.secondary)

          ReadOnlyShortcutRow(icon: "square.and.arrow.down", label: L10n.ShortcutOverlay.saveDone, shortcut: "⌘ S")
          ReadOnlyShortcutRow(icon: "square.and.arrow.down.on.square", label: L10n.ShortcutOverlay.saveAs, shortcut: "⌘ ⇧ S")
          ReadOnlyShortcutRow(icon: "arrow.uturn.backward", label: L10n.ShortcutOverlay.undo, shortcut: "⌘ Z")
          ReadOnlyShortcutRow(icon: "arrow.uturn.forward", label: L10n.ShortcutOverlay.redo, shortcut: "⌘ ⇧ Z")
          ReadOnlyShortcutRow(icon: "trash", label: L10n.ShortcutOverlay.deleteAnnotation, shortcut: "⌫")
          ReadOnlyShortcutRow(icon: "escape", label: L10n.ShortcutOverlay.cancelDeselect, shortcut: "⎋")
          ReadOnlyShortcutRow(icon: "return", label: L10n.ShortcutOverlay.confirmCrop, shortcut: "↩")
          ReadOnlyShortcutRow(icon: "arrow.up.arrow.down.arrow.left.arrow.right", label: L10n.ShortcutOverlay.nudgeAnnotation, shortcut: "← → ↑ ↓")
          ReadOnlyShortcutRow(icon: "arrow.up.arrow.down.arrow.left.arrow.right", label: L10n.ShortcutOverlay.nudgeTenPixels, shortcut: "⇧ ← → ↑ ↓")
        }
      }
    }
    .formStyle(.grouped)
    .safeAreaInset(edge: .bottom) {
      HStack {
        Spacer()
        Button(L10n.PreferencesShortcuts.resetToDefaults) {
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
    areaApplicationCaptureShortcut = CaptureOverlayShortcutSettings.defaultApplicationCaptureShortcut
    scrollingCaptureShortcut = .defaultScrollingCapture
    objectCutoutShortcut = .defaultObjectCutout
    ocrShortcut = .defaultOCR
    recordingShortcut = .defaultRecording
    annotateShortcut = .defaultAnnotate
    videoEditorShortcut = .defaultVideoEditor
    cloudUploadsShortcut = .defaultCloudUploads
    shortcutListShortcut = .defaultShortcutList
    historyShortcut = .defaultHistory
    copyAndCloseShortcut = AnnotateShortcutManager.defaultCopyAndClose
    togglePinShortcut = AnnotateShortcutManager.defaultTogglePin
    cloudUploadShortcut = AnnotateShortcutManager.defaultCloudUpload
    globalShortcutEnabled = Dictionary(
      uniqueKeysWithValues: GlobalShortcutKind.allCases.map { ($0, true) }
    )
    annotateActionEnabled = Dictionary(
      uniqueKeysWithValues: AnnotateActionShortcutKind.allCases.map { ($0, true) }
    )
    globalValidationIssues = [:]
    annotateActionValidationIssues = [:]
    annotateToolValidationIssues = [:]

    manager.setFullscreenShortcut(.defaultFullscreen)
    manager.setAreaShortcut(.defaultArea)
    manager.setScrollingCaptureShortcut(.defaultScrollingCapture)
    manager.setObjectCutoutShortcut(.defaultObjectCutout)
    manager.setOCRShortcut(.defaultOCR)
    manager.setRecordingShortcut(.defaultRecording)
    manager.setAnnotateShortcut(.defaultAnnotate)
    manager.setVideoEditorShortcut(.defaultVideoEditor)
    manager.setCloudUploadsShortcut(.defaultCloudUploads)
    manager.setShortcutListShortcut(.defaultShortcutList)
    manager.setHistoryShortcut(.defaultHistory)
    CaptureOverlayShortcutSettings.resetApplicationCaptureShortcut()
    for kind in GlobalShortcutKind.allCases {
      manager.setShortcutEnabled(true, for: kind)
    }

    // Reset annotation tool + action shortcuts
    annotateManager.resetToDefaults()
    hasSystemConflict = SystemScreenshotShortcutManager.shared.hasConflictingSystemShortcuts()
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

  private func toolEnabledBinding(for tool: AnnotationToolType) -> Binding<Bool> {
    Binding(
      get: { annotateManager.isShortcutEnabled(for: tool) },
      set: { newValue in
        if newValue, let key = annotateManager.shortcut(for: tool) {
          switch validator.validateAnnotateToolShortcut(key, for: tool) {
          case .accept(let issue):
            annotateToolValidationIssues[tool] = issue
          case .reject(let issue):
            annotateToolValidationIssues[tool] = issue
            return
          }
        }

        annotateManager.setShortcutEnabled(newValue, for: tool)
        if !newValue {
          annotateToolValidationIssues.removeValue(forKey: tool)
        }
      }
    )
  }

  private func globalEnabledBinding(for kind: GlobalShortcutKind) -> Binding<Bool> {
    Binding(
      get: { globalShortcutEnabled[kind] ?? true },
      set: { newValue in
        if newValue {
          switch validator.validateGlobalShortcut(manager.shortcut(for: kind), for: kind) {
          case .accept(let issue):
            globalValidationIssues[kind] = issue
          case .reject(let issue):
            globalValidationIssues[kind] = issue
            return
          }
        }

        globalShortcutEnabled[kind] = newValue
        manager.setShortcutEnabled(newValue, for: kind)
        if !newValue {
          globalValidationIssues.removeValue(forKey: kind)
        }
        if kind.isSystemConflictRelevant {
          hasSystemConflict = SystemScreenshotShortcutManager.shared.hasConflictingSystemShortcuts()
        }
      }
    )
  }

  private func annotateActionEnabledBinding(for kind: AnnotateActionShortcutKind) -> Binding<Bool> {
    Binding(
      get: { annotateActionEnabled[kind] ?? true },
      set: { newValue in
        if newValue {
          switch validator.validateAnnotateActionShortcut(annotateManager.shortcut(for: kind), for: kind) {
          case .accept(let issue):
            annotateActionValidationIssues[kind] = issue
          case .reject(let issue):
            annotateActionValidationIssues[kind] = issue
            return
          }
        }

        annotateActionEnabled[kind] = newValue
        annotateManager.setActionShortcutEnabled(newValue, for: kind)
        if !newValue {
          annotateActionValidationIssues.removeValue(forKey: kind)
        }
      }
    )
  }

  private func conflictForTool(_ tool: AnnotationToolType) -> AnnotationToolType? {
    guard annotateManager.isShortcutEnabled(for: tool),
          let key = annotateManager.shortcut(for: tool) else { return nil }
    return annotateManager.conflictingTool(for: key, excluding: tool)
  }

  private func handleGlobalShortcutChange(_ config: ShortcutConfig, for kind: GlobalShortcutKind) -> Bool {
    switch validator.validateGlobalShortcut(config, for: kind) {
    case .accept(let issue):
      globalValidationIssues[kind] = issue
      switch kind {
      case .fullscreen:
        fullscreenShortcut = config
        manager.setFullscreenShortcut(config)
      case .area:
        areaShortcut = config
        manager.setAreaShortcut(config)
      case .scrollingCapture:
        scrollingCaptureShortcut = config
        manager.setScrollingCaptureShortcut(config)
      case .recording:
        recordingShortcut = config
        manager.setRecordingShortcut(config)
      case .annotate:
        annotateShortcut = config
        manager.setAnnotateShortcut(config)
      case .videoEditor:
        videoEditorShortcut = config
        manager.setVideoEditorShortcut(config)
      case .cloudUploads:
        cloudUploadsShortcut = config
        manager.setCloudUploadsShortcut(config)
      case .shortcutList:
        shortcutListShortcut = config
        manager.setShortcutListShortcut(config)
      case .ocr:
        ocrShortcut = config
        manager.setOCRShortcut(config)
      case .objectCutout:
        objectCutoutShortcut = config
        manager.setObjectCutoutShortcut(config)
      case .history:
        historyShortcut = config
        manager.setHistoryShortcut(config)
      }

      if kind.isSystemConflictRelevant {
        hasSystemConflict = SystemScreenshotShortcutManager.shared.hasConflictingSystemShortcuts()
      }
      return true
    case .reject(let issue):
      globalValidationIssues[kind] = issue
      return false
    }
  }

  private func handleAnnotateActionShortcutChange(
    _ config: ShortcutConfig,
    for kind: AnnotateActionShortcutKind
  ) -> Bool {
    switch validator.validateAnnotateActionShortcut(config, for: kind) {
    case .accept(let issue):
      annotateActionValidationIssues[kind] = issue
      switch kind {
      case .copyAndClose:
        copyAndCloseShortcut = config
        annotateManager.setCopyAndCloseShortcut(config)
      case .togglePin:
        togglePinShortcut = config
        annotateManager.setTogglePinShortcut(config)
      case .cloudUpload:
        cloudUploadShortcut = config
        annotateManager.setCloudUploadShortcut(config)
      }
      return true
    case .reject(let issue):
      annotateActionValidationIssues[kind] = issue
      return false
    }
  }

  private func handleAnnotateToolShortcutChange(
    _ key: Character?,
    for tool: AnnotationToolType
  ) -> Bool {
    guard let key else {
      annotateToolValidationIssues.removeValue(forKey: tool)
      annotateManager.setShortcut(nil, for: tool)
      return true
    }

    switch validator.validateAnnotateToolShortcut(key, for: tool) {
    case .accept(let issue):
      annotateToolValidationIssues[tool] = issue
      annotateManager.setShortcut(key, for: tool)
      return true
    case .reject(let issue):
      annotateToolValidationIssues[tool] = issue
      return false
    }
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

private struct CaptureOverlayShortcutRecorderRow: View {
  let label: String
  let description: String
  @Binding var shortcut: Character
  let isEnabled: Binding<Bool>
  let onShortcutChanged: (Character) -> Void

  @State private var isRecording = false
  @State private var eventMonitor: Any?
  @State private var didSuspendGlobalShortcuts = false

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "macwindow")
        .font(.title2)
        .foregroundColor(.secondary)
        .frame(width: 28)

      VStack(alignment: .leading, spacing: 2) {
        Text(label)
          .fontWeight(.medium)
        Text(description)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      shortcutRecorderButton

      toggleStatus
    }
    .padding(.vertical, 4)
    .opacity(rowOpacity)
    .onChange(of: isEnabled.wrappedValue) { newValue in
      if !newValue {
        stopRecording()
      }
    }
    .onDisappear {
      stopRecording()
    }
  }

  private var shortcutRecorderButton: some View {
    Button {
      startRecording()
    } label: {
      if isRecording {
        Text(L10n.ShortcutRecorder.pressKeys)
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(.accentColor)
          .frame(minWidth: 100)
      } else {
        KeyCapGroupView(parts: [String(shortcut).uppercased()])
      }
    }
    .buttonStyle(ShortcutKeycapButtonStyle(isRecording: isRecording))
    .disabled(!isEnabled.wrappedValue)
    .help(isEnabled.wrappedValue ? L10n.ShortcutRecorder.clickToRecord : L10n.ShortcutRecorder.turnOnToEdit)
  }

  private var toggleStatus: some View {
    HStack(spacing: 6) {
      Text(isEnabled.wrappedValue ? L10n.Common.on : L10n.Common.off)
        .font(.caption)
        .foregroundColor(.secondary)

      Toggle("", isOn: isEnabled)
        .labelsHidden()
    }
  }

  private var rowOpacity: Double {
    isEnabled.wrappedValue ? 1 : 0.62
  }

  private func startRecording() {
    guard !isRecording, isEnabled.wrappedValue else { return }
    isRecording = true
    KeyboardShortcutManager.shared.beginTemporaryShortcutSuppression()
    didSuspendGlobalShortcuts = true

    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      if event.keyCode == 53 {
        stopRecording()
        return nil
      }

      guard event.modifierFlags.intersection([.command, .control, .option, .function]).isEmpty else {
        return nil
      }

      guard let newShortcut = event.charactersIgnoringModifiers?.lowercased().first,
            newShortcut.isLetter else {
        return nil
      }

      shortcut = newShortcut
      onShortcutChanged(newShortcut)
      stopRecording()
      return nil
    }
  }

  private func stopRecording() {
    isRecording = false
    if let monitor = eventMonitor {
      NSEvent.removeMonitor(monitor)
      eventMonitor = nil
    }
    if didSuspendGlobalShortcuts {
      KeyboardShortcutManager.shared.endTemporaryShortcutSuppression()
      didSuspendGlobalShortcuts = false
    }
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

      if shouldUseKeycaps {
        KeyCapGroupView(parts: shortcutParts)
      } else {
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
    }
    .padding(.vertical, 2)
  }

  /// Split the display string (e.g. "⌘ ⇧ Z" or "← → ↑ ↓") into individual parts
  private var shortcutParts: [String] {
    shortcut
      .split(separator: " ")
      .map(String.init)
  }

  private var shouldUseKeycaps: Bool {
    shortcutParts.filter { !modifierTokens.contains($0) }.count <= 1
  }

  private var modifierTokens: Set<String> {
    ["⌘", "⇧", "⌥", "⌃"]
  }
}
