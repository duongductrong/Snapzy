//
//  CloudUploadFloatingPosition.swift
//  Snapzy
//
//  Position options for the floating Cloud Uploads panel
//

import AppKit
import Foundation

enum CloudUploadFloatingPosition: String, CaseIterable, Codable, Identifiable {
  case top
  case center
  case bottom

  static let defaultPosition: CloudUploadFloatingPosition = .center

  var id: String { rawValue }

  static func stored(userDefaults: UserDefaults = .standard) -> CloudUploadFloatingPosition {
    CloudUploadFloatingPosition(
      rawValue: userDefaults.string(forKey: PreferencesKeys.cloudUploadsFloatingPosition) ?? ""
    ) ?? .defaultPosition
  }

  func calculateOrigin(for size: CGSize, on screen: NSScreen, padding: CGFloat = 20) -> CGPoint {
    let frame = screen.visibleFrame
    let x = frame.midX - size.width / 2

    switch self {
    case .top:
      return CGPoint(x: x, y: frame.maxY - size.height - padding)
    case .center:
      return CGPoint(x: x, y: frame.midY - size.height / 2)
    case .bottom:
      return CGPoint(x: x, y: frame.minY + padding)
    }
  }

  var displayName: String {
    switch self {
    case .top: return L10n.CloudSettings.uploadsWindowPositionTop
    case .center: return L10n.CloudSettings.uploadsWindowPositionCenter
    case .bottom: return L10n.CloudSettings.uploadsWindowPositionBottom
    }
  }
}
