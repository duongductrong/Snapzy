//
//  CropAspectRatio.swift
//  ClaudeShot
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

  /// Display name for UI
  var displayName: String {
    rawValue
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
