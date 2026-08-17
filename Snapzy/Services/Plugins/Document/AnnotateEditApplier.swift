import AppKit
import Foundation
import SnapzyPluginAPI

/// Applies validated edits to a live `AnnotateState` as **one** undo group:
/// `saveState()` is pushed exactly once, before the first mutation, so the
/// plugin's entire batch collapses into one ⌘Z. Plugin-created items are
/// built exactly the way native ones are — indistinguishable downstream.
@MainActor
enum AnnotateEditApplier {
  /// Maps plugin-supplied id strings to internal UUIDs, stable per session
  /// (projected items reuse their own UUID; added items get a stable
  /// plugin-id → UUID mapping so later patches can update them).
  private static var idMap: [String: UUID] = [:]

  static func resetIDMap() {
    idMap.removeAll()
  }

  /// Applies the accepted set. Returns the number applied.
  static func apply(_ edits: [DocumentEdit], to state: AnnotateState) -> Int {
    guard !edits.isEmpty else { return 0 }

    // One checkpoint for the whole batch.
    state.saveState()

    var applied = 0
    var newSelection: [UUID] = []

    for edit in edits {
      switch edit {
      case .addItem(let item):
        if let annotation = makeAnnotation(from: item) {
          state.annotations.append(annotation)
          newSelection.append(annotation.id)
          applied += 1
        }

      case .updateItem(let id, let patch):
        guard let uuid = resolveID(id) else { continue }
        guard let index = state.annotations.firstIndex(where: { $0.id == uuid }) else { continue }
        var existing = state.annotations[index]
        if let rect = patch.rect {
          existing.bounds = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
        }
        if let text = patch.text {
          existing.type = .text(text)
        }
        applyStyle(patch.style, to: &existing)
        state.annotations[index] = existing
        applied += 1

      case .removeItem(let id):
        guard let uuid = resolveID(id) else { continue }
        let before = state.annotations.count
        state.annotations.removeAll { $0.id == uuid }
        if state.annotations.count < before {
          applied += 1
        }

      case .setCrop(let rect):
        state.cropRect = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
        applied += 1
      }
    }

    if !newSelection.isEmpty {
      state.setSelectedAnnotationIds(Set(newSelection))
      state.selectedTool = .selection
    }
    return applied
  }

  /// Projected id (a UUID string) or plugin-chosen id (mapped stably).
  static func resolveID(_ id: String) -> UUID? {
    if let mapped = idMap[id] { return mapped }
    if let uuid = UUID(uuidString: id) { return uuid }
    return nil
  }

  /// Acquires the internal UUID for a plugin-supplied item id: existing
  /// mapping wins, real UUIDs parse, anything else gets a stable fresh UUID.
  static func acquireID(for itemID: String) -> UUID {
    if let uuid = UUID(uuidString: itemID) { return uuid }
    if let mapped = idMap[itemID] { return mapped }
    let fresh = UUID()
    idMap[itemID] = fresh
    return fresh
  }

  // MARK: - Construction

  private static func makeAnnotation(from item: AnnotateDocItem) -> AnnotationItem? {
    let id = acquireID(for: item.id)
    let bounds = CGRect(x: item.rect.x, y: item.rect.y, width: item.rect.width, height: item.rect.height)
    let properties = makeProperties(from: item.style)

    switch item.kind {
    case "text":
      return AnnotationItem(id: id, type: .text(item.text ?? ""), bounds: bounds, properties: properties)
    case "rect":
      return AnnotationItem(id: id, type: .rectangle, bounds: bounds, properties: properties)
    case "filledRect":
      return AnnotationItem(id: id, type: .filledRectangle, bounds: bounds, properties: properties)
    case "ellipse":
      return AnnotationItem(id: id, type: .oval, bounds: bounds, properties: properties)
    case "highlight":
      return AnnotationItem(
        id: id,
        type: .highlight([
          CGPoint(x: bounds.minX, y: bounds.midY),
          CGPoint(x: bounds.maxX, y: bounds.midY),
        ]),
        bounds: bounds,
        properties: properties
      )
    case "blur":
      return AnnotationItem(id: id, type: .blur(.pixelated), bounds: bounds, properties: properties)
    case "counter":
      let value = Int(item.text ?? "1") ?? 1
      return AnnotationItem(id: id, type: .counter(value), bounds: bounds, properties: properties)
    case "arrow":
      let geometry = ArrowGeometry(
        start: CGPoint(x: bounds.minX, y: bounds.midY),
        end: CGPoint(x: bounds.maxX, y: bounds.midY),
        style: .straight
      )
      return AnnotationItem(id: id, type: .arrow(geometry), bounds: bounds, properties: properties)
    default:
      // Unknown item kinds from a newer plugin cannot be constructed by an
      // older host — skip rather than guess.
      return nil
    }
  }

  private static func makeProperties(from style: AnnotateDocStyle) -> AnnotationProperties {
    var properties = AnnotationProperties()
    if let color = style.strokeColor {
      properties.strokeColor = color.swiftUIColor
    }
    if let color = style.fillColor {
      properties.fillColor = color.swiftUIColor
    }
    if let strokeWidth = style.strokeWidth {
      properties.strokeWidth = CGFloat(strokeWidth)
    }
    if let fontSize = style.fontSize {
      properties.fontSize = CGFloat(fontSize)
    }
    if let fontName = style.fontName, !fontName.isEmpty {
      properties.fontName = fontName
    }
    if let opacity = style.opacity {
      properties.opacity = CGFloat(opacity)
    }
    if let rotation = style.rotation {
      properties.rotationDegrees = CGFloat(rotation)
    }
    if let presentation = style.presentation,
      let value = TextPresentation(rawValue: presentation)
    {
      properties.textPresentation = value
    }
    return properties
  }

  private static func applyStyle(_ style: AnnotateDocStyle?, to item: inout AnnotationItem) {
    guard let style else { return }
    if let color = style.strokeColor {
      item.properties.strokeColor = color.swiftUIColor
    }
    if let color = style.fillColor {
      item.properties.fillColor = color.swiftUIColor
    }
    if let strokeWidth = style.strokeWidth {
      item.properties.strokeWidth = CGFloat(strokeWidth)
    }
    if let fontSize = style.fontSize {
      item.properties.fontSize = CGFloat(fontSize)
    }
    if let fontName = style.fontName, !fontName.isEmpty {
      item.properties.fontName = fontName
    }
    if let opacity = style.opacity {
      item.properties.opacity = CGFloat(opacity)
    }
    if let rotation = style.rotation {
      item.properties.rotationDegrees = CGFloat(rotation)
    }
  }
}
