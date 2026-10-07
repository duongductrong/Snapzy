//
//  RecordingMicrophoneDevice.swift
//  Snapzy
//
//  Microphone input choices for screen recordings.
//

import AVFoundation
import Foundation

nonisolated struct RecordingMicrophoneDevice: Identifiable, Equatable, Sendable {
  static let systemDefaultID = "system-default"

  let id: String
  let name: String
  let isSystemDefault: Bool
  let isUnavailable: Bool

  var displayName: String {
    if isSystemDefault {
      return L10n.Microphone.systemDefault
    }
    if isUnavailable {
      return L10n.Microphone.unavailable
    }
    return name
  }

  static var systemDefault: RecordingMicrophoneDevice {
    RecordingMicrophoneDevice(
      id: systemDefaultID,
      name: L10n.Microphone.systemDefault,
      isSystemDefault: true,
      isUnavailable: false
    )
  }
}

nonisolated enum RecordingMicrophoneDeviceProvider {
  static func storedDeviceID(defaults: UserDefaults = .standard) -> String {
    let value = defaults.string(forKey: PreferencesKeys.recordingMicrophoneDeviceID)
    return normalizedStoredDeviceID(value)
  }

  static func normalizedCaptureDeviceID(_ deviceID: String?) -> String? {
    guard let deviceID, !deviceID.isEmpty, deviceID != RecordingMicrophoneDevice.systemDefaultID else {
      return nil
    }
    return deviceID
  }

  static func availableDevices(selectedDeviceID: String? = nil) -> [RecordingMicrophoneDevice] {
    var devices = [RecordingMicrophoneDevice.systemDefault]
    let inputDevices = captureDevices()
    let mappedDevices = inputDevices.map {
      RecordingMicrophoneDevice(
        id: $0.uniqueID,
        name: $0.localizedName,
        isSystemDefault: false,
        isUnavailable: false
      )
    }

    var seenIDs = Set(devices.map(\.id))
    for device in mappedDevices where seenIDs.insert(device.id).inserted {
      devices.append(device)
    }

    if let selectedDeviceID = normalizedCaptureDeviceID(selectedDeviceID),
       !seenIDs.contains(selectedDeviceID) {
      devices.append(
        RecordingMicrophoneDevice(
          id: selectedDeviceID,
          name: L10n.Microphone.unavailable,
          isSystemDefault: false,
          isUnavailable: true
        )
      )
    }

    return devices
  }

  static func captureDevice(matching deviceID: String?) -> AVCaptureDevice? {
    if let deviceID = normalizedCaptureDeviceID(deviceID),
       let device = captureDevices().first(where: { $0.uniqueID == deviceID }) {
      return device
    }

    return AVCaptureDevice.default(for: .audio) ?? captureDevices().first
  }

  static func captureDevices() -> [AVCaptureDevice] {
    let session = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInMicrophone, .externalUnknown],
      mediaType: .audio,
      position: .unspecified
    )
    return session.devices.sorted { lhs, rhs in
      lhs.localizedName.localizedCaseInsensitiveCompare(rhs.localizedName) == .orderedAscending
    }
  }

  private static func normalizedStoredDeviceID(_ value: String?) -> String {
    guard let value, !value.isEmpty else {
      return RecordingMicrophoneDevice.systemDefaultID
    }
    return value
  }
}
