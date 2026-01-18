//
//  AnnotateExporter.swift
//  ZapShot
//
//  Export functionality for annotated images
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Handles exporting annotated images
@MainActor
final class AnnotateExporter {

  static func saveAs(state: AnnotateState, closeWindow: Bool = true) {
    guard state.hasImage else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png, .jpeg]
    panel.nameFieldStringValue = generateFileName(from: state.sourceURL)
    panel.canCreateDirectories = true

    if panel.runModal() == .OK, let url = panel.url {
      save(state: state, to: url)
      if closeWindow {
        NSApp.keyWindow?.close()
      }
    }
  }

  /// Save annotated image to original file location (overwrite)
  static func saveToOriginal(state: AnnotateState) {
    guard let sourceURL = state.sourceURL else { return }
    save(state: state, to: sourceURL)
  }

  static func save(state: AnnotateState, to url: URL) {
    guard let image = renderFinalImage(state: state) else { return }

    let format: NSBitmapImageRep.FileType = url.pathExtension.lowercased() == "jpg" ? .jpeg : .png

    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let data = bitmap.representation(using: format, properties: [:])
    else { return }

    try? data.write(to: url)
    NSSound(named: "Pop")?.play()
  }

  static func copyToClipboard(state: AnnotateState) {
    guard let image = renderFinalImage(state: state) else { return }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.writeObjects([image])
    NSSound(named: "Pop")?.play()
  }

  static func share(state: AnnotateState, from view: NSView) {
    guard let image = renderFinalImage(state: state) else { return }

    let picker = NSSharingServicePicker(items: [image])
    picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
  }

  // MARK: - Private

  private static func generateFileName(from url: URL?) -> String {
    guard let url = url else { return "annotated_image" }
    let baseName = url.deletingPathExtension().lastPathComponent
    return "\(baseName)_annotated"
  }

  private static func renderFinalImage(state: AnnotateState) -> NSImage? {
    guard let sourceImage = state.sourceImage else { return nil }

    // Determine effective bounds (crop or full image)
    let effectiveBounds: CGRect
    if let cropRect = state.cropRect {
      effectiveBounds = cropRect
    } else {
      effectiveBounds = CGRect(origin: .zero, size: sourceImage.size)
    }

    let padding = state.backgroundStyle != .none ? state.padding : 0
    let totalSize = NSSize(
      width: effectiveBounds.width + padding * 2,
      height: effectiveBounds.height + padding * 2
    )

    let image = NSImage(size: totalSize)
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
      image.unlockFocus()
      return nil
    }

    // Draw background
    drawBackground(state: state, in: context, size: totalSize)

    // Draw cropped portion of source image
    let destRect = NSRect(
      x: padding,
      y: padding,
      width: effectiveBounds.width,
      height: effectiveBounds.height
    )

    // Source rect in image coordinates (flip Y for NSImage drawing)
    let sourceRect = NSRect(
      x: effectiveBounds.origin.x,
      y: sourceImage.size.height - effectiveBounds.origin.y - effectiveBounds.height,
      width: effectiveBounds.width,
      height: effectiveBounds.height
    )

    if state.cornerRadius > 0 {
      let path = NSBezierPath(roundedRect: destRect, xRadius: state.cornerRadius, yRadius: state.cornerRadius)
      path.addClip()
    }

    sourceImage.draw(in: destRect, from: sourceRect, operation: .sourceOver, fraction: 1.0)

    // Reset clip
    context.resetClip()

    // Draw annotations (offset by crop origin and padding)
    let renderer = AnnotationRenderer(context: context, sourceImage: sourceImage)
    for annotation in state.annotations {
      // Only include annotations that intersect with crop bounds
      if let cropRect = state.cropRect {
        guard annotation.bounds.intersects(cropRect) else { continue }
      }
      let offsetAnnotation = offsetAnnotationForCrop(
        annotation,
        cropOrigin: effectiveBounds.origin,
        padding: padding
      )
      renderer.draw(offsetAnnotation)
    }

    image.unlockFocus()
    return image
  }

  /// Offset annotation for crop, accounting for crop origin and padding
  private static func offsetAnnotationForCrop(
    _ annotation: AnnotationItem,
    cropOrigin: CGPoint,
    padding: CGFloat
  ) -> AnnotationItem {
    var result = annotation
    result.bounds = CGRect(
      x: annotation.bounds.origin.x - cropOrigin.x + padding,
      y: annotation.bounds.origin.y - cropOrigin.y + padding,
      width: annotation.bounds.width,
      height: annotation.bounds.height
    )

    // Offset internal points for types that store coordinates
    switch annotation.type {
    case .arrow(let start, let end):
      result.type = .arrow(
        start: CGPoint(x: start.x - cropOrigin.x + padding, y: start.y - cropOrigin.y + padding),
        end: CGPoint(x: end.x - cropOrigin.x + padding, y: end.y - cropOrigin.y + padding)
      )
    case .line(let start, let end):
      result.type = .line(
        start: CGPoint(x: start.x - cropOrigin.x + padding, y: start.y - cropOrigin.y + padding),
        end: CGPoint(x: end.x - cropOrigin.x + padding, y: end.y - cropOrigin.y + padding)
      )
    case .path(let points):
      result.type = .path(points.map {
        CGPoint(x: $0.x - cropOrigin.x + padding, y: $0.y - cropOrigin.y + padding)
      })
    case .highlight(let points):
      result.type = .highlight(points.map {
        CGPoint(x: $0.x - cropOrigin.x + padding, y: $0.y - cropOrigin.y + padding)
      })
    default:
      break
    }

    return result
  }

  /// Offset an annotation by padding, including internal points for lines/arrows
  private static func offsetAnnotation(_ annotation: AnnotationItem, by padding: CGFloat) -> AnnotationItem {
    var result = annotation
    result.bounds = annotation.bounds.offsetBy(dx: padding, dy: padding)

    // Also offset internal points for types that store coordinates
    switch annotation.type {
    case .arrow(let start, let end):
      result.type = .arrow(
        start: CGPoint(x: start.x + padding, y: start.y + padding),
        end: CGPoint(x: end.x + padding, y: end.y + padding)
      )
    case .line(let start, let end):
      result.type = .line(
        start: CGPoint(x: start.x + padding, y: start.y + padding),
        end: CGPoint(x: end.x + padding, y: end.y + padding)
      )
    case .path(let points):
      result.type = .path(points.map { CGPoint(x: $0.x + padding, y: $0.y + padding) })
    case .highlight(let points):
      result.type = .highlight(points.map { CGPoint(x: $0.x + padding, y: $0.y + padding) })
    default:
      break
    }

    return result
  }

  private static func drawBackground(state: AnnotateState, in context: CGContext, size: NSSize) {
    let rect = CGRect(origin: .zero, size: size)

    switch state.backgroundStyle {
    case .none:
      break

    case .gradient(let preset):
      let colors = preset.colors.map { NSColor($0).cgColor }
      let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: nil
      )
      if let gradient = gradient {
        context.drawLinearGradient(
          gradient,
          start: .zero,
          end: CGPoint(x: size.width, y: size.height),
          options: []
        )
      }

    case .solidColor(let color):
      context.setFillColor(NSColor(color).cgColor)
      context.fill(rect)

    case .wallpaper(let url), .blurred(let url):
      if let wallpaper = NSImage(contentsOf: url) {
        wallpaper.draw(in: rect)
        if case .blurred = state.backgroundStyle {
          // Apply blur effect would require CIFilter
        }
      }
    }
  }
}
