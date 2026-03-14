//
//  AnnotateExporter.swift
//  Snapzy
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
      let didSave = save(state: state, to: url)
      if didSave && closeWindow {
        NSApp.keyWindow?.close()
      }
    }
  }

  /// Save annotated image to original file location (overwrite)
  @discardableResult
  static func saveToOriginal(state: AnnotateState) -> Bool {
    guard let sourceURL = state.sourceURL else { return false }
    return save(state: state, to: sourceURL)
  }

  @discardableResult
  static func save(state: AnnotateState, to url: URL) -> Bool {
    guard let image = renderFinalImage(state: state) else { return false }

    let format: NSBitmapImageRep.FileType = url.pathExtension.lowercased() == "jpg" ? .jpeg : .png

    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let data = bitmap.representation(using: format, properties: [:])
    else { return false }

    do {
      try SandboxFileAccessManager.shared.withScopedAccess(to: url.deletingLastPathComponent()) {
        try data.write(to: url, options: .atomic)
      }
      NSSound(named: "Pop")?.play()
      return true
    } catch {
      NSSound(named: "Basso")?.play()
      print("Annotate save failed: \(error.localizedDescription)")
      return false
    }
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

  /// Render the final annotated image to a temporary PNG file for drag-and-drop.
  /// Returns the file URL on success, nil on failure.
  static func renderToTempFile(state: AnnotateState) -> URL? {
    guard let image = renderFinalImage(state: state) else { return nil }

    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:])
    else { return nil }

    let tempDir = TempCaptureManager.shared.tempCaptureDirectory
    let fileName = "annotated_drag_\(UUID().uuidString.prefix(8)).png"
    let fileURL = tempDir.appendingPathComponent(fileName)

    do {
      try pngData.write(to: fileURL, options: .atomic)
      return fileURL
    } catch {
      print("[AnnotateExporter] Failed to write drag temp file: \(error.localizedDescription)")
      return nil
    }
  }

  // MARK: - Private

  private static func generateFileName(from url: URL?) -> String {
    guard let url = url else { return "annotated_image" }
    let baseName = url.deletingPathExtension().lastPathComponent
    return "\(baseName)_annotated"
  }

  /// Generate unique copy URL from original file path
  static func generateCopyURL(from originalURL: URL) -> URL {
    let directory = originalURL.deletingLastPathComponent()
    let baseName = originalURL.deletingPathExtension().lastPathComponent
    let ext = originalURL.pathExtension

    var copyNumber = 1
    var newURL = directory.appendingPathComponent("\(baseName)_copy.\(ext)")

    while FileManager.default.fileExists(atPath: newURL.path) {
      copyNumber += 1
      newURL = directory.appendingPathComponent("\(baseName)_copy\(copyNumber).\(ext)")
    }

    return newURL
  }

  private static func renderFinalImage(state: AnnotateState) -> NSImage? {
    guard let sourceImage = state.sourceImage else { return nil }

    // If mockup mode is active, use mockup rendering path with 3D transforms
    if state.editorMode == .mockup {
      return renderMockupImage(state: state)
    }

    // Determine effective bounds (crop or full image)
    let effectiveBounds: CGRect
    if let cropRect = state.cropRect {
      effectiveBounds = cropRect
    } else {
      effectiveBounds = CGRect(origin: .zero, size: sourceImage.size)
    }

    let padding = state.backgroundStyle != .none ? state.padding : 0

    // Add alignment space for non-center alignments (matches preview)
    let alignmentSpace: CGFloat = state.imageAlignment != .center ? 40 : 0

    let totalSize = NSSize(
      width: effectiveBounds.width + padding * 2 + alignmentSpace,
      height: effectiveBounds.height + padding * 2 + alignmentSpace
    )

    let image = NSImage(size: totalSize)
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
      image.unlockFocus()
      return nil
    }

    // Draw background
    drawBackground(state: state, in: context, size: totalSize)

    // Calculate image position based on alignment
    let imageWidth = effectiveBounds.width
    let imageHeight = effectiveBounds.height
    let totalExtraWidth = totalSize.width - imageWidth
    let totalExtraHeight = totalSize.height - imageHeight

    // Calculate destRect origin based on alignment
    // Note: CoreGraphics Y=0 is at bottom, so top alignment needs higher Y value
    let destX: CGFloat
    let destY: CGFloat

    switch state.imageAlignment {
    case .center:
      destX = totalExtraWidth / 2
      destY = totalExtraHeight / 2
    case .topLeft:
      destX = 0
      destY = totalExtraHeight  // Top in CG = max Y
    case .top:
      destX = totalExtraWidth / 2
      destY = totalExtraHeight
    case .topRight:
      destX = totalExtraWidth
      destY = totalExtraHeight
    case .left:
      destX = 0
      destY = totalExtraHeight / 2
    case .right:
      destX = totalExtraWidth
      destY = totalExtraHeight / 2
    case .bottomLeft:
      destX = 0
      destY = 0  // Bottom in CG = Y=0
    case .bottom:
      destX = totalExtraWidth / 2
      destY = 0
    case .bottomRight:
      destX = totalExtraWidth
      destY = 0
    }

    // Draw cropped portion of source image
    let destRect = NSRect(
      x: destX,
      y: destY,
      width: effectiveBounds.width,
      height: effectiveBounds.height
    )

    // Source rect in image coordinates (no Y-flip needed - cropRect already uses bottom-left origin like NSImage)
    let sourceRect = NSRect(
      x: effectiveBounds.origin.x,
      y: effectiveBounds.origin.y,
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

    // Draw annotations (offset by crop origin and image position based on alignment)
    let renderer = AnnotationRenderer(context: context, sourceImage: sourceImage)
    for annotation in state.annotations {
      // Only include annotations that intersect with crop bounds
      if let cropRect = state.cropRect {
        guard annotation.bounds.intersects(cropRect) else { continue }
      }
      let offsetAnnotation = offsetAnnotationForExport(
        annotation,
        cropOrigin: effectiveBounds.origin,
        imageX: destX,
        imageY: destY
      )
      renderer.draw(offsetAnnotation)
    }

    image.unlockFocus()
    return image
  }

  /// Offset annotation for export, accounting for crop origin and alignment-based image position
  private static func offsetAnnotationForExport(
    _ annotation: AnnotationItem,
    cropOrigin: CGPoint,
    imageX: CGFloat,
    imageY: CGFloat
  ) -> AnnotationItem {
    var result = annotation
    result.bounds = CGRect(
      x: annotation.bounds.origin.x - cropOrigin.x + imageX,
      y: annotation.bounds.origin.y - cropOrigin.y + imageY,
      width: annotation.bounds.width,
      height: annotation.bounds.height
    )

    // Offset internal points for types that store coordinates
    switch annotation.type {
    case .arrow(let start, let end):
      result.type = .arrow(
        start: CGPoint(x: start.x - cropOrigin.x + imageX, y: start.y - cropOrigin.y + imageY),
        end: CGPoint(x: end.x - cropOrigin.x + imageX, y: end.y - cropOrigin.y + imageY)
      )
    case .line(let start, let end):
      result.type = .line(
        start: CGPoint(x: start.x - cropOrigin.x + imageX, y: start.y - cropOrigin.y + imageY),
        end: CGPoint(x: end.x - cropOrigin.x + imageX, y: end.y - cropOrigin.y + imageY)
      )
    case .path(let points):
      result.type = .path(points.map {
        CGPoint(x: $0.x - cropOrigin.x + imageX, y: $0.y - cropOrigin.y + imageY)
      })
    case .highlight(let points):
      result.type = .highlight(points.map {
        CGPoint(x: $0.x - cropOrigin.x + imageX, y: $0.y - cropOrigin.y + imageY)
      })
    default:
      break
    }

    return result
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
      if let wallpaper = SandboxFileAccessManager.shared.withScopedAccess(to: url, {
        NSImage(contentsOf: url)
      }) {
        wallpaper.draw(in: rect)
        if case .blurred = state.backgroundStyle {
          // Apply blur effect would require CIFilter
        }
      }
    }
  }

  // MARK: - Mockup Rendering

  /// Render mockup image with 3D transforms using ImageRenderer
  /// First flattens image + annotations, then applies 3D transforms
  private static func renderMockupImage(state: AnnotateState) -> NSImage? {
    guard state.sourceImage != nil else { return nil }

    // Step 1: Render flat image with annotations (temporarily disable mockup mode)
    let savedMode = state.editorMode
    state.editorMode = .annotate
    guard let flatImage = renderFlatImageWithAnnotations(state: state) else {
      state.editorMode = savedMode
      return nil
    }
    state.editorMode = savedMode

    // Step 2: Apply mockup transforms to the flattened image
    let mockupView = MockupExportViewForAnnotate(flatImage: flatImage, state: state)
    let renderer = ImageRenderer(content: mockupView)
    renderer.scale = 2.0

    return renderer.nsImage
  }

  /// Render flat image with annotations (no mockup transforms)
  private static func renderFlatImageWithAnnotations(state: AnnotateState) -> NSImage? {
    guard let sourceImage = state.sourceImage else { return nil }

    // Determine effective bounds (crop or full image)
    let effectiveBounds: CGRect
    if let cropRect = state.cropRect {
      effectiveBounds = cropRect
    } else {
      effectiveBounds = CGRect(origin: .zero, size: sourceImage.size)
    }

    let image = NSImage(size: effectiveBounds.size)
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
      image.unlockFocus()
      return nil
    }

    // Draw cropped portion of source image
    let destRect = NSRect(origin: .zero, size: effectiveBounds.size)
    let sourceRect = NSRect(
      x: effectiveBounds.origin.x,
      y: effectiveBounds.origin.y,
      width: effectiveBounds.width,
      height: effectiveBounds.height
    )

    sourceImage.draw(in: destRect, from: sourceRect, operation: .sourceOver, fraction: 1.0)

    // Draw annotations offset by crop origin
    let renderer = AnnotationRenderer(context: context, sourceImage: sourceImage)
    for annotation in state.annotations {
      if let cropRect = state.cropRect {
        guard annotation.bounds.intersects(cropRect) else { continue }
      }
      let offsetAnnotation = offsetAnnotationForCrop(
        annotation,
        cropOrigin: effectiveBounds.origin,
        padding: 0
      )
      renderer.draw(offsetAnnotation)
    }

    image.unlockFocus()
    return image
  }
}

