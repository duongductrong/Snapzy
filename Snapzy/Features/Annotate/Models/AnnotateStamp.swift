//
//  AnnotateStamp.swift
//  Snapzy
//
//  Stamp annotation content: designed sticker badges, emoji and image stamps.
//

import AppKit
import CoreGraphics
import CoreText
import Foundation

/// A placed stamp. Size lives in the item's `bounds` (content is aspect-fit inside it),
/// opacity in `AnnotationProperties.opacity` and rotation in `rotationDegrees`.
nonisolated struct StampAnnotation: Equatable {
  var content: StampContent
  /// White die-cut outline and soft drop shadow around the stamp.
  var isStickerStyle: Bool

  init(content: StampContent, isStickerStyle: Bool = true) {
    self.content = content
    self.isStickerStyle = isStickerStyle
  }
}

nonisolated enum StampContent: Equatable {
  case sticker(StampSticker)
  case emoji(String)
  case image(StampImage)

  /// Width / height of the drawn content, used to size new stamps and to aspect-fit
  /// the content inside resized bounds.
  var aspectRatio: CGFloat {
    switch self {
    case .sticker(let sticker):
      return sticker.aspectRatio
    case .emoji:
      return 1
    case .image(let image):
      return image.aspectRatio
    }
  }

  /// Stable identifier for recents (`sticker:approved`, `emoji:🔥`). Image stamps are not
  /// kept in recents: their pixels live only in the session.
  var recentKey: String? {
    switch self {
    case .sticker(let sticker): return "sticker:\(sticker.rawValue)"
    case .emoji(let emoji): return "emoji:\(emoji)"
    case .image: return nil
    }
  }

  init?(recentKey: String) {
    if recentKey.hasPrefix("sticker:") {
      guard let sticker = StampSticker(rawValue: String(recentKey.dropFirst("sticker:".count))) else { return nil }
      self = .sticker(sticker)
    } else if recentKey.hasPrefix("emoji:") {
      let emoji = String(recentKey.dropFirst("emoji:".count))
      guard !emoji.isEmpty else { return nil }
      self = .emoji(emoji)
    } else {
      return nil
    }
  }
}

/// An image file used as a stamp. The PNG bytes travel with the annotation (copy/paste,
/// undo, sidecars) so a stamp never depends on the original file. Equality is by `id`;
/// the renderer caches the decoded image under the same id.
nonisolated struct StampImage: Equatable {
  /// Longest side, in pixels, kept when an image is imported.
  static let maximumPixelDimension: CGFloat = 1024

  let id: UUID
  let pngData: Data
  let pixelSize: CGSize

  init(id: UUID = UUID(), pngData: Data, pixelSize: CGSize) {
    self.id = id
    self.pngData = pngData
    self.pixelSize = pixelSize
  }

  var aspectRatio: CGFloat {
    guard pixelSize.width > 0, pixelSize.height > 0 else { return 1 }
    return pixelSize.width / pixelSize.height
  }

  static func == (lhs: StampImage, rhs: StampImage) -> Bool {
    lhs.id == rhs.id
  }
}

// MARK: - Stickers

