//
//  VideoEditorTextOverlay.swift
//  Snapzy
//
//  Timeline text / title overlay model powered by shared CoreText typography,
//  studio surface formats, and deterministic In/Out motion curves. Maintains full
//  backward compatibility with legacy JSON sessions and property accessors.
//

import CoreGraphics
import Foundation

nonisolated struct VideoEditorTextOverlay: Identifiable, Equatable, Hashable, Codable, Sendable {
  enum AnimationStyle: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case none
    case fade
    case pop

    var displayName: String {
      switch self {
      case .none: L10n.VideoEditor.noneOption
      case .fade: L10n.VideoEditor.textAnimationFade
      case .pop: L10n.VideoEditor.textAnimationPop
      }
    }
  }

  static let minDuration: TimeInterval = 0.2
  static let defaultDuration: TimeInterval = 3.0
  static let minFontSize: CGFloat = 14
  static let maxFontSize: CGFloat = 140
  static let defaultFontSize: CGFloat = 38
  static let animationDuration: TimeInterval = 0.26

  let id: UUID
  var text: String
  var startTime: TimeInterval
  var duration: TimeInterval
  /// Normalized center X on the video canvas (`0.05 ... 0.95`).
  var normalizedX: CGFloat
  /// Normalized center Y on the video canvas in top-down UI coordinates (`0.08 ... 0.92`).
  var normalizedY: CGFloat
  /// Reference font size in points at a 720p vertical canvas height (`style.fontSize = fontSize / 720`).
  var fontSize: CGFloat {
    didSet {
      let clamped = Self.clampFontSize(fontSize)
      if abs(style.fontSize - clamped / 720.0) > 0.0001 {
        style.fontSize = clamped / 720.0
      }
    }
  }

  var textColorHex: String {
    didSet {
      let rgb = Self.rgbComponents(from: textColorHex)
      style.textColor = VideoEditorRGBAColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
    }
  }

  var backgroundColorHex: String {
    didSet {
      let rgb = Self.rgbComponents(from: backgroundColorHex)
      style.backgroundColor = VideoEditorRGBAColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
    }
  }

  var hasBackground: Bool {
    didSet {
      guard !isSyncingLegacyMirror else { return }
      if hasBackground {
        if !style.surfaceStyle.drawsBackdropBox {
          style.surfaceStyle = .studioGlass
        }
        if style.backgroundOpacity < 0.1 {
          style.backgroundOpacity = 0.84
        }
      } else if style.surfaceStyle == .classicPill || style.surfaceStyle == .studioGlass {
        style.surfaceStyle = .glowBloom
        style.backgroundOpacity = 0
      }
    }
  }

  var isBold: Bool {
    didSet {
      guard !isSyncingLegacyMirror else { return }
      style.isBold = isBold
      if isBold, style.fontWeight < 700 {
        style.fontWeight = 700
      } else if !isBold, style.fontWeight >= 700 {
        style.fontWeight = 500
      }
      style.syncLegacyFontFamilyEnum()
    }
  }

  private var isSyncingLegacyMirror: Bool = false

  var isEnabled: Bool
  var animation: AnimationStyle {
    didSet {
      switch animation {
      case .none:
        style.animationIn = .none
        style.animationOut = .none
      case .fade:
        style.animationIn = .cinematicFade
        style.animationOut = .cinematicFade
      case .pop:
        style.animationIn = .studioPop
        style.animationOut = .studioPop
      }
    }
  }

  /// Full typography, surface format, gradient, glow, and In/Out motion recipe.
  var style: VideoEditorCaptionSettings
  /// Zero-based vertical track lane index (`0 = T1`, `1 = T2`, ...) for multi-track text stacking.
  /// Higher `trackIndex` renders above lower lanes in both Preview and GPU Export.
  var trackIndex: Int

  init(
    id: UUID = UUID(),
    text: String = L10n.VideoEditor.defaultTitleText,
    startTime: TimeInterval = 0,
    duration: TimeInterval = defaultDuration,
    normalizedX: CGFloat = 0.5,
    normalizedY: CGFloat = 0.80,
    fontSize: CGFloat = defaultFontSize,
    textColorHex: String = "#FAFAFA",
    backgroundColorHex: String = "#0B0F17",
    hasBackground: Bool = false,
    isBold: Bool = true,
    isEnabled: Bool = true,
    animation: AnimationStyle = .fade,
    style: VideoEditorCaptionSettings? = nil,
    trackIndex: Int = 0
  ) {
    self.id = id
    self.text = String(text.prefix(2_000))
    self.startTime = startTime.isFinite ? min(max(0, startTime), 864_000) : 0
    self.duration = duration.isFinite ? min(max(Self.minDuration, duration), 864_000) : Self.defaultDuration
    self.normalizedX = Self.clampNormalizedX(normalizedX)
    self.normalizedY = Self.clampNormalizedY(normalizedY)
    let clampedSize = Self.clampFontSize(fontSize)
    self.fontSize = clampedSize
    self.textColorHex = textColorHex
    self.backgroundColorHex = backgroundColorHex
    self.hasBackground = hasBackground
    self.isBold = isBold
    self.isEnabled = isEnabled
    self.animation = animation
    self.trackIndex = max(0, min(TextTimelineLaneLayout.maxLanes - 1, trackIndex))

    if var explicitStyle = style {
      explicitStyle.isEnabled = true
      self.style = explicitStyle
      self.fontSize = Self.clampFontSize(explicitStyle.fontSize * 720.0)
      self.isBold = explicitStyle.isBold
      self.hasBackground = explicitStyle.surfaceStyle.drawsBackdropBox && explicitStyle.backgroundOpacity > 0.05
      self.textColorHex = Self.hexString(from: explicitStyle.textColor)
      self.backgroundColorHex = Self.hexString(from: explicitStyle.backgroundColor)
    } else {
      var built = VideoEditorCaptionSettings.default
      built.fontFamily = isBold ? .montserratBold : .montserratMedium
      built.isBold = isBold
      built.fontSize = clampedSize / 720.0
      let tRGB = Self.rgbComponents(from: textColorHex)
      let bRGB = Self.rgbComponents(from: backgroundColorHex)
      built.textColor = VideoEditorRGBAColor(red: tRGB.r, green: tRGB.g, blue: tRGB.b, alpha: 1)
      built.backgroundColor = VideoEditorRGBAColor(red: bRGB.r, green: bRGB.g, blue: bRGB.b, alpha: 1)
      built.surfaceStyle = hasBackground ? .studioGlass : .glowBloom
      built.backgroundOpacity = hasBackground ? 0.82 : 0.0
      switch animation {
      case .none:
        built.animationIn = .none
        built.animationOut = .none
      case .fade:
        built.animationIn = .cinematicFade
        built.animationOut = .cinematicFade
      case .pop:
        built.animationIn = .studioPop
        built.animationOut = .studioPop
      }
      self.style = built
    }
  }

  /// Apply one of the 12 studio presets to this individual text overlay.
  mutating func applyPreset(_ preset: VideoEditorCaptionSettings.EditorialPreset) {
    style.apply(preset: preset)
    syncLegacyMirrorFromStyle()
  }

  /// Synchronize legacy mirror properties after mutating `style` directly without
  /// re-firing legacy `didSet` side effects that would snap opacity or alter `surfaceStyle`.
  mutating func syncLegacyMirrorFromStyle() {
    isSyncingLegacyMirror = true
    defer { isSyncingLegacyMirror = false }
    fontSize = Self.clampFontSize(style.fontSize * 720.0)
    isBold = style.isBold
    hasBackground = style.surfaceStyle.drawsBackdropBox && style.backgroundOpacity > 0.05
    textColorHex = Self.hexString(from: style.textColor)
    backgroundColorHex = Self.hexString(from: style.backgroundColor)
  }

  var safeTimeRange: ClosedRange<TimeInterval> {
    let safeStart = startTime.isFinite ? min(max(0, startTime), 864_000) : 0
    let safeDuration = duration.isFinite && duration > 0
      ? min(max(Self.minDuration, duration), 864_000)
      : Self.minDuration
    return safeStart ... (safeStart + safeDuration)
  }

  var endTime: TimeInterval {
    guard startTime.isFinite, duration.isFinite, duration > 0 else {
      return startTime.isFinite ? max(0, startTime) : 0
    }
    return startTime + duration
  }

  func contains(time: TimeInterval) -> Bool {
    guard isEnabled,
          time.isFinite,
          startTime.isFinite,
          duration.isFinite,
          duration > 0
    else {
      return false
    }
    return time >= startTime && time < (startTime + duration)
  }

  /// True when `time` sits strictly inside the stationary hold window (past entrance,
  /// before exit, with no per-word or shimmer animation active), allowing the preview
  /// host to skip 60Hz SwiftUI body invalidations during static holds.
  func isInStaticHoldWindow(at time: TimeInterval) -> Bool {
    guard contains(time: time),
          style.wordMode == .fullLine,
          !style.shimmerSweep
    else { return false }
    let animDur = max(0, style.animationDuration)
    let holdStart = style.animationIn == .none ? startTime : (startTime + animDur + 0.04)
    let holdEnd = style.animationOut == .none ? endTime : (endTime - animDur - 0.04)
    return holdEnd > holdStart && time >= holdStart && time <= holdEnd
  }

  func clamped(to timelineDuration: TimeInterval) -> VideoEditorTextOverlay {
    guard timelineDuration.isFinite, timelineDuration > 0 else { return self }
    var copy = self
    let rawDur = copy.duration.isFinite ? copy.duration : Self.defaultDuration
    let rawStart = copy.startTime.isFinite ? copy.startTime : 0
    let clampedDuration = max(Self.minDuration, min(rawDur, timelineDuration))
    let clampedStart = max(0, min(rawStart, max(0, timelineDuration - clampedDuration)))
    copy.startTime = clampedStart
    copy.duration = clampedDuration
    return copy
  }

  /// Evaluate deterministic motion state for `time` (timeline/output seconds) using the
  /// unified `VideoEditorCaptionMotion` engine.
  func motionState(at time: TimeInterval) -> VideoEditorCaptionMotionState {
    guard contains(time: time) else {
      var hidden = VideoEditorCaptionMotionState.identity
      hidden.opacity = 0
      return hidden
    }
    let pseudoSegment = CaptionSegment(id: id, sourceRange: safeTimeRange, text: text)
    return VideoEditorCaptionMotion.evaluate(
      atSource: time,
      in: pseudoSegment,
      settings: style
    )
  }

  /// Backward-compatible tuple helper used by existing unit tests.
  func opacityAndScale(at time: TimeInterval) -> (opacity: Double, scale: CGFloat) {
    let m = motionState(at: time)
    return (Double(m.opacity), m.scale)
  }

  static func clampNormalizedX(_ value: CGFloat) -> CGFloat {
    guard value.isFinite else { return 0.5 }
    return min(max(value, 0.05), 0.95)
  }

  static func clampNormalizedY(_ value: CGFloat) -> CGFloat {
    guard value.isFinite else { return 0.80 }
    return min(max(value, 0.08), 0.92)
  }

  static func clampFontSize(_ value: CGFloat) -> CGFloat {
    guard value.isFinite else { return defaultFontSize }
    return min(max(value, minFontSize), maxFontSize)
  }

  static func scaledFontSize(for referenceSize: CGFloat, canvasHeight: CGFloat) -> CGFloat {
    guard canvasHeight > 1 else { return referenceSize }
    return max(10, referenceSize * (canvasHeight / 720.0))
  }

  static func rgbComponents(from hex: String) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
      return (1, 1, 1)
    }
    let r = CGFloat((value >> 16) & 0xFF) / 255.0
    let g = CGFloat((value >> 8) & 0xFF) / 255.0
    let b = CGFloat(value & 0xFF) / 255.0
    return (r, g, b)
  }

  static func hexString(from rgba: VideoEditorRGBAColor) -> String {
    let r = Int(min(255, max(0, (rgba.red * 255.0).rounded())))
    let g = Int(min(255, max(0, (rgba.green * 255.0).rounded())))
    let b = Int(min(255, max(0, (rgba.blue * 255.0).rounded())))
    return String(format: "#%02X%02X%02X", r, g, b)
  }

  static var textColorPresets: [(name: String, hex: String)] {
    [
      (L10n.VideoEditor.colorWhite, "#FAFAFA"),
      (L10n.VideoEditor.colorYellow, "#FFDC00"),
      (L10n.VideoEditor.colorCyan, "#59C3F0"),
      (L10n.VideoEditor.colorCoral, "#8C6CFF"),
      (L10n.VideoEditor.colorBlack, "#111111"),
    ]
  }

  static var backgroundColorPresets: [(name: String, hex: String)] {
    [
      (L10n.VideoEditor.colorBlack, "#0B0F17"),
      (L10n.VideoEditor.colorNavy, "#1754BC"),
      (L10n.VideoEditor.colorViolet, "#FFDC00"),
      (L10n.VideoEditor.colorCrimson, "#FAFAFA"),
    ]
  }

  private enum CodingKeys: String, CodingKey {
    case id, text, startTime, duration, normalizedX, normalizedY
    case fontSize, textColorHex, backgroundColorHex, hasBackground, isBold, isEnabled, animation
    case style, trackIndex
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let decodedId = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    let decodedText = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
    let decodedStart = try c.decodeIfPresent(TimeInterval.self, forKey: .startTime) ?? 0
    let decodedDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? Self.defaultDuration
    let decodedX = try c.decodeIfPresent(CGFloat.self, forKey: .normalizedX) ?? 0.5
    let decodedY = try c.decodeIfPresent(CGFloat.self, forKey: .normalizedY) ?? 0.80
    let decodedSize = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? Self.defaultFontSize
    let decodedTextHex = try c.decodeIfPresent(String.self, forKey: .textColorHex) ?? "#FAFAFA"
    let decodedBgHex = try c.decodeIfPresent(String.self, forKey: .backgroundColorHex) ?? "#0B0F17"
    let decodedHasBg = try c.decodeIfPresent(Bool.self, forKey: .hasBackground) ?? true
    let decodedBold = try c.decodeIfPresent(Bool.self, forKey: .isBold) ?? true
    let decodedEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    let decodedAnim = try c.decodeIfPresent(AnimationStyle.self, forKey: .animation) ?? .fade
    let decodedStyle = try c.decodeIfPresent(VideoEditorCaptionSettings.self, forKey: .style)
    let decodedTrackIndex = try c.decodeIfPresent(Int.self, forKey: .trackIndex) ?? 0

    self.init(
      id: decodedId,
      text: decodedText,
      startTime: decodedStart,
      duration: decodedDuration,
      normalizedX: decodedX,
      normalizedY: decodedY,
      fontSize: decodedSize,
      textColorHex: decodedTextHex,
      backgroundColorHex: decodedBgHex,
      hasBackground: decodedHasBg,
      isBold: decodedBold,
      isEnabled: decodedEnabled,
      animation: decodedAnim,
      style: decodedStyle,
      trackIndex: decodedTrackIndex
    )
  }
}

