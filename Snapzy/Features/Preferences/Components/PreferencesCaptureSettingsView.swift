//
//  CaptureSettingsView.swift
//  Snapzy
//
//  Capture preferences tab combining screenshot behavior, recording settings, and post-capture actions
//

import AVFoundation
import SwiftUI

struct CaptureSettingsView: View {
  // Screenshot behavior
  @AppStorage(PreferencesKeys.hideDesktopIcons) private var hideDesktopIcons = false
  @AppStorage(PreferencesKeys.hideDesktopWidgets) private var hideDesktopWidgets = false
  @AppStorage(PreferencesKeys.screenshotIncludeOwnApp) private var includeOwnAppInScreenshots = false
  @AppStorage(PreferencesKeys.screenshotShowCursor) private var screenshotShowCursor = false
  @AppStorage(PreferencesKeys.screenshotFormat) private var screenshotFormat = "png"
  @AppStorage(PreferencesKeys.scrollingCaptureShowHints) private var scrollingCaptureShowHints = true
  @AppStorage(PreferencesKeys.backgroundCutoutAutoCropEnabled) private var backgroundCutoutAutoCropEnabled = true
  @AppStorage(PreferencesKeys.screenshotFileNameTemplate)
  private var screenshotFileNameTemplate = CaptureOutputKind.screenshot.defaultTemplate

  // Recording settings
  @AppStorage(PreferencesKeys.recordingFormat) private var format = "mov"
  @AppStorage(PreferencesKeys.recordingFileNameTemplate)
  private var recordingFileNameTemplate = CaptureOutputKind.recording.defaultTemplate
  @AppStorage(PreferencesKeys.recordingFPS) private var fps = 30
  @AppStorage(PreferencesKeys.recordingQuality) private var quality = "high"
  @AppStorage(PreferencesKeys.recordingCaptureAudio) private var captureAudio = true
  @AppStorage(PreferencesKeys.recordingCaptureMicrophone) private var captureMicrophone = false
  @AppStorage(PreferencesKeys.recordingRememberLastArea) private var rememberLastArea = true
  @AppStorage(PreferencesKeys.recordingIncludeOwnApp) private var includeOwnAppInRecordings = false

  // Mouse Highlight settings
  @AppStorage(PreferencesKeys.mouseHighlightSize) private var mouseHighlightSize: Double = 50
  @AppStorage(PreferencesKeys.mouseHighlightAnimationDuration) private var mouseHighlightAnimDuration: Double = 0.7
  @AppStorage(PreferencesKeys.mouseHighlightRippleCount) private var mouseHighlightRippleCount: Int = 3
  @AppStorage(PreferencesKeys.mouseHighlightOpacity) private var mouseHighlightOpacity: Double = 0.5

  // Keystroke Overlay settings
  @AppStorage(PreferencesKeys.keystrokeFontSize) private var keystrokeFontSize: Double = 16
  @AppStorage(PreferencesKeys.keystrokePosition) private var keystrokePosition: String = KeystrokeOverlayPosition.bottomCenter.rawValue
  @AppStorage(PreferencesKeys.keystrokeDisplayDuration) private var keystrokeDisplayDuration: Double = 1.5

  @State private var showPermissionDeniedAlert = false