/// Curated vector stickers. Raw values are persisted in sidecars: never rename one.
nonisolated enum StampSticker: String, CaseIterable, Identifiable {
  // Text badges
  case approved, rejected, lgtm, new, beta, hot, todo, wip, bug, fixed
  // Round icon stickers
  case thumbsUp, heart, star, check, cross, warning, question, idea, sparkles, pin
  case arrowRight, arrowLeft, arrowUp, arrowDown

  nonisolated enum Shape {
    case badge
    case round
  }

  /// sRGB color, 0…1 components.
  nonisolated struct RGB: Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    init(_ hex: UInt32) {
      red = CGFloat((hex >> 16) & 0xFF) / 255
      green = CGFloat((hex >> 8) & 0xFF) / 255
      blue = CGFloat(hex & 0xFF) / 255
    }

    func cgColor(alpha: CGFloat = 1) -> CGColor {
      CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
  }

  var id: String { rawValue }

  static let badges: [StampSticker] = [.approved, .rejected, .lgtm, .new, .beta, .hot, .todo, .wip, .bug, .fixed]
  static let icons: [StampSticker] = [
    .thumbsUp, .heart, .star, .check, .cross, .warning, .question, .idea, .sparkles, .pin,
    .arrowRight, .arrowLeft, .arrowUp, .arrowDown
  ]

  var shape: Shape {
    switch self {
    case .approved, .rejected, .lgtm, .new, .beta, .hot, .todo, .wip, .bug, .fixed:
      return .badge
    default:
      return .round
    }
  }

  /// Badge text. Kept in English on purpose: these are the short labels reviewers use
  /// across languages, and a placed stamp must render the same on every machine.
  var label: String? {
    switch self {
    case .approved: return "APPROVED"
    case .rejected: return "REJECTED"
    case .lgtm: return "LGTM"
    case .new: return "NEW"
    case .beta: return "BETA"
    case .hot: return "HOT"
    case .todo: return "TODO"
    case .wip: return "WIP"
    case .bug: return "BUG"
    case .fixed: return "FIXED"
    default: return nil
    }
  }

  var symbolName: String {
    switch self {
    case .approved: return "checkmark.seal.fill"
    case .rejected: return "xmark.octagon.fill"
    case .lgtm: return "hand.thumbsup.fill"
    case .new: return "sparkles"
    case .beta: return "testtube.2"
    case .hot: return "flame.fill"
    case .todo: return "checklist"
    case .wip: return "hammer.fill"
    case .bug: return "ladybug.fill"
    case .fixed: return "wrench.and.screwdriver.fill"
    case .thumbsUp: return "hand.thumbsup.fill"
    case .heart: return "heart.fill"
    case .star: return "star.fill"
    case .check: return "checkmark"
    case .cross: return "xmark"
    case .warning: return "exclamationmark"
    case .question: return "questionmark"
    case .idea: return "lightbulb.fill"
    case .sparkles: return "sparkles"
    case .pin: return "pin.fill"
    case .arrowRight: return "arrow.right"
    case .arrowLeft: return "arrow.left"
    case .arrowUp: return "arrow.up"
    case .arrowDown: return "arrow.down"
    }
  }

  /// Gradient from the top of the sticker to the bottom.
  var gradient: (top: RGB, bottom: RGB) {
    switch self {
    case .approved, .check: return (RGB(0x4ADE80), RGB(0x16A34A))
    case .rejected, .cross: return (RGB(0xFF7A70), RGB(0xE5312B))
    case .lgtm: return (RGB(0x2DD4BF), RGB(0x0D9488))
    case .new: return (RGB(0x8B7CFF), RGB(0x4F6BFF))
    case .beta: return (RGB(0xFFC24D), RGB(0xFF8A00))
    case .hot: return (RGB(0xFFA14A), RGB(0xFF3B30))
    case .todo: return (RGB(0xFFE066), RGB(0xF5B400))
    case .wip: return (RGB(0x94A3B8), RGB(0x526079))
    case .bug: return (RGB(0xFF7EAA), RGB(0xE8366E))
    case .fixed: return (RGB(0x67D3FF), RGB(0x0A84FF))
    case .thumbsUp: return (RGB(0x5AB0FF), RGB(0x0A6CFF))
    case .heart: return (RGB(0xFF7A98), RGB(0xFF2D55))
    case .star: return (RGB(0xFFDD3C), RGB(0xFF9F0A))
    case .warning: return (RGB(0xFFD43B), RGB(0xFF9500))
    case .question: return (RGB(0xC77DFF), RGB(0x8944D8))
    case .idea: return (RGB(0xFFE97A), RGB(0xFFC300))
    case .sparkles: return (RGB(0xFF7AD9), RGB(0x9B5CFF))
    case .pin: return (RGB(0xFF7B72), RGB(0xD92D20))
    case .arrowRight, .arrowLeft, .arrowUp, .arrowDown: return (RGB(0x7C8BFF), RGB(0x3F4BDB))
    }
  }

  /// Icon and label color. Dark on the light yellow stickers, white elsewhere.
  var foreground: RGB {
    switch self {
    case .todo, .idea: return RGB(0x4A3500)
    default: return RGB(0xFFFFFF)
    }
  }

  var aspectRatio: CGFloat {
    switch shape {
    case .round:
      return 1
    case .badge:
      return StampBadgeLayout.layout(for: self).aspectRatio
    }
  }

  var displayName: String {
    switch self {
    case .approved: return L10n.AnnotateStamp.stickerApproved
    case .rejected: return L10n.AnnotateStamp.stickerRejected
    case .lgtm: return L10n.AnnotateStamp.stickerLGTM
    case .new: return L10n.AnnotateStamp.stickerNew
    case .beta: return L10n.AnnotateStamp.stickerBeta
    case .hot: return L10n.AnnotateStamp.stickerHot
    case .todo: return L10n.AnnotateStamp.stickerTodo
    case .wip: return L10n.AnnotateStamp.stickerWIP
    case .bug: return L10n.AnnotateStamp.stickerBug
    case .fixed: return L10n.AnnotateStamp.stickerFixed
    case .thumbsUp: return L10n.AnnotateStamp.stickerThumbsUp
    case .heart: return L10n.AnnotateStamp.stickerHeart
    case .star: return L10n.AnnotateStamp.stickerStar
    case .check: return L10n.AnnotateStamp.stickerCheck
    case .cross: return L10n.AnnotateStamp.stickerCross
    case .warning: return L10n.AnnotateStamp.stickerWarning
    case .question: return L10n.AnnotateStamp.stickerQuestion
    case .idea: return L10n.AnnotateStamp.stickerIdea
    case .sparkles: return L10n.AnnotateStamp.stickerSparkles
    case .pin: return L10n.AnnotateStamp.stickerPin
    case .arrowRight: return L10n.AnnotateStamp.stickerArrowRight
    case .arrowLeft: return L10n.AnnotateStamp.stickerArrowLeft
    case .arrowUp: return L10n.AnnotateStamp.stickerArrowUp
    case .arrowDown: return L10n.AnnotateStamp.stickerArrowDown
    }
  }
}

