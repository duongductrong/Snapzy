import Foundation
import SnapzyPluginAPI

/// Pure, unit-testable edit validation — no AppKit, no state. One rule, one
/// test. Rejected edits are *skipped with a reason*; the accepted set still
/// applies. Unknown ops are rejected (fail-closed): the host must never guess
/// at mutation.
struct DocumentEditValidator {
  static let maxTextLength = 4_000
  static let maxItemsAddedPerPatch = 500
  static let minRectDimension: Double = 1
  static let maxCanvasDimension: Double = 100_000

  /// The projected-document view an edit is validated against: canvas size
  /// and the ids that already exist (update/remove must reference them).
  struct Context {
    let canvasSize: SnapzySize
    let existingIDs: Set<String>

    init(canvasSize: SnapzySize, existingIDs: Set<String>) {
      self.canvasSize = canvasSize
      self.existingIDs = existingIDs
    }
  }

  /// Validates the whole patch. Returns skipped edits with reasons; accepted
  /// edits are everything else. New ids introduced by earlier accepted edits
  /// in the same patch become valid targets for later update/remove edits
  /// (a patch can add then modify in one batch).
  static func validate(_ edits: [DocumentEdit], context: Context) -> (accepted: [DocumentEdit], skipped: [DocumentPatchSkip]) {
    var accepted: [DocumentEdit] = []
    var skipped: [DocumentPatchSkip] = []
    var knownIDs = context.existingIDs

    for (index, edit) in edits.enumerated() {
      if let reason = validate(edit, context: context, knownIDs: knownIDs) {
        skipped.append(DocumentPatchSkip(index: index, reason: reason))
      } else {
        accepted.append(edit)
        // Track ids this edit introduces for the rest of the batch.
        switch edit {
        case .addItem(let item): knownIDs.insert(item.id)
        case .updateItem(let id, _): knownIDs.insert(id)
        default: break
        }
      }
    }
    return (accepted, skipped)
  }

  /// Returns a rejection reason, or nil when the edit is acceptable.
  static func validate(_ edit: DocumentEdit, context: Context, knownIDs: Set<String>) -> String? {
    switch edit {
    case .addItem(let item):
      if let reason = validateItemShape(item, context: context) {
        return reason
      }
      if knownIDs.contains(item.id) {
        return "An item with id “\(item.id)” already exists."
      }
      return nil

    case .updateItem(let id, let patch):
      guard knownIDs.contains(id) else {
        return "Item “\(id)” does not exist in the projected document."
      }
      if let rect = patch.rect, !isValidRect(rect, canvas: context.canvasSize) {
        return "The updated rect for “\(id)” is outside the canvas."
      }
      if let text = patch.text, text.count > maxTextLength {
        return "The updated text for “\(id)” exceeds the \(maxTextLength) character cap."
      }
      return nil

    case .removeItem(let id):
      guard knownIDs.contains(id) else {
        return "Item “\(id)” does not exist in the projected document."
      }
      return nil

    case .setCrop(let rect):
      guard isValidRect(rect, canvas: context.canvasSize) else {
        return "The crop rect is outside the canvas."
      }
      return nil
    }
  }

  private static func validateItemShape(_ item: AnnotateDocItem, context: Context) -> String? {
    guard isValidRect(item.rect, canvas: context.canvasSize) else {
      return "Item “\(item.id)” has a rect outside the canvas."
    }
    if let text = item.text, text.count > maxTextLength {
      return "Item “\(item.id)” text exceeds the \(maxTextLength) character cap."
    }
    if let fontSize = item.style.fontSize, fontSize <= 0 || fontSize > 4_000 {
      return "Item “\(item.id)” has an invalid font size."
    }
    if let strokeWidth = item.style.strokeWidth, strokeWidth < 0 || strokeWidth > 1_000 {
      return "Item “\(item.id)” has an invalid stroke width."
    }
    if let opacity = item.style.opacity, opacity < 0 || opacity > 1 {
      return "Item “\(item.id)” has an invalid opacity."
    }
    if let rotation = item.style.rotation, abs(rotation) > 360 * 4 {
      return "Item “\(item.id)” has an invalid rotation."
    }
    return nil
  }

  static func isValidRect(_ rect: SnapzyRect, canvas: SnapzySize) -> Bool {
    let standardized = rect.standardized
    guard standardized.width >= minRectDimension, standardized.height >= minRectDimension else {
      return false
    }
    let tolerance = 1.0
    guard standardized.x >= -tolerance,
      standardized.y >= -tolerance,
      standardized.x + standardized.width <= canvas.width + tolerance,
      standardized.y + standardized.height <= canvas.height + tolerance
    else {
      return false
    }
    guard standardized.width <= maxCanvasDimension, standardized.height <= maxCanvasDimension else {
      return false
    }
    return true
  }
}
