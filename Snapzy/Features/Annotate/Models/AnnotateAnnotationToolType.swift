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
  case spotlight
  case counter
  case watermark
  case pencil
  case mockup

  var id: String { rawValue }

  /// Annotation tools that create or edit drawable items on the image canvas.
  /// Shared by the full Annotate window and inline area-annotate overlay so the
  /// two surfaces stay in sync when tools are added.
  static let drawableTools: [AnnotationToolType] = [
    .rectangle, .filledRectangle, .oval, .arrow, .line, .text, .highlighter,
    .blur, .spotlight, .counter, .watermark, .pencil
  ]

  static let inlineAnnotateTools: [AnnotationToolType] = [.selection] + drawableTools

  private static let inlineShapeToolSet: Set<AnnotationToolType> = [
    .rectangle, .filledRectangle, .oval, .arrow, .line
  ]

  static let inlineToolGroups: [[AnnotationToolType]] = [
    [.selection],
    drawableTools.filter { inlineShapeToolSet.contains($0) },
    drawableTools.filter { !inlineShapeToolSet.contains($0) }
  ]

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
    case .spotlight: return "viewfinder"
    case .counter: return "list.number"
    case .watermark: return "seal"
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
    case .spotlight: return "s"
    case .counter: return "n"
    case .watermark: return "w"
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
    case .spotlight: return L10n.Annotate.spotlightTool
    case .counter: return L10n.Annotate.counterTool
    case .watermark: return L10n.Annotate.watermarkTool
    case .pencil: return L10n.Annotate.pencilTool
    case .mockup: return L10n.Annotate.mockupTool
    }
  }

  var supportsQuickPropertiesBar: Bool {
    switch self {
    case .rectangle, .filledRectangle, .oval, .arrow, .line, .text, .highlighter, .blur, .spotlight, .counter, .watermark, .pencil:
      return true
    case .selection, .crop, .mockup:
      return false
    }
  }

  /// Drawable tools that should only commit a new blank-canvas item after a
  /// drag intent. Counter stays click-to-place, text keeps its click-to-edit
  /// flow, and freehand tools keep their existing path-count behavior.
  var requiresDragToCreateAnnotation: Bool {
    switch self {
    case .rectangle, .filledRectangle, .oval, .arrow, .line, .blur, .spotlight, .watermark:
      return true
    case .selection, .crop, .text, .highlighter, .counter, .pencil, .mockup:
      return false
    }
  }

  var supportsQuickStrokeColor: Bool {
    switch self {
    case .rectangle, .filledRectangle, .oval, .arrow, .line, .text, .highlighter, .counter, .watermark, .pencil:
      return true
    case .selection, .crop, .blur, .spotlight, .mockup:
      return false
    }
  }

  var supportsQuickFillColor: Bool {
    false
  }

  var supportsQuickStrokeWidth: Bool {
    switch self {
    case .rectangle, .filledRectangle, .oval, .arrow, .line, .highlighter, .blur, .counter, .pencil:
      return true
    case .selection, .crop, .text, .watermark, .spotlight, .mockup:
      return false
    }
  }

  var supportsQuickCornerRadius: Bool {
    switch self {
    case .rectangle, .filledRectangle, .text, .spotlight:
      return true
    case .selection, .crop, .oval, .arrow, .line, .highlighter, .blur, .counter, .watermark, .pencil, .mockup:
      return false
    }
  }
}