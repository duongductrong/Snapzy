//
//  AnnotationToolType.swift
//  Snapzy
//
//  Enum defining all available annotation tools
//

import Foundation

/// Tool types available in annotation editor
enum AnnotationToolType: String, CaseIterable, Identifiable {
  case selection
  case crop
  case rectangle
  case oval
  case arrow
  case line
  case text
  case highlighter
  case blur
  case counter
  case pencil
  case mockup

  var id: String { rawValue }

  var icon: String {
    switch self {
    case .selection: return "cursorarrow"
    case .crop: return "crop"
    case .rectangle: return "rectangle"
    case .oval: return "circle"
    case .arrow: return "arrow.right"
    case .line: return "line.diagonal"
    case .text: return "textformat"
    case .highlighter: return "highlighter"
    case .blur: return "aqi.medium"
    case .counter: return "number"
    case .pencil: return "pencil"
    case .mockup: return "cube.transparent"
    }
  }

  /// Default keyboard shortcut for this tool
  var defaultShortcut: Character {
    switch self {
    case .selection: return "v"
    case .crop: return "c"
    case .rectangle: return "r"
    case .oval: return "o"
    case .arrow: return "a"
    case .line: return "l"
    case .text: return "t"
    case .highlighter: return "h"
    case .blur: return "b"
    case .counter: return "n"
    case .pencil: return "p"
    case .mockup: return "m"
    }
  }

  /// Display name for the tool
  var displayName: String {
    switch self {
    case .selection: return "Selection"
    case .crop: return "Crop"
    case .rectangle: return "Rectangle"
    case .oval: return "Oval"
    case .arrow: return "Arrow"
    case .line: return "Line"
    case .text: return "Text"
    case .highlighter: return "Highlighter"
    case .blur: return "Blur"
    case .counter: return "Counter"
    case .pencil: return "Pencil"
    case .mockup: return "Mockup"
    }
  }
}
