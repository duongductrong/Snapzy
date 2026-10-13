//
//  RecordingToolbarCameraToggleButton.swift
//  Snapzy
//
//  Camera input menu for the recording toolbar.
//

import AVFoundation
import SwiftUI

struct RecordingToolbarCameraToggleButton: View {
  @ObservedObject var state: RecordingToolbarState
  @State private var isHovered = false
  @State private var showPermissionDeniedAlert = false

  private var systemName: String {
    state.captureCamera ? "video.fill" : "video.slash.fill"
  }

  private var tooltipText: String {
    state.captureCamera ? L10n.Camera.on : L10n.Camera.off
  }

  var body: some View {
    Menu {
      Button {
        selectNoCamera()
      } label: {
        menuItemLabel(
          title: L10n.Camera.doNotUse,
          isSelected: !state.captureCamera
        )
      }

      Divider()

      ForEach(cameraMenuDevices) { device in
        Button {
          selectCameraDevice(device)
        } label: {
          menuItemLabel(
            title: device.displayName,
            isSelected: state.captureCamera && state.cameraDeviceID == device.id
          )
        }
      }

      if state.captureCamera {
        Divider()

        Menu {
          ForEach(RecordingCameraShape.allCases) { shape in
            Button {
              selectShape(shape)
            } label: {
              menuItemLabel(
                title: shape.displayName,
                isSelected: state.cameraShape == shape
              )
            }
          }
        } label: {
          Text(L10n.Camera.shape)
        }

        Menu {
          ForEach(RecordingCameraSize.allCases) { size in
            Button {
              selectSize(size)
            } label: {
              menuItemLabel(
                title: size.displayName,
                isSelected: state.cameraSize == size
              )
            }
          }
        } label: {
          Text(L10n.Camera.size)
        }

        Divider()

        Button {
          toggleMirrored()
        } label: {
          menuItemLabel(
            title: L10n.Camera.mirrorCamera,
            isSelected: state.cameraMirrored
          )
        }
      }
    } label: {
      ToolbarIconButtonLabel(
        systemName: systemName,
        isHovered: isHovered
      )
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .buttonStyle(.plain)
    .frame(
      width: ToolbarConstants.iconButtonSize,
      height: ToolbarConstants.iconButtonSize
    )
    .onHover { isHovered = $0 }
    .help(tooltipText)
    .accessibilityLabel(L10n.Camera.options)
    .accessibilityHint(L10n.Camera.chooseInput)
    .alert(L10n.Camera.accessRequiredTitle, isPresented: $showPermissionDeniedAlert) {
      Button(L10n.Common.openSystemSettings) {
        openCameraSettings()
      }
      Button(L10n.Common.cancel, role: .cancel) {}
    } message: {
      Text(L10n.Camera.preferencesMessage)
    }
  }

  private var cameraMenuDevices: [RecordingCameraDevice] {
    RecordingCameraDeviceProvider.availableDevices(
      selectedDeviceID: state.cameraDeviceID
    )
    .filter { !$0.isUnavailable }
  }

  @ViewBuilder
  private func menuItemLabel(title: String, isSelected: Bool) -> some View {
    if isSelected {
      Label(title, systemImage: "checkmark")
    } else {
      Text(title)
    }
  }

  private func selectNoCamera() {
    state.captureCamera = false
    UserDefaults.standard.set(false, forKey: PreferencesKeys.recordingCaptureCamera)
  }

  private func selectShape(_ shape: RecordingCameraShape) {
    state.cameraShape = shape
    UserDefaults.standard.set(shape.rawValue, forKey: PreferencesKeys.recordingCameraShape)
  }

  private func selectSize(_ size: RecordingCameraSize) {
    state.cameraSize = size
    UserDefaults.standard.set(size.rawValue, forKey: PreferencesKeys.recordingCameraSize)
  }

  private func toggleMirrored() {
    let newMirrored = !state.cameraMirrored
    state.cameraMirrored = newMirrored
    UserDefaults.standard.set(newMirrored, forKey: PreferencesKeys.recordingCameraMirrored)
  }

  private func selectCameraDevice(_ device: RecordingCameraDevice) {
    let status = AVCaptureDevice.authorizationStatus(for: .video)

    switch status {
    case .notDetermined:
      Task {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        await MainActor.run {
          if granted {
            enableCamera(device)
          } else {
            showPermissionDeniedAlert = true
          }
        }
      }
    case .authorized:
      enableCamera(device)
    case .denied, .restricted:
      showPermissionDeniedAlert = true
    @unknown default:
      showPermissionDeniedAlert = true
    }
  }

  private func enableCamera(_ device: RecordingCameraDevice) {
    state.cameraDeviceID = device.id
    state.captureCamera = true
    UserDefaults.standard.set(device.id, forKey: PreferencesKeys.recordingCameraDeviceID)
    UserDefaults.standard.set(true, forKey: PreferencesKeys.recordingCaptureCamera)
  }

  private func openCameraSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
      NSWorkspace.shared.open(url)
    }
  }
}

#Preview {
  HStack(spacing: 4) {
    RecordingToolbarCameraToggleButton(state: RecordingToolbarState())
  }
  .padding(10)
  .background(.ultraThinMaterial)
  .clipShape(Radius.rect(Radius.card))
}
