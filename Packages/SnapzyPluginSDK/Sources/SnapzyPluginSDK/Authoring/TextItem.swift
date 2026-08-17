import Foundation
import SnapzyPluginAPI

public enum TextItemAuthoring {
  /// A text item sized to fit `rect`.
  public static func textItem(
    id: String,
    rect: SnapzyRect,
    text: String,
    style: AnnotateDocStyle = AnnotateDocStyle(),
    zIndex: Int = 0
  ) -> AnnotateDocItem {
    var computedStyle = style
    if computedStyle.fontSize == nil {
      computedStyle.fontSize = fitFontSize(text, in: rect)
    }
    return AnnotateDocItem(
      id: id,
      kind: "text",
      rect: rect,
      text: text,
      style: computedStyle,
      zIndex: zIndex
    )
  }

  /// Calculates a font size that keeps `text` inside `rect`.
  ///
  /// CJK glyphs are close to square and Latin glyphs about half as wide, so the
  /// per-character width estimate is picked from the text itself.
  public static func fitFontSize(_ text: String, in rect: SnapzyRect) -> Double {
    if text.isEmpty { return max(8, rect.height * 0.8) }
    let hasWideGlyphs = text.unicodeScalars.contains { scalar in
      (0x3000...0x9FFF).contains(scalar.value) ||
      (0xAC00...0xD7AF).contains(scalar.value) ||
      (0xFF00...0xFFEF).contains(scalar.value)
    }
    let widthPerPoint = hasWideGlyphs ? 1.0 : 0.55
    let byWidth = rect.width / (Double(text.count) * widthPerPoint)
    let byHeight = rect.height * 0.9
    return max(8, min(byWidth, byHeight))
  }
}

public func textItem(
  id: String,
  rect: SnapzyRect,
  text: String,
  style: AnnotateDocStyle = AnnotateDocStyle(),
  zIndex: Int = 0
) -> AnnotateDocItem {
  TextItemAuthoring.textItem(id: id, rect: rect, text: text, style: style, zIndex: zIndex)
}

public func fitFontSize(_ text: String, in rect: SnapzyRect) -> Double {
  TextItemAuthoring.fitFontSize(text, in: rect)
}

public func addItem(_ item: AnnotateDocItem) -> DocumentEdit {
  .addItem(item)
}

public func updateItem(id: String, patch: AnnotateDocItemPatch) -> DocumentEdit {
  .updateItem(id: id, patch: patch)
}

public func removeItem(id: String) -> DocumentEdit {
  .removeItem(id: id)
}

public func setCrop(_ crop: SnapzyRect) -> DocumentEdit {
  .setCrop(crop)
}
