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
      Section("App Windows") {
        SettingRow(
          icon: "photo.on.rectangle",
          title: "Include in Screenshots",
          description: "Show Snapzy windows such as Annotate in captured images"
        ) {
          Toggle("", isOn: $includeOwnAppInScreenshots)
            .labelsHidden()
        }

        SettingRow(
          icon: "video",
          title: "Include in Recordings",
          description: "Show Snapzy windows such as Annotate in recorded videos"
        ) {
          Toggle("", isOn: $includeOwnAppInRecordings)
            .labelsHidden()
        }
      }

      // MARK: - Desktop

      Section("Desktop") {
        SettingRow(icon: "eye.slash", title: "Hide desktop icons", description: "Temporarily hide icons during capture") {
          Toggle("", isOn: $hideDesktopIcons)
            .labelsHidden()
        }

        SettingRow(icon: "widget.small", title: "Hide desktop widgets", description: "Temporarily hide widgets during capture") {
          Toggle("", isOn: $hideDesktopWidgets)
            .labelsHidden()
        }
      }

      // MARK: - Screenshot Format

      Section("Screenshot Format") {
        SettingRow(
          icon: "cursorarrow",
          title: "Show cursor",
          description: "Include mouse pointer in captured screenshots"
        ) {
          Toggle("", isOn: $screenshotShowCursor)
            .labelsHidden()
        }

        SettingRow(icon: "photo", title: "Image Format", description: "Output format for captured screenshots") {
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
            Text("WebP encoding is slower than other formats. For faster capture speed, consider using PNG or JPEG.")
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
            Text("Object cutout captures require transparency. Snapzy will save them as PNG even when JPEG is selected.")
              .font(.system(size: 11))
              .foregroundColor(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(.vertical, 4)
        }
      }

      Section("Output Naming") {
        SettingRow(
          icon: "textformat",
          title: "Screenshot Template",
          description: "Pattern for auto-saved screenshot filename"
        ) {
          TextField("", text: $screenshotFileNameTemplate)
            .textFieldStyle(.roundedBorder)
            .frame(width: 260)
        }

        SettingRow(
          icon: "textformat.abc",
          title: "Recording Template",
          description: "Pattern for auto-saved recording filename"
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
          Text("Available tokens: {datetime}, {date}, {time}, {ms}, {timestamp}, {type}")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)

        VStack(alignment: .leading, spacing: 2) {
          Text("Screenshot preview: \(screenshotFilenamePreview)")
          Text("Recording preview: \(recordingFilenamePreview)")
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .padding(.top, 2)

        HStack {
          Spacer()
          Button("Reset Naming Defaults") {
            resetOutputNamingDefaults()
          }
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .buttonStyle(.plain)
        }
      }

      // MARK: - Recording

      Section("Recording Format") {
        SettingRow(icon: "film", title: "Video Format", description: "MOV offers better quality. MP4 provides wider compatibility.") {
          Picker("", selection: $format) {
            Text("MOV").tag("mov")
            Text("MP4").tag("mp4")
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }
      }

      Section("Recording Quality") {
        SettingRow(icon: "gauge.with.dots.needle.33percent", title: "Frame Rate", description: "Higher FPS for smoother motion") {
          Picker("", selection: $fps) {
            Text("30 FPS").tag(30)
            Text("60 FPS").tag(60)
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }

        SettingRow(icon: "sparkles", title: "Quality", description: "Higher quality = larger file size") {
          Picker("", selection: $quality) {
            Text("High").tag("high")
            Text("Medium").tag("medium")
            Text("Low").tag("low")
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }
      }

      Section("Recording Behavior") {
        SettingRow(icon: "rectangle.dashed", title: "Remember Last Area", description: "Restore previous recording area on next capture") {
          Toggle("", isOn: $rememberLastArea)
            .labelsHidden()
        }
      }

      // MARK: - Recording Overlays

      Section("Mouse Highlight") {
        SettingRow(icon: "cursorarrow.click.2", title: "Highlight Size", description: "Diameter of ripple effect (\(Int(mouseHighlightSize))px)") {
          Slider(value: $mouseHighlightSize, in: 30...100, step: 2)
            .frame(width: 140)
        }

        SettingRow(icon: "timer", title: "Animation Duration", description: "Ripple expand speed (\(String(format: "%.1f", mouseHighlightAnimDuration))s)") {
          Slider(value: $mouseHighlightAnimDuration, in: 0.3...2.0, step: 0.1)
            .frame(width: 140)
        }

        SettingRow(icon: "circle.grid.3x3", title: "Ripple Count", description: "Number of expanding rings") {
          Picker("", selection: $mouseHighlightRippleCount) {
            ForEach(1...5, id: \.self) { count in
              Text("\(count)").tag(count)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(width: 80)
        }

        SettingRow(icon: "paintpalette", title: "Highlight Color", description: "Color of click rings") {
          ColorPicker("", selection: mouseHighlightSwiftColor, supportsOpacity: false)
            .labelsHidden()
        }

        SettingRow(icon: "circle.lefthalf.filled", title: "Opacity", description: "Ring transparency (\(Int(mouseHighlightOpacity * 100))%)") {
          Slider(value: $mouseHighlightOpacity, in: 0.2...1.0, step: 0.05)
            .frame(width: 140)
        }

        HStack {
          Spacer()
          Button("Reset to Default") {
            resetMouseHighlightDefaults()
          }
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .buttonStyle(.plain)
        }
      }

      Section("Keystroke Overlay") {
        SettingRow(icon: "textformat.size", title: "Font Size", description: "Badge text size (\(Int(keystrokeFontSize))pt)") {
          Slider(value: $keystrokeFontSize, in: 12...32, step: 1)
            .frame(width: 140)
        }

        SettingRow(icon: "square.and.arrow.down.on.square", title: "Position", description: "Badge placement in recording area") {
          Picker("", selection: $keystrokePosition) {
            ForEach(KeystrokeOverlayPosition.allCases) { pos in
              Text(pos.displayName).tag(pos.rawValue)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(width: 140)
        }

        SettingRow(icon: "clock", title: "Display Duration", description: "Time before badge fades (\(String(format: "%.1f", keystrokeDisplayDuration))s)") {
          Slider(value: $keystrokeDisplayDuration, in: 0.5...5.0, step: 0.5)
            .frame(width: 140)
        }

        HStack {
          Spacer()
          Button("Reset to Default") {
            resetKeystrokeDefaults()
          }
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .buttonStyle(.plain)
        }
      }

      Section("Audio") {
        SettingRow(icon: "speaker.wave.3.fill", title: "System Audio", description: "Capture sounds from apps") {
          Toggle("", isOn: $captureAudio)
            .labelsHidden()
        }

        SettingRow(icon: "mic.fill", title: "Microphone", description: microphoneDescription) {
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
      .alert("Microphone Access Required", isPresented: $showPermissionDeniedAlert) {
        Button("Open System Settings") {
          openMicrophoneSettings()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Snapzy needs microphone permission. Please enable it in System Settings > Privacy & Security > Microphone.")
      }

      // MARK: - After Capture

      Section("After Capture") {
        AfterCaptureMatrixView()
      }
    }
    .formStyle(.grouped)
  }

  // MARK: - Helpers

  private var microphoneDescription: String {
    if !isMicAvailable {
      return "Requires macOS 15.0+"
    }
    return "Capture your voice"
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