// MARK: - Mockup Export View for Annotate

/// SwiftUI view for exporting mockup with 3D transforms
struct MockupExportViewForAnnotate: View {
  let flatImage: NSImage  // Pre-rendered image with annotations
  let state: AnnotateState

  var body: some View {
    ZStack {
      backgroundLayer
        .frame(width: canvasSize.width, height: canvasSize.height)

      Image(nsImage: flatImage)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(maxWidth: imageSize.width, maxHeight: imageSize.height)
        .clipShape(RoundedRectangle(cornerRadius: state.cornerRadius, style: .continuous))
        .rotation3DEffect(
          .degrees(state.mockupRotationY),
          axis: (x: 0, y: 1, z: 0),
          anchor: .center,
          anchorZ: 0,
          perspective: state.mockupPerspective
        )
        .rotation3DEffect(
          .degrees(state.mockupRotationX),
          axis: (x: 1, y: 0, z: 0),
          anchor: .center,
          anchorZ: 0,
          perspective: state.mockupPerspective
        )
        .rotation3DEffect(
          .degrees(state.mockupRotationZ),
          axis: (x: 0, y: 0, z: 1),
          anchor: .center
        )
        .shadow(
          color: .black.opacity(state.shadowIntensity),
          radius: state.mockupShadowRadius,
          x: state.mockupShadowOffsetX,
          y: state.mockupShadowOffsetY
        )
    }
  }

  // MARK: - Size Calculations

  private var imageSize: CGSize {
    flatImage.size
  }

  private var canvasSize: CGSize {
    let padding = state.backgroundStyle != .none ? state.padding : 0
    let extraSpace = padding * 2 + 100 // Extra for shadow and rotation
    return CGSize(
      width: imageSize.width + extraSpace,
      height: imageSize.height + extraSpace
    )
  }

  // MARK: - Background

  @ViewBuilder
  private var backgroundLayer: some View {
    switch state.backgroundStyle {
    case .none:
      Color.clear
    case .gradient(let preset):
      LinearGradient(
        colors: preset.colors,
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    case .solidColor(let color):
      color
    case .wallpaper(let url):
      // Check if this is a preset wallpaper
      if url.scheme == "preset", let presetName = url.host,
         let preset = WallpaperPreset(rawValue: presetName) {
        preset.gradient
      } else if let image = NSImage(contentsOf: url) {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        Color.gray.opacity(0.3)
      }
    case .blurred(let url):
      if let image = NSImage(contentsOf: url) {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .blur(radius: 30)
      } else {
        Color.gray.opacity(0.3)
      }
    }
  }
}
