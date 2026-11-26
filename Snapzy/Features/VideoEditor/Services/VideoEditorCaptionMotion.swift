//
//  VideoEditorCaptionMotion.swift
//  Snapzy
//
//  Deterministic, resolution-independent motion curves, staggered per-word cascades,
//  character typewriter cursor, X-axis shutter flip, cinema tracking pull, directional
//  motion blur, and specular sheen shared 1:1 by SwiftUI preview and Core Image export.
//

import CoreGraphics
import Foundation

nonisolated struct VideoEditorActiveWordTiming: Equatable, Sendable {
  let index: Int
  /// Normalized progress (`0 ... 1`) across the active word's full spoken span.
  let wordProgress: CGFloat
  /// Normalized entrance progress (`0 ... 1`) across the active word's arrival animation window.
  let arrivalProgress: CGFloat
}

nonisolated struct VideoEditorWordKineticTransform: Equatable, Sendable {
  var opacity: CGFloat = 1
  var scale: CGFloat = 1
  var scaleY: CGFloat = 1
  /// Horizontal offset in `em` units.
  var offsetXEm: CGFloat = 0
  /// Vertical offset in CoreGraphics Y-up `em` units (`< 0` starts below baseline and rises to `0`).
  var offsetYEm: CGFloat = 0
  /// Luminous aura pulse boost (`0 ... 1`) during word arrival.
  var glowBoost: CGFloat = 0
  /// Pill glide interpolation (`0 ... 1`) from previous word to active word.
  var pillSlideProgress: CGFloat = 1

  static let identity = VideoEditorWordKineticTransform()
}

nonisolated struct VideoEditorCaptionMotionState: Equatable, Sendable {
  enum SubwordAnimationKind: String, Equatable, Hashable, Sendable {
    case wordCascade
    case wordFocus
    case typewriter
  }

  var opacity: CGFloat = 1
  var offsetXFraction: CGFloat = 0
  var offsetYFraction: CGFloat = 0
  var scale: CGFloat = 1
  /// Independent X/Y scale multipliers (e.g. `scaleY: 0.06 -> 1.0` for `.shutterFlip`).
  var scaleX: CGFloat = 1
  var scaleY: CGFloat = 1
  var blurRadiusFraction: CGFloat = 0
  /// Optional directional smear angle in degrees (`0` = horizontal whip, `90` = vertical flip).
  var directionalBlurAngleDegrees: CGFloat?
  var wipeProgress: CGFloat = 1
  var verticalRevealProgress: CGFloat = 1
  /// Dynamic letter-spacing offset in `em` units (`+0.14 -> 0` for `.trackingPull`).
  var trackingDeltaEm: CGFloat = 0
  /// Active subword/character stagger progress (`0 ... 1`) during entrance; `nil` when settled.
  var subwordKind: SubwordAnimationKind?
  var subwordProgress: CGFloat?
  var shimmerProgress: CGFloat?
  /// Dynamic per-word timing & motion physics when `wordMode != .fullLine`.
  var activeWordIndex: Int?
  var activeWordArrivalProgress: CGFloat?
  var activeWordScale: CGFloat = 1
  var activeWordOffsetYEm: CGFloat = 0
  var activeWordOpacity: CGFloat = 1
  var activeWordGlowBoost: CGFloat = 0

  static let identity = VideoEditorCaptionMotionState()
}

