//
//  ContentView.swift
//  ZapShot
//
//  Test interface for core screenshot functions
//

import Combine
import SwiftUI

struct ContentView: View {
  @StateObject private var viewModel = ScreenCaptureViewModel()

  var body: some View {
    VStack(spacing: 24) {
      // Header
      Text("ZapShot")
        .font(.largeTitle)
        .fontWeight(.bold)

      Text("Screenshot Tool - Core Functions Test")
        .font(.subheadline)
        .foregroundColor(.secondary)

      Divider()

      // Permission Status
      permissionSection

      Divider()

      // Capture Actions
      captureSection

      Divider()

      // Settings
      settingsSection

      Spacer()

      // Status / Result
      statusSection
    }
    .padding(24)
    .frame(minWidth: 400, minHeight: 500)
  }

  // MARK: - Permission Section

  private var permissionSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Permissions")
        .font(.headline)

      HStack {
        Circle()
          .fill(viewModel.hasPermission ? Color.green : Color.red)
          .frame(width: 12, height: 12)

        Text(
          viewModel.hasPermission ? "Screen Recording: Granted" : "Screen Recording: Not Granted"
        )
        .font(.body)

        Spacer()

        Button("Request Permission") {
          viewModel.requestPermission()
        }
        .disabled(viewModel.hasPermission)

        Button("Open Settings") {
          viewModel.openSettings()
        }
      }
    }
  }

  // MARK: - Capture Section

  private var captureSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Capture Actions")
        .font(.headline)

      HStack(spacing: 16) {
        Button {
          viewModel.captureFullscreen()
        } label: {
          VStack {
            Image(systemName: "rectangle.dashed")
              .font(.title)
            Text("Fullscreen")
              .font(.caption)
          }
          .frame(width: 100, height: 60)
        }
        .buttonStyle(.bordered)
        .disabled(!viewModel.hasPermission || viewModel.isCapturing)

        Button {
          viewModel.captureArea()
        } label: {
          VStack {
            Image(systemName: "crop")
              .font(.title)
            Text("Area")
              .font(.caption)
          }
          .frame(width: 100, height: 60)
        }
        .buttonStyle(.bordered)
        .disabled(!viewModel.hasPermission || viewModel.isCapturing)
      }

      if viewModel.isCapturing {
        HStack {
          ProgressView()
            .scaleEffect(0.8)
          Text("Capturing...")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }
  }

  // MARK: - Settings Section

  private var settingsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Settings")
        .font(.headline)

      // Save Directory
      HStack {
        Text("Save to:")
          .font(.body)

        Text(viewModel.saveDirectory.path)
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)

        Spacer()

        Button("Choose...") {
          viewModel.chooseSaveDirectory()
        }
      }

      // Image Format
      HStack {
        Text("Format:")
          .font(.body)

        Picker("", selection: $viewModel.selectedFormat) {
          Text("PNG").tag(ImageFormatOption.png)
          Text("JPEG").tag(ImageFormatOption.jpeg)
          Text("TIFF").tag(ImageFormatOption.tiff)
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
      }

      // Options
      Toggle("Show cursor in capture", isOn: $viewModel.showCursor)

      Toggle("Play sound after capture", isOn: $viewModel.playSound)

      Divider()

      // Keyboard Shortcuts
      Text("Keyboard Shortcuts")
        .font(.headline)

      Toggle("Enable global shortcuts", isOn: $viewModel.shortcutsEnabled)

      if viewModel.shortcutsEnabled {
        VStack(alignment: .leading, spacing: 8) {
          ShortcutRecorderView(
            label: "Fullscreen:",
            shortcut: $viewModel.fullscreenShortcut,
            onShortcutChanged: { viewModel.updateFullscreenShortcut($0) }
          )

          ShortcutRecorderView(
            label: "Area:",
            shortcut: $viewModel.areaShortcut,
            onShortcutChanged: { viewModel.updateAreaShortcut($0) }
          )

          Text("Click to record new shortcut. Press Esc to cancel.")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.leading, 4)
      }

      Divider()

      // Floating Preview
      Text("Floating Preview")
        .font(.headline)

      Toggle("Show floating preview after capture", isOn: Binding(
        get: { viewModel.floatingEnabled },
        set: { viewModel.floatingEnabled = $0 }
      ))

      if viewModel.floatingEnabled {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Position:")
              .font(.body)

            Picker("", selection: Binding(
              get: { viewModel.floatingPosition },
              set: { viewModel.floatingPosition = $0 }
            )) {
              Text("Top Left").tag(FloatingPosition.topLeft)
              Text("Top Right").tag(FloatingPosition.topRight)
              Text("Bottom Left").tag(FloatingPosition.bottomLeft)
              Text("Bottom Right").tag(FloatingPosition.bottomRight)
            }
            .pickerStyle(.menu)
            .frame(width: 140)
          }

          Toggle("Auto-dismiss cards", isOn: Binding(
            get: { viewModel.floatingAutoDismiss },
            set: { viewModel.floatingAutoDismiss = $0 }
          ))

          if viewModel.floatingAutoDismiss {
            HStack {
              Text("Dismiss after:")
              Slider(
                value: Binding(
                  get: { viewModel.floatingAutoDismissDelay },
                  set: { viewModel.floatingAutoDismissDelay = $0 }
                ),
                in: 3...30,
                step: 1
              )
              .frame(width: 120)
              Text("\(Int(viewModel.floatingAutoDismissDelay))s")
                .frame(width: 30)
            }
          }
        }
        .padding(.leading, 4)
      }
    }
  }

  // MARK: - Status Section

  private var statusSection: some View {
    VStack(spacing: 8) {
      if let lastResult = viewModel.lastCaptureResult {
        switch lastResult {
        case .success(let url):
          HStack {
            Image(systemName: "checkmark.circle.fill")
              .foregroundColor(.green)
            Text("Saved: \(url.lastPathComponent)")
              .font(.caption)
          }

          Button("Show in Finder") {
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
          }
          .font(.caption)

        case .failure(let error):
          HStack {
            Image(systemName: "exclamationmark.circle.fill")
              .foregroundColor(.red)
            Text("Error: \(error.localizedDescription)")
              .font(.caption)
          }
        }
      } else {
        Text("Ready to capture")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .padding()
    .background(Color.gray.opacity(0.1))
    .cornerRadius(8)
  }
}

// MARK: - Image Format Option

enum ImageFormatOption: String, CaseIterable {
  case png
  case jpeg
  case tiff

  var format: ImageFormat {
    switch self {
    case .png: return .png
    case .jpeg: return .jpeg(quality: 0.9)
    case .tiff: return .tiff
    }
  }
}

// MARK: - ViewModel

@MainActor
final class ScreenCaptureViewModel: ObservableObject, KeyboardShortcutDelegate {
  @Published var hasPermission: Bool = false
  @Published var isCapturing: Bool = false
  @Published var saveDirectory: URL
  @Published var selectedFormat: ImageFormatOption = .png
  @Published var showCursor: Bool = true
  @Published var playSound: Bool = true
  @Published var lastCaptureResult: CaptureResult?
  @Published var shortcutsEnabled: Bool = false {
    didSet {
      if shortcutsEnabled {
        shortcutManager.enable()
      } else {
        shortcutManager.disable()
      }
    }
  }

  private let captureManager = ScreenCaptureManager.shared
  private let shortcutManager = KeyboardShortcutManager.shared
  private let floatingManager = FloatingScreenshotManager.shared
  private var areaSelectionController: AreaSelectionController?
  private var cancellables = Set<AnyCancellable>()

  // Shortcut bindings for UI
  @Published var fullscreenShortcut: ShortcutConfig
  @Published var areaShortcut: ShortcutConfig

  init() {
    // Default save directory: Desktop/ZapShot
    let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
    saveDirectory = desktop.appendingPathComponent("ZapShot")

    // Initialize shortcuts from manager
    fullscreenShortcut = KeyboardShortcutManager.shared.fullscreenShortcut
    areaShortcut = KeyboardShortcutManager.shared.areaShortcut

    // Set up shortcut delegate
    shortcutManager.delegate = self

    // Subscribe to capture completions for floating preview
    captureManager.captureCompletedPublisher
      .receive(on: DispatchQueue.main)
      .sink { [weak self] url in
        guard self?.floatingManager.isEnabled == true else { return }
        Task {
          await self?.floatingManager.addScreenshot(url: url)
        }
      }
      .store(in: &cancellables)

    // Sync permission state
    Task {
      await updatePermissionState()
    }
  }

  // MARK: - Floating Screenshot Settings

  var floatingEnabled: Bool {
    get { floatingManager.isEnabled }
    set { floatingManager.isEnabled = newValue }
  }

  var floatingPosition: FloatingPosition {
    get { floatingManager.position }
    set { floatingManager.setPosition(newValue) }
  }

  var floatingAutoDismiss: Bool {
    get { floatingManager.autoDismissEnabled }
    set { floatingManager.autoDismissEnabled = newValue }
  }

  var floatingAutoDismissDelay: TimeInterval {
    get { floatingManager.autoDismissDelay }
    set { floatingManager.autoDismissDelay = newValue }
  }

  // MARK: - Shortcut Management

  func updateFullscreenShortcut(_ config: ShortcutConfig) {
    shortcutManager.setFullscreenShortcut(config)
    fullscreenShortcut = config
  }

  func updateAreaShortcut(_ config: ShortcutConfig) {
    shortcutManager.setAreaShortcut(config)
    areaShortcut = config
  }

  // MARK: - KeyboardShortcutDelegate

  func shortcutTriggered(_ action: ShortcutAction) {
    switch action {
    case .captureFullscreen:
      captureFullscreen()
    case .captureArea:
      captureArea()
    }
  }

  func updatePermissionState() async {
    await captureManager.checkPermission()
    hasPermission = captureManager.hasPermission
  }

  func requestPermission() {
    Task {
      _ = await captureManager.requestPermission()
      await updatePermissionState()
    }
  }

  func openSettings() {
    captureManager.openScreenRecordingPreferences()
  }

  func captureFullscreen() {
    Task {
      isCapturing = true

      // Small delay to hide our window before capture
      try? await Task.sleep(nanoseconds: 200_000_000)  // 200ms

      let result = await captureManager.captureFullscreen(
        saveDirectory: saveDirectory,
        format: selectedFormat.format
      )

      isCapturing = false
      lastCaptureResult = result

      if case .success = result, playSound {
        playScreenshotSound()
      }
    }
  }

  func captureArea() {
    // Prevent multiple area captures - only one at a time
    if areaSelectionController != nil {
      return
    }

    // Hide main window
    NSApp.hide(nil)

    // Small delay to ensure window is hidden
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      guard let self = self else { return }

      // Double-check to prevent race condition
      guard self.areaSelectionController == nil else { return }

      self.areaSelectionController = AreaSelectionController()
      self.areaSelectionController?.startSelection { [weak self] rect in
        guard let self = self else { return }

        // Show main window again
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)

        guard let selectedRect = rect else {
          // Cancelled
          self.lastCaptureResult = .failure(.cancelled)
          return
        }

        Task { @MainActor in
          self.isCapturing = true

          let result = await self.captureManager.captureArea(
            rect: selectedRect,
            saveDirectory: self.saveDirectory,
            format: self.selectedFormat.format
          )

          self.isCapturing = false
          self.lastCaptureResult = result

          if case .success = result, self.playSound {
            self.playScreenshotSound()
          }
        }

        self.areaSelectionController = nil
      }
    }
  }

  func chooseSaveDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.message = "Choose where to save screenshots"

    if panel.runModal() == .OK, let url = panel.url {
      saveDirectory = url
    }
  }

  private func playScreenshotSound() {
    NSSound(named: "Glass")?.play()
  }
}

#Preview {
  ContentView()
}
