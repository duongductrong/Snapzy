//
//  MenuBarIconRenderer.swift
//  Snapzy
//
//  Renders 18pt template status bar images for each menu bar icon style and
//  manages the user-imported custom icon file.
//

import AppKit

@MainActor
final class MenuBarIconRenderer {
  static let shared = MenuBarIconRenderer()

  private let fileManager = FileManager.default
  private let appSupportFolderName = "Snapzy"
  private let customIconFolderName = "MenuBarIcon"
  private let customIconFileName = "custom.png"

  private init() {}

  // MARK: - Rendering

  /// 18pt template image for the given style. Falls back to the bundled
  /// default artwork when a custom icon is missing or undecodable.
  func statusImage(for style: MenuBarIconStyle) -> NSImage? {
    switch style {
    case .default:
      return makeBundledStatusImage()
    case .custom:
      if let custom = makeCustomStatusImage() {
        return custom
      }
      return makeBundledStatusImage()
    default:
      return makeSymbolStatusImage(symbolName: style.symbolName)
    }
  }

  /// Current bundled-artwork rendering (moved from AppStatusBarController).
  private func makeBundledStatusImage() -> NSImage? {
    guard let appIcon = NSImage(named: "MenubarIcon") else { return nil }

    let canvasSize = NSSize(width: 18, height: 18)
    let targetVisibleOccupancy: CGFloat = 0.89
    // Current MenubarIcon PNG alpha bounds occupy 75.28% of its transparent canvas.
    let sourceVisibleOccupancy: CGFloat = 0.7528
    let drawSize = NSSize(
      width: canvasSize.width * targetVisibleOccupancy / sourceVisibleOccupancy,
      height: canvasSize.height * targetVisibleOccupancy / sourceVisibleOccupancy
    )
    let drawRect = NSRect(
      x: (canvasSize.width - drawSize.width) / 2,
      y: (canvasSize.height - drawSize.height) / 2,
      width: drawSize.width,
      height: drawSize.height
    )

    let resizedIcon = NSImage(size: canvasSize)
    resizedIcon.lockFocus()
    appIcon.draw(
      in: drawRect,
      from: NSRect(origin: .zero, size: appIcon.size),
      operation: .copy,
      fraction: 1.0
    )
    resizedIcon.unlockFocus()
    // Template images let AppKit adapt the glyph color to the current menu bar material.
    resizedIcon.isTemplate = true
    return resizedIcon
  }

  private func makeSymbolStatusImage(symbolName: String?) -> NSImage? {
    guard let symbolName else { return nil }
    let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
    let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
      .withSymbolConfiguration(config)
    image?.isTemplate = true
    return image
  }

  /// Renders the user-imported PNG with alpha-bounds normalization so its
  /// visible content matches the bundled icon's 89% canvas occupancy.
  private func makeCustomStatusImage() -> NSImage? {
    guard let url = customIconURL,
          fileManager.fileExists(atPath: url.path),
          let source = NSImage(contentsOf: url),
          let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return nil
    }

    let canvasSize = NSSize(width: 18, height: 18)
    let targetVisibleOccupancy: CGFloat = 0.89
    let imageSize = NSSize(width: cgImage.width, height: cgImage.height)

    let drawSize: NSSize
    if let alphaBounds = Self.alphaBoundingBox(of: cgImage), !alphaBounds.isEmpty {
      // Scale so the larger visible dimension fills the target occupancy.
      let sourceOccupancy = max(
        alphaBounds.width / imageSize.width,
        alphaBounds.height / imageSize.height
      )
      guard sourceOccupancy > 0 else { return nil }
      let scale = targetVisibleOccupancy / sourceOccupancy
      drawSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
    } else {
      // Fully opaque (or undetectable bounds): fit the longest side to the target.
      let fit = min(
        canvasSize.width * targetVisibleOccupancy / imageSize.width,
        canvasSize.height * targetVisibleOccupancy / imageSize.height
      )
      drawSize = NSSize(width: imageSize.width * fit, height: imageSize.height * fit)
    }

