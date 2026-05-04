//
//  CropAspectRatio.swift
//  Snapzy
//
//  Aspect ratio options for crop tool
//

import Foundation

/// Predefined aspect ratio options for crop tool
enum CropAspectRatio: String, CaseIterable, Identifiable {
  case free = "Free"
  case square = "1:1"
  case ratio4x3 = "4:3"
  case ratio3x2 = "3:2"
  case ratio16x9 = "16:9"
  case ratio21x9 = "21:9"

  var id: String { rawValue }

  /// The numeric ratio (width / height)
  var ratio: CGFloat {
    switch self {
    case .free: return 0  // No constraint
    case .square: return 1.0
    case .ratio4x3: return 4.0 / 3.0
    case .ratio3x2: return 3.0 / 2.0
    case .ratio16x9: return 16.0 / 9.0
    case .ratio21x9: return 21.0 / 9.0
    }
  }

  /// Effective ratio accounting for portrait orientation.
  func effectiveRatio(isPortrait: Bool) -> CGFloat {
    let r = ratio
    guard r > 0 else { return 0 }
    return isPortrait ? 1.0 / r : r
  }

  /// Display name for UI
  var displayName: String {
    switch self {
    case .free:
      return L10n.Common.free
    default:
      return rawValue
    }
  }

  /// Effective display name accounting for portrait orientation.
  func effectiveDisplayName(isPortrait: Bool) -> String {
    switch self {
    case .free:
      return L10n.Common.free
    case .square:
      return rawValue
    case .ratio4x3:
      return isPortrait ? "3:4" : rawValue
    case .ratio3x2:
      return isPortrait ? "2:3" : rawValue
    case .ratio16x9:
      return isPortrait ? "9:16" : rawValue
    case .ratio21x9:
      return isPortrait ? "9:21" : rawValue
    }
  }

  /// Icon for the aspect ratio
  var icon: String {
    switch self {
    case .free: return "arrow.up.left.and.arrow.down.right"
    case .square: return "square"
    case .ratio4x3: return "rectangle"
    case .ratio3x2: return "rectangle"
    case .ratio16x9: return "rectangle.ratio.16.to.9"
    case .ratio21x9: return "rectangle"
    }
  }
}