/// Proportions of a text badge, in units of the badge height (height = 1).
nonisolated struct StampBadgeLayout {
  static let horizontalPadding: CGFloat = 0.36
  static let iconSize: CGFloat = 0.46
  static let iconGap: CGFloat = 0.16
  static let fontSize: CGFloat = 0.42
  /// Letter spacing, as a fraction of the font size.
  static let kerning: CGFloat = 0.06

  let textWidth: CGFloat

  var aspectRatio: CGFloat {
    Self.horizontalPadding + Self.iconSize + Self.iconGap + textWidth + Self.horizontalPadding * 1.05
  }

  private static let lock = NSLock()
  nonisolated(unsafe) private static var cache: [StampSticker: StampBadgeLayout] = [:]

  static func layout(for sticker: StampSticker) -> StampBadgeLayout {
    lock.lock()
    defer { lock.unlock() }
    if let cached = cache[sticker] { return cached }
    let width = textLine(for: sticker, height: 100).map {
      CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) / 100
    } ?? 0
    let layout = StampBadgeLayout(textWidth: width)
    cache[sticker] = layout
    return layout
  }

  /// The badge label laid out for a badge `height` points tall.
  static func textLine(for sticker: StampSticker, height: CGFloat, color: CGColor? = nil) -> CTLine? {
    guard let label = sticker.label, height > 0 else { return nil }
    let font = roundedHeavyFont(size: height * fontSize)
    var attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTKernAttributeName as String): height * fontSize * kerning,
    ]
    if let color {
      attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = color
    } else {
      attributes[NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String)] = true
    }
    return CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: attributes))
  }

  static func roundedHeavyFont(size: CGFloat) -> CTFont {
    let base = NSFont.systemFont(ofSize: size, weight: .heavy)
    let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
    return (NSFont(descriptor: descriptor, size: size) ?? base) as CTFont
  }
}

// MARK: - Persistence

/// Sidecar form of a stamp (`kind: "stamp"`). Builds that predate stamps decode the kind as
/// unknown and skip the item. An unknown sticker id (from a newer build) drops only that item.
nonisolated struct PersistedStamp: Codable, Equatable {
  var content: String
  var sticker: String?
  var emoji: String?
  var imageId: UUID?
  var imagePNG: Data?
  var imageWidth: CGFloat?
  var imageHeight: CGFloat?
  var isStickerStyle: Bool?

  init(stamp: StampAnnotation) {
    isStickerStyle = stamp.isStickerStyle
    switch stamp.content {
    case .sticker(let value):
      content = "sticker"
      sticker = value.rawValue
    case .emoji(let value):
      content = "emoji"
      emoji = value
    case .image(let value):
      content = "image"
      imageId = value.id
      imagePNG = value.pngData
      imageWidth = value.pixelSize.width
      imageHeight = value.pixelSize.height
    }
  }

  var stampAnnotation: StampAnnotation? {
    let stampContent: StampContent
    switch content {
    case "sticker":
      guard let sticker, let value = StampSticker(rawValue: sticker) else { return nil }
      stampContent = .sticker(value)
    case "emoji":
      guard let emoji, !emoji.isEmpty else { return nil }
      stampContent = .emoji(emoji)
    case "image":
      guard let imagePNG, !imagePNG.isEmpty else { return nil }
      let size = CGSize(width: imageWidth ?? 1, height: imageHeight ?? 1)
      stampContent = .image(StampImage(id: imageId ?? UUID(), pngData: imagePNG, pixelSize: size))
    default:
      return nil
    }
    return StampAnnotation(content: stampContent, isStickerStyle: isStickerStyle ?? true)
  }
}
