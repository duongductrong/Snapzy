//
//  ToolbarMicToggleButton.swift
//  Snapzy
//
//  Toggle button for microphone mute/unmute in recording toolbar
//

import AVFoundation
import SwiftUI

struct ToolbarMicToggleButton: View {
  @Binding var isOn: Bool
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
    return isOn ? "mic.fill" : "mic.slash.fill"
  }

  private var accessibilityLabel: String {
    if !isAvailable {
      return "Microphone unavailable on this macOS version"
    }
    return isOn ? "Mute microphone" : "Unmute microphone"
  }

  private var tooltipText: String {
    if !isAvailable {
      return "Requires macOS 15.0+"
    }
    return isOn ? "Microphone on" : "Microphone off"
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
      return .secondary.opacity(0.5)
    }
    return isOn ? .primary : .secondary
  }

  /// Request microphone permission when user enables toggle
  private func handleMicToggle() {
    if isOn {
      // Turning off - no permission needed
      isOn = false
      return
    }

    // Turning on - check/request permission first
    let status = AVCaptureDevice.authorizationStatus(for: .audio)

    switch status {
    case .notDetermined:
      // First time - request permission (this adds app to System Settings list)
      Task {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        await MainActor.run {
          if granted {
            isOn = true
          } else {
            showPermissionDeniedAlert = true
          }
        }
      }
    case .authorized:
      isOn = true
    case .denied, .restricted:
      showPermissionDeniedAlert = true
    @unknown default:
      isOn = true
    }
  }

  private func openMicrophoneSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
      NSWorkspace.shared.open(url)
    }
  }
}

#Preview {
  HStack(spacing: 16) {
    ToolbarMicToggleButton(isOn: .constant(true))
    ToolbarMicToggleButton(isOn: .constant(false))
  }
  .padding()
  .background(.ultraThinMaterial)
  .clipShape(RoundedRectangle(cornerRadius: 14))
}
