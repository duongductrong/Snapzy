//
//  AnnotateStampStore.swift
//  Snapzy
//
//  Stamp tool defaults shared by every Annotate window and the inline overlay:
//  the stamp the next click places, recents, size, opacity and sticker style.
//

import AppKit
import Combine
import CoreText
import UniformTypeIdentifiers

@MainActor
final class AnnotateStampStore: ObservableObject {
  static let shared = AnnotateStampStore()

  static let sizeRange: ClosedRange<CGFloat> = 24 ... 480
  static let opacityRange: ClosedRange<CGFloat> = 0.2 ... 1
  static let defaultSize: CGFloat = 120
  static let maximumRecentCount = 16

  private enum Keys {
    static let current = "annotate.stamp.current"
    static let recents = "annotate.stamp.recents"
    static let size = "annotate.stamp.size"
    static let opacity = "annotate.stamp.opacity"
    static let stickerStyle = "annotate.stamp.stickerStyle"
  }

  /// What the next click places. Image stamps stay in memory only.
  @Published private(set) var current: StampContent
  @Published private(set) var recents: [StampContent]
  @Published var size: CGFloat {
    didSet { defaults.set(Double(size), forKey: Keys.size) }
  }
  @Published var opacity: CGFloat {
    didSet { defaults.set(Double(opacity), forKey: Keys.opacity) }
  }
  @Published var isStickerStyle: Bool {
    didSet { defaults.set(isStickerStyle, forKey: Keys.stickerStyle) }
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    current = defaults.string(forKey: Keys.current).flatMap(StampContent.init(recentKey:)) ?? .sticker(.approved)
    recents = (defaults.stringArray(forKey: Keys.recents) ?? []).compactMap(StampContent.init(recentKey:))
    let storedSize = defaults.object(forKey: Keys.size) as? Double
    size = storedSize.map { min(max(CGFloat($0), Self.sizeRange.lowerBound), Self.sizeRange.upperBound) } ?? Self.defaultSize
    let storedOpacity = defaults.object(forKey: Keys.opacity) as? Double
    opacity = storedOpacity.map { min(max(CGFloat($0), Self.opacityRange.lowerBound), Self.opacityRange.upperBound) } ?? 1
    isStickerStyle = defaults.object(forKey: Keys.stickerStyle) as? Bool ?? true
    // Build the emoji catalog off the main thread so the picker opens instantly.
    DispatchQueue.global(qos: .utility).async {
      _ = AnnotateEmojiCatalog.all
    }
  }

  /// The stamp new placements use, with the current style.
  var currentStamp: StampAnnotation {
    StampAnnotation(content: current, isStickerStyle: isStickerStyle)
  }

  func choose(_ content: StampContent) {
    current = content
    if let key = content.recentKey {
      defaults.set(key, forKey: Keys.current)
    }
    noteUsed(content)
  }

  /// Moves `content` to the front of recents (stickers and emoji only).
  func noteUsed(_ content: StampContent) {
    guard content.recentKey != nil else { return }
    var updated = recents.filter { $0 != content }
    updated.insert(content, at: 0)
    if updated.count > Self.maximumRecentCount {
      updated.removeLast(updated.count - Self.maximumRecentCount)
    }
    guard updated != recents else { return }
    recents = updated
    defaults.set(updated.compactMap(\.recentKey), forKey: Keys.recents)
  }

  // MARK: - Slider gestures

  private var isSliderGestureActive = false
  private var didRecordSliderGestureUndo = false

  func setSliderEditing(_ isEditing: Bool) {
    isSliderGestureActive = isEditing
    didRecordSliderGestureUndo = false
  }

  /// True for the first change of a slider drag (and for every change outside a drag), so a
  /// whole drag is one undo step.
  func shouldRecordSliderUndo() -> Bool {
    guard isSliderGestureActive else { return true }
    guard !didRecordSliderGestureUndo else { return false }
    didRecordSliderGestureUndo = true
    return true
  }

  // MARK: - Image stamps

