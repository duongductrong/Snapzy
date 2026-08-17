import AppKit
import Foundation
import SnapzyPluginAPI
import SwiftUI

/// Projects an open Annotate document into the public `SnapzyDocument` schema.
///
/// Deliberately lossy: a *view*, not a mirror. `AnnotationItem` (1690 lines of
/// SwiftUI types) must never cross the boundary — the projection is a sibling
/// type, so internal refactors and plugin compatibility move on separate
/// clocks. Image bytes are never embedded here; they travel through
/// `snapzy.asset.read` for the invocation only.
@MainActor
enum AnnotateDocumentProjector {
  static func project(state: AnnotateState) -> AnnotateDocument {
    let imageSize = SnapzySize(
      width: Double(state.imageWidth),
      height: Double(state.imageHeight)
    )
    let renderOrder = state.annotations.renderOrdered

    var items: [AnnotateDocItem] = []
    for item in renderOrder {
      let zIndex = renderOrder.firstIndex(where: { $0.id == item.id }) ?? 0
      items.append(project(item: item, zIndex: zIndex))
    }

    let crop: SnapzyRect? = state.cropRect.map {
      SnapzyRect(x: $0.minX, y: $0.minY, width: $0.width, height: $0.height)
    }

    return AnnotateDocument(
      schema: SnapzyVocabulary.documentSchemaVersion,
      size: imageSize,
      scale: Double(Self.backingScale(of: state.sourceImage) ?? 1),
      items: items,
      crop: crop
    )
  }

  /// Internal → projected. IDs stay stable: the projected id *is* the
  /// internal UUID's string, so patches referencing projected items resolve
  /// back to the same identity.
  static func project(item: AnnotationItem, zIndex: Int) -> AnnotateDocItem {
    let (kind, text) = kindAndText(for: item.type)
    return AnnotateDocItem(
      id: item.id.uuidString,
      kind: kind,
      rect: SnapzyRect(
        x: item.bounds.minX, y: item.bounds.minY,
        width: item.bounds.width, height: item.bounds.height
      ),
      text: text,
      style: AnnotateDocStyle(
        strokeColor: item.properties.strokeColor.snapzyColor,
        fillColor: item.properties.fillColor.snapzyColor,
        strokeWidth: Double(item.properties.strokeWidth),
        fontSize: Double(item.properties.fontSize),
        fontName: item.properties.fontName,
        opacity: Double(item.properties.opacity),
        rotation: Double(item.properties.rotationDegrees),
        presentation: item.properties.textPresentation.rawValue
      ),
      zIndex: zIndex
    )
  }

  static func kindAndText(for type: AnnotationType) -> (String, String?) {
    switch type {
    case .text(let text): return ("text", text)
    case .rectangle: return ("rect", nil)
    case .filledRectangle: return ("filledRect", nil)
    case .oval: return ("ellipse", nil)
    case .arrow: return ("arrow", nil)
    case .line: return ("line", nil)
    case .highlight: return ("highlight", nil)
    case .blur: return ("blur", nil)
    case .counter(let value): return ("counter", "\(value)")
    case .watermark(let text): return ("watermark", text)
    case .path: return ("path", nil)
    case .embeddedImage: return ("embeddedImage", nil)
    case .spotlight: return ("spotlight", nil)
    }
  }

  /// The backing scale of the source image, for export-fidelity decisions.
  private static func backingScale(of image: NSImage?) -> CGFloat? {
    guard let image, image.size.width > 0 else { return nil }
    guard let rep = image.representations.first else { return nil }
    return rep.pixelsWide > 0 ? CGFloat(rep.pixelsWide) / image.size.width : nil
  }
}

// MARK: - Color bridging

extension SwiftUI.Color {
  /// Converts a SwiftUI color into the projection's RGBA color. Falls back
  /// to nil for unrepresentable colors (system/catalog colors) — the plugin
  /// sees style as absent rather than wrong.
  var snapzyColor: SnapzyColor? {
    guard let nsColor = NSColor(self).usingColorSpace(.deviceRGB) else { return nil }
    return SnapzyColor(
      red: Double(nsColor.redComponent),
      green: Double(nsColor.greenComponent),
      blue: Double(nsColor.blueComponent),
      alpha: Double(nsColor.alphaComponent)
    )
  }
}

extension SnapzyColor {
  var swiftUIColor: SwiftUI.Color {
    SwiftUI.Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
  }
}