    let drawRect = NSRect(
      x: (canvasSize.width - drawSize.width) / 2,
      y: (canvasSize.height - drawSize.height) / 2,
      width: drawSize.width,
      height: drawSize.height
    )

    let rendered = NSImage(size: canvasSize)
    rendered.lockFocus()
    source.draw(
      in: drawRect,
      from: NSRect(origin: .zero, size: source.size),
      operation: .copy,
      fraction: 1.0
    )
    rendered.unlockFocus()
    // Template rendering makes any imported PNG monochrome automatically.
    rendered.isTemplate = true
    return rendered
  }

  // MARK: - Custom Icon Storage

  /// URL of the stored custom icon: Application Support/Snapzy/MenuBarIcon/custom.png
  var customIconURL: URL? {
    guard
      let appSupportURL = fileManager.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first
    else {
      return nil
    }

    return appSupportURL
      .appendingPathComponent(appSupportFolderName, isDirectory: true)
      .appendingPathComponent(customIconFolderName, isDirectory: true)
      .appendingPathComponent(customIconFileName, isDirectory: false)
  }

  var hasCustomIcon: Bool {
    guard let url = customIconURL else { return false }
    return fileManager.fileExists(atPath: url.path)
  }

  /// Modification date of the stored custom icon, used for cache invalidation.
  var customIconModificationDate: Date? {
    guard let url = customIconURL else { return nil }
    return try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
  }

  /// Validates and copies a user-picked PNG into Application Support.
  @discardableResult
  func saveCustomIcon(from sourceURL: URL) -> Bool {
    guard let destinationURL = customIconURL else { return false }

    // Validate the pick decodes as an image before replacing the stored copy.
    guard let image = NSImage(contentsOf: sourceURL),
          image.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil else {
      DiagnosticLogger.shared.log(
        .warning, .ui, "Custom menu bar icon rejected: undecodable image",
        context: ["path": sourceURL.path]
      )
      return false
    }

    do {
      let directory = destinationURL.deletingLastPathComponent()
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      if fileManager.fileExists(atPath: destinationURL.path) {
        try fileManager.removeItem(at: destinationURL)
      }
      try fileManager.copyItem(at: sourceURL, to: destinationURL)
      DiagnosticLogger.shared.log(.info, .ui, "Custom menu bar icon imported")
      return true
    } catch {
      DiagnosticLogger.shared.log(
        .error, .ui, "Custom menu bar icon import failed",
        context: ["error": error.localizedDescription]
      )
      return false
    }
  }

  func removeCustomIcon() {
    guard let url = customIconURL, fileManager.fileExists(atPath: url.path) else { return }
    try? fileManager.removeItem(at: url)
  }

  // MARK: - Alpha Bounds

  /// Alpha bounding box of the image in pixel coordinates, detected on a
  /// downsampled bitmap. Returns nil when the image has no transparent pixels.
  static nonisolated func alphaBoundingBox(of cgImage: CGImage) -> CGRect? {
    let sampleSize = 128
    var bitmap = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)

    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: &bitmap,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: 8,
            bytesPerRow: sampleSize * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else {
      return nil
    }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

    var minX = sampleSize
    var minY = sampleSize
    var maxX = -1
    var maxY = -1
    var foundTransparent = false

    for y in 0..<sampleSize {
      for x in 0..<sampleSize {
        let alpha = bitmap[(y * sampleSize + x) * 4 + 3]
        if alpha < 8 {
          foundTransparent = true
          continue
        }
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)
      }
    }

    // No transparent pixels means the content fills the canvas; normalization
    // by alpha bounds would be meaningless.
    guard foundTransparent, maxX >= minX, maxY >= minY else { return nil }

    let scaleX = CGFloat(cgImage.width) / CGFloat(sampleSize)
    let scaleY = CGFloat(cgImage.height) / CGFloat(sampleSize)
    return CGRect(
      x: CGFloat(minX) * scaleX,
      y: CGFloat(minY) * scaleY,
      width: CGFloat(maxX - minX + 1) * scaleX,
      height: CGFloat(maxY - minY + 1) * scaleY
    )
  }
}
