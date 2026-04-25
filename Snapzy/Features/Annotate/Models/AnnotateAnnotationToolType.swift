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
  case filledRectangle
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
    case .filledRectangle: return "rectangle.fill"
    case .oval: return "circle"
    case .arrow: return "arrow.up.right"
    case .line: return "line.diagonal"
    case .text: return "character.textbox"
    case .highlighter: return "highlighter"
    case .blur: return "eye.slash"
    case .counter: return "list.number"
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
    case .filledRectangle: return "f"
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
    case .selection: return L10n.Annotate.selectionTool
    case .crop: return L10n.Annotate.cropTool
    case .rectangle: return L10n.Annotate.rectangleTool
    case .filledRectangle: return L10n.Annotate.filledRectangleTool
    case .oval: return L10n.Annotate.ovalTool
    case .arrow: return L10n.Annotate.arrowTool
    case .line: return L10n.Annotate.lineTool
    case .text: return L10n.Annotate.textTool
    case .highlighter: return L10n.Annotate.highlighterTool
    case .blur: return L10n.Annotate.blurTool
    case .counter: return L10n.Annotate.counterTool
    case .pencil: return L10n.Annotate.pencilTool
    case .mockup: return L10n.Annotate.mockupTool
    }
  }

  var supportsQuickPropertiesBar: Bool {
    switch self {
    case .rectangle, .filledRectangle, .oval, .arrow, .line, .text, .highlighter, .blur, .counter, .pencil:
      return true
    case .selection, .crop, .mockup:
      return false
    }
  }

  var supportsQuickStrokeColor: Bool {
    switch self {
    case .rectangle, .filledRectangle, .oval, .arrow, .line, .text, .highlighter, .counter, .pencil:
      return true
    case .selection, .crop, .blur, .mockup:
      return false
    }
  }

  var supportsQuickFillColor: Bool {
    self == .filledRectangle
  }

  var supportsQuickStrokeWidth: Bool {
    switch self {
    case .rectangle, .filledRectangle, .oval, .arrow, .line, .highlighter, .blur, .counter, .pencil:
      return true
    case .selection, .crop, .text, .mockup:
      return false
    }
  }

  var supportsQuickCornerRadius: Bool {
    switch self {
    case .rectangle, .filledRectangle:
      return true
    case .selection, .crop, .oval, .arrow, .line, .text, .highlighter, .blur, .counter, .pencil, .mockup:
      return false
    }
  }
}