/// Multi-track lane layout math for Text Overlays (`T1`, `T2`, `T3`, ...).
nonisolated enum TextTimelineLaneLayout {
  static let maxLanes: Int = 6
  static let laneHeight: CGFloat = 34
  static let laneSpacing: CGFloat = 4

  static func laneCount(for overlays: [VideoEditorTextOverlay], minimumLanes: Int = 1) -> Int {
    let highest = overlays.map(\.trackIndex).max() ?? 0
    return max(1, min(maxLanes, max(minimumLanes, highest + 1)))
  }

  static func totalHeight(forLaneCount count: Int) -> CGFloat {
    let clamped = max(1, min(maxLanes, count))
    return CGFloat(clamped) * laneHeight + CGFloat(max(0, clamped - 1)) * laneSpacing
  }

  static func isLaneFree(
    _ lane: Int,
    start: TimeInterval,
    duration: TimeInterval,
    existing: [VideoEditorTextOverlay],
    excluding ignoredId: UUID? = nil
  ) -> Bool {
    guard lane >= 0, lane < maxLanes else { return false }
    let end = start + max(VideoEditorTextOverlay.minDuration, duration)
    return !existing.contains { item in
      item.id != ignoredId
        && item.trackIndex == lane
        && item.startTime < end - 0.01
        && item.endTime > start + 0.01
    }
  }

  /// Find a non-overlapping `(start, trackIndex)` across `T1...T6`. If all 6 lanes are full at
  /// `requestedStart`, advances `start` to the earliest non-overlapping slot within `axisDuration`
  /// (or returns `nil` when even the timeline has zero non-overlapping room across all 6 lanes).
  static func nonOverlappingPlacement(
    requestedStart: TimeInterval,
    duration: TimeInterval,
    axisDuration: TimeInterval,
    existing: [VideoEditorTextOverlay],
    excluding ignoredId: UUID? = nil,
    preferredTrack: Int = 0
  ) -> (start: TimeInterval, duration: TimeInterval, trackIndex: Int)? {
    let safeDuration = max(VideoEditorTextOverlay.minDuration, duration)
    let clampedPref = max(0, min(maxLanes - 1, preferredTrack))
    let candidateOrder = [clampedPref] + (0 ..< maxLanes).filter { $0 != clampedPref }
    let others = existing.filter { $0.id != ignoredId }
    var candidateStart = max(0, requestedStart)

    for _ in 0 ... others.count {
      let maxAllowedStart = max(0, axisDuration - VideoEditorTextOverlay.minDuration)
      if candidateStart > maxAllowedStart + 0.0001 {
        break
      }
      let clampedStart = min(candidateStart, maxAllowedStart)
      let fittedDuration = max(
        VideoEditorTextOverlay.minDuration,
        min(safeDuration, max(VideoEditorTextOverlay.minDuration, axisDuration - clampedStart))
      )
      for lane in candidateOrder {
        if isLaneFree(lane, start: clampedStart, duration: fittedDuration, existing: others) {
          return (clampedStart, fittedDuration, lane)
        }
      }
      let candidateEnd = clampedStart + fittedDuration
      let earliestEnd = others
        .filter { $0.startTime < candidateEnd - 0.01 && $0.endTime > clampedStart + 0.01 }
        .map(\.endTime)
        .min()
      guard let nextStart = earliestEnd, nextStart > candidateStart + 0.0001 else {
        break
      }
      candidateStart = nextStart
    }
    return nil
  }

  /// Picks the lowest track lane `[0 ..< maxLanes]` without a time overlap with `existing`.
  static func firstAvailableTrackIndex(
    start: TimeInterval,
    duration: TimeInterval,
    existing: [VideoEditorTextOverlay],
    excluding ignoredId: UUID? = nil,
    preferredTrack: Int = 0
  ) -> Int {
    let clampedPref = max(0, min(maxLanes - 1, preferredTrack))
    let candidateOrder = [clampedPref] + (0 ..< maxLanes).filter { $0 != clampedPref }
    for lane in candidateOrder {
      if isLaneFree(lane, start: start, duration: duration, existing: existing, excluding: ignoredId) {
        return lane
      }
    }
    return clampedPref
  }
}
