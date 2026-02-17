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

  // Recording settings
  @AppStorage(PreferencesKeys.recordingFormat) private var format = "mov"
  @AppStorage(PreferencesKeys.recordingFPS) private var fps = 30
  @AppStorage(PreferencesKeys.recordingQuality) private var quality = "high"
  @AppStorage(PreferencesKeys.recordingCaptureAudio) private var captureAudio = true
  @AppStorage(PreferencesKeys.recordingCaptureMicrophone) private var captureMicrophone = false
  @AppStorage(PreferencesKeys.recordingRememberLastArea) private var rememberLastArea = true

  @State private var showPermissionDeniedAlert = false

  private var isMicAvailable: Bool {
    if #available(macOS 15.0, *) {
      return true
    }
    return false
  }

  var body: some View {
    Form {
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

      // MARK: - Recording

      Section("Recording Format") {
        SettingRow(icon: "film", title: "Video Format", description: "MOV offers better quality. MP4 provides wider compatibility.") {
          Picker("", selection: $format) {
            Text("MOV").tag("mov")
            Text("MP4").tag("mp4")
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 120)
        }
      }

      Section("Recording Quality") {
        SettingRow(icon: "gauge.with.dots.needle.33percent", title: "Frame Rate", description: "Higher FPS for smoother motion") {
          Picker("", selection: $fps) {
            Text("30 FPS").tag(30)
            Text("60 FPS").tag(60)
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 140)
        }

        SettingRow(icon: "sparkles", title: "Quality", description: "Higher quality = larger file size") {
          Picker("", selection: $quality) {
            Text("High").tag("high")
            Text("Medium").tag("medium")
            Text("Low").tag("low")
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 180)
        }
      }

      Section("Recording Behavior") {
        SettingRow(icon: "rectangle.dashed", title: "Remember Last Area", description: "Restore previous recording area on next capture") {
          Toggle("", isOn: $rememberLastArea)
            .labelsHidden()
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
}

#Preview {
  CaptureSettingsView()
    .frame(width: 600, height: 550)
}
