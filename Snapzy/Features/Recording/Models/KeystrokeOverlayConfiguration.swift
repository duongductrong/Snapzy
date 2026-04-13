//
//  KeystrokeOverlayConfiguration.swift
//  Snapzy
//
//  Configuration for the keystroke overlay badge.
//  Reads persisted values from UserDefaults with sensible defaults.
//

import Foundation

/// Position of the keystroke badge relative to the recording area
enum KeystrokeOverlayPosition: String, CaseIterable, Identifiable {
  case bottomCenter = "bottomCenter"
  case bottomLeft = "bottomLeft"
  case bottomRight = "bottomRight"
  case topCenter = "topCenter"
  case topLeft = "topLeft"
  case topRight = "topRight"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .bottomCenter: return L10n.KeystrokePosition.bottomCenter
    case .bottomLeft: return L10n.KeystrokePosition.bottomLeft
    case .bottomRight: return L10n.KeystrokePosition.bottomRight
    case .topCenter: return L10n.KeystrokePosition.topCenter
    case .topLeft: return L10n.KeystrokePosition.topLeft
    case .topRight: return L10n.KeystrokePosition.topRight
    }
  }
}

struct KeystrokeOverlayConfiguration {

  /// Font size for the keystroke text
  let fontSize: CGFloat

  /// Position of the badge within the recording area
  let position: KeystrokeOverlayPosition

  /// How long the badge remains visible before fading (seconds)
  let displayDuration: Double

  /// Distance from the nearest edge (px)
  let edgeOffset: CGFloat

  // MARK: - Defaults

  static let defaultFontSize: CGFloat = 16
  static let defaultPosition: KeystrokeOverlayPosition = .bottomCenter
  static let defaultDisplayDuration: Double = 1.5
  static let defaultEdgeOffset: CGFloat = 40

  // MARK: - Init from UserDefaults

  init() {
    let ud = UserDefaults.standard

    let size = ud.object(forKey: PreferencesKeys.keystrokeFontSize) as? CGFloat
    self.fontSize = size ?? Self.defaultFontSize

    if let raw = ud.string(forKey: PreferencesKeys.keystrokePosition),
       let pos = KeystrokeOverlayPosition(rawValue: raw) {
      self.position = pos
    } else {
      self.position = Self.defaultPosition
    }

    self.displayDuration = ud.object(forKey: PreferencesKeys.keystrokeDisplayDuration) as? Double
      ?? Self.defaultDisplayDuration

    self.edgeOffset = Self.defaultEdgeOffset
  }
}
