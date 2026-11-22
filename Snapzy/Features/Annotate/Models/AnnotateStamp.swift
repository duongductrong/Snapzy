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
  /// White die-cut outline and hard drop shadow around the stamp.
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
  case approved, rejected, lgtm, done, todo, wip, blocked, bug, fixed, new, beta, hot, note, fyi
  // Round icon stickers
  case thumbsUp, heart, star, check, cross, warning, question, idea, pin, smile, eyes, party, fire

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

  static let badges: [StampSticker] = [
    .approved, .rejected, .lgtm, .done, .todo, .wip, .blocked, .bug, .fixed, .new, .beta, .hot, .note, .fyi
  ]
  static let icons: [StampSticker] = [
    .thumbsUp, .heart, .star, .check, .cross, .warning, .question, .idea, .pin, .smile, .eyes, .party, .fire
  ]

  var shape: Shape {
    switch self {
    case .approved, .rejected, .lgtm, .done, .todo, .wip, .blocked, .bug, .fixed, .new, .beta, .hot, .note, .fyi:
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
    case .done: return "DONE"
    case .todo: return "TODO"
    case .wip: return "WIP"
    case .blocked: return "BLOCKED"
    case .bug: return "BUG"
    case .fixed: return "FIXED"
    case .new: return "NEW"
    case .beta: return "BETA"
    case .hot: return "HOT"
    case .note: return "NOTE"
    case .fyi: return "FYI"
    default: return nil
    }
  }

  var symbolName: String {
    switch self {
    case .approved: return "checkmark.circle.fill"
    case .rejected: return "xmark.circle.fill"
    case .lgtm: return "hand.thumbsup.fill"
    case .done: return "checkmark"
    case .todo: return "circle.dashed"
    case .wip: return "hammer.fill"
    case .blocked: return "nosign"
    case .bug: return "ladybug.fill"
    case .fixed: return "wrench.adjustable.fill"
    case .new: return "sparkle"
    case .beta: return "flask.fill"
    case .hot: return "flame.fill"
    case .note: return "pencil"
    case .fyi: return "info.circle.fill"
    case .thumbsUp: return "hand.thumbsup.fill"
    case .heart: return "heart.fill"
    case .star: return "star.fill"
    case .check: return "checkmark"
    case .cross: return "xmark"
    case .warning: return "exclamationmark"
    case .question: return "questionmark"
    case .idea: return "lightbulb.fill"
    case .pin: return "pin.fill"
    case .smile: return "face.smiling.inverse"
    case .eyes: return "eyes"
    case .party: return "party.popper.fill"
    case .fire: return "flame.fill"
    }
  }

  /// Solid body color. Flat on purpose: no gradient, gloss or highlight.
  var fill: RGB {
    switch self {
    case .approved, .done, .check: return StampPalette.green
    case .rejected, .blocked, .cross, .pin: return StampPalette.red
    case .lgtm: return StampPalette.teal
    case .fixed, .fyi, .thumbsUp: return StampPalette.blue
    case .new, .question, .party: return StampPalette.violet
    case .beta, .hot, .warning, .fire: return StampPalette.orange
    case .todo, .note, .star, .idea, .smile: return StampPalette.yellow
    case .bug, .heart: return StampPalette.pink
    case .wip, .eyes: return StampPalette.slate
    }
  }

  /// Icon and label color: dark brown on yellow, white elsewhere.
  var foreground: RGB {
    fill == StampPalette.yellow ? RGB(0x422006) : RGB(0xFFFFFF)
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
    case .done: return L10n.AnnotateStamp.stickerDone
    case .todo: return L10n.AnnotateStamp.stickerTodo
    case .wip: return L10n.AnnotateStamp.stickerWIP
    case .blocked: return L10n.AnnotateStamp.stickerBlocked
    case .bug: return L10n.AnnotateStamp.stickerBug
    case .fixed: return L10n.AnnotateStamp.stickerFixed
    case .new: return L10n.AnnotateStamp.stickerNew
    case .beta: return L10n.AnnotateStamp.stickerBeta
    case .hot: return L10n.AnnotateStamp.stickerHot
    case .note: return L10n.AnnotateStamp.stickerNote
    case .fyi: return L10n.AnnotateStamp.stickerFYI
    case .thumbsUp: return L10n.AnnotateStamp.stickerThumbsUp
    case .heart: return L10n.AnnotateStamp.stickerHeart
    case .star: return L10n.AnnotateStamp.stickerStar
    case .check: return L10n.AnnotateStamp.stickerCheck
    case .cross: return L10n.AnnotateStamp.stickerCross
    case .warning: return L10n.AnnotateStamp.stickerWarning
    case .question: return L10n.AnnotateStamp.stickerQuestion
    case .idea: return L10n.AnnotateStamp.stickerIdea
    case .pin: return L10n.AnnotateStamp.stickerPin
    case .smile: return L10n.AnnotateStamp.stickerSmile
    case .eyes: return L10n.AnnotateStamp.stickerEyes
    case .party: return L10n.AnnotateStamp.stickerParty
    case .fire: return L10n.AnnotateStamp.stickerFire
    }
  }
}

/// Friendly, saturated-but-not-neon sticker colors (sRGB).
nonisolated enum StampPalette {
  static let green = StampSticker.RGB(0x22C55E)
  static let red = StampSticker.RGB(0xEF4444)
  static let teal = StampSticker.RGB(0x14B8A6)
  static let blue = StampSticker.RGB(0x3B82F6)
  static let violet = StampSticker.RGB(0x8B5CF6)
  static let orange = StampSticker.RGB(0xF97316)
  static let yellow = StampSticker.RGB(0xFACC15)
  static let pink = StampSticker.RGB(0xEC4899)
  static let slate = StampSticker.RGB(0x64748B)
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
