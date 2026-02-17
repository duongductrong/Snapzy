//
//  BackgroundStyle.swift
//  Snapzy
//
//  Background style types and presets for annotation canvas
//

import SwiftUI

/// Background style types
enum BackgroundStyle: Equatable {
  case none
  case gradient(GradientPreset)
  case wallpaper(URL)
  case blurred(URL)
  case solidColor(Color)
}

/// Predefined gradient presets
enum GradientPreset: String, CaseIterable, Identifiable {
  case pinkOrange
  case bluePurple
  case greenBlue
  case orangeRed
  case purplePink
  case blueGreen
  case yellowOrange
  case cyanBlue

  var id: String { rawValue }

  var colors: [Color] {
    switch self {
    case .pinkOrange: return [.pink, .orange]
    case .bluePurple: return [.blue, .purple]
    case .greenBlue: return [.green, .blue]
    case .orangeRed: return [.orange, .red]
    case .purplePink: return [.purple, .pink]
    case .blueGreen: return [.blue, .green]
    case .yellowOrange: return [.yellow, .orange]
    case .cyanBlue: return [.cyan, .blue]
    }
  }
}

/// Image alignment within background
enum ImageAlignment: String, CaseIterable {
  case topLeft, top, topRight
  case left, center, right
  case bottomLeft, bottom, bottomRight
}

/// Predefined wallpaper presets (abstract gradient patterns)
enum WallpaperPreset: String, CaseIterable, Identifiable {
  case oceanBreeze
  case sunsetGlow
  case forestMist

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .oceanBreeze: return "Ocean"
    case .sunsetGlow: return "Sunset"
    case .forestMist: return "Forest"
    }
  }

  var colors: [Color] {
    switch self {
    case .oceanBreeze: return [Color(red: 0.1, green: 0.4, blue: 0.6), Color(red: 0.2, green: 0.6, blue: 0.8), Color(red: 0.4, green: 0.8, blue: 0.9)]
    case .sunsetGlow: return [Color(red: 0.9, green: 0.3, blue: 0.2), Color(red: 0.95, green: 0.5, blue: 0.3), Color(red: 1.0, green: 0.7, blue: 0.4)]
    case .forestMist: return [Color(red: 0.1, green: 0.3, blue: 0.2), Color(red: 0.2, green: 0.5, blue: 0.3), Color(red: 0.4, green: 0.7, blue: 0.5)]
    }
  }

  var gradient: LinearGradient {
    LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
  }
}

/// Aspect ratio options for export
enum AspectRatioOption: String, CaseIterable, Identifiable {
  case auto = "Auto"
  case square = "1:1"
  case ratio4x3 = "4:3"
  case ratio16x9 = "16:9"
  case ratio3x2 = "3:2"

  var id: String { rawValue }
}