  /// Asks for an image file and turns it into a stamp. Returns nil when the user cancelled
  /// or the file could not be read. The caller makes it current (`AnnotateState.chooseStamp`).
  @discardableResult
  func chooseImageFile(panelLevel: NSWindow.Level? = nil) -> StampImage? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.title = L10n.AnnotateStamp.chooseImage
    if let panelLevel {
      panel.level = panelLevel
    }
    NSApp.activate(ignoringOtherApps: true)
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    guard let image = NSImage(contentsOf: url), let stampImage = Self.makeStampImage(from: image) else {
      NSSound.beep()
      return nil
    }
    return stampImage
  }

  /// Rasterizes `image` (keeping transparency) to at most `StampImage.maximumPixelDimension`
  /// on its long side and encodes it as PNG.
  nonisolated static func makeStampImage(from image: NSImage) -> StampImage? {
    var pixelSize = CGSize.zero
    for representation in image.representations {
      let width = CGFloat(representation.pixelsWide)
      let height = CGFloat(representation.pixelsHigh)
      if width > 0, height > 0, width * height > pixelSize.width * pixelSize.height {
        pixelSize = CGSize(width: width, height: height)
      }
    }
    if pixelSize == .zero {
      // Vector images (PDF, SVG) report no pixels: render at 2× their point size.
      pixelSize = CGSize(width: image.size.width * 2, height: image.size.height * 2)
    }
    guard pixelSize.width >= 1, pixelSize.height >= 1 else { return nil }
    let scale = min(1, StampImage.maximumPixelDimension / max(pixelSize.width, pixelSize.height))
    let width = max(Int((pixelSize.width * scale).rounded()), 1)
    let height = max(Int((pixelSize.height * scale).rounded()), 1)

    guard let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: width,
      pixelsHigh: height,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ) else { return nil }
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { return nil }
    return StampImage(pngData: data, pixelSize: CGSize(width: width, height: height))
  }
}

// MARK: - Emoji catalog

/// Every single-codepoint emoji the system emoji font can draw, with its Unicode name for search.
nonisolated enum AnnotateEmojiCatalog {
  nonisolated struct Entry: Identifiable, Hashable {
    let emoji: String
    /// Lowercased Unicode name, e.g. "smiling face with heart-shaped eyes".
    let name: String
    var id: String { emoji }
  }

  /// A friendly first row: the reactions people reach for most in screenshots.
  static let popular: [String] = [
    "👍", "👎", "👏", "🙌", "🎉", "🔥", "✅", "❌", "⚠️", "❗️", "❓", "💡",
    "⭐️", "❤️", "😀", "😂", "😍", "🤔", "😮", "😱", "😎", "🥳", "🤯", "🙏",
    "👀", "👉", "👈", "👆", "👇", "🚀", "🐛", "🛠️", "📌", "📎", "🔒", "⏰",
    "💯", "✨", "🎯", "🆕",
  ]

  static let all: [Entry] = buildCatalog()
  static let allEmoji: [String] = all.map(\.emoji)

  static func search(_ query: String) -> [Entry] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return all }
    let terms = trimmed.split(separator: " ").map(String.init)
    return all.filter { entry in
      entry.emoji == trimmed || terms.allSatisfy { entry.name.contains($0) }
    }
  }

  static func name(for emoji: String) -> String {
    emoji.unicodeScalars.first?.properties.name?.capitalized ?? emoji
  }

  private static let ranges: [ClosedRange<UInt32>] = [
    0x2190 ... 0x21FF, 0x2300 ... 0x23FF, 0x2460 ... 0x24FF, 0x25A0 ... 0x27BF,
    0x2900 ... 0x297F, 0x2B00 ... 0x2BFF, 0x3030 ... 0x303F, 0x3290 ... 0x329F,
    0x1F000 ... 0x1F2FF, 0x1F300 ... 0x1F5FF, 0x1F600 ... 0x1F64F, 0x1F680 ... 0x1F6FF,
    0x1F900 ... 0x1F9FF, 0x1FA70 ... 0x1FAFF,
  ]

  private static func buildCatalog() -> [Entry] {
    let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 16, nil)
    var entries: [Entry] = []
    for range in ranges {
      for value in range {
        guard let scalar = Unicode.Scalar(value) else { continue }
        let properties = scalar.properties
        guard properties.isEmoji,
              !properties.isEmojiModifier,
              !(0x1F1E6 ... 0x1F1FF).contains(value), // regional indicator letters
              let name = properties.name else { continue }
        let emoji = properties.isEmojiPresentation
          ? String(scalar)
          : String(scalar) + "\u{FE0F}"
        guard fontCanDraw(scalar, font: font) else { continue }
        entries.append(Entry(emoji: emoji, name: name.lowercased()))
      }
    }
    return entries
  }

  private static func fontCanDraw(_ scalar: Unicode.Scalar, font: CTFont) -> Bool {
    var characters = Array(String(scalar).utf16)
    var glyphs = [CGGlyph](repeating: 0, count: characters.count)
    // A surrogate pair maps to one glyph in the first slot; the second slot stays 0.
    return CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count) && glyphs.first != 0
  }
}