  /// SwiftUI Color binding backed by archived NSColor in UserDefaults
  private var mouseHighlightSwiftColor: Binding<Color> {
    Binding<Color>(
      get: {
        if let data = UserDefaults.standard.data(forKey: PreferencesKeys.mouseHighlightColor),
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
          return Color(nsColor: nsColor)
        }
        return Color(nsColor: MouseHighlightConfiguration.defaultHighlightColor)
      },
      set: { newColor in
        let nsColor = NSColor(newColor)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: true) {
          UserDefaults.standard.set(data, forKey: PreferencesKeys.mouseHighlightColor)
        }
      }
    )
  }


  private var isMicAvailable: Bool {
    if #available(macOS 15.0, *) {
      return true
    }
    return false
  }

  var body: some View {
    Form {
      Section(L10n.PreferencesCapture.appWindowsSection) {
        SettingRow(
          icon: "photo.on.rectangle",
          title: L10n.PreferencesCapture.includeInScreenshotsTitle,
          description: L10n.PreferencesCapture.includeInScreenshotsDescription
        ) {
          Toggle("", isOn: $includeOwnAppInScreenshots)
            .labelsHidden()
        }

        SettingRow(
          icon: "video",
          title: L10n.PreferencesCapture.includeInRecordingsTitle,
          description: L10n.PreferencesCapture.includeInRecordingsDescription
        ) {
          Toggle("", isOn: $includeOwnAppInRecordings)
            .labelsHidden()
        }
      }

      // MARK: - Desktop

      Section(L10n.PreferencesCapture.desktopSection) {
        SettingRow(
          icon: "eye.slash",
          title: L10n.PreferencesCapture.hideDesktopIconsTitle,
          description: L10n.PreferencesCapture.hideDesktopIconsDescription
        ) {
          Toggle("", isOn: $hideDesktopIcons)
            .labelsHidden()
        }

        SettingRow(
          icon: "widget.small",
          title: L10n.PreferencesCapture.hideDesktopWidgetsTitle,
          description: L10n.PreferencesCapture.hideDesktopWidgetsDescription
        ) {
          Toggle("", isOn: $hideDesktopWidgets)
            .labelsHidden()
        }
      }

      // MARK: - Screenshot Format

      Section(L10n.PreferencesCapture.screenshotFormatSection) {
        SettingRow(
          icon: "cursorarrow",
          title: L10n.PreferencesCapture.showCursorTitle,
          description: L10n.PreferencesCapture.showCursorDescription
        ) {
          Toggle("", isOn: $screenshotShowCursor)
            .labelsHidden()
        }

        SettingRow(
          icon: "photo",
          title: L10n.PreferencesCapture.imageFormatTitle,
          description: L10n.PreferencesCapture.imageFormatDescription
        ) {
          Picker("", selection: $screenshotFormat) {
            ForEach(ImageFormatOption.allCases, id: \.self) { option in
              Text(option.displayName).tag(option.rawValue)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }

        if screenshotFormat == ImageFormatOption.webp.rawValue {
          HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundColor(.orange)
              .font(.system(size: 12))
              .padding(.top, 1)
            Text(L10n.PreferencesCapture.webpWarning)
              .font(.system(size: 11))
              .foregroundColor(.orange)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(.vertical, 4)
        }

        if screenshotFormat == ImageFormatOption.jpeg.rawValue {
          HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle.fill")
              .foregroundColor(.blue)
              .font(.system(size: 12))
              .padding(.top, 1)
            Text(L10n.PreferencesCapture.jpegCutoutNote)
              .font(.system(size: 11))
              .foregroundColor(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(.vertical, 4)
        }
      }

      Section(L10n.PreferencesCapture.scrollingCaptureSection) {
        SettingRow(
          icon: "lightbulb",
          title: L10n.PreferencesCapture.showSessionHintsTitle,
          description: L10n.PreferencesCapture.showSessionHintsDescription
        ) {
          Toggle("", isOn: $scrollingCaptureShowHints)
            .labelsHidden()
        }

        HStack(alignment: .top, spacing: 6) {
          Image(systemName: "info.circle.fill")
            .foregroundColor(.blue)
            .font(.system(size: 12))
            .padding(.top, 1)
          Text(L10n.PreferencesCapture.scrollingCaptureInfo)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
      }

      Section(L10n.PreferencesCapture.outputNamingSection) {
        SettingRow(
          icon: "textformat",
          title: L10n.PreferencesCapture.screenshotTemplateTitle,
          description: L10n.PreferencesCapture.screenshotTemplateDescription
        ) {
          TextField("", text: $screenshotFileNameTemplate)
            .textFieldStyle(.roundedBorder)
            .frame(width: 260)
        }

        SettingRow(
          icon: "textformat.abc",
          title: L10n.PreferencesCapture.recordingTemplateTitle,
          description: L10n.PreferencesCapture.recordingTemplateDescription
        ) {
          TextField("", text: $recordingFileNameTemplate)
            .textFieldStyle(.roundedBorder)
            .frame(width: 260)
        }

        HStack(alignment: .top, spacing: 6) {
          Image(systemName: "info.circle")
            .foregroundColor(.secondary)
            .font(.system(size: 12))
            .padding(.top, 1)
          Text(L10n.PreferencesCapture.availableTokens)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)

        VStack(alignment: .leading, spacing: 2) {
          Text(L10n.PreferencesCapture.screenshotPreview(screenshotFilenamePreview))
          Text(L10n.PreferencesCapture.recordingPreview(recordingFilenamePreview))
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .padding(.top, 2)

        HStack {
          Spacer()
          Button(L10n.PreferencesCapture.resetNamingDefaults) {
            resetOutputNamingDefaults()
          }
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .buttonStyle(.plain)
        }
      }

      // MARK: - Recording

      Section(L10n.PreferencesCapture.recordingFormatSection) {
        SettingRow(
          icon: "film",
          title: L10n.PreferencesCapture.videoFormatTitle,
          description: L10n.PreferencesCapture.videoFormatDescription
        ) {
          Picker("", selection: $format) {
            Text(verbatim: "MOV").tag("mov")
            Text(verbatim: "MP4").tag("mp4")
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }
      }

      Section(L10n.PreferencesCapture.recordingQualitySection) {
        SettingRow(
          icon: "gauge.with.dots.needle.33percent",
          title: L10n.PreferencesCapture.frameRateTitle,
          description: L10n.PreferencesCapture.frameRateDescription
        ) {
          Picker("", selection: $fps) {
            Text("30 FPS").tag(30)
            Text("60 FPS").tag(60)
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }

        SettingRow(
          icon: "sparkles",
          title: L10n.PreferencesCapture.qualityTitle,
          description: L10n.PreferencesCapture.qualityDescription
        ) {
          Picker("", selection: $quality) {
            ForEach(VideoQuality.allCases, id: \.self) { option in
              Text(option.displayName).tag(option.rawValue)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }
      }

      Section(L10n.PreferencesCapture.recordingBehaviorSection) {
        SettingRow(
          icon: "rectangle.dashed",
          title: L10n.PreferencesCapture.rememberLastAreaTitle,
          description: L10n.PreferencesCapture.rememberLastAreaDescription
        ) {
          Toggle("", isOn: $rememberLastArea)
            .labelsHidden()
        }
      }

      // MARK: - Recording Overlays

      Section(L10n.PreferencesCapture.mouseHighlightSection) {
        SettingRow(
          icon: "cursorarrow.click.2",
          title: L10n.PreferencesCapture.highlightSizeTitle,
          description: L10n.PreferencesCapture.highlightSizeDescription(Int(mouseHighlightSize))
        ) {
          Slider(value: $mouseHighlightSize, in: 30...100, step: 2)
            .frame(width: 140)
        }

        SettingRow(
          icon: "timer",
          title: L10n.PreferencesCapture.animationDurationTitle,
          description: L10n.PreferencesCapture.animationDurationDescription(
            String(format: "%.1f", mouseHighlightAnimDuration)
          )
        ) {
          Slider(value: $mouseHighlightAnimDuration, in: 0.3...2.0, step: 0.1)
            .frame(width: 140)
        }

        SettingRow(
          icon: "circle.grid.3x3",
          title: L10n.PreferencesCapture.rippleCountTitle,
          description: L10n.PreferencesCapture.rippleCountDescription
        ) {
          Picker("", selection: $mouseHighlightRippleCount) {
            ForEach(1...5, id: \.self) { count in
              Text("\(count)").tag(count)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(width: 80)
        }

        SettingRow(
          icon: "paintpalette",
          title: L10n.PreferencesCapture.highlightColorTitle,
          description: L10n.PreferencesCapture.highlightColorDescription
        ) {
          ColorPicker("", selection: mouseHighlightSwiftColor, supportsOpacity: false)
            .labelsHidden()
        }

        SettingRow(
          icon: "circle.lefthalf.filled",
          title: L10n.PreferencesCapture.opacityTitle,
          description: L10n.PreferencesCapture.opacityDescription(Int(mouseHighlightOpacity * 100))
        ) {
          Slider(value: $mouseHighlightOpacity, in: 0.2...1.0, step: 0.05)
            .frame(width: 140)
        }

        HStack {
          Spacer()
          Button(L10n.Common.resetToDefault) {
            resetMouseHighlightDefaults()
          }
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .buttonStyle(.plain)
        }
      }

      Section(L10n.PreferencesCapture.keystrokeOverlaySection) {
        SettingRow(
          icon: "textformat.size",
          title: L10n.PreferencesCapture.fontSizeTitle,
          description: L10n.PreferencesCapture.fontSizeDescription(Int(keystrokeFontSize))
        ) {
          Slider(value: $keystrokeFontSize, in: 12...32, step: 1)
            .frame(width: 140)
        }

        SettingRow(
          icon: "square.and.arrow.down.on.square",
          title: L10n.PreferencesCapture.positionTitle,
          description: L10n.PreferencesCapture.positionDescription
        ) {
          Picker("", selection: $keystrokePosition) {
            ForEach(KeystrokeOverlayPosition.allCases) { pos in
              Text(pos.displayName).tag(pos.rawValue)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(width: 140)
        }

        SettingRow(
          icon: "clock",
          title: L10n.PreferencesCapture.displayDurationTitle,
          description: L10n.PreferencesCapture.displayDurationDescription(
            String(format: "%.1f", keystrokeDisplayDuration)
          )
        ) {
          Slider(value: $keystrokeDisplayDuration, in: 0.5...5.0, step: 0.5)
            .frame(width: 140)
        }

        HStack {
          Spacer()
          Button(L10n.Common.resetToDefault) {
            resetKeystrokeDefaults()
          }
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .buttonStyle(.plain)
        }
      }

      Section(L10n.PreferencesCapture.audioSection) {
        SettingRow(
          icon: "speaker.wave.3.fill",
          title: L10n.PreferencesCapture.systemAudioTitle,
          description: L10n.PreferencesCapture.systemAudioDescription
        ) {
          Toggle("", isOn: $captureAudio)
            .labelsHidden()
        }

        SettingRow(
          icon: "mic.fill",
          title: L10n.Onboarding.microphone,
          description: microphoneDescription
        ) {
          Toggle("", isOn: Binding(
            get: { captureMicrophone },
            set: { newValue in
              if newValue {
                handleMicrophoneEnable()
              } else {
                captureMicrophone = false
              }
            }
          ))
          .labelsHidden()
          .disabled(!captureAudio || !isMicAvailable)
        }
      }
      .alert(L10n.Microphone.accessRequiredTitle, isPresented: $showPermissionDeniedAlert) {
        Button(L10n.Common.openSystemSettings) {
          openMicrophoneSettings()
        }
        Button(L10n.Common.cancel, role: .cancel) {}
      } message: {
        Text(L10n.Microphone.preferencesMessage)
      }

      // MARK: - After Capture

      Section(L10n.PreferencesCapture.afterCaptureSection) {
        AfterCaptureMatrixView()

        Text(L10n.PreferencesCapture.removeBackground)
          .font(.caption)
          .foregroundColor(.secondary)

        SettingRow(
          icon: "person.crop.rectangle",
          title: L10n.PreferencesCapture.autoCropSubjectTitle,
          description: L10n.PreferencesCapture.autoCropSubjectDescription
        ) {
          Toggle("", isOn: $backgroundCutoutAutoCropEnabled)
            .labelsHidden()
        }
      }
    }
    .formStyle(.grouped)
  }

  // MARK: - Helpers

  private var microphoneDescription: String {
    if !isMicAvailable {
      return L10n.PreferencesCapture.microphoneRequiresMacOS
    }
    return L10n.PreferencesCapture.microphoneDescription
  }

  private var screenshotFilenamePreview: String {
    let baseName = CaptureOutputNaming.resolveBaseName(
      customName: screenshotFileNameTemplate,
      kind: .screenshot
    )
    return "\(baseName).\(screenshotFileExtension)"
  }

  private var recordingFilenamePreview: String {
    let baseName = CaptureOutputNaming.resolveBaseName(
      customName: recordingFileNameTemplate,
      kind: .recording
    )
    return "\(baseName).\(recordingFileExtension)"
  }

  private var screenshotFileExtension: String {
    ImageFormatOption(rawValue: screenshotFormat)?.format.fileExtension ?? "png"
  }

  private var recordingFileExtension: String {
    VideoFormat(rawValue: format)?.fileExtension ?? "mov"
  }

  private func handleMicrophoneEnable() {
    let status = AVCaptureDevice.authorizationStatus(for: .audio)

    switch status {
    case .notDetermined:
      Task {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        await MainActor.run {
          if granted {
            captureMicrophone = true
          } else {
            showPermissionDeniedAlert = true
          }
        }
      }
    case .authorized:
      captureMicrophone = true
    case .denied, .restricted:
      showPermissionDeniedAlert = true
    @unknown default:
      captureMicrophone = true
    }
  }

  private func openMicrophoneSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
      NSWorkspace.shared.open(url)
    }
  }

  // MARK: - Reset Defaults

  private func resetOutputNamingDefaults() {
    screenshotFileNameTemplate = CaptureOutputKind.screenshot.defaultTemplate
    recordingFileNameTemplate = CaptureOutputKind.recording.defaultTemplate
  }

  private func resetMouseHighlightDefaults() {
    mouseHighlightSize = MouseHighlightConfiguration.defaultHighlightSize
    mouseHighlightAnimDuration = MouseHighlightConfiguration.defaultAnimationDuration
    mouseHighlightRippleCount = MouseHighlightConfiguration.defaultRippleCount
    mouseHighlightOpacity = MouseHighlightConfiguration.defaultHighlightOpacity
    UserDefaults.standard.removeObject(forKey: PreferencesKeys.mouseHighlightColor)
  }

  private func resetKeystrokeDefaults() {
    keystrokeFontSize = KeystrokeOverlayConfiguration.defaultFontSize
    keystrokePosition = KeystrokeOverlayConfiguration.defaultPosition.rawValue
    keystrokeDisplayDuration = KeystrokeOverlayConfiguration.defaultDisplayDuration
  }
}

#Preview {
  CaptureSettingsView()
    .frame(width: 600, height: 550)
}
