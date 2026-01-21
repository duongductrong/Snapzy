//
//  RecordingSettingsView.swift
//  ClaudeShot
//
//  Recording preferences tab with format, quality, and audio settings
//

import SwiftUI

struct RecordingSettingsView: View {
  @AppStorage(PreferencesKeys.recordingFormat) private var format = "mov"
  @AppStorage(PreferencesKeys.recordingFPS) private var fps = 30
  @AppStorage(PreferencesKeys.recordingQuality) private var quality = "high"
  @AppStorage(PreferencesKeys.recordingCaptureAudio) private var captureAudio = true
  @AppStorage(PreferencesKeys.recordingCaptureMicrophone) private var captureMicrophone = false

  var body: some View {
    Form {
      Section("Format") {
        Picker("Video Format", selection: $format) {
          Text("MOV (Recommended)").tag("mov")
          Text("MP4").tag("mp4")
        }
        .pickerStyle(.radioGroup)

        Text("MOV offers better quality. MP4 provides wider compatibility.")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Quality") {
        Picker("Frame Rate", selection: $fps) {
          Text("30 FPS").tag(30)
          Text("60 FPS").tag(60)
        }

        Picker("Quality", selection: $quality) {
          Text("High").tag("high")
          Text("Medium").tag("medium")
          Text("Low").tag("low")
        }

        Text("Higher quality results in larger file sizes.")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Audio") {
        Toggle("Capture System Audio", isOn: $captureAudio)
        Toggle("Capture Microphone", isOn: $captureMicrophone)
          .disabled(!captureAudio)

        Text("System audio captures sounds from apps. Microphone captures your voice.")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Save Location") {
        HStack {
          Text("Recordings save to the same location as screenshots.")
            .foregroundColor(.secondary)
          Spacer()
          Text("See General tab")
            .foregroundColor(.accentColor)
            .font(.caption)
        }
      }
    }
    .formStyle(.grouped)
  }
}

#Preview {
  RecordingSettingsView()
    .frame(width: 500, height: 400)
}
