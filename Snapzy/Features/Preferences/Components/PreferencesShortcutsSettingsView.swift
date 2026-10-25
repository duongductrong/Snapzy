//
//  PreferencesShortcutsSettingsView.swift
//  Snapzy
//
//  Keyboard shortcuts configuration tab
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutsSettingsView: View {
  @State private var fullscreenShortcut: ShortcutConfig?
  @State private var areaShortcut: ShortcutConfig?
  @State private var repeatAreaShortcut: ShortcutConfig?
  @State private var delayedCaptureShortcut: ShortcutConfig?
  @State private var delayedFullscreenShortcut: ShortcutConfig?
  @State private var areaAnnotateShortcut: ShortcutConfig?
  @State private var activeWindowShortcut: ShortcutConfig?
  @State private var areaApplicationCaptureShortcut: CaptureOverlayShortcut?
  @State private var recordingApplicationCaptureShortcut: CaptureOverlayShortcut?
  @State private var scrollingCaptureShortcut: ShortcutConfig?
  @State private var objectCutoutShortcut: ShortcutConfig?
  @State private var ocrShortcut: ShortcutConfig?
  @State private var smartElementShortcut: ShortcutConfig?
  @State private var recordingShortcut: ShortcutConfig?
  @State private var pauseResumeRecordingShortcut: ShortcutConfig?
  @State private var togglePenRecordingShortcut: ShortcutConfig?
  @State private var restartRecordingShortcut: ShortcutConfig?
  @State private var deleteRecordingShortcut: ShortcutConfig?
  @State private var annotateShortcut: ShortcutConfig?
  @State private var videoEditorShortcut: ShortcutConfig?
  @State private var cloudUploadsShortcut: ShortcutConfig?
  @State private var shortcutListShortcut: ShortcutConfig?
  @State private var pickColorShortcut: ShortcutConfig?
  @State private var historyShortcut: ShortcutConfig?
  @State private var openEditorShortcut: ShortcutConfig?
  @State private var openEditorShortcutEnabled: Bool
  @State private var copyAndCloseShortcut: ShortcutConfig?
  @State private var toggleSidebarShortcut: ShortcutConfig?
  @State private var togglePinShortcut: ShortcutConfig?
  @State private var cloudUploadShortcut: ShortcutConfig?
  @State private var autoRedactSensitiveDataShortcut: ShortcutConfig?
  @State private var globalShortcutEnabled: [GlobalShortcutKind: Bool]
  @State private var annotateActionEnabled: [AnnotateActionShortcutKind: Bool]
  @State private var globalValidationIssues: [GlobalShortcutKind: ShortcutValidationIssue] = [:]
  @State private var captureOverlayValidationIssues: [CaptureOverlayShortcutKind: ShortcutValidationIssue] = [:]
  @State private var annotateActionValidationIssues: [AnnotateActionShortcutKind: ShortcutValidationIssue] = [:]
  @State private var annotateToolValidationIssues: [AnnotationToolType: ShortcutValidationIssue] = [:]
  @State private var shortcutsEnabled: Bool
  @State private var showDisableConfirmation: Bool = false
  @State private var isConfirmedDisable: Bool = false
  @State private var hasSystemConflict: Bool = false
  @State private var isRefreshingConflict: Bool = false
  @State private var accessibilityGranted: Bool = AXIsProcessTrusted()
  /// Overview cards open in place; all start collapsed.
  @State private var expandedPages: Set<ShortcutsPage> = []
  /// Bumped by Quick Access reset so the card-action rows drop stale validation highlights.
  @State private var quickAccessResetCount = 0

  private let manager = KeyboardShortcutManager.shared
  private let validator = ShortcutValidationService.shared
  @ObservedObject private var annotateManager = AnnotateShortcutManager.shared
  @ObservedObject private var historyFloatingManager = HistoryFloatingManager.shared

  init() {
    _fullscreenShortcut = State(initialValue: KeyboardShortcutManager.shared.shortcut(for: .fullscreen))
    _areaShortcut = State(initialValue: KeyboardShortcutManager.shared.shortcut(for: .area))
    _repeatAreaShortcut = State(initialValue: KeyboardShortcutManager.shared.shortcut(for: .repeatArea))
    _delayedCaptureShortcut = State(initialValue: KeyboardShortcutManager.shared.shortcut(for: .delayedCapture))
    _delayedFullscreenShortcut = State(initialValue: KeyboardShortcutManager.shared.shortcut(for: .delayedFullscreen))
    _areaAnnotateShortcut = State(initialValue: KeyboardShortcutManager.shared.shortcut(for: .areaAnnotate))
    _activeWindowShortcut = State(initialValue: KeyboardShortcutManager.shared.shortcut(for: .activeWindow))
    _areaApplicationCaptureShortcut = State(
      initialValue: CaptureOverlayShortcutSettings.applicationCaptureShortcut
    )
    _recordingApplicationCaptureShortcut = State(
      initialValue: CaptureOverlayShortcutSettings.recordingApplicationCaptureShortcut
    )
    _scrollingCaptureShortcut = State(initialValue: KeyboardShortcutManager.shared.shortcut(for: .scrollingCapture))
    _objectCutoutShortcut = State(initialValue: KeyboardShortcutManager.shared.shortcut(for: .objectCutout))
    _ocrShortcut = State(initialValue: KeyboardShortcutManager.shared.shortcut(for: .ocr))
    _smartElementShortcut = State(initialValue: KeyboardShortcutManager.shared.shortcut(for: .smartElement))
    _recordingShortcut = State(initialValue: KeyboardShortcutManager.shared.shortcut(for: .recording))
    _pauseResumeRecordingShortcut = State(
      initialValue: KeyboardShortcutManager.shared.shortcut(for: .pauseResumeRecording)
    )
    _togglePenRecordingShortcut = State(
      initialValue: KeyboardShortcutManager.shared.shortcut(for: .togglePenRecording)
    )
    _restartRecordingShortcut = State(
      initialValue: KeyboardShortcutManager.shared.shortcut(for: .restartRecording)
    )
    _deleteRecordingShortcut = State(
      initialValue: KeyboardShortcutManager.shared.shortcut(for: .deleteRecording)
    )
    _annotateShortcut = State(initialValue: KeyboardShortcutManager.shared.shortcut(for: .annotate))
    _videoEditorShortcut = State(initialValue: KeyboardShortcutManager.shared.shortcut(for: .videoEditor))
    _cloudUploadsShortcut = State(initialValue: KeyboardShortcutManager.shared.shortcut(for: .cloudUploads))
    _shortcutListShortcut = State(initialValue: KeyboardShortcutManager.shared.shortcut(for: .shortcutList))
    _pickColorShortcut = State(initialValue: KeyboardShortcutManager.shared.shortcut(for: .pickColor))
    _historyShortcut = State(initialValue: KeyboardShortcutManager.shared.shortcut(for: .history))
    _openEditorShortcut = State(initialValue: QuickAccessManager.shared.openEditorShortcut)
    _openEditorShortcutEnabled = State(initialValue: QuickAccessManager.shared.openEditorShortcutEnabled)
    _copyAndCloseShortcut = State(initialValue: AnnotateShortcutManager.shared.copyAndCloseShortcut)
    _toggleSidebarShortcut = State(initialValue: AnnotateShortcutManager.shared.toggleSidebarShortcut)
    _togglePinShortcut = State(initialValue: AnnotateShortcutManager.shared.togglePinShortcut)
    _cloudUploadShortcut = State(initialValue: AnnotateShortcutManager.shared.cloudUploadShortcut)
    _autoRedactSensitiveDataShortcut = State(
      initialValue: AnnotateShortcutManager.shared.autoRedactSensitiveDataShortcut
    )
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
      overview
    }
    .formStyle(.grouped)
    .toolbar {
      if shortcutsEnabled {
        ToolbarItem(placement: .primaryAction) {
          SystemShortcutConflictBadge(
            hasConflict: hasSystemConflict,
            isRefreshing: isRefreshingConflict,
            onRefresh: refreshSystemConflict
          )
        }
      }
      ToolbarItem(placement: .primaryAction) {
        Toggle(L10n.PreferencesShortcuts.enableShortcutsTitle, isOn: $shortcutsEnabled)
          .toggleStyle(.switch)
          .controlSize(.small)
          .labelsHidden()
          // Inset so the switch sits inside the toolbar's capsule like the back/forward pair.
          .padding(.horizontal, 8)
          .help(L10n.PreferencesShortcuts.enableShortcutsDescription)
      }
    }
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
    .alert(L10n.PreferencesShortcuts.disableShortcutsTitle, isPresented: $showDisableConfirmation) {
      Button(L10n.Common.cancel, role: .cancel) {}
      Button(L10n.Common.disable, role: .destructive) {
        isConfirmedDisable = true
        shortcutsEnabled = false
      }
    } message: {
      Text(L10n.PreferencesShortcuts.disableShortcutsMessage)
    }
    .onAppear {
      accessibilityGranted = AXIsProcessTrusted()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
      accessibilityGranted = AXIsProcessTrusted()
    }
  }

  // MARK: - Overview

  @ViewBuilder
  private var overview: some View {
    Section {
    } header: {
      PreferencesPageHero(tab: .shortcuts, subtitle: L10n.PreferencesShortcuts.heroSubtitle)
    }

    if shortcutsEnabled {
      if showsFnAccessibilityHint {
        Section {
          if showsFnAccessibilityHint {
            HStack(spacing: 10) {
              Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(.orange)

              Text(L10n.PreferencesShortcuts.fnAccessibilityHint)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

              Spacer()

              Button(L10n.Common.openSettings) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                  NSWorkspace.shared.open(url)
                }
              }
              .buttonStyle(.bordered)
              .controlSize(.regular)
            }
          }
        }
      }
    } else {
      Section {
        HStack(spacing: 10) {
          Image(systemName: "keyboard.badge.ellipsis")
            .font(.system(size: 16))
            .foregroundColor(.secondary)
          Text(L10n.PreferencesShortcuts.shortcutsOff)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }

    pageGroup(
      ShortcutsPage.globalPages,
      title: L10n.PreferencesShortcuts.globalSection,
      help: L10n.PreferencesShortcuts.globalSectionDescription
    )
    pageGroup(ShortcutsPage.inAppPages, title: L10n.PreferencesShortcuts.inAppSection)

    // Lives in the scroll content (not a pinned inset) so it never floats over rows.
    Section {
    } footer: {
      HStack {
        Spacer()
        Button(L10n.PreferencesShortcuts.resetToDefaults) {
          resetToDefaults()
        }
        .controlSize(.regular)
      }
    }
  }

  /// One card per page, each in its own section so they read as separate cards. Clicking a
  /// card's header expands its shortcuts inside the card, like Droppy's Shortcuts settings.
  @ViewBuilder
  private func pageGroup(_ pages: [ShortcutsPage], title: String, help: String? = nil) -> some View {
    ForEach(pages) { page in
      Section {
        PreferencesExpandableCardHeader(
          symbol: page.symbol,
          title: page.title,
          subtitle: page.subtitle,
          help: page.help,
          tint: page.iconTint,
          isExpanded: expansion(for: page),
          onReset: resetAction(for: page)
        )

        if expandedPages.contains(page) {
          pageRows(page)
        }
      } header: {
        if page == pages.first {
          ShortcutSectionHeader(title: title, help: help)
        }
      }
      .disabled(!shortcutsEnabled)
      .opacity(shortcutsEnabled ? 1 : 0.5)
    }
  }

  // MARK: - Pages

  private func expansion(for page: ShortcutsPage) -> Binding<Bool> {
    Binding(
      get: { expandedPages.contains(page) },
      set: { expanded in
        if expanded {
          expandedPages.insert(page)
        } else {
          expandedPages.remove(page)
        }
      }
    )
  }

  private func resetAction(for page: ShortcutsPage) -> (() -> Void)? {
    switch page {
    case .capture: return { resetCaptureSection() }
    case .recording: return { resetRecordingSection() }
    case .tools: return { resetToolsSection() }
    case .history: return { resetHistorySection() }
    case .quickAccess: return resetQuickAccessSection
    case .annotateActions: return resetAnnotateActionsSection
    case .annotateTools: return resetAnnotateToolKeysSection
    case .annotateReference: return nil
    }
  }

  @ViewBuilder
  private func pageRows(_ page: ShortcutsPage) -> some View {
    switch page {
    case .capture:
      captureRows
    case .recording:
      recordingRows
    case .tools:
      toolsRows
    case .history:
      historyRows
    case .quickAccess:
      quickAccessRows
      QuickAccessActionShortcutRows(resetCount: quickAccessResetCount)
    case .annotateActions:
      annotateActionsRows
    case .annotateTools:
      annotateToolKeysRows
    case .annotateReference:
      annotateReferenceRows
    }
  }

  @ViewBuilder
  private var captureRows: some View {
    ShortcutRecorderView(
      label: L10n.Actions.captureFullscreen,
      description: L10n.PreferencesShortcuts.captureFullscreenDescription,
      shortcut: $fullscreenShortcut,
      defaultShortcut: .defaultFullscreen,
      isEnabled: globalEnabledBinding(for: .fullscreen),
      validationIssue: globalValidationIssues[.fullscreen],
      onShortcutChanged: { handleGlobalShortcutChange($0, for: .fullscreen) }
    )

    ShortcutRecorderView(
      label: L10n.Actions.captureArea,
      description: L10n.PreferencesShortcuts.captureAreaDescription,
      shortcut: $areaShortcut,
      defaultShortcut: .defaultArea,
      isEnabled: globalEnabledBinding(for: .area),
      validationIssue: globalValidationIssues[.area],
      onShortcutChanged: { handleGlobalShortcutChange($0, for: .area) }
    )

    CaptureOverlayShortcutRecorderRow(
      label: L10n.PreferencesShortcuts.applicationCaptureTitle,
      description: L10n.PreferencesShortcuts.applicationCaptureDescription,
      shortcut: $areaApplicationCaptureShortcut,
      defaultShortcut: CaptureOverlayShortcutSettings.defaultApplicationCaptureShortcut,
      isEnabled: globalEnabledBinding(for: .area),
      validationIssue: captureOverlayValidationIssues[.applicationCapture]
    ) { newShortcut in
      handleCaptureOverlayShortcutChange(newShortcut, for: .applicationCapture)
    }

    ShortcutRecorderView(
      label: L10n.Actions.captureRepeatArea,
      description: L10n.PreferencesShortcuts.captureRepeatAreaDescription,
      shortcut: $repeatAreaShortcut,
      defaultShortcut: .defaultRepeatArea,
      isEnabled: globalEnabledBinding(for: .repeatArea),
      validationIssue: globalValidationIssues[.repeatArea],
      onShortcutChanged: { handleGlobalShortcutChange($0, for: .repeatArea) }
    )

    ShortcutRecorderView(
      label: L10n.Actions.captureDelayed,
      description: L10n.PreferencesShortcuts.captureDelayedDescription,
      shortcut: $delayedCaptureShortcut,
      defaultShortcut: nil,
      isEnabled: globalEnabledBinding(for: .delayedCapture),
      validationIssue: globalValidationIssues[.delayedCapture],
      onShortcutChanged: { handleGlobalShortcutChange($0, for: .delayedCapture) }
    )

    ShortcutRecorderView(
      label: L10n.Actions.captureDelayedFullscreen,
      description: L10n.PreferencesShortcuts.captureDelayedFullscreenDescription,
      shortcut: $delayedFullscreenShortcut,
      defaultShortcut: nil,
      isEnabled: globalEnabledBinding(for: .delayedFullscreen),
      validationIssue: globalValidationIssues[.delayedFullscreen],
      onShortcutChanged: { handleGlobalShortcutChange($0, for: .delayedFullscreen) }
    )

    ShortcutRecorderView(
      label: L10n.Actions.captureAreaAnnotate,
      description: L10n.PreferencesShortcuts.captureAreaAnnotateDescription,
      shortcut: $areaAnnotateShortcut,
      defaultShortcut: .defaultAreaAnnotate,
      isEnabled: globalEnabledBinding(for: .areaAnnotate),
      validationIssue: globalValidationIssues[.areaAnnotate],
      onShortcutChanged: { handleGlobalShortcutChange($0, for: .areaAnnotate) }
    )

    ShortcutRecorderView(
      label: L10n.Actions.captureActiveWindow,
      description: L10n.PreferencesShortcuts.captureActiveWindowDescription,
      shortcut: $activeWindowShortcut,
      defaultShortcut: .defaultActiveWindowCapture,
      isEnabled: globalEnabledBinding(for: .activeWindow),
      validationIssue: globalValidationIssues[.activeWindow],
      onShortcutChanged: { handleGlobalShortcutChange($0, for: .activeWindow) }
    )

    ShortcutRecorderView(
      label: GlobalShortcutKind.scrollingCapture.displayName,
      description: "Guided session for long screenshots",
      shortcut: $scrollingCaptureShortcut,
      defaultShortcut: .defaultScrollingCapture,
      isEnabled: globalEnabledBinding(for: .scrollingCapture),
      validationIssue: globalValidationIssues[.scrollingCapture],
      onShortcutChanged: { handleGlobalShortcutChange($0, for: .scrollingCapture) }
    )

    ShortcutRecorderView(
      label: GlobalShortcutKind.objectCutout.displayName,
      description: "Select an area, isolate the subject, and optionally auto-crop",
      shortcut: $objectCutoutShortcut,
      defaultShortcut: .defaultObjectCutout,
      isEnabled: globalEnabledBinding(for: .objectCutout),
      validationIssue: globalValidationIssues[.objectCutout],
      onShortcutChanged: { handleGlobalShortcutChange($0, for: .objectCutout) }
    )

    ShortcutRecorderView(
      label: L10n.Actions.captureTextOCR,
      description: L10n.PreferencesShortcuts.captureTextDescription,
      shortcut: $ocrShortcut,
      defaultShortcut: .defaultOCR,
      isEnabled: globalEnabledBinding(for: .ocr),
      validationIssue: globalValidationIssues[.ocr],
      onShortcutChanged: { handleGlobalShortcutChange($0, for: .ocr) }
    )

    ShortcutRecorderView(
      label: L10n.Actions.captureSmartElement,
      description: L10n.PreferencesShortcuts.smartElementCaptureDescription,
      shortcut: $smartElementShortcut,
      defaultShortcut: .defaultSmartElement,
      isEnabled: globalEnabledBinding(for: .smartElement),
      validationIssue: globalValidationIssues[.smartElement],
      onShortcutChanged: { handleGlobalShortcutChange($0, for: .smartElement) }
    )
  }

  @ViewBuilder
  private var recordingRows: some View {
    ShortcutRecorderView(
      label: L10n.Actions.recordVideo,
      description: L10n.PreferencesShortcuts.recordVideoDescription,
      shortcut: $recordingShortcut,
      defaultShortcut: .defaultRecording,
      isEnabled: globalEnabledBinding(for: .recording),
      validationIssue: globalValidationIssues[.recording],
      onShortcutChanged: { handleGlobalShortcutChange($0, for: .recording) }
    )

    CaptureOverlayShortcutRecorderRow(
      label: L10n.PreferencesShortcuts.applicationRecordingTitle,
      description: L10n.PreferencesShortcuts.applicationRecordingDescription,
      shortcut: $recordingApplicationCaptureShortcut,
      defaultShortcut: CaptureOverlayShortcutSettings.defaultRecordingApplicationCaptureShortcut,
      isEnabled: globalEnabledBinding(for: .recording),
      validationIssue: captureOverlayValidationIssues[.applicationRecording]
    ) { newShortcut in
      handleCaptureOverlayShortcutChange(newShortcut, for: .applicationRecording)
    }

    ShortcutRecorderView(
      label: L10n.Actions.pauseResumeRecording,
      description: L10n.PreferencesShortcuts.pauseResumeRecordingDescription,
      footnote: L10n.PreferencesShortcuts.activeOnlyWhileRecording,
      shortcut: $pauseResumeRecordingShortcut,
      defaultShortcut: nil,
      isEnabled: globalEnabledBinding(for: .pauseResumeRecording),
      validationIssue: globalValidationIssues[.pauseResumeRecording],
      onShortcutChanged: { handleGlobalShortcutChange($0, for: .pauseResumeRecording) }
    )

    ShortcutRecorderView(
      label: L10n.Actions.togglePenRecording,
      description: L10n.PreferencesShortcuts.togglePenRecordingDescription,
      footnote: L10n.PreferencesShortcuts.activeOnlyWhileRecording,
      shortcut: $togglePenRecordingShortcut,
      defaultShortcut: nil,
      isEnabled: globalEnabledBinding(for: .togglePenRecording),
      validationIssue: globalValidationIssues[.togglePenRecording],
      onShortcutChanged: { handleGlobalShortcutChange($0, for: .togglePenRecording) }
    )

    ShortcutRecorderView(
      label: L10n.Actions.restartRecording,
      description: L10n.PreferencesShortcuts.restartRecordingDescription,
      footnote: L10n.PreferencesShortcuts.activeOnlyWhileRecording,
      shortcut: $restartRecordingShortcut,
      defaultShortcut: nil,
      isEnabled: globalEnabledBinding(for: .restartRecording),
      validationIssue: globalValidationIssues[.restartRecording],
      onShortcutChanged: { handleGlobalShortcutChange($0, for: .restartRecording) }
    )

    ShortcutRecorderView(
      label: L10n.Actions.deleteRecording,
      description: L10n.PreferencesShortcuts.deleteRecordingDescription,
      footnote: L10n.PreferencesShortcuts.activeOnlyWhileRecording,
      shortcut: $deleteRecordingShortcut,
      defaultShortcut: nil,
      isEnabled: globalEnabledBinding(for: .deleteRecording),
      validationIssue: globalValidationIssues[.deleteRecording],
      onShortcutChanged: { handleGlobalShortcutChange($0, for: .deleteRecording) }
    )
  }

  @ViewBuilder
  private var toolsRows: some View {
    ShortcutRecorderView(
      label: L10n.Actions.openAnnotate,
      description: L10n.PreferencesShortcuts.openAnnotateDescription,
      shortcut: $annotateShortcut,
      defaultShortcut: .defaultAnnotate,
      isEnabled: globalEnabledBinding(for: .annotate),
      validationIssue: globalValidationIssues[.annotate],
      onShortcutChanged: { handleGlobalShortcutChange($0, for: .annotate) }
    )

    ShortcutRecorderView(
      label: L10n.Actions.openVideoEditor,
      description: L10n.PreferencesShortcuts.openVideoEditorDescription,
      shortcut: $videoEditorShortcut,
      defaultShortcut: .defaultVideoEditor,
      isEnabled: globalEnabledBinding(for: .videoEditor),
      validationIssue: globalValidationIssues[.videoEditor],
      onShortcutChanged: { handleGlobalShortcutChange($0, for: .videoEditor) }
    )

    ShortcutRecorderView(
      label: L10n.Actions.cloudUploads,
      description: L10n.PreferencesShortcuts.cloudUploadsDescription,
      shortcut: $cloudUploadsShortcut,
      defaultShortcut: .defaultCloudUploads,
      isEnabled: globalEnabledBinding(for: .cloudUploads),
      validationIssue: globalValidationIssues[.cloudUploads],
      onShortcutChanged: { handleGlobalShortcutChange($0, for: .cloudUploads) }
    )

    ShortcutRecorderView(
      label: L10n.Actions.pickColor,
      description: L10n.PreferencesShortcuts.pickColorDescription,
      shortcut: $pickColorShortcut,
      defaultShortcut: nil,
      isEnabled: globalEnabledBinding(for: .pickColor),
      validationIssue: globalValidationIssues[.pickColor],
      onShortcutChanged: { handleGlobalShortcutChange($0, for: .pickColor) }
    )

    ShortcutRecorderView(
      label: L10n.Actions.showShortcutList,
      description: L10n.PreferencesShortcuts.shortcutListDescription,
      shortcut: $shortcutListShortcut,
      defaultShortcut: .defaultShortcutList,
      isEnabled: globalEnabledBinding(for: .shortcutList),
      validationIssue: globalValidationIssues[.shortcutList],
      onShortcutChanged: { handleGlobalShortcutChange($0, for: .shortcutList) }
    )
  }

  @ViewBuilder
  private var historyRows: some View {
    ShortcutRecorderView(
      label: L10n.Actions.openHistory,
      description: L10n.PreferencesShortcuts.openHistoryDescription,
      shortcut: $historyShortcut,
      defaultShortcut: .defaultHistory,
      isEnabled: globalEnabledBinding(for: .history),
      validationIssue: globalValidationIssues[.history],
      onShortcutChanged: { handleGlobalShortcutChange($0, for: .history) }
    )

    ShortcutRecorderView(
      label: L10n.PreferencesHistory.toggleModeShortcutTitle,
      description: L10n.PreferencesHistory.toggleModeShortcutDescription,
      shortcut: $historyFloatingManager.toggleModeShortcut,
      defaultShortcut: HistoryFloatingManager.defaultToggleModeShortcut,
      isEnabled: $historyFloatingManager.isToggleModeShortcutEnabled,
      onShortcutChanged: { config in
        historyFloatingManager.toggleModeShortcut = config
        return true
      }
    )
    .disabled(!historyFloatingManager.isEnabled)
    .opacity(historyFloatingManager.isEnabled ? 1.0 : 0.6)
  }

  @ViewBuilder
  private var quickAccessRows: some View {
    ShortcutRecorderView(
      label: L10n.PreferencesShortcuts.editLatestCapture,
      description: L10n.PreferencesShortcuts.editLatestCaptureDescription,
      shortcut: $openEditorShortcut,
      defaultShortcut: QuickAccessManager.defaultOpenEditorShortcut,
      isEnabled: Binding(
        get: { openEditorShortcutEnabled },
        set: { newValue in
          openEditorShortcutEnabled = newValue
          QuickAccessManager.shared.openEditorShortcutEnabled = newValue
        }
      ),
      onShortcutChanged: { config in
        QuickAccessManager.shared.setOpenEditorShortcut(config)
        return true
      }
    )
  }

  @ViewBuilder
  private var annotateActionsRows: some View {
    ShortcutRecorderView(
      label: L10n.ShortcutOverlay.copyAndClose,
      description: L10n.PreferencesShortcuts.copyAndCloseDescription,
      shortcut: $copyAndCloseShortcut,
      defaultShortcut: AnnotateShortcutManager.defaultCopyAndClose,
      isEnabled: annotateActionEnabledBinding(for: .copyAndClose),
      validationIssue: annotateActionValidationIssues[.copyAndClose],
      onShortcutChanged: { handleAnnotateActionShortcutChange($0, for: .copyAndClose) }
    )

    ShortcutRecorderView(
      label: L10n.AnnotateUI.toggleSidebar,
      shortcut: $toggleSidebarShortcut,
      defaultShortcut: AnnotateShortcutManager.defaultToggleSidebar,
      isEnabled: annotateActionEnabledBinding(for: .toggleSidebar),
      validationIssue: annotateActionValidationIssues[.toggleSidebar],
      onShortcutChanged: { handleAnnotateActionShortcutChange($0, for: .toggleSidebar) }
    )

    ShortcutRecorderView(
      label: L10n.ShortcutOverlay.togglePin,
      description: L10n.PreferencesShortcuts.togglePinDescription,
      shortcut: $togglePinShortcut,
      defaultShortcut: AnnotateShortcutManager.defaultTogglePin,
      isEnabled: annotateActionEnabledBinding(for: .togglePin),
      validationIssue: annotateActionValidationIssues[.togglePin],
      onShortcutChanged: { handleAnnotateActionShortcutChange($0, for: .togglePin) }
    )

    ShortcutRecorderView(
      label: L10n.ShortcutOverlay.cloudUpload,
      description: L10n.PreferencesShortcuts.cloudUploadDescription,
      shortcut: $cloudUploadShortcut,
      defaultShortcut: AnnotateShortcutManager.defaultCloudUpload,
      isEnabled: annotateActionEnabledBinding(for: .cloudUpload),
      validationIssue: annotateActionValidationIssues[.cloudUpload],
      onShortcutChanged: { handleAnnotateActionShortcutChange($0, for: .cloudUpload) }
    )

    ShortcutRecorderView(
      label: L10n.ShortcutOverlay.autoRedactSensitiveData,
      description: L10n.PreferencesShortcuts.autoRedactSensitiveDataDescription,
      shortcut: $autoRedactSensitiveDataShortcut,
      defaultShortcut: AnnotateShortcutManager.defaultAutoRedactSensitiveData,
      isEnabled: annotateActionEnabledBinding(for: .autoRedactSensitiveData),
      validationIssue: annotateActionValidationIssues[.autoRedactSensitiveData],
      onShortcutChanged: { handleAnnotateActionShortcutChange($0, for: .autoRedactSensitiveData) }
    )
  }

  @ViewBuilder
  private var annotateToolKeysRows: some View {
    ForEach(AnnotateShortcutManager.configurableTools, id: \.self) { tool in
      SingleKeyRecorderView(
        tool: tool,
        shortcut: bindingForTool(tool),
        isEnabled: toolEnabledBinding(for: tool),
        validationIssue: annotateToolValidationIssues[tool],
        onChanged: { handleAnnotateToolShortcutChange($0, for: tool) },
        conflictingTool: conflictForTool(tool),
        context: toolContext(for: tool),
        defaultShortcut: tool.defaultShortcut
      )
    }
  }

  @ViewBuilder
  private var annotateReferenceRows: some View {
    ReadOnlyShortcutRow(label: L10n.ShortcutOverlay.saveDone, shortcut: "⌘ S")
    ReadOnlyShortcutRow(
      label: L10n.ShortcutOverlay.saveAs,
      shortcut: "⌘ ⇧ S"
    )
    ReadOnlyShortcutRow(label: L10n.ShortcutOverlay.undo, shortcut: "⌘ Z")
    ReadOnlyShortcutRow(label: L10n.ShortcutOverlay.redo, shortcut: "⌘ ⇧ Z")
    ReadOnlyShortcutRow(label: L10n.ShortcutOverlay.deleteAnnotation, shortcut: "⌫")
    ReadOnlyShortcutRow(label: L10n.ShortcutOverlay.cancelDeselect, shortcut: "⎋")
    ReadOnlyShortcutRow(label: L10n.ShortcutOverlay.confirmCrop, shortcut: "↩")
    ReadOnlyShortcutRow(
      label: L10n.ShortcutOverlay.nudgeAnnotation,
      shortcut: "← → ↑ ↓"
    )
    ReadOnlyShortcutRow(
      label: L10n.ShortcutOverlay.nudgeTenPixels,
      shortcut: "⇧ ← → ↑ ↓"
    )
  }


  // MARK: - Actions

  /// Show the Accessibility hint only when an Fn-based binding exists and the
  /// permission the Fn key monitors rely on is missing.
  private var showsFnAccessibilityHint: Bool {
    shortcutsEnabled && manager.hasFnBoundShortcuts && !accessibilityGranted
  }

  private func resetCaptureSection(refresh: Bool = true) {
    fullscreenShortcut = .defaultFullscreen
    areaShortcut = .defaultArea
    repeatAreaShortcut = .defaultRepeatArea
    delayedCaptureShortcut = nil
    delayedFullscreenShortcut = nil
    areaAnnotateShortcut = .defaultAreaAnnotate
    activeWindowShortcut = .defaultActiveWindowCapture
    areaApplicationCaptureShortcut = CaptureOverlayShortcutSettings.defaultApplicationCaptureShortcut
    scrollingCaptureShortcut = .defaultScrollingCapture
    objectCutoutShortcut = .defaultObjectCutout
    ocrShortcut = .defaultOCR
    smartElementShortcut = .defaultSmartElement

    let captureKinds: [GlobalShortcutKind] = [
      .fullscreen, .area, .repeatArea, .delayedCapture, .delayedFullscreen, .areaAnnotate, .activeWindow, .scrollingCapture, .objectCutout, .ocr,
      .smartElement,
    ]
    for kind in captureKinds {
      globalShortcutEnabled[kind] = true
      manager.setShortcutEnabled(true, for: kind)
      globalValidationIssues.removeValue(forKey: kind)
    }
    captureOverlayValidationIssues.removeValue(forKey: .applicationCapture)

    manager.setFullscreenShortcut(.defaultFullscreen)
    manager.setAreaShortcut(.defaultArea)
    manager.setRepeatAreaShortcut(.defaultRepeatArea)
    manager.setDelayedCaptureShortcut(nil)
    manager.setDelayedFullscreenShortcut(nil)
    manager.setAreaAnnotateShortcut(.defaultAreaAnnotate)
    manager.setActiveWindowShortcut(.defaultActiveWindowCapture)
    manager.setScrollingCaptureShortcut(.defaultScrollingCapture)
    manager.setObjectCutoutShortcut(.defaultObjectCutout)
    manager.setOCRShortcut(.defaultOCR)
    manager.setSmartElementShortcut(.defaultSmartElement)
    CaptureOverlayShortcutSettings.resetApplicationCaptureShortcut()

    if refresh {
      manager.refreshShortcutRegistration()
      hasSystemConflict = SystemScreenshotShortcutManager.shared.hasConflictingSystemShortcuts()
    }
  }

  private func resetRecordingSection(refresh: Bool = true) {
    recordingShortcut = .defaultRecording
    recordingApplicationCaptureShortcut = CaptureOverlayShortcutSettings.defaultRecordingApplicationCaptureShortcut
    pauseResumeRecordingShortcut = nil
    togglePenRecordingShortcut = nil
    restartRecordingShortcut = nil
    deleteRecordingShortcut = nil

    globalShortcutEnabled[.recording] = true
    globalShortcutEnabled[.pauseResumeRecording] = true
    globalShortcutEnabled[.togglePenRecording] = true
    globalShortcutEnabled[.restartRecording] = true
    globalShortcutEnabled[.deleteRecording] = true

    manager.setShortcutEnabled(true, for: .recording)
    manager.setShortcutEnabled(true, for: .pauseResumeRecording)
    manager.setShortcutEnabled(true, for: .togglePenRecording)
    manager.setShortcutEnabled(true, for: .restartRecording)
    manager.setShortcutEnabled(true, for: .deleteRecording)

    globalValidationIssues.removeValue(forKey: .recording)
    globalValidationIssues.removeValue(forKey: .pauseResumeRecording)
    globalValidationIssues.removeValue(forKey: .togglePenRecording)
    globalValidationIssues.removeValue(forKey: .restartRecording)
    globalValidationIssues.removeValue(forKey: .deleteRecording)
    captureOverlayValidationIssues.removeValue(forKey: .applicationRecording)

    manager.setRecordingShortcut(.defaultRecording)
    manager.setPauseResumeRecordingShortcut(nil)
    manager.setTogglePenRecordingShortcut(nil)
    manager.setRestartRecordingShortcut(nil)
    manager.setDeleteRecordingShortcut(nil)
    CaptureOverlayShortcutSettings.resetRecordingApplicationCaptureShortcut()

    if refresh {
      manager.refreshShortcutRegistration()
      hasSystemConflict = SystemScreenshotShortcutManager.shared.hasConflictingSystemShortcuts()
    }
  }

  private func resetToolsSection(refresh: Bool = true) {
    annotateShortcut = .defaultAnnotate
    videoEditorShortcut = .defaultVideoEditor
    cloudUploadsShortcut = .defaultCloudUploads
    shortcutListShortcut = .defaultShortcutList
    pickColorShortcut = nil

    let toolsKinds: [GlobalShortcutKind] = [.annotate, .videoEditor, .cloudUploads, .shortcutList, .pickColor]
    for kind in toolsKinds {
      globalShortcutEnabled[kind] = true
      manager.setShortcutEnabled(true, for: kind)
      globalValidationIssues.removeValue(forKey: kind)
    }

    manager.setAnnotateShortcut(.defaultAnnotate)
    manager.setVideoEditorShortcut(.defaultVideoEditor)
    manager.setCloudUploadsShortcut(.defaultCloudUploads)
    manager.setShortcutListShortcut(.defaultShortcutList)
    manager.setPickColorShortcut(nil)

    if refresh {
      manager.refreshShortcutRegistration()
      hasSystemConflict = SystemScreenshotShortcutManager.shared.hasConflictingSystemShortcuts()
    }
  }

  private func resetHistorySection(refresh: Bool = true) {
    historyShortcut = .defaultHistory
    globalShortcutEnabled[.history] = true
    manager.setShortcutEnabled(true, for: .history)
    globalValidationIssues.removeValue(forKey: .history)
    manager.setHistoryShortcut(.defaultHistory)

    HistoryFloatingManager.shared.resetToggleModeShortcut()

    if refresh {
      manager.refreshShortcutRegistration()
      hasSystemConflict = SystemScreenshotShortcutManager.shared.hasConflictingSystemShortcuts()
    }
  }

  private func resetQuickAccessSection() {
    openEditorShortcut = QuickAccessManager.defaultOpenEditorShortcut
    QuickAccessManager.shared.setOpenEditorShortcut(QuickAccessManager.defaultOpenEditorShortcut)
    openEditorShortcutEnabled = false
    QuickAccessManager.shared.openEditorShortcutEnabled = false
    QuickAccessActionShortcutStore.shared.resetToDefaults()
    quickAccessResetCount += 1
  }

  private func resetAnnotateActionsSection() {
    copyAndCloseShortcut = AnnotateShortcutManager.defaultCopyAndClose
    toggleSidebarShortcut = AnnotateShortcutManager.defaultToggleSidebar
    togglePinShortcut = AnnotateShortcutManager.defaultTogglePin
    cloudUploadShortcut = AnnotateShortcutManager.defaultCloudUpload
    autoRedactSensitiveDataShortcut = AnnotateShortcutManager.defaultAutoRedactSensitiveData

    for kind in AnnotateActionShortcutKind.allCases {
      annotateActionEnabled[kind] = true
      annotateManager.setActionShortcutEnabled(true, for: kind)
      annotateActionValidationIssues.removeValue(forKey: kind)
    }

    annotateManager.setCopyAndCloseShortcut(AnnotateShortcutManager.defaultCopyAndClose)
    annotateManager.setToggleSidebarShortcut(AnnotateShortcutManager.defaultToggleSidebar)
    annotateManager.setTogglePinShortcut(AnnotateShortcutManager.defaultTogglePin)
    annotateManager.setCloudUploadShortcut(AnnotateShortcutManager.defaultCloudUpload)
    annotateManager.setAutoRedactSensitiveDataShortcut(AnnotateShortcutManager.defaultAutoRedactSensitiveData)
  }

  private func resetAnnotateToolKeysSection() {
    for tool in AnnotateShortcutManager.configurableTools {
      annotateManager.setShortcut(tool.defaultShortcut, for: tool)
      annotateManager.setShortcutEnabled(true, for: tool)
      annotateToolValidationIssues.removeValue(forKey: tool)
    }
  }

  private func resetToDefaults() {
    resetCaptureSection(refresh: false)
    resetRecordingSection(refresh: false)
    resetToolsSection(refresh: false)
    resetQuickAccessSection()
    resetAnnotateActionsSection()
    resetAnnotateToolKeysSection()

    manager.refreshShortcutRegistration()
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

  private func handleGlobalShortcutChange(_ config: ShortcutConfig?, for kind: GlobalShortcutKind) -> Bool {
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
      case .repeatArea:
        repeatAreaShortcut = config
        manager.setRepeatAreaShortcut(config)
      case .delayedCapture:
        delayedCaptureShortcut = config
        manager.setDelayedCaptureShortcut(config)
      case .delayedFullscreen:
        delayedFullscreenShortcut = config
        manager.setDelayedFullscreenShortcut(config)
      case .areaAnnotate:
        areaAnnotateShortcut = config
        manager.setAreaAnnotateShortcut(config)
      case .activeWindow:
        activeWindowShortcut = config
        manager.setActiveWindowShortcut(config)
      case .scrollingCapture:
        scrollingCaptureShortcut = config
        manager.setScrollingCaptureShortcut(config)
      case .recording:
        recordingShortcut = config
        manager.setRecordingShortcut(config)
      case .pauseResumeRecording:
        pauseResumeRecordingShortcut = config
        manager.setPauseResumeRecordingShortcut(config)
      case .togglePenRecording:
        togglePenRecordingShortcut = config
        manager.setTogglePenRecordingShortcut(config)
      case .restartRecording:
        restartRecordingShortcut = config
        manager.setRestartRecordingShortcut(config)
      case .deleteRecording:
        deleteRecordingShortcut = config
        manager.setDeleteRecordingShortcut(config)
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
      case .smartElement:
        smartElementShortcut = config
        manager.setSmartElementShortcut(config)
      case .objectCutout:
        objectCutoutShortcut = config
        manager.setObjectCutoutShortcut(config)
      case .history:
        historyShortcut = config
        manager.setHistoryShortcut(config)
      case .pickColor:
        pickColorShortcut = config
        manager.setPickColorShortcut(config)
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
    _ config: ShortcutConfig?,
    for kind: AnnotateActionShortcutKind
  ) -> Bool {
    switch validator.validateAnnotateActionShortcut(config, for: kind) {
    case .accept(let issue):
      annotateActionValidationIssues[kind] = issue
      switch kind {
      case .copyAndClose:
        copyAndCloseShortcut = config
        annotateManager.setCopyAndCloseShortcut(config)
      case .toggleSidebar:
        toggleSidebarShortcut = config
        annotateManager.setToggleSidebarShortcut(config)
      case .togglePin:
        togglePinShortcut = config
        annotateManager.setTogglePinShortcut(config)
      case .cloudUpload:
        cloudUploadShortcut = config
        annotateManager.setCloudUploadShortcut(config)
      case .autoRedactSensitiveData:
        autoRedactSensitiveDataShortcut = config
        annotateManager.setAutoRedactSensitiveDataShortcut(config)
      }
      return true
    case .reject(let issue):
      annotateActionValidationIssues[kind] = issue
      return false
    }
  }

  private func handleCaptureOverlayShortcutChange(
    _ shortcut: CaptureOverlayShortcut?,
    for kind: CaptureOverlayShortcutKind
  ) -> Bool {
    switch validator.validateCaptureOverlayShortcut(shortcut, for: kind) {
    case .accept(let issue):
      captureOverlayValidationIssues[kind] = issue
      switch kind {
      case .applicationCapture:
        areaApplicationCaptureShortcut = shortcut
        CaptureOverlayShortcutSettings.setApplicationCaptureShortcut(shortcut)
      case .applicationRecording:
        recordingApplicationCaptureShortcut = shortcut
        CaptureOverlayShortcutSettings.setRecordingApplicationCaptureShortcut(shortcut)
      }
      manager.refreshShortcutRegistration()
      hasSystemConflict = SystemScreenshotShortcutManager.shared.hasConflictingSystemShortcuts()
      return true
    case .reject(let issue):
      captureOverlayValidationIssues[kind] = issue
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
    if inScreenshot, inRecording { return .both }
    if inRecording { return .recordingOnly }
    return .screenshotOnly
  }
}

private struct CaptureOverlayShortcutRecorderRow: View {
  let label: String
  let description: String
  @Binding var shortcut: CaptureOverlayShortcut?
  let defaultShortcut: CaptureOverlayShortcut?
  let isEnabled: Binding<Bool>
  let validationIssue: ShortcutValidationIssue?
  let onShortcutChanged: (CaptureOverlayShortcut?) -> Bool

  @State private var isRecording = false
  @State private var eventMonitor: Any?
  @State private var didSuspendGlobalShortcuts = false

  var body: some View {
    HStack(spacing: 12) {
      Text(label)
        .hint(description, variant: .icon(.info))

      Spacer()

      shortcutRecorderButton

      ShortcutOptionsMenuButton(
        isEnabled: isEnabled,
        isDefault: shortcut == defaultShortcut,
        isBusy: isRecording,
        onReset: resetToDefault
      )
    }
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
          KeyCapRecordingView(minWidth: 100)
        } else if let shortcut {
          KeyCapGroupView(parts: shortcut.displayParts)
        } else {
          KeyCapPlaceholderView(title: L10n.PreferencesShortcuts.setKey, minWidth: 72)
        }
    }
    .buttonStyle(ShortcutKeycapButtonStyle(isRecording: isRecording))
    .shortcutValidationHighlight(issue: validationIssue)
    .disabled(!isEnabled.wrappedValue)
    .help(isEnabled.wrappedValue ? L10n.ShortcutRecorder.clickToRecord : L10n.ShortcutRecorder.turnOnToEdit)
  }

  private var rowOpacity: Double {
    isEnabled.wrappedValue ? 1 : 0.62
  }

  private func resetToDefault() {
    if onShortcutChanged(defaultShortcut) {
      shortcut = defaultShortcut
    }
  }

  private func startRecording() {
    guard !isRecording, isEnabled.wrappedValue else { return }
    isRecording = true
    KeyboardShortcutManager.shared.beginTemporaryShortcutSuppression()
    didSuspendGlobalShortcuts = true

    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      if event.keyCode == UInt16(kVK_Escape) {
        stopRecording()
        return nil
      }

      if isClearShortcutEvent(event) {
        _ = onShortcutChanged(nil)
        stopRecording()
        return nil
      }

      guard let newShortcut = CaptureOverlayShortcut(from: event) else {
        return nil
      }

      if onShortcutChanged(newShortcut) {
        shortcut = newShortcut
        stopRecording()
      }
      return nil
    }
  }

  private func isClearShortcutEvent(_ event: NSEvent) -> Bool {
    switch Int(event.keyCode) {
    case kVK_Delete, kVK_ForwardDelete:
      event.modifierFlags
        .intersection([.command, .control, .option, .shift])
        .isEmpty
    default:
      false
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

// MARK: - Pages

/// Shortcut groups listed as expandable cards on the Shortcuts overview.
private enum ShortcutsPage: String, CaseIterable, Identifiable {
  case capture
  case recording
  case tools
  case history
  case quickAccess
  case annotateActions
  case annotateTools
  case annotateReference

  var id: String { rawValue }

  /// Registered system-wide; they work while any app is frontmost.
  static let globalPages: [ShortcutsPage] = [.capture, .recording, .tools, .history]
  /// Only active inside a Snapzy surface (Quick Access card, editor).
  static let inAppPages: [ShortcutsPage] = [.quickAccess, .annotateActions, .annotateTools, .annotateReference]

  /// Extra guidance behind the ⓘ beside the card title.
  var help: String? {
    switch self {
    case .tools: return L10n.PreferencesShortcuts.recorderHint
    case .history: return L10n.PreferencesShortcuts.historySectionDescription
    case .quickAccess: return L10n.PreferencesShortcuts.quickAccessSectionDescription
    case .annotateActions: return L10n.PreferencesShortcuts.annotateActionsDescription
    case .annotateTools:
      return [
        L10n.PreferencesShortcuts.annotationToolDescription,
        L10n.PreferencesShortcuts.singleKeyHint,
      ].joined(separator: "\n")
    case .annotateReference: return L10n.PreferencesShortcuts.referenceDescription
    case .capture, .recording: return nil
    }
  }

  var title: String {
    switch self {
    case .capture: return L10n.ShortcutOverlay.captureSection
    case .recording: return L10n.PreferencesShortcuts.recordingPage
    case .tools: return L10n.ShortcutOverlay.toolsSection
    case .history: return L10n.Preferences.historyTab
    case .quickAccess: return L10n.PreferencesShortcuts.quickAccessSection
    case .annotateActions: return L10n.ShortcutOverlay.annotateActions
    case .annotateTools: return L10n.ShortcutOverlay.annotateToolKeys
    case .annotateReference: return L10n.ShortcutOverlay.annotateReference
    }
  }

  var subtitle: String {
    switch self {
    case .capture: return L10n.PreferencesShortcuts.capturePageDescription
    case .recording: return L10n.PreferencesShortcuts.recordingPageDescription
    case .tools: return L10n.PreferencesShortcuts.toolsPageDescription
    case .history: return L10n.PreferencesShortcuts.historyPageDescription
    case .quickAccess: return L10n.PreferencesShortcuts.quickAccessPageDescription
    case .annotateActions: return L10n.PreferencesShortcuts.annotateActionsPageDescription
    case .annotateTools: return L10n.PreferencesShortcuts.annotateToolsPageDescription
    case .annotateReference: return L10n.PreferencesShortcuts.annotateReferencePageDescription
    }
  }

  /// Accent layer of the card's duotone tile, echoing the sidebar page each group belongs to.
  var iconTint: PreferencesIconTint {
    switch self {
    case .capture: return PreferencesTab.capture.iconTint
    case .recording: return PreferencesIconTint(hue: 2, saturation: 0.62)
    case .tools: return .periwinkle
    case .history: return PreferencesTab.history.iconTint
    case .quickAccess: return PreferencesTab.quickAccess.iconTint
    case .annotateActions: return PreferencesTab.annotate.iconTint
    case .annotateTools: return PreferencesTab.menuBar.iconTint
    case .annotateReference: return PreferencesIconTint(hue: 138, saturation: 0.55)
    }
  }

  var symbol: String {
    switch self {
    case .capture: return "camera.viewfinder"
    case .recording: return "record.circle"
    case .tools: return "wrench.and.screwdriver.fill"
    case .history: return "clock.arrow.circlepath"
    case .quickAccess: return "square.stack.3d.up.fill"
    case .annotateActions: return "paintbrush.pointed.fill"
    case .annotateTools: return "character.cursor.ibeam"
    case .annotateReference: return "book.closed.fill"
    }
  }
}

// MARK: - System Shortcut Conflict Badge

/// Toolbar badge summarising whether macOS screenshot shortcuts overlap Snapzy's.
/// Clicking it opens a popover with the details, fix-up steps and a re-check button.
private struct SystemShortcutConflictBadge: View {
  let hasConflict: Bool
  let isRefreshing: Bool
  let onRefresh: () -> Void

  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      Image(systemName: hasConflict ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 24, height: 24)
        .background(Circle().fill(tint.opacity(0.15)))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    // Equal inset on every side so the circle sits centred in the toolbar capsule.
    .padding(6)
    .accessibilityLabel(
      hasConflict ? L10n.PreferencesShortcuts.conflictBadge : L10n.PreferencesShortcuts.noConflictsBadge
    )
    .help(hasConflict ? L10n.PreferencesShortcuts.systemConflictTitle : L10n.PreferencesShortcuts.noConflictsDetected)
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      popoverContent
        .padding(16)
        .frame(width: 340)
    }
  }

  private var tint: Color { hasConflict ? .orange : .green }

  @ViewBuilder
  private var popoverContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: hasConflict ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
          .font(.system(size: 18))
          .foregroundColor(tint)

        VStack(alignment: .leading, spacing: 2) {
          Text(hasConflict ? L10n.PreferencesShortcuts.systemConflictTitle : L10n.PreferencesShortcuts.noConflictsDetected)
            .font(.system(size: 13, weight: .semibold))
          Text(hasConflict ? L10n.PreferencesShortcuts.systemConflictDescription : L10n.PreferencesShortcuts.noConflictsDescription)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      if hasConflict {
        VStack(alignment: .leading, spacing: 6) {
          Text(L10n.PreferencesShortcuts.howToDisable)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(0.8)

          PreferencesGuideStep(step: "1", text: L10n.Onboarding.guideStep1)
          PreferencesGuideStep(step: "2", text: L10n.Onboarding.guideStep2)
          PreferencesGuideStep(step: "3", text: L10n.Onboarding.guideStep3)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          Radius.rect(Radius.card)
            .fill(Color.orange.opacity(0.06))
        )
      }

      HStack(spacing: 8) {
        if hasConflict {
          Button {
            SystemScreenshotShortcutManager.shared.openSystemScreenshotSettings()
          } label: {
            Label(L10n.PreferencesShortcuts.openKeyboardShortcutsSettings, systemImage: "gear")
          }
        }

        Spacer(minLength: 0)

        Button(action: onRefresh) {
          Label {
            Text(L10n.Common.refresh)
          } icon: {
            Image(systemName: "arrow.clockwise")
              .rotationEffect(.degrees(isRefreshing ? 360 : 0))
              .animation(
                isRefreshing
                  ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                  : .default,
                value: isRefreshing
              )
          }
        }
        .disabled(isRefreshing)
      }
      .controlSize(.regular)
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

      Text(.init(text)) // Supports **bold** markdown
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
  let label: String
  let shortcut: String

  var body: some View {
    HStack(spacing: 12) {
      Text(label)

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
            Radius.rect(Radius.ornament)
              .fill(Color.gray.opacity(0.1))
          )
      }
    }
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
