//
//  ToolbarMicToggleButton.swift
//  Snapzy
//
//  Toggle button for microphone mute/unmute in recording toolbar
//  Styled to match Apple's native macOS recording toolbar
//

import AVFoundation
import SwiftUI

struct ToolbarMicToggleButton: View {
  @ObservedObject var state: RecordingToolbarState
  @State private var isHovered = false
  @State private var showPermissionDeniedAlert = false

  /// Microphone capture via ScreenCaptureKit requires macOS 15.0+
  private var isAvailable: Bool {
    if #available(macOS 15.0, *) {
      return true
    }
    return false
  }

  private var systemName: String {
    if !isAvailable {
      return "mic.slash"
    }
    return state.captureMicrophone ? "mic.fill" : "mic.slash.fill"
  }

  private var accessibilityLabel: String {
    if !isAvailable {
      return "Microphone unavailable on this macOS version"
    }
    return state.captureMicrophone ? "Mute microphone" : "Unmute microphone"
  }

  private var tooltipText: String {
    if !isAvailable {
      return "Requires macOS 15.0+"
    }
    return state.captureMicrophone ? "Microphone on" : "Microphone off"
  }

  var body: some View {
    Button {
      if isAvailable {
        handleMicToggle()
      }
    } label: {
      Image(systemName: systemName)
        .font(.system(size: ToolbarConstants.iconSize, weight: .medium))
        .foregroundColor(foregroundColor)
        .frame(
          width: ToolbarConstants.iconButtonSize,
          height: ToolbarConstants.iconButtonSize
        )
        .background(
          RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius)
            .fill(Color.primary.opacity(isHovered && isAvailable ? 0.1 : 0))
        )
        .contentShape(RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius))
        .animation(ToolbarConstants.hoverAnimation, value: isHovered)
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .disabled(!isAvailable)
    .help(tooltipText)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityHint(isAvailable ? "Double-tap to toggle" : "")
    .alert("Microphone Access Required", isPresented: $showPermissionDeniedAlert) {
      Button("Open System Settings") {
        openMicrophoneSettings()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Snapzy needs microphone permission. Please enable it in System Settings > Privacy & Security > Microphone.")
    }
  }

  private var foregroundColor: Color {
    if !isAvailable {
      return .primary.opacity(0.3)
    }
    return .primary.opacity(state.captureMicrophone ? 1.0 : 0.5)
  }

  /// Request microphone permission when user enables toggle
  private func handleMicToggle() {
    if state.captureMicrophone {
      state.captureMicrophone = false
      return
    }

    let status = AVCaptureDevice.authorizationStatus(for: .audio)

    switch status {
    case .notDetermined:
      Task {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        await MainActor.run {
          if granted {
            state.captureMicrophone = true
          } else {
            showPermissionDeniedAlert = true
          }
        }
      }
    case .authorized:
      state.captureMicrophone = true
    case .denied, .restricted:
      showPermissionDeniedAlert = true
    @unknown default:
      state.captureMicrophone = true
    }
  }

  private func openMicrophoneSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
      NSWorkspace.shared.open(url)
    }
  }
}

#Preview {
  HStack(spacing: 4) {
    ToolbarMicToggleButton(state: RecordingToolbarState())
  }
  .padding(10)
  .background(.ultraThinMaterial)
  .clipShape(RoundedRectangle(cornerRadius: 14))
}