nonisolated enum VideoEditorCaptionMotion {
  static func evaluate(
    atSource sourceTime: TimeInterval,
    in segment: CaptionSegment,
    visibleRange: ClosedRange<TimeInterval>? = nil,
    settings: VideoEditorCaptionSettings
  ) -> VideoEditorCaptionMotionState {
    let start = max(segment.start, visibleRange?.lowerBound ?? segment.start)
    let end = min(segment.end, visibleRange?.upperBound ?? segment.end)
    let duration = max(0.05, end - start)
    let inSpan = min(
      max(settings.animationDuration, VideoEditorCaptionSettings.animationDurationRange.lowerBound),
      min(VideoEditorCaptionSettings.animationDurationRange.upperBound, duration * 0.44)
    )
    let outSpan = min(inSpan * 0.76, duration * 0.34)

    let elapsed = max(0, sourceTime - start)
    let remaining = max(0, end - sourceTime)

    var state = VideoEditorCaptionMotionState.identity

    if settings.animationIn != .none, inSpan > 0.01, elapsed < inSpan {
      let rawT = CGFloat(min(1, max(0, elapsed / inSpan)))
      state = combine(state, with: entranceState(style: settings.animationIn, t: rawT))
    }

    if settings.animationOut != .none, outSpan > 0.01, remaining < outSpan {
      let rawT = CGFloat(min(1, max(0, 1.0 - (remaining / outSpan))))
      state = combine(state, with: exitState(style: settings.animationOut, t: rawT))
    }

    if settings.shimmerSweep, duration > inSpan + outSpan + 0.25 {
      let sheenStart = inSpan + 0.06
      let sheenDuration = min(0.68, max(0.28, (duration - inSpan - outSpan) * 0.45))
      if elapsed >= sheenStart, elapsed <= sheenStart + sheenDuration {
        let rawS = CGFloat((elapsed - sheenStart) / sheenDuration)
        state.shimmerProgress = easeInOutCubic(rawS)
      }
    }

    if settings.wordMode != .fullLine {
      let words = segment.text
        .split(whereSeparator: \.isWhitespace)
        .map(String.init)
      if let timing = activeWordTiming(
        atSource: sourceTime,
        in: segment,
        wordsInLayout: words,
        settings: settings
      ) {
        state.activeWordIndex = timing.index
        if settings.wordAnimation != .none {
          let wt = wordMotionTransform(style: settings.wordAnimation, arrivalProgress: timing.arrivalProgress)
          state.activeWordArrivalProgress = timing.arrivalProgress
          state.activeWordScale = wt.scale
          state.activeWordOffsetYEm = wt.offsetYEm
          state.activeWordOpacity = wt.opacity
          state.activeWordGlowBoost = wt.glowBoost
        }
      }
    }

    return state
  }

  static func activeWordIndex(
    atSource sourceTime: TimeInterval,
    in segment: CaptionSegment,
    wordsInLayout: [String]
  ) -> Int? {
    activeWordTiming(
      atSource: sourceTime,
      in: segment,
      wordsInLayout: wordsInLayout,
      settings: .default
    )?.index
  }

  static func activeWordTiming(
    atSource sourceTime: TimeInterval,
    in segment: CaptionSegment,
    wordsInLayout: [String],
    settings: VideoEditorCaptionSettings
  ) -> VideoEditorActiveWordTiming? {
    guard !wordsInLayout.isEmpty else { return nil }
    let animBase = max(
      0.10,
      min(0.28, settings.animationDuration * 0.78)
    )

    if wordsInLayout.count == 1 {
      let span = max(0.05, segment.end - segment.start)
      let elapsed = max(0, sourceTime - segment.start)
      let wordProg = CGFloat(min(1, max(0, elapsed / span)))
      let arrSpan = min(animBase, max(0.05, span * 0.85))
      let arrProg = CGFloat(min(1, max(0, elapsed / arrSpan)))
      return VideoEditorActiveWordTiming(index: 0, wordProgress: wordProg, arrivalProgress: arrProg)
    }

    if let timedWords = segment.words, timedWords.count == wordsInLayout.count {
      var chosen = 0
      for (idx, word) in timedWords.enumerated() {
        if sourceTime >= word.start - 0.015 {
          chosen = idx
        } else {
          break
        }
      }
      let clampedIdx = min(max(chosen, 0), wordsInLayout.count - 1)
      let wStart = timedWords[clampedIdx].start
      let nextStart = clampedIdx + 1 < timedWords.count ? timedWords[clampedIdx + 1].start : segment.end
      let wEnd = max(wStart + 0.05, max(timedWords[clampedIdx].end, min(segment.end, nextStart)))
      let wSpan = max(0.05, wEnd - wStart)
      let elapsed = max(0, sourceTime - wStart)
      let wordProg = CGFloat(min(1, max(0, elapsed / wSpan)))
      let arrSpan = min(animBase, max(0.045, wSpan * 0.82))
      let arrProg = CGFloat(min(1, max(0, elapsed / arrSpan)))
      return VideoEditorActiveWordTiming(index: clampedIdx, wordProgress: wordProg, arrivalProgress: arrProg)
    }

    let span = max(0.05, segment.end - segment.start)
    let progress = min(0.9999, max(0, (sourceTime - segment.start) / span))
    let weights = wordsInLayout.map { Double(max(1, $0.count)) + 2.0 }
    let totalWeight = max(1.0, weights.reduce(0, +))
    let target = progress * totalWeight
    var cumulativeBefore = 0.0
    for (idx, w) in weights.enumerated() {
      let cumulativeAfter = cumulativeBefore + w
      if target < cumulativeAfter || idx == wordsInLayout.count - 1 {
        let wStart = segment.start + span * (cumulativeBefore / totalWeight)
        let wEnd = segment.start + span * (cumulativeAfter / totalWeight)
        let wSpan = max(0.045, wEnd - wStart)
        let elapsed = max(0, sourceTime - wStart)
        let wordProg = CGFloat(min(1, max(0, elapsed / wSpan)))
        let arrSpan = min(animBase, max(0.045, wSpan * 0.82))
        let arrProg = CGFloat(min(1, max(0, elapsed / arrSpan)))
        return VideoEditorActiveWordTiming(index: idx, wordProgress: wordProg, arrivalProgress: arrProg)
      }
      cumulativeBefore = cumulativeAfter
    }
    return VideoEditorActiveWordTiming(index: wordsInLayout.count - 1, wordProgress: 1, arrivalProgress: 1)
  }

  static func wordMotionTransform(
    style: VideoEditorCaptionSettings.AnimationStyle,
    arrivalProgress: CGFloat
  ) -> VideoEditorWordKineticTransform {
    let t = min(1, max(0, arrivalProgress))
    guard style != .none, t < 0.999 else { return .identity }

    switch style {
    case .none:
      return .identity

    case .springRise, .wordCascade:
      let sp = studioSpring(t)
      let p = easeOutExpo(t)
      return VideoEditorWordKineticTransform(
        opacity: min(1, 0.36 + 0.64 * easeOutQuart(min(1, t * 1.8))),
        scale: 0.88 + 0.12 * sp,
        offsetYEm: -(1 - p) * 0.24,
        glowBoost: sin(t * .pi) * 0.65,
        pillSlideProgress: p
      )

    case .studioPop:
      let sp = studioSpring(t)
      return VideoEditorWordKineticTransform(
        opacity: min(1, 0.42 + 0.58 * easeOutQuart(min(1, t * 2.0))),
        scale: 0.78 + 0.22 * sp,
        offsetYEm: -(1 - min(1, sp)) * 0.12,
        glowBoost: sin(t * .pi) * 0.75,
        pillSlideProgress: easeOutExpo(t)
      )

    case .elasticBounce:
      let sp = elasticSpring(t)
      return VideoEditorWordKineticTransform(
        opacity: min(1, 0.40 + 0.60 * easeOutQuart(min(1, t * 2.2))),
        scale: max(0.55, 0.70 + 0.30 * sp),
        offsetYEm: -(1 - sp) * 0.18,
        glowBoost: sin(t * .pi) * 0.80,
        pillSlideProgress: min(1.06, max(0, sp))
      )

    case .opticalBlur, .wordBlurIn, .trackingPull:
      let p = easeOutExpo(t)
      return VideoEditorWordKineticTransform(
        opacity: min(1, 0.28 + 0.72 * easeOutQuart(min(1, t * 1.6))),
        scale: 1.12 - 0.12 * p,
        glowBoost: (1 - p) * 0.85,
        pillSlideProgress: p
      )

    case .maskSlideUp:
      let p = easeOutExpo(t)
      return VideoEditorWordKineticTransform(
        opacity: min(1, 0.26 + 0.74 * p),
        scale: 0.94 + 0.06 * p,
        offsetYEm: -(1 - p) * 0.30,
        glowBoost: sin(t * .pi) * 0.50,
        pillSlideProgress: p
      )

    case .shutterFlip:
      let sp = studioSpring(t)
      return VideoEditorWordKineticTransform(
        opacity: min(1, 0.35 + 0.65 * easeOutQuart(min(1, t * 2.0))),
        scale: 1.0,
        scaleY: max(0.20, 0.20 + 0.80 * sp),
        glowBoost: sin(t * .pi) * 0.55,
        pillSlideProgress: easeOutExpo(t)
      )

    case .whipBlur, .driftSlide, .editorialWipe, .typewriterPro:
      let p = easeOutExpo(t)
      return VideoEditorWordKineticTransform(
        opacity: min(1, 0.32 + 0.68 * easeOutQuart(min(1, t * 1.8))),
        scale: 0.95 + 0.05 * p,
        offsetXEm: -(1 - p) * 0.26,
        glowBoost: sin(t * .pi) * 0.55,
        pillSlideProgress: p
      )

    case .neonFlicker:
      let env = neonFlickerEnvelope(t)
      return VideoEditorWordKineticTransform(
        opacity: max(0.28, env),
        scale: 0.94 + 0.06 * easeOutQuart(t),
        glowBoost: (1 - t) * 0.92,
        pillSlideProgress: easeOutExpo(t)
      )

    case .cinematicFade:
      let p = easeInOutCubic(t)
      return VideoEditorWordKineticTransform(
        opacity: 0.25 + 0.75 * p,
        scale: 0.96 + 0.04 * p,
        glowBoost: sin(t * .pi) * 0.40,
        pillSlideProgress: p
      )
    }
  }

  // MARK: - Motion Curves

  static func easeOutExpo(_ t: CGFloat) -> CGFloat {
    let x = min(1, max(0, t))
    return x >= 0.999 ? 1 : 1 - pow(2, -9.5 * x)
  }

  static func easeOutQuart(_ t: CGFloat) -> CGFloat {
    let inv = 1 - min(1, max(0, t))
    return 1 - inv * inv * inv * inv
  }

  static func easeInOutCubic(_ t: CGFloat) -> CGFloat {
    let x = min(1, max(0, t))
    return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
  }

  static func easeInCubic(_ t: CGFloat) -> CGFloat {
    let x = min(1, max(0, t))
    return x * x * x
  }

  static func studioSpring(_ t: CGFloat) -> CGFloat {
    let x = min(1, max(0, t))
    if x >= 0.999 {
      return 1
    }
    let decay = exp(-6.8 * x)
    let osc = cos(9.5 * x) + 0.58 * sin(9.5 * x)
    return 1 - decay * osc
  }

  static func elasticSpring(_ t: CGFloat) -> CGFloat {
    let x = min(1, max(0, t))
    if x >= 0.999 {
      return 1
    }
    let decay = exp(-5.4 * x)
    let osc = cos(13.2 * x) + 0.41 * sin(13.2 * x)
    return 1 - decay * osc
  }

  static func neonFlickerEnvelope(_ t: CGFloat) -> CGFloat {
    let x = min(1, max(0, t))
    if x < 0.15 {
      return (x / 0.15) * 0.88
    } else if x < 0.28 {
      return 0.14
    } else if x < 0.45 {
      return 0.96
    } else if x < 0.58 {
      return 0.36
    } else {
      return 0.36 + 0.64 * easeOutQuart((x - 0.58) / 0.42)
    }
  }

  private static func entranceState(
    style: VideoEditorCaptionSettings.AnimationStyle,
    t: CGFloat
  ) -> VideoEditorCaptionMotionState {
    switch style {
    case .none:
      return .identity

    case .wordCascade:
      var s = VideoEditorCaptionMotionState.identity
      s.opacity = min(1, easeOutQuart(min(1, t * 2.6)))
      s.subwordKind = .wordCascade
      s.subwordProgress = t
      return s

    case .wordBlurIn:
      var s = VideoEditorCaptionMotionState.identity
      s.opacity = min(1, easeOutQuart(min(1, t * 2.4)))
      s.blurRadiusFraction = (1 - easeOutExpo(t)) * 0.005
      s.subwordKind = .wordFocus
      s.subwordProgress = t
      return s

    case .typewriterPro:
      var s = VideoEditorCaptionMotionState.identity
      s.opacity = min(1, t * 4.0)
      s.subwordKind = .typewriter
      s.subwordProgress = t
      return s

    case .shutterFlip:
      let sp = studioSpring(t)
      var s = VideoEditorCaptionMotionState.identity
      s.opacity = min(1, easeOutQuart(min(1, t * 2.2)))
      s.scaleX = 1.0
      s.scaleY = max(0.05, 0.06 + 0.94 * sp)
      s.blurRadiusFraction = (1 - easeOutExpo(t)) * 0.008
      s.directionalBlurAngleDegrees = 90
      return s

    case .trackingPull:
      let p = easeOutExpo(t)
      var s = VideoEditorCaptionMotionState.identity
      s.opacity = easeInOutCubic(min(1, t * 1.25))
      s.scaleX = 1.12 - 0.12 * p
      s.blurRadiusFraction = (1 - p) * 0.005
      s.trackingDeltaEm = (1 - p) * 0.14
      return s

    case .opticalBlur:
      let p = easeOutExpo(t)
      let op = easeOutQuart(min(1, t * 1.35))
      return VideoEditorCaptionMotionState(
        opacity: op,
        offsetXFraction: 0,
        offsetYFraction: (1 - p) * 0.008,
        scale: 1.065 - 0.065 * p,
        blurRadiusFraction: (1 - p) * 0.013
      )

    case .maskSlideUp:
      let p = easeOutExpo(t)
      return VideoEditorCaptionMotionState(
        opacity: min(1, t * 3.2),
        offsetXFraction: 0,
        offsetYFraction: (1 - p) * 0.036,
        scale: 0.98 + 0.02 * p,
        blurRadiusFraction: (1 - p) * 0.003,
        verticalRevealProgress: max(0.02, p)
      )

    case .elasticBounce:
      let sp = elasticSpring(t)
      return VideoEditorCaptionMotionState(
        opacity: min(1, easeOutQuart(min(1, t * 2.2))),
        offsetXFraction: 0,
        offsetYFraction: (1 - sp) * 0.016,
        scale: max(0.2, 0.72 + 0.28 * sp)
      )

    case .whipBlur:
      let p = easeOutExpo(t)
      return VideoEditorCaptionMotionState(
        opacity: min(1, easeOutQuart(min(1, t * 1.8))),
        offsetXFraction: -(1 - p) * 0.058,
        blurRadiusFraction: (1 - p) * 0.016,
        directionalBlurAngleDegrees: 0
      )

    case .neonFlicker:
      let env = neonFlickerEnvelope(t)
      return VideoEditorCaptionMotionState(
        opacity: env,
        scale: 0.985 + 0.015 * easeOutQuart(t),
        blurRadiusFraction: (1 - env) * 0.0045
      )

    case .springRise:
      let p = easeOutQuart(t)
      return VideoEditorCaptionMotionState(
        opacity: min(1, easeOutQuart(min(1, t * 1.25))),
        offsetYFraction: (1 - p) * 0.022,
        scale: 0.965 + 0.035 * p
      )

    case .studioPop:
      let sp = studioSpring(t)
      return VideoEditorCaptionMotionState(
        opacity: min(1, easeOutQuart(min(1, t * 1.6))),
        offsetYFraction: (1 - min(1, sp)) * 0.012,
        scale: 0.84 + 0.16 * sp
      )

    case .editorialWipe:
      let p = easeOutExpo(t)
      return VideoEditorCaptionMotionState(
        opacity: min(1, t * 2.8),
        wipeProgress: max(0.01, p)
      )

    case .cinematicFade:
      let p = easeInOutCubic(t)
      return VideoEditorCaptionMotionState(
        opacity: p,
        scale: 1.02 - 0.02 * p
      )

    case .driftSlide:
      let p = easeOutQuart(t)
      return VideoEditorCaptionMotionState(
        opacity: easeInOutCubic(min(1, t * 1.25)),
        offsetXFraction: -(1 - p) * 0.026
      )
    }
  }

  private static func exitState(
    style: VideoEditorCaptionSettings.AnimationStyle,
    t: CGFloat
  ) -> VideoEditorCaptionMotionState {
    switch style {
    case .none:
      return .identity

    case .wordCascade, .springRise:
      let p = easeInCubic(t)
      return VideoEditorCaptionMotionState(
        opacity: max(0, 1 - easeInOutCubic(t)),
        offsetYFraction: -p * 0.016,
        scale: 1 - 0.025 * p
      )

    case .wordBlurIn, .opticalBlur:
      let p = easeInCubic(t)
      return VideoEditorCaptionMotionState(
        opacity: max(0, 1 - easeInOutCubic(t)),
        offsetYFraction: -p * 0.008,
        scale: 1 - 0.035 * p,
        blurRadiusFraction: p * 0.010
      )

    case .typewriterPro, .editorialWipe:
      let p = easeInOutCubic(t)
      return VideoEditorCaptionMotionState(
        opacity: max(0, 1 - p),
        wipeProgress: max(0.01, 1 - p * 0.45)
      )

    case .shutterFlip:
      let p = easeInCubic(t)
      var s = VideoEditorCaptionMotionState.identity
      s.opacity = max(0, 1 - easeInOutCubic(t))
      s.scaleY = max(0.05, 1 - 0.90 * p)
      s.blurRadiusFraction = p * 0.008
      s.directionalBlurAngleDegrees = 90
      return s

    case .trackingPull:
      let p = easeInCubic(t)
      var s = VideoEditorCaptionMotionState.identity
      s.opacity = max(0, 1 - easeInOutCubic(t))
      s.scaleX = 1 + 0.08 * p
      s.blurRadiusFraction = p * 0.005
      return s

    case .maskSlideUp:
      let p = easeInCubic(t)
      return VideoEditorCaptionMotionState(
        opacity: max(0, 1 - easeInOutCubic(t)),
        offsetYFraction: -p * 0.026,
        verticalRevealProgress: max(0.02, 1 - p * 0.85)
      )

    case .elasticBounce, .studioPop:
      let p = easeInCubic(t)
      return VideoEditorCaptionMotionState(
        opacity: max(0, 1 - easeInOutCubic(t)),
        offsetYFraction: p * 0.012,
        scale: 1 - 0.14 * p
      )

    case .whipBlur:
      let p = easeInCubic(t)
      return VideoEditorCaptionMotionState(
        opacity: max(0, 1 - easeInOutCubic(t)),
        offsetXFraction: p * 0.052,
        blurRadiusFraction: p * 0.014,
        directionalBlurAngleDegrees: 0
      )

    case .neonFlicker:
      let env = neonFlickerEnvelope(max(0, 1 - t))
      return VideoEditorCaptionMotionState(
        opacity: max(0, env * (1 - easeInCubic(t))),
        blurRadiusFraction: t * 0.004
      )

    case .cinematicFade:
      let p = easeInOutCubic(t)
      return VideoEditorCaptionMotionState(
        opacity: max(0, 1 - p),
        scale: 1 - 0.012 * p
      )

    case .driftSlide:
      let p = easeInCubic(t)
      return VideoEditorCaptionMotionState(
        opacity: max(0, 1 - easeInOutCubic(t)),
        offsetXFraction: p * 0.022
      )
    }
  }

  private static func combine(
    _ a: VideoEditorCaptionMotionState,
    with b: VideoEditorCaptionMotionState
  ) -> VideoEditorCaptionMotionState {
    VideoEditorCaptionMotionState(
      opacity: a.opacity * b.opacity,
      offsetXFraction: a.offsetXFraction + b.offsetXFraction,
      offsetYFraction: a.offsetYFraction + b.offsetYFraction,
      scale: a.scale * b.scale,
      scaleX: a.scaleX * b.scaleX,
      scaleY: a.scaleY * b.scaleY,
      blurRadiusFraction: max(a.blurRadiusFraction, b.blurRadiusFraction),
      directionalBlurAngleDegrees: a.directionalBlurAngleDegrees ?? b.directionalBlurAngleDegrees,
      wipeProgress: min(a.wipeProgress, b.wipeProgress),
      verticalRevealProgress: min(a.verticalRevealProgress, b.verticalRevealProgress),
      trackingDeltaEm: a.trackingDeltaEm + b.trackingDeltaEm,
      subwordKind: a.subwordKind ?? b.subwordKind,
      subwordProgress: a.subwordProgress ?? b.subwordProgress,
      shimmerProgress: a.shimmerProgress ?? b.shimmerProgress
    )
  }
}
