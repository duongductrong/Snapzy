//
//  RecordingSettingsView.swift
//  Snapzy
//
//  Recording preferences tab with format, quality, and audio settings
//

import AVFoundation
import SwiftUI

struct RecordingSettingsView: View {
  @AppStorage(PreferencesKeys.recordingFormat) private var format = "mov"
  @AppStorage(PreferencesKeys.recordingFPS) private var fps = 30
  @AppStorage(PreferencesKeys.recordingQuality) private var quality = "high"
  @AppStorage(PreferencesKeys.recordingCaptureAudio) private var captureAudio = true
  @AppStorage(PreferencesKeys.recordingCaptureMicrophone) private var captureMicrophone = false

  @State private var showPermissionDeniedAlert = false

  private var isMicAvailable: Bool {
    if #available(macOS 15.0, *) {
      return true
    }
    return false
  }

  var body: some View {
    Form {
      Section("Format") {
        settingRow(icon: "film", title: "Video Format", description: "MOV offers better quality. MP4 provides wider compatibility.") {
          Picker("", selection: $format) {
            Text("MOV").tag("mov")
            Text("MP4").tag("mp4")
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 120)
        }
      }

      Section("Quality") {
        settingRow(icon: "gauge.with.dots.needle.33percent", title: "Frame Rate", description: "Higher FPS for smoother motion") {
          Picker("", selection: $fps) {
            Text("30 FPS").tag(30)
            Text("60 FPS").tag(60)
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 140)
        }

        settingRow(icon: "sparkles", title: "Quality", description: "Higher quality = larger file size") {
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

      Section("Audio") {
        settingRow(icon: "speaker.wave.3.fill", title: "System Audio", description: "Capture sounds from apps") {
          Toggle("", isOn: $captureAudio)
            .labelsHidden()
        }

        settingRow(icon: "mic.fill", title: "Microphone", description: microphoneDescription) {
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

      Section("Save Location") {
        settingRow(icon: "folder.fill", title: "Recording Location", description: "Same as screenshots") {
          Text("See General tab")
            .font(.caption)
            .foregroundColor(.accentColor)
        }
      }
    }
    .formStyle(.grouped)
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
  RecordingSettingsView()
    .frame(width: 600, height: 400)
}
