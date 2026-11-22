//
//  QuickAccessOptimizeSettings.swift
//  Snapzy
//
//  User-tunable Optimize settings (size, format, quality, file-size cap) shared by
//  the Quick Access "Custom…" editor and saved presets, plus the pure pipeline that
//  renders a screenshot with them.
//

import CoreGraphics
import Foundation

/// Output format of a custom optimize. `.original` keeps the file's own format.
nonisolated enum QuickAccessOptimizeFormat: String, Codable, CaseIterable, Identifiable, Sendable {
  case original
  case png
  case jpeg
  case webp
  case heic
  case avif

  var id: String { rawValue }

  /// Formats this Mac can write; AVIF needs a macOS release with an ImageIO AVIF encoder.
  static var availableCases: [QuickAccessOptimizeFormat] {
    allCases.filter(\.isEncoderAvailable)
  }

  var isEncoderAvailable: Bool {
    switch self {
    case .original, .png, .jpeg, .webp: true
    case .heic: ImageEncoderSupport.canEncodeHEIC
    case .avif: ImageEncoderSupport.canEncodeAVIF
    }
  }

  /// Extension written for this format, given the file's current one.
  func fileExtension(forOriginal originalExtension: String) -> String {
    switch self {
    case .original: originalExtension.lowercased()
    case .png: "png"
    case .jpeg:
      // Keep "jpeg" when the original already used it, so nothing gets renamed.
      originalExtension.lowercased() == "jpeg" ? "jpeg" : "jpg"
    case .webp: "webp"
    case .heic:
      originalExtension.lowercased() == "heif" ? "heif" : "heic"
    case .avif: "avif"
    }
  }

  static func isLossy(fileExtension: String) -> Bool {
    ImageEncoderSupport.isLossy(fileExtension: fileExtension)
  }

  /// Fixed lossy formats; `.original` depends on the file, so it is `false` here.
  var isLossy: Bool {
    switch self {
    case .jpeg, .webp, .heic, .avif: true
    case .original, .png: false
    }
  }

  /// "PNG", "JPEG", "WebP", "HEIC", "AVIF"; `.original` shows the file's own format.
  func displayName(originalExtension: String?) -> String {
    switch self {
    case .original:
      guard let originalExtension else { return L10n.QuickAccess.optimizeFormatOriginal }
      return L10n.QuickAccess.optimizeFormatKeep(Self.name(forExtension: originalExtension))
    case .png: return "PNG"
    case .jpeg: return "JPEG"
    case .webp: return "WebP"
    case .heic: return "HEIC"
    case .avif: return "AVIF"
    }
  }

  static func name(forExtension fileExtension: String) -> String {
    switch fileExtension.lowercased() {
    case "png": "PNG"
    case "jpg", "jpeg": "JPEG"
    case "webp": "WebP"
    case "heic", "heif": "HEIC"
    case "avif": "AVIF"
    default: fileExtension.uppercased()
    }
  }
}

nonisolated struct QuickAccessOptimizeSettings: Codable, Equatable, Hashable, Sendable {
  static let scaleRange: ClosedRange<Int> = 10...100
  static let qualityRange: ClosedRange<Int> = 30...100
  /// File-size caps offered in the editor, in bytes.
  static let maxFileSizeOptions: [Int] = [500, 1000, 2000, 5000].map { $0 * 1000 }

  /// Percent of the original pixel dimensions.
  var scalePercent: Int
  var format: QuickAccessOptimizeFormat
  /// Encoder quality for lossy formats, in percent.
  var qualityPercent: Int
  /// Upper bound on the encoded file; the pipeline lowers quality, then size, to fit.
  var maxFileSize: Int?

  static let `default` = QuickAccessOptimizeSettings(
    scalePercent: 100,
    format: .webp,
    qualityPercent: 80,
    maxFileSize: nil
  )

  init(scalePercent: Int, format: QuickAccessOptimizeFormat, qualityPercent: Int, maxFileSize: Int?) {
    self.scalePercent = scalePercent
    self.format = format
    self.qualityPercent = qualityPercent
    self.maxFileSize = maxFileSize
  }

  /// Values outside the editor's ranges (e.g. from a hand-edited defaults file) are clamped.
  /// The format is kept even when this Mac cannot encode it, so a synced AVIF preset
  /// survives edits on an older macOS; `render` falls back to PNG instead.
  var clamped: QuickAccessOptimizeSettings {
    QuickAccessOptimizeSettings(
      scalePercent: min(max(scalePercent, Self.scaleRange.lowerBound), Self.scaleRange.upperBound),
      format: format,
      qualityPercent: min(max(qualityPercent, Self.qualityRange.lowerBound), Self.qualityRange.upperBound),
      maxFileSize: maxFileSize.map { max($0, 10000) }
    )
  }

  var scaleFraction: CGFloat { CGFloat(clamped.scalePercent) / 100 }
  var quality: CGFloat { CGFloat(clamped.qualityPercent) / 100 }

  /// Short description for tooltips and the presets list, e.g. "50% · WebP 80 · ≤ 1 MB".
  func summary(originalExtension: String? = nil) -> String {
    let settings = clamped
    var parts = ["\(settings.scalePercent)%"]
    let formatName = settings.format.displayName(originalExtension: originalExtension)
    let outputExtension = originalExtension.map { settings.format.fileExtension(forOriginal: $0) }
    let showsQuality = settings.format.isLossy
      || (outputExtension.map(QuickAccessOptimizeFormat.isLossy(fileExtension:)) ?? false)
    parts.append(showsQuality ? "\(formatName) \(settings.qualityPercent)" : formatName)
    if let maxFileSize = settings.maxFileSize {
      parts.append("≤ \(QuickAccessImageOptimizer.formatByteCount(maxFileSize))")
    }
    return parts.joined(separator: " · ")
  }
}

nonisolated struct QuickAccessOptimizePreset: Codable, Equatable, Identifiable, Sendable {
  var id: UUID
  var name: String
  var settings: QuickAccessOptimizeSettings

  init(id: UUID = UUID(), name: String, settings: QuickAccessOptimizeSettings) {
    self.id = id
    self.name = name
    self.settings = settings
  }
}

/// A custom render ready to be written: bytes plus where they belong.
nonisolated struct QuickAccessOptimizeRendering: Equatable, Sendable {
  let data: Data
  let fileExtension: String
  let pixelWidth: Int
  let pixelHeight: Int
  let scale: CGFloat
  let qualityPercent: Int?
  /// False when even the smallest attempt stayed above `maxFileSize`.
  let meetsFileSizeLimit: Bool

  var dimensionsLabel: String { "\(pixelWidth)×\(pixelHeight)" }
}

// Explicitly nonisolated: with MainActor default isolation an extension's members
// would otherwise run on the main actor, freezing the UI during every encode.
nonisolated extension QuickAccessImageOptimizer {
  /// Lowest quality the file-size search will drop to before shrinking pixels.
  static let minimumSearchQuality = 40
  /// Each pixel step down while chasing a file-size cap.
  static let fileSizeScaleStep: CGFloat = 0.85

  /// Renders `original` with `settings`. With a file-size cap, lossy formats first
  /// search quality (down to `minimumSearchQuality`), then everything shrinks in
  /// `fileSizeScaleStep`s until it fits or hits `minimumLongEdge`.
  static func render(
    _ settings: QuickAccessOptimizeSettings,
    from original: CGImage,
    source: QuickAccessOptimizeSourceInfo,
    originalExtension: String,
    isCancelled: () -> Bool = { false }
  ) -> QuickAccessOptimizeRendering? {
    var settings = settings.clamped
    if !settings.format.isEncoderAvailable {
      // An AVIF preset on a macOS without the AVIF encoder.
      settings.format = .png
    }
    let fileExtension = settings.format.fileExtension(forOriginal: originalExtension)
    let isLossy = QuickAccessOptimizeFormat.isLossy(fileExtension: fileExtension)
    let longEdge = CGFloat(max(source.pixelWidth, source.pixelHeight))
    let minimumFraction = min(1, CGFloat(minimumLongEdge) / max(longEdge, 1))

    var fraction = settings.scaleFraction
    var best: QuickAccessOptimizeRendering?

    while true {
      guard !isCancelled() else { return nil }
      let width = max(1, Int((CGFloat(source.pixelWidth) * fraction).rounded()))
      let height = max(1, Int((CGFloat(source.pixelHeight) * fraction).rounded()))
      let scale = source.nativeScale * fraction
      guard let image = resized(
        original,
        width: width,
        height: height,
        flattensAlpha: !supportsAlpha(fileExtension: fileExtension)
      ) else {
        return best
      }

      func attempt(quality: Int?) -> QuickAccessOptimizeRendering? {
        guard let data = encode(
          image,
          fileExtension: fileExtension,
          scale: scale,
          quality: quality.map { CGFloat($0) / 100 }
        ) else {
          return nil
        }
        return QuickAccessOptimizeRendering(
          data: data,
          fileExtension: fileExtension,
          pixelWidth: width,
          pixelHeight: height,
          scale: scale,
          qualityPercent: quality,
          meetsFileSizeLimit: settings.maxFileSize.map { data.count <= $0 } ?? true
        )
      }

      let requestedQuality = isLossy ? settings.qualityPercent : nil
      guard let first = attempt(quality: requestedQuality) else { return best }
      guard let limit = settings.maxFileSize else { return first }
      if first.meetsFileSizeLimit { return first }
      best = smaller(best, first)

      if isLossy, let requestedQuality, requestedQuality > minimumSearchQuality {
        // Binary search the highest quality that fits at this size.
        var low = minimumSearchQuality
        var high = requestedQuality - 1
        var fitting: QuickAccessOptimizeRendering?
        while low <= high {
          guard !isCancelled() else { return nil }
          let mid = (low + high) / 2
          guard let candidate = attempt(quality: mid) else { break }
          best = smaller(best, candidate)
          if candidate.data.count <= limit {
            fitting = candidate
            low = mid + 1
          } else {
            high = mid - 1
          }
        }
        if let fitting { return fitting }
      }

      let nextFraction = fraction * fileSizeScaleStep
      guard nextFraction >= minimumFraction - 0.0001, nextFraction < fraction else { return best }
      fraction = nextFraction
    }
  }

  private static func smaller(
    _ lhs: QuickAccessOptimizeRendering?,
    _ rhs: QuickAccessOptimizeRendering
  ) -> QuickAccessOptimizeRendering {
    guard let lhs else { return rhs }
    return rhs.data.count < lhs.data.count ? rhs : lhs
  }

  static func supportsAlpha(fileExtension: String) -> Bool {
    ImageEncoderSupport.supportsAlpha(fileExtension: fileExtension)
  }
}
