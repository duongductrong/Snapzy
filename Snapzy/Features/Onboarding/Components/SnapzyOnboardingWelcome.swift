//
//  SnapzyOnboardingWelcome.swift
//  Snapzy
//
//  Arc-inspired opening beat re-themed to Snapzy's electric cobalt & white brand palette:
//  a seamless liquid-aurora orb awakens in a midnight-cobalt void and unfolds edge-to-edge into
//  a living 4x4 fluid cobalt-and-white aurora finished with clean photographic film grain, holds
//  the crisp white Snapzy mark in a solo beat, pulls the headline into focus word by word with a
//  trailing period spark, and reveals a magnetic Liquid Glass cobalt-jewel arrow button.
//

import AppKit
import CoreGraphics
import SwiftUI

// MARK: - Brand Palette (Snapzy Electric Cobalt & Luminous White)

/// Derived directly from `Snapzy/SnapzyIcon.icon/icon.json` (`#1138FF` → `#3A5FFF`) paired with
/// glacial white highlights. Kept local to the welcome canvas because app-wide tokens model dark
/// glass chrome rather than a full-bleed luminous aurora.
private struct WelcomeRGB {
  var r: Double
  var g: Double
  var b: Double

  var color: Color {
    Color(red: r, green: g, blue: b)
  }

  static func mix(_ a: WelcomeRGB, _ b: WelcomeRGB, _ t: Double) -> WelcomeRGB {
    WelcomeRGB(
      r: a.r + (b.r - a.r) * t,
      g: a.g + (b.g - a.g) * t,
      b: a.b + (b.b - a.b) * t
    )
  }
}

private enum SnapzyWelcomePalette {
  /// Luminous silk-white cloud peak (clean, never muddy gray).
  static let pureLight = WelcomeRGB(r: 0.980, g: 0.988, b: 1.000)
  /// Glacial sky-white pocket — bright and airy, cooled to Snapzy blue.
  static let icePocket = WelcomeRGB(r: 0.875, g: 0.930, b: 1.000)
  /// Crystalline mist blue bridging white clouds into electric azure without desaturation.
  static let mistBlue = WelcomeRGB(r: 0.700, g: 0.822, b: 1.000)
  /// Airy luminous sky-azure mid-tone.
  static let skyAzure = WelcomeRGB(r: 0.460, g: 0.625, b: 1.000)
  /// Lively radiant periwinkle-azure surrounding the cobalt core.
  static let radiantAzure = WelcomeRGB(r: 0.320, g: 0.490, b: 1.000)
  /// Luminous Snapzy app-icon bright azure (`#3C66FF`).
  static let brandAzure = WelcomeRGB(r: 0.235, g: 0.400, b: 1.000)
  /// Radiant electric Snapzy blue (`#2A58FF`) — vibrant without heavy dark navy troughs.
  static let brandCobalt = WelcomeRGB(r: 0.165, g: 0.345, b: 1.000)

  /// Midnight-cobalt void for the opening bloom.
  static let voidDark = Color(red: 0.014, green: 0.032, blue: 0.095)

  /// Atmospheric azure shadow tint (keeps white text luminous instead of muddy black).
  static let cobaltShadow = Color(red: 0.055, green: 0.155, blue: 0.560)

  /// Crisp hover & press electric-blue fills for the arrow button (flat, editorial, zero gloss).
  static let buttonHoverFill = Color(red: 0.115, green: 0.275, blue: 0.920)
  static let buttonPressFill = Color(red: 0.088, green: 0.225, blue: 0.810)
}

// MARK: - Main Welcome View

struct SnapzyOnboardingWelcome: View {
  var externalStartTrigger: Int = 0
  /// Exact pixel frame of the top-left `26×26` Snapzy app icon in the onboarding root coordinate
  /// space so the exiting Welcome screen contracts and docks straight into the brand logo.
  var targetLogoFrame: CGRect = CGRect(
    x: SnapzyOnboardingMetrics.gutter,
    y: (SnapzyOnboardingMetrics.gutter - 10) + (SnapzyOnboardingMetrics.headerHeight - 26) * 0.5,
    width: 26,
    height: 26
  )
  /// Called once the welcome CTA is visible so the host can silently pre-warm Step 1 offscreen
  /// behind the opaque aurora — eliminating any frame drop on the click frame.
  var onReadyForPrewarm: () -> Void = {}
  var onBeginTransition: () -> Void
  var onDockLogo: () -> Void = {}
  var onCompleteTransition: () -> Void
  var onClose: () -> Void

  @Environment(\.accessibilityReduceMotion) private var envReduceMotion

  @State private var hasStarted = false
  /// Continuous portal expansion driving the orb → full-bleed aurora transition:
  /// `0.0` = void, `0.27` = breathing liquid orb, `1.0` = full-bleed window edge-to-edge.
  @State private var portalProgress: CGFloat = 0
  @State private var isFlooded = false
  @State private var markIn = false
  @State private var markBreathing = false
  /// Continuous elevation of the solo brand mark from dead center (`0.0`, 84pt) up to its hero
  /// perch directly above `Meet Snapzy.` (`1.0`, 56pt) with a silky optical rack-focus blur shimmer.
  @State private var markElevation: CGFloat = 0
  @State private var revealedWordCount = 0
  @State private var periodRevealed = false
  @State private var subtitleIn = false
  @State private var ctaIn = false
  @State private var isExiting = false
  /// Smoothly exhales and dissolves the full-window blue aurora into the Dark Liquid Glass canvas
  /// (`0.0` = opaque full-bleed aurora → `1.0` = gently expanded & completely dissolved).
  @State private var auroraExitProgress: CGFloat = 0
  /// Drives the silky top-left Logo Dock flight (0.0 = perched Hero Mark → 1.0 = docked pixel-for-
  /// pixel onto the 26×26 top-left Snapzy app icon).
  @State private var logoMorphProgress: CGFloat = 0
  /// Crisp optical hairline ring expanding once around the top-left 26×26 logo on exact dock.
  @State private var dockRingProgress: CGFloat = 0
  /// Used only under Reduce Motion for a simple crossfade exit.
  @State private var reduceMotionOpacity: Double = 1.0

  private var reduceMotion: Bool {
    SnapzyMotionPreferences.shared.reduceMotion || envReduceMotion
  }

  private func phaseAnimation(_ base: Animation) -> Animation? {
    reduceMotion ? nil : base
  }

  private var headlineTokens: WelcomeHeadlineTokens {
    WelcomeHeadlineTokens(headline: L10n.Onboarding.welcomeHeadline)
  }

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      ZStack(alignment: .topLeading) {
        // Opening midnight-cobalt void (fades away once flooded so Liquid Glass shows beneath
        // the morphing aurora frame during exit).
        if !isFlooded {
          SnapzyWelcomePalette.voidDark
            .frame(width: size.width, height: size.height)
            .clipShape(Radius.rect(SnapzyRadius.window))
        }

        // Soft ambient cobalt aura warming the void around the awakening orb
        if !isFlooded {
          WelcomeOrbAmbientAura(progress: portalProgress, drifts: !reduceMotion)
            .position(x: size.width * 0.5, y: size.height * 0.5)
            .allowsHitTesting(false)
        }

        // Living Aurora Backdrop:
        // - During opening: fills the full window through the living plasma orb portal.
        // - On arrow click: exhales gently (`scale 1.0 → 1.055`) and dissolves cleanly away into
        //   the Dark Liquid Glass workspace (never dragging a shrinking rectangular box over Step 1).
        dissolvingAuroraSurface(in: size)

        // Single crisp optical hairline ring pulsing once around the top-left brand logo on dock
        if !reduceMotion && dockRingProgress > 0.001 {
          dockArrivalRing
            .position(x: targetLogoFrame.midX, y: targetLogoFrame.midY)
            .allowsHitTesting(false)
        }

        // Arc focus-pull wave headline + airy subtitle + clean editorial arrow pill button.
        // Keeping `.blur` scoped to the tight `welcomeContent` bounds (before expanding to full
        // window frame) avoids running a full-window Gaussian blur during the 120fps exit flight.
        welcomeContent
          .opacity(isExiting ? 0 : 1)
          .blur(radius: isExiting && !reduceMotion ? 10 : 0)
          .scaleEffect(isExiting && !reduceMotion ? 0.94 : 1.0)
          .offset(y: isExiting && !reduceMotion ? -14 : 0)
          .animation(
            phaseAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.28)),
            value: isExiting
          )
          .frame(width: size.width, height: size.height)

        // Continuous Living Hero Brand Mark:
        // Pulls out of cinema blur in the center → glides up with optical focus shimmer to perch
        // above `Meet Snapzy.` → leads a silky arc straight into the 26×26 top-left onboarding logo.
        heroMark(in: size)

        // Top-right adaptive close button
        closeButton
          .frame(width: size.width, height: size.height)
          .opacity(isExiting ? 0 : 1)
          .animation(phaseAnimation(.easeOut(duration: 0.18)), value: isExiting)
      }
      .frame(width: size.width, height: size.height)
    }
    .allowsHitTesting(!isExiting)
    .task {
      await playTimeline()
    }
    .onChange(of: externalStartTrigger) { _ in
      triggerStart(allowEarly: true)
    }
    .onDisappear {
      SnapzyOnboardingWelcomeAudio.shared.stopAmbient(fadeDuration: 1.25)
    }
  }

  /// Renders the living aurora + photographic grain inside a GPU-cached surface that freezes at
  /// its exact live frame on exit and exhales/dissolves smoothly into Dark Liquid Glass.
  private func dissolvingAuroraSurface(in windowSize: CGSize) -> some View {
    let shouldDrift = !reduceMotion && !isExiting
    let windowShape = Radius.rect(SnapzyRadius.window)
    let exitT = reduceMotion ? 0 : max(0, min(1, auroraExitProgress))
    let exitOpacity = reduceMotion ? reduceMotionOpacity : Double(1.0 - exitT)

    return ZStack {
      WelcomeAuroraBackdrop(drifts: shouldDrift)
      WelcomeFilmGrainOverlay()
        .allowsHitTesting(false)

      if !isFlooded {
        WelcomeOrbSwirlCore(progress: portalProgress, drifts: shouldDrift)
          .allowsHitTesting(false)
      }
    }
    .frame(width: windowSize.width, height: windowSize.height)
    .drawingGroup(opaque: isFlooded)
    .modifier(WelcomeLiquidPortalModifier(
      progress: portalProgress,
      isFullyOpen: isFlooded,
      drifts: shouldDrift
    ))
    .scaleEffect(1.0 + 0.055 * exitT)
    .clipShape(windowShape)
    .overlay {
      windowShape.strokeBorder(
        LinearGradient(
          colors: [
            Color.white.opacity(isFlooded ? 0.30 : 0.14),
            Color.white.opacity(isFlooded ? 0.08 : 0.05),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        ),
        lineWidth: LiquidGlassTokens.specularLineWidth
      )
      .allowsHitTesting(false)
    }
    .opacity(exitOpacity)
  }

  // MARK: - Living Hero Brand Mark (Center Blur Reveal → Hero Perch → Top-Left Logo Dock)

  private func heroMark(in windowSize: CGSize) -> some View {
    Image("WelcomeMark")
      .resizable()
      .interpolation(.high)
      .aspectRatio(contentMode: .fit)
      .modifier(
        WelcomeHeroMarkFlightModifier(
          elevation: markElevation,
          dockProgress: logoMorphProgress,
          markIn: markIn,
          markBreathing: markBreathing && !isExiting,
          windowSize: windowSize,
          targetLogoFrame: targetLogoFrame,
          reduceMotion: reduceMotion
        )
      )
      .opacity(reduceMotionOpacity)
      .allowsHitTesting(false)
  }

  private var dockArrivalRing: some View {
    let clamped = max(0, min(1, dockRingProgress))
    let diameter = 18 + 26 * clamped
    let opacity = 0.62 * Double(pow(1.0 - clamped, 1.5))
    return Circle()
      .strokeBorder(
        LinearGradient(
          colors: [
            Color.white.opacity(opacity),
            SnapzyWelcomePalette.skyAzure.color.opacity(opacity * 0.85),
          ],
          startPoint: .top,
          endPoint: .bottom
        ),
        lineWidth: 1.0
      )
      .frame(width: diameter, height: diameter)
  }

  // MARK: - Hero Content (Arc Focus-Pull Wave + Subtitle + Jewel Arrow Button)

  private var welcomeContent: some View {
    VStack(spacing: 0) {
      // Reserves clean optical space directly above `Meet Snapzy.` for the elevated 56×56 Hero Mark
      Spacer()
        .frame(height: 76)

      WelcomeFocusWaveHeadline(
        tokens: headlineTokens,
        revealedWordCount: revealedWordCount,
        periodRevealed: periodRevealed,
        reduceMotion: reduceMotion
      )

      Text(L10n.Onboarding.welcomeSubtitle)
        .font(.system(size: 16.5, weight: .medium))
        .tracking(-0.15)
        .foregroundStyle(Color.white.opacity(0.90))
        .multilineTextAlignment(.center)
        .frame(maxWidth: 460)
        .shadow(color: SnapzyWelcomePalette.cobaltShadow.opacity(0.28), radius: 14, y: 3)
        .padding(.top, 14)
        .opacity(subtitleIn ? 1 : 0)
        .blur(radius: reduceMotion ? 0 : (subtitleIn ? 0 : 12))
        .offset(y: reduceMotion ? 0 : (subtitleIn ? 0 : 7))
        .animation(phaseAnimation(.timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.72)), value: subtitleIn)

      SnapzyWelcomeArrowButton(
        isRevealed: ctaIn,
        reduceMotion: reduceMotion,
        action: { triggerStart(allowEarly: false) }
      )
      .padding(.top, 30)
    }
    .padding(.horizontal, SnapzyOnboardingMetrics.gutter)
  }

  // MARK: - Adaptive Close Button

  private var closeButton: some View {
    VStack {
      HStack {
        Spacer()
        WelcomeCloseButton(flooded: isFlooded, reduceMotion: reduceMotion, action: onClose)
      }
      Spacer()
    }
    .padding(.trailing, SnapzyOnboardingMetrics.gutter - 10)
    .padding(.top, SnapzyOnboardingMetrics.gutter - 10)
  }

  // MARK: - Choreography Timeline

  @MainActor
  private func playTimeline() async {
    guard !hasStarted else { return }
    hasStarted = true

    let tokenCount = headlineTokens.words.count

    SnapzyOnboardingWelcomeAudio.shared.playWelcomeScore(reducedMotion: reduceMotion)

    if reduceMotion {
      portalProgress = 1.0
      isFlooded = true
      markIn = true
      markElevation = 1.0
      revealedWordCount = tokenCount
      periodRevealed = true
      subtitleIn = true
      ctaIn = true
      onReadyForPrewarm()
      return
    }

    // Beat 1: Organic liquid-aurora orb blooms smoothly out of the midnight-cobalt void
    withAnimation(.timingCurve(0.16, 1.0, 0.3, 1.0, duration: 1.25)) {
      portalProgress = 0.27
    }

    // Brief calm hover beat so the liquid orb breathes smoothly
    guard await sleepSeconds(1.45) else { return }

    // Beat 2: The orb itself seamlessly unfolds and floods outward edge-to-edge into the window
    withAnimation(.timingCurve(0.32, 0.04, 0.16, 1.0, duration: 1.35)) {
      portalProgress = 1.0
    }

    // Beat 3: Solo white Snapzy mark pulls out of deep optical cinema blur in the dead center
    guard await sleepSeconds(0.85) else { return }
    markIn = true

    guard await sleepSeconds(0.50) else { return }
    isFlooded = true
    markBreathing = true

    // Beat 4: Hold calm solo beat, then glide the mark gracefully upward through a soft optical
    // rack-focus blur shimmer to perch right above `Meet Snapzy.` (staying visible on hero!).
    guard await sleepSeconds(0.95) else { return }
    withAnimation(.timingCurve(0.22, 0.0, 0.12, 1.0, duration: 0.90)) {
      markElevation = 1.0
    }

    // Beat 5: Arc signature word-by-word optical focus-pull wave unfolds directly beneath the logo
    guard await sleepSeconds(0.24) else { return }
    for index in 1...max(tokenCount, 1) {
      revealedWordCount = index
      if index < tokenCount {
        guard await sleepSeconds(0.14) else { return }
      }
    }

    // Trailing period lands a crisp beat after the last word
    if headlineTokens.trailingPunctuation != nil {
      guard await sleepSeconds(0.18) else { return }
      periodRevealed = true
    }

    // Beat 6: Subtitle focuses gently into place
    guard await sleepSeconds(0.22) else { return }
    subtitleIn = true

    // Beat 7: Editorial arrow button materializes + quietly pre-warm Step 1 behind the aurora
    guard await sleepSeconds(0.30) else { return }
    ctaIn = true
    onReadyForPrewarm()
  }

  private func sleepSeconds(_ seconds: Double) async -> Bool {
    do {
      try await Task.sleep(for: .seconds(seconds))
      return !Task.isCancelled
    } catch {
      return false
    }
  }

  private func triggerStart(allowEarly: Bool = false) {
    guard (ctaIn || allowEarly), !isExiting else { return }
    isExiting = true
    // Ensure opening portal & hero mark are ready if triggered early via Return/Esc
    portalProgress = 1.0
    isFlooded = true
    markIn = true
    markElevation = 1.0
    SnapzyOnboardingWelcomeAudio.shared.playConfirmChime()

    if reduceMotion {
      onReadyForPrewarm()
      onBeginTransition()
      onDockLogo()
      withAnimation(.easeOut(duration: 0.24)) {
        reduceMotionOpacity = 0.0
      }
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(250))
        onCompleteTransition()
      }
      return
    }

    onReadyForPrewarm()

    Task { @MainActor in
      // Beat 1: Headline & arrow pill softly rack-focus out while the blue aurora exhales cleanly
      // into Dark Liquid Glass AND the perched white logo crystallizes into the gleaming Snapzy
      // App Icon squircle, gliding along one silky C∞ arc straight into the 26×26 top-left slot.
      try? await Task.sleep(for: .milliseconds(25))
      withAnimation(.timingCurve(0.22, 0.0, 0.16, 1.0, duration: 0.58)) {
        auroraExitProgress = 1.0
      }
      withAnimation(.timingCurve(0.22, 0.0, 0.10, 1.0, duration: 0.94)) {
        logoMorphProgress = 1.0
      }

      // Beat 2: Right as the blue veil turns translucent, bloom the pre-warmed Liquid Glass Step 1
      // workspace seamlessly beneath the gliding Snapzy icon.
      try? await Task.sleep(for: .milliseconds(70))
      onBeginTransition()

      // Beat 3: On exact landing (t = 1.0), lock in the pixel-identical real brand icon beneath
      // and expand one crisp 1pt optical hairline ring as the "Snapzy" wordmark unfolds beside it.
      try? await Task.sleep(for: .milliseconds(875))
      onDockLogo()
      withAnimation(.timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.40)) {
        dockRingProgress = 1.0
      }

      try? await Task.sleep(for: .milliseconds(420))
      onCompleteTransition()
    }
  }
}

// MARK: - Continuous Living Hero Mark → Crystallized App Icon Dock (Pure GPU 120fps)

/// Drives the visible white Snapzy `WelcomeMark` across two unbroken, harmonious beats:
/// 1. `elevation` (0 → 1): glides from dead center (`84pt`) up to its hero perch above `Meet Snapzy.`
///    (`56pt`) through a silky rack-focus cinema blur shimmer.
/// 2. `dockProgress` (0 → 1): as the full-window blue aurora exhales & dissolves into Dark Liquid
///    Glass, the crisp Snapzy App Icon squircle crystallizes effortlessly right behind the white
///    mark and glides as a single gleaming icon along a weightless upward-left arc straight into
///    the `26×26` top-left onboarding brand logo — zero shrinking-background clutter.
private struct WelcomeHeroMarkFlightModifier: ViewModifier, Animatable {
  var elevation: CGFloat
  var dockProgress: CGFloat
  let markIn: Bool
  let markBreathing: Bool
  let windowSize: CGSize
  let targetLogoFrame: CGRect
  let reduceMotion: Bool

  var animatableData: AnimatablePair<CGFloat, CGFloat> {
    get { AnimatablePair(elevation, dockProgress) }
    set {
      elevation = newValue.first
      dockProgress = newValue.second
    }
  }

  private static func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
    let t = max(0, min(1, (x - edge0) / max(0.0001, edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)
  }

  func body(content: Content) -> some View {
    let e = max(0, min(1, elevation))
    let d = reduceMotion ? 0 : max(0, min(1, dockProgress))

    // Beat A: Center (84pt) → Hero Perch directly above `Meet Snapzy.` (56pt)
    let centerX = windowSize.width * 0.5
    let centerY = windowSize.height * 0.5
    let heroY = centerY - 94
    let perchY = centerY + (heroY - centerY) * e
    let perchSize: CGFloat = 84 + (56 - 84) * e

    // Beat B: Weightless curved arc from Hero Perch straight into the 26×26 top-left brand icon
    let targetW = max(16, targetLogoFrame.width)
    let targetX = targetLogoFrame.midX
    let targetY = targetLogoFrame.midY
    let arcSine = sin(d * .pi)
    let currentX = centerX + (targetX - centerX) * d - 20 * arcSine
    let currentY = perchY + (targetY - perchY) * d - 28 * arcSine

    // Icon squircle crystallizes seamlessly around the white mark as the blue aurora dissolves
    let iconCrystallize = Double(Self.smoothstep(0.02, 0.28, d))
    let markCrossfadeOut = Double(Self.smoothstep(0.14, 0.34, d))
    let markOpacity = 1.0 - markCrossfadeOut

    // Continuous size: 62pt crystallized icon squircle → exact 26pt docked brand icon
    let startIconSize: CGFloat = 62
    let currentIconSize = startIconSize + (targetW - startIconSize) * d
    let currentIconRadius = Radius.card + (Radius.controlS - Radius.card) * d
    let iconShape = RoundedRectangle(cornerRadius: currentIconRadius, style: .continuous) // radius-lint:allow — continuous interpolation between Radius.card and Radius.controlS

    // White WelcomeMark shrinks gracefully inside the crystallizing squircle so it aligns with
    // the real macOS app icon's own white glyph (`~56%` of icon box) during cross-dissolve.
    let insideIconMarkSize = currentIconSize * 0.56
    let settleBlend = Self.smoothstep(0.0, 0.30, d)
    let currentMarkSize = perchSize + (insideIconMarkSize - perchSize) * settleBlend

    // Optical rack-focus blur shimmer scoped ONLY to the tiny logo bounds (< 0.08 ms GPU cost)
    let elevationBlur = reduceMotion ? 0 : sin(e * .pi) * 6.0
    let flightBlur = reduceMotion ? 0 : arcSine * 1.8
    let revealBlur: CGFloat = reduceMotion ? 0 : (markIn ? 0 : 28)
    let motionBlur = d > 0.001 ? flightBlur : elevationBlur
    let breatheScale: CGFloat = reduceMotion ? 1.0 : (markBreathing ? 1.03 : (markIn ? 1.0 : 0.80))

    ZStack {
      // Crystallized real macOS Snapzy App Icon gliding straight to the top-left header slot
      if iconCrystallize > 0.004 {
        Image(nsImage: SnapzyOnboardingIconCache.appIcon)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fit)
          .frame(width: currentIconSize, height: currentIconSize)
          .clipShape(iconShape)
          .overlay {
            iconShape.strokeBorder(
              LinearGradient(
                colors: [
                  Color.white.opacity(0.32 * Double(arcSine)),
                  Color.white.opacity(0.06 * Double(arcSine)),
                ],
                startPoint: .top,
                endPoint: .bottom
              ),
              lineWidth: 0.6
            )
            .allowsHitTesting(false)
          }
          // Constant shadow radius with opacity-only modulation keeps 120fps free of kernel rebuilds
          .shadow(
            color: Color.black.opacity(0.36 * Double(arcSine)),
            radius: 16,
            x: 0,
            y: 7
          )
          .scaleEffect(0.88 + 0.12 * CGFloat(iconCrystallize))
          .opacity(iconCrystallize)
      }

      // Crisp white Snapzy WelcomeMark dissolving seamlessly into the icon's own white mark
      if markOpacity > 0.004 {
        content
          .frame(width: currentMarkSize, height: currentMarkSize)
          .shadow(
            color: SnapzyWelcomePalette.cobaltShadow.opacity(0.28 * markOpacity),
            radius: 16,
            y: 6
          )
          .shadow(
            color: Color.white.opacity(0.24 * markOpacity),
            radius: 8,
            y: 0
          )
          .blur(radius: revealBlur)
          .scaleEffect(breatheScale)
          .opacity(markIn ? markOpacity : 0)
          .animation(reduceMotion ? nil : .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.92), value: markIn)
          .animation(reduceMotion ? nil : .easeInOut(duration: 1.50), value: markBreathing)
      }
    }
    .blur(radius: motionBlur)
    .position(x: currentX, y: currentY)
  }
}

// MARK: - Seamless Liquid Portal (Organic Morphing Orb → Full-Bleed Aurora)

/// Reveals the living aurora through an organic, softly-blurred 3-lobe morphing silhouette
/// (recreating Arc's asymmetric liquid cloud) that smoothly relaxes and expands past all four
/// corners into the full-bleed window.
private struct WelcomeLiquidPortalModifier: ViewModifier, Animatable {
  var progress: CGFloat
  let isFullyOpen: Bool
  let drifts: Bool

  var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    if isFullyOpen || progress >= 0.999 {
      content
    } else {
      let clamped = max(0, min(1, progress))
      let organicAmount = max(0, 1 - max(0, (clamped - 0.27) / 0.45))
      // Crisp, silky backlit-plasma feather (20pt instead of muddy 38pt) so internal fluid caustics
      // stay luminous and sculpted instead of washing out into fog.
      let featherBlur = 20 * organicAmount

      content.mask {
        Group {
          if drifts {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
              portalCanvas(at: context.date.timeIntervalSinceReferenceDate)
            }
          } else {
            portalCanvas(at: 0)
          }
        }
        .blur(radius: featherBlur)
      }
    }
  }

  private func portalCanvas(at time: TimeInterval) -> some View {
    Canvas { context, size in
      let clamped = max(0, min(1, progress))
      guard clamped > 0.001 else { return }

      let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
      let maxDiagonal = hypot(size.width, size.height) * 0.65

      // Commanding, breathing organic emergence up to 0.27, then sweeping liquid surge edge-to-edge
      let organicAmount = max(0, 1 - max(0, (clamped - 0.27) / 0.48))
      let breathe: CGFloat = drifts ? (1.0 + CGFloat(sin(time * 2.35)) * 0.042 * organicAmount) : 1.0
      let orbRadius: CGFloat = 154 * breathe
      let radius: CGFloat
      if clamped <= 0.27 {
        let localT = clamped / 0.27
        radius = orbRadius * localT
      } else {
        let floodT = (clamped - 0.27) / 0.73
        let eased = floodT * floodT * (3 - 2 * floodT)
        radius = orbRadius + (maxDiagonal * 1.45 - orbRadius) * eased
      }

      let path = Self.organicBlobPath(
        center: center,
        radius: radius,
        organicAmount: organicAmount,
        time: drifts ? time : 0.8
      )

      context.fill(path, with: .color(.white))

      // Smooth full-canvas seal as progress finishes so all four corners reach pure 1.0 opacity
      if clamped > 0.72 {
        let sealOpacity = Double((clamped - 0.72) / 0.28)
        context.fill(
          Path(CGRect(origin: .zero, size: size)),
          with: .color(.white.opacity(sealOpacity))
        )
      }
    }
  }

  /// Smooth 36-segment closed quadratic spline sculpted by 4 lively polar harmonics — creates a
  /// genuinely fluid, undulating zero-gravity liquid-aurora silhouette.
  static func organicBlobPath(
    center: CGPoint,
    radius: CGFloat,
    organicAmount: CGFloat,
    time: TimeInterval
  ) -> Path {
    let steps = 36
    let t = Double(time)
    var pts: [CGPoint] = []
    pts.reserveCapacity(steps)

    for i in 0..<steps {
      let theta = (Double(i) / Double(steps)) * (.pi * 2.0)
      let wave =
        0.155 * sin(3.0 * theta + t * 1.55)
        + 0.110 * cos(2.0 * theta - t * 1.15 + 0.8)
        + 0.065 * sin(4.0 * theta + t * 2.05 + 1.7)
        + 0.035 * cos(5.0 * theta - t * 1.75 + 2.6)
      let r = radius * (1.0 + CGFloat(wave) * organicAmount)
      pts.append(CGPoint(
        x: center.x + CGFloat(cos(theta)) * r,
        y: center.y + CGFloat(sin(theta)) * r
      ))
    }

    var path = Path()
    guard let last = pts.last, let first = pts.first else { return path }
    let startMid = CGPoint(x: (last.x + first.x) * 0.5, y: (last.y + first.y) * 0.5)
    path.move(to: startMid)

    for i in 0..<steps {
      let current = pts[i]
      let next = pts[(i + 1) % steps]
      let mid = CGPoint(x: (current.x + next.x) * 0.5, y: (current.y + next.y) * 0.5)
      path.addQuadCurve(to: mid, control: current)
    }
    path.closeSubpath()
    return path
  }
}

/// Living multi-lobe atmospheric corona warming the midnight void around the awakening orb.
/// Three gently counter-orbiting azure & crystalline-sky light clouds breathe with the orb and
/// dissolve cleanly as the full-window aurora floods outward.
private struct WelcomeOrbAmbientAura: View, Animatable {
  var progress: CGFloat
  let drifts: Bool

  var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  var body: some View {
    let clamped = max(0, min(1, progress))
    let fadeIn = min(1.0, clamped / 0.22)
    let fadeOut = 1.0 - max(0, min(1, (clamped - 0.32) / 0.42))
    let opacity = Double(fadeIn * fadeOut)

    Group {
      if drifts {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
          corona(at: context.date.timeIntervalSinceReferenceDate, clamped: clamped, opacity: opacity)
        }
      } else {
        corona(at: 0.8, clamped: clamped, opacity: opacity)
      }
    }
  }

  private func corona(at time: TimeInterval, clamped: CGFloat, opacity: Double) -> some View {
    let breathe = 1.0 + sin(time * 2.1) * 0.055
    let orbit1X = cos(time * 1.15) * 48
    let orbit1Y = sin(time * 0.95) * 40
    let orbit2X = cos(-time * 0.90 + 2.2) * 54
    let orbit2Y = sin(-time * 1.10 + 1.4) * 44

    return ZStack {
      // Deep wide electric-azure atmospheric bed
      Circle()
        .fill(
          RadialGradient(
            stops: [
              .init(color: SnapzyWelcomePalette.brandAzure.color.opacity(0.44 * opacity), location: 0.0),
              .init(color: SnapzyWelcomePalette.brandCobalt.color.opacity(0.20 * opacity), location: 0.46),
              .init(color: .clear, location: 1.0),
            ],
            center: .center,
            startRadius: 0,
            endRadius: 320
          )
        )
        .frame(width: 640, height: 640)
        .scaleEffect(breathe)

      // Orbiting luminous sky-cyan light cloud
      Circle()
        .fill(
          RadialGradient(
            stops: [
              .init(color: Color(red: 0.40, green: 0.72, blue: 1.0).opacity(0.34 * opacity), location: 0.0),
              .init(color: SnapzyWelcomePalette.skyAzure.color.opacity(0.12 * opacity), location: 0.52),
              .init(color: .clear, location: 1.0),
            ],
            center: .center,
            startRadius: 0,
            endRadius: 210
          )
        )
        .frame(width: 420, height: 420)
        .offset(x: orbit1X, y: orbit1Y)

      // Counter-orbiting vibrant periwinkle-indigo depth halo
      Circle()
        .fill(
          RadialGradient(
            stops: [
              .init(color: Color(red: 0.30, green: 0.40, blue: 1.0).opacity(0.32 * opacity), location: 0.0),
              .init(color: SnapzyWelcomePalette.radiantAzure.color.opacity(0.10 * opacity), location: 0.55),
              .init(color: .clear, location: 1.0),
            ],
            center: .center,
            startRadius: 0,
            endRadius: 220
          )
        )
        .frame(width: 440, height: 440)
        .offset(x: orbit2X, y: orbit2Y)
    }
    .scaleEffect(0.86 + clamped * 1.25)
  }
}

/// High-chroma living liquid plasma inside the opening organic orb: a fold-free 4×4 iridescent
/// azure-sky-white swirling mesh layered with counter-rotating luminous silk caustic currents
/// (`.screen` blend) for unmistakable 3D fluid vitality. Dissolves seamlessly into the full-window
/// 5×5 aurora as the portal surges outward.
private struct WelcomeOrbSwirlCore: View, Animatable {
  var progress: CGFloat
  let drifts: Bool

  var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  var body: some View {
    let clamped = max(0, min(1, progress))
    // Dissolve completely before the portal reaches half-screen so no circular halo ever lingers
    let dissolve = 1.0 - max(0, min(1, (clamped - 0.26) / 0.22))
    let expansionScale = 1.0 + max(0, clamped - 0.27) * 1.85

    Group {
      if drifts {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
          livingFluidCore(at: context.date.timeIntervalSinceReferenceDate)
        }
      } else {
        livingFluidCore(at: 0.8)
      }
    }
    .frame(width: 460, height: 460)
    .mask {
      Circle()
        .fill(
          RadialGradient(
            stops: [
              .init(color: .white, location: 0.0),
              .init(color: .white.opacity(0.92), location: 0.50),
              .init(color: .clear, location: 1.0),
            ],
            center: .center,
            startRadius: 0,
            endRadius: 230
          )
        )
    }
    .scaleEffect(expansionScale)
    .opacity(Double(dissolve * dissolve))
  }

  private func livingFluidCore(at time: TimeInterval) -> some View {
    ZStack {
      swirlField(at: time)

      // Counter-rotating luminous silk caustic ribbons flowing inside the liquid orb
      causticRibbons(at: time)
        .blur(radius: 14)
        .blendMode(.screen)
        .opacity(0.82)
    }
  }

  @ViewBuilder
  private func swirlField(at time: TimeInterval) -> some View {
    if #available(macOS 15.0, *) {
      let t = Float(time)
      // Fold-free 4×4 mesh (spacing 0.333, max sway 0.055 → min gap ≥ 0.22) for rich fluid depth
      let p11x = 0.333 + sin(t * 1.35) * 0.052
      let p11y = 0.333 + cos(t * 1.18 + 0.5) * 0.052
      let p12x = 0.667 + cos(t * 1.28 + 1.4) * 0.052
      let p12y = 0.333 + sin(t * 1.42 + 0.9) * 0.052
      let p21x = 0.333 + cos(t * 1.15 + 2.3) * 0.052
      let p21y = 0.667 + sin(t * 1.30 + 1.8) * 0.052
      let p22x = 0.667 + sin(t * 1.24 + 3.1) * 0.052
      let p22y = 0.667 + cos(t * 1.38 + 2.5) * 0.052

      let electricCyan = Color(red: 0.42, green: 0.78, blue: 1.00)
      let vibrantIndigo = Color(red: 0.25, green: 0.36, blue: 1.00)

      MeshGradient(
        width: 4,
        height: 4,
        points: [
          [0.0, 0.0], [0.333, 0.0], [0.667, 0.0], [1.0, 0.0],
          [0.0, 0.333], [p11x, p11y], [p12x, p12y], [1.0, 0.333],
          [0.0, 0.667], [p21x, p21y], [p22x, p22y], [1.0, 0.667],
          [0.0, 1.0], [0.333, 1.0], [0.667, 1.0], [1.0, 1.0],
        ],
        colors: [
          SnapzyWelcomePalette.pureLight.color,
          electricCyan,
          SnapzyWelcomePalette.brandAzure.color,
          vibrantIndigo,
          SnapzyWelcomePalette.brandCobalt.color,
          SnapzyWelcomePalette.pureLight.color,
          electricCyan,
          SnapzyWelcomePalette.icePocket.color,
          vibrantIndigo,
          SnapzyWelcomePalette.brandAzure.color,
          SnapzyWelcomePalette.pureLight.color,
          SnapzyWelcomePalette.skyAzure.color,
          SnapzyWelcomePalette.brandCobalt.color,
          SnapzyWelcomePalette.icePocket.color,
          electricCyan,
          SnapzyWelcomePalette.pureLight.color,
        ],
        smoothsColors: true
      )
      .rotationEffect(.degrees(time * 34))
    } else {
      AngularGradient(
        colors: [
          SnapzyWelcomePalette.pureLight.color,
          Color(red: 0.42, green: 0.78, blue: 1.00),
          SnapzyWelcomePalette.brandCobalt.color,
          SnapzyWelcomePalette.icePocket.color,
          SnapzyWelcomePalette.brandAzure.color,
          SnapzyWelcomePalette.pureLight.color,
        ],
        center: .center,
        angle: .degrees(time * 34)
      )
      .blur(radius: 28)
    }
  }

  /// Sweeping translucent white & ice-cyan internal light currents rotating in counter-motion to
  /// give the opening orb luminous 3D liquid refraction and vitality.
  private func causticRibbons(at time: TimeInterval) -> some View {
    Canvas { context, size in
      let cx = size.width * 0.5
      let cy = size.height * 0.5
      let r = min(size.width, size.height) * 0.28

      // Ribbon 1: Bright silk-white S-arc gliding across the upper-left to lower-right hemisphere
      let a1 = time * 1.45
      var p1 = Path()
      p1.move(to: CGPoint(x: cx + cos(a1) * r * 1.15, y: cy + sin(a1) * r * 1.15))
      p1.addCurve(
        to: CGPoint(x: cx + cos(a1 + .pi * 0.92) * r * 1.10, y: cy + sin(a1 + .pi * 0.92) * r * 1.10),
        control1: CGPoint(x: cx + cos(a1 + 0.9) * r * 0.75, y: cy + sin(a1 + 0.9) * r * 0.75),
        control2: CGPoint(x: cx + cos(a1 - 0.8) * r * 0.68, y: cy + sin(a1 - 0.8) * r * 0.68)
      )
      context.stroke(
        p1,
        with: .color(Color.white.opacity(0.68)),
        style: StrokeStyle(lineWidth: 26, lineCap: .round)
      )

      // Ribbon 2: Counter-sweeping crystalline sky-cyan caustic filament
      let a2 = -time * 1.15 + 1.9
      var p2 = Path()
      p2.move(to: CGPoint(x: cx + cos(a2) * r * 1.05, y: cy + sin(a2) * r * 1.05))
      p2.addCurve(
        to: CGPoint(x: cx + cos(a2 + .pi * 1.05) * r * 1.00, y: cy + sin(a2 + .pi * 1.05) * r * 1.00),
        control1: CGPoint(x: cx + cos(a2 - 1.1) * r * 0.82, y: cy + sin(a2 - 1.1) * r * 0.82),
        control2: CGPoint(x: cx + cos(a2 + 1.2) * r * 0.64, y: cy + sin(a2 + 1.2) * r * 0.64)
      )
      context.stroke(
        p2,
        with: .color(Color(red: 0.52, green: 0.86, blue: 1.0).opacity(0.62)),
        style: StrokeStyle(lineWidth: 22, lineCap: .round)
      )

      // Ribbon 3: Crisp luminous highlight pocket drifting near the rim
      let a3 = time * 1.85 + 3.4
      let highlightCenter = CGPoint(
        x: cx + cos(a3) * r * 0.56,
        y: cy + sin(a3) * r * 0.56
      )
      let highlightRect = CGRect(x: highlightCenter.x - 42, y: highlightCenter.y - 30, width: 84, height: 60)
      context.fill(Path(ellipseIn: highlightRect), with: .color(Color.white.opacity(0.55)))
    }
  }
}

// MARK: - Living 5x5 Fold-Free Fluid Aurora Backdrop (Zero Seams, Zero Creases)

/// Pure 5x5 MeshGradient on macOS 15+ using a strictly monotonic, non-folding vertex grid
/// (maximum vertex sway 0.032 on 0.25 spacing → guaranteed minimum spacing ≥ 0.186 so Coons
/// patches can NEVER fold or form a hard dividing crease at any timestamp).
private struct WelcomeAuroraBackdrop: View {
  var drifts: Bool

  var body: some View {
    if #available(macOS 15.0, *) {
      WelcomeMesh5x5Backdrop(drifts: drifts)
    } else {
      WelcomeLegacyAuroraBackdrop(drifts: drifts)
    }
  }
}

/// Tracks the live aurora clock without triggering SwiftUI state invalidations so pausing drift
/// on exit freezes at the exact current frame with zero visual jump.
private final class WelcomeAuroraClock {
  var lastTime: TimeInterval = 2.1
}

@available(macOS 15.0, *)
private struct WelcomeMesh5x5Backdrop: View {
  var drifts: Bool
  @State private var clock = WelcomeAuroraClock()

  // Luminous radiant Snapzy electric-azure → pure silk-white ramp: eliminates dark navy pockets
  // and keeps the vibrant mid-electric blue surrounding the core flowing smoothly into bright mist.
  private static let paletteRamp: [WelcomeRGB] = [
    SnapzyWelcomePalette.brandCobalt,         // #2A58FF radiant electric blue (no dark navy!)
    SnapzyWelcomePalette.brandAzure,          // #3C66FF luminous Snapzy azure
    SnapzyWelcomePalette.radiantAzure,        // #527DFF airy electric periwinkle
    SnapzyWelcomePalette.skyAzure,            // #759FFF bright sky azure
    SnapzyWelcomePalette.mistBlue,            // #B3D2FF crystalline mist
    SnapzyWelcomePalette.icePocket,           // crisp ice mist
    SnapzyWelcomePalette.pureLight,           // pure silk white peak
  ]

  // Uniform 5×5 base lattice (row-major, step = 0.25).
  private static let bases: [SIMD2<Float>] = {
    var grid: [SIMD2<Float>] = []
    grid.reserveCapacity(25)
    for row in 0..<5 {
      for col in 0..<5 {
        grid.append(SIMD2<Float>(Float(col) * 0.25, Float(row) * 0.25))
      }
    }
    return grid
  }()

  // Strictly bounded gentle vertex motion (≤ 0.030 on a 0.25 cell) guarantees the bicubic
  // surface remains 100% diffeomorphic (no creases, no folds, no dividing lines ever).
  static func points(at time: TimeInterval) -> [SIMD2<Float>] {
    let t = Float(time)
    var result: [SIMD2<Float>] = []
    result.reserveCapacity(25)

    for row in 0..<5 {
      for col in 0..<5 {
        let base = bases[row * 5 + col]
        let isLeftOrRightEdge = (col == 0 || col == 4)
        let isTopOrBottomEdge = (row == 0 || row == 4)

        let phase = Float(row * 5 + col) * 0.73
        let dx: Float = isLeftOrRightEdge ? 0 : sin(t * 0.85 + phase) * 0.030
        let dy: Float = isTopOrBottomEdge ? 0 : cos(t * 0.74 + phase * 1.29) * 0.030

        result.append([base.x + dx, base.y + dy])
      }
    }
    return result
  }

  /// Evaluates a vivid, briskly-flowing rotating two-wave silk field across the fold-free 5×5
  /// lattice so bold pure-white clouds and rich Snapzy electric-cobalt rivers sweep continuously
  /// and blend seamlessly with zero seams, while keeping vivid cobalt contrast behind center text.
  static func colors(at time: TimeInterval, points: [SIMD2<Float>]) -> [Color] {
    let t = time
    let theta1 = t * 0.56
    let cos1 = cos(theta1)
    let sin1 = sin(theta1)

    let theta2 = -t * 0.40 + 1.4
    let cos2 = cos(theta2)
    let sin2 = sin(theta2)

    var result: [Color] = []
    result.reserveCapacity(points.count)

    for pt in points {
      let dx = Double(pt.x) - 0.5
      let dy = Double(pt.y) - 0.5

      // Brisk, sweeping primary silk ribbon
      let u = dx * cos1 + dy * sin1
      let wave1 = sin(u * 2.55 + t * 1.15)

      // Counter-flowing harmonic swell creating organic luminous white pockets
      let v = dx * cos2 + dy * sin2
      let wave2 = cos(v * 2.05 - t * 0.85 + 0.7)

      // Full-range amplitude reaches both deep electric cobalt (0.0) and luminous silk white (1.0)
      let raw = 0.46 + 0.46 * wave1 + 0.28 * wave2
      var field = max(0.0, min(1.0, raw))

      // Keep the center typography zone anchored in radiant electric blue (≤ 0.34) so white text
      // stays crisp while bright silk-white clouds sweep boldly around all four flanks and corners.
      let nx = dx / 0.34
      let ny = dy / 0.24
      let centerProximity = exp(-(nx * nx + ny * ny) * 1.25)
      let maxCenterField = 0.34
      if field > maxCenterField {
        field -= (field - maxCenterField) * centerProximity * 0.90
      }

      result.append(sampleRamp(at: field))
    }
    return result
  }

  private static func sampleRamp(at t: Double) -> Color {
    let clamped = max(0.0, min(1.0, t))
    let scaled = clamped * Double(paletteRamp.count - 1)
    let index = min(Int(scaled), paletteRamp.count - 2)
    let frac = scaled - Double(index)
    return WelcomeRGB.mix(paletteRamp[index], paletteRamp[index + 1], frac).color
  }

  var body: some View {
    if drifts {
      TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
        let t = context.date.timeIntervalSinceReferenceDate
        let _ = (clock.lastTime = t)
        mesh(at: t)
      }
    } else {
      mesh(at: clock.lastTime)
    }
  }

  private func mesh(at time: TimeInterval) -> some View {
    let livePoints = Self.points(at: time)
    return MeshGradient(
      width: 5,
      height: 5,
      points: livePoints,
      colors: Self.colors(at: time, points: livePoints),
      smoothsColors: true
    )
  }
}

/// Pre-MeshGradient fallback for macOS 13–14 with matching Snapzy electric-cobalt & white clouds.
private struct WelcomeLegacyAuroraBackdrop: View {
  var drifts: Bool

  var body: some View {
    GeometryReader { geo in
      ZStack {
        LinearGradient(
          colors: [
            SnapzyWelcomePalette.brandCobalt.color,
            SnapzyWelcomePalette.brandAzure.color,
            SnapzyWelcomePalette.radiantAzure.color,
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )

        if drifts {
          TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            clouds(at: context.date.timeIntervalSinceReferenceDate, size: geo.size)
          }
        } else {
          clouds(at: 2.1, size: geo.size)
        }
      }
      .frame(width: geo.size.width, height: geo.size.height)
      .clipped()
    }
  }

  private func clouds(at time: TimeInterval, size: CGSize) -> some View {
    ZStack {
      cloud(
        SnapzyWelcomePalette.pureLight, 740,
        anchor: CGPoint(x: 0.16, y: 0.18),
        dx: sin(time * 0.46) * 240, dy: cos(time * 0.38 + 1.1) * 180, size: size
      )
      cloud(
        SnapzyWelcomePalette.icePocket, 680,
        anchor: CGPoint(x: 0.84, y: 0.82),
        dx: cos(time * 0.42 + 2.4) * 250, dy: sin(time * 0.44 + 0.6) * 190, size: size
      )
      cloud(
        SnapzyWelcomePalette.brandCobalt, 760,
        anchor: CGPoint(x: 0.52, y: 0.50),
        dx: sin(time * 0.36 + 3.2) * 160, dy: cos(time * 0.32 + 2.0) * 130, size: size
      )
      cloud(
        SnapzyWelcomePalette.mistBlue, 620,
        anchor: CGPoint(x: 0.82, y: 0.22),
        dx: sin(time * 0.50 + 4.4) * 220, dy: cos(time * 0.40 + 1.8) * 160, size: size
      )
      cloud(
        SnapzyWelcomePalette.skyAzure, 640,
        anchor: CGPoint(x: 0.22, y: 0.80),
        dx: cos(time * 0.44 + 0.9) * 220, dy: sin(time * 0.36 + 3.7) * 170, size: size
      )
    }
  }

  private func cloud(
    _ rgb: WelcomeRGB,
    _ diameter: CGFloat,
    anchor: CGPoint,
    dx: CGFloat,
    dy: CGFloat,
    size: CGSize
  ) -> some View {
    Circle()
      .fill(
        RadialGradient(
          stops: [
            .init(color: rgb.color.opacity(0.92), location: 0),
            .init(color: rgb.color.opacity(0.45), location: 0.46),
            .init(color: .clear, location: 1),
          ],
          center: .center,
          startRadius: 0,
          endRadius: diameter / 2
        )
      )
      .frame(width: diameter, height: diameter)
      .position(x: size.width * anchor.x + dx, y: size.height * anchor.y + dy)
  }
}

// MARK: - Tactile Clean Photographic Film Grain

/// Editorial monochromatic 35mm micro-grain generated once at init with a crisp 2-tap triangular
/// distribution around neutral mid-gray (128 ± 124) on a 512×512 non-repeating tile. Composited in
/// `.overlay`, giving the radiant azure aurora a distinctly rich, velvety print grain while
/// naturally attenuating near pure white so bright clouds stay clean and luminous.
private struct WelcomeFilmGrainOverlay: View {
  private static let tileImage: CGImage? = makeGrainTile(size: 512)

  var body: some View {
    if let cgImage = Self.tileImage {
      Image(decorative: cgImage, scale: 1.4)
        .resizable(resizingMode: .tile)
        .blendMode(.overlay)
        .opacity(0.32)
    }
  }

  private static func makeGrainTile(size: Int) -> CGImage? {
    var pixels = [UInt8](repeating: 128, count: size * size)
    var state: UInt64 = 0x5A92_C0B4_17E3_9D11

    @inline(__always)
    func nextByte() -> Int {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      z = z ^ (z >> 31)
      return Int(z & 0xFF)
    }

    // 2-tap triangular sum gives richer photographic grain contrast without harsh salt-and-pepper
    for i in 0..<pixels.count {
      let sum = nextByte() + nextByte()      // 0...510, mean 255
      let centered = (sum - 255) * 124 / 255 // ±124 crisp analog grain
      pixels[i] = UInt8(clamping: 128 + centered)
    }

    let data = Data(pixels)
    guard let provider = CGDataProvider(data: data as CFData) else { return nil }
    return CGImage(
      width: size,
      height: size,
      bitsPerComponent: 8,
      bitsPerPixel: 8,
      bytesPerRow: size,
      space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )
  }
}

// MARK: - Arc Signature Word-by-Word Focus-Pull Headline

private struct WelcomeHeadlineTokens {
  let words: [String]
  let trailingPunctuation: String?

  init(headline: String) {
    let trimmed = headline.trimmingCharacters(in: .whitespacesAndNewlines)
    let punctuationChars: Set<Character> = [".", "。", "!"]

    let body: String
    let trailing: String?
    if let last = trimmed.last, punctuationChars.contains(last), trimmed.count > 1 {
      body = String(trimmed.dropLast())
      trailing = String(last)
    } else {
      body = trimmed
      trailing = nil
    }

    let splitWords = body
      .split(whereSeparator: \.isWhitespace)
      .map(String.init)
    self.words = splitWords.isEmpty ? [trimmed] : splitWords
    self.trailingPunctuation = trailing
  }
}

/// Pulls each word into optical focus left-to-right with crisp, natural inter-word spacing and a
/// subtle calligraphic settle, then lands the trailing period a crisp beat later.
private struct WelcomeFocusWaveHeadline: View {
  let tokens: WelcomeHeadlineTokens
  let revealedWordCount: Int
  let periodRevealed: Bool
  let reduceMotion: Bool

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 0) {
      ForEach(Array(tokens.words.enumerated()), id: \.offset) { index, word in
        let isShown = index < revealedWordCount

        if index > 0 {
          // Explicit optical word gap so tight negative letter-tracking never crams words together
          Spacer()
            .frame(width: 15)
        }

        Text(word)
          .font(.system(size: 60, weight: .bold))
          .tracking(-1.4)
          .foregroundStyle(Color.white)
          .opacity(isShown ? 1 : 0)
          .blur(radius: reduceMotion ? 0 : (isShown ? 0 : 22))
          .scaleEffect(reduceMotion ? 1.0 : (isShown ? 1.0 : 1.07))
          .offset(y: reduceMotion ? 0 : (isShown ? 0 : 7))
          .rotationEffect(.degrees(reduceMotion ? 0 : (isShown ? 0 : -1.5)))
          .animation(
            reduceMotion ? nil : .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.78),
            value: isShown
          )
      }

      if let punctuation = tokens.trailingPunctuation {
        Text(punctuation)
          .font(.system(size: 60, weight: .bold))
          .tracking(-1.4)
          .foregroundStyle(Color.white)
          .opacity(periodRevealed ? 1 : 0)
          .blur(radius: reduceMotion ? 0 : (periodRevealed ? 0 : 14))
          .scaleEffect(reduceMotion ? 1.0 : (periodRevealed ? 1.0 : 1.42))
          .animation(
            reduceMotion ? nil : .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.56),
            value: periodRevealed
          )
      }
    }
    .multilineTextAlignment(.center)
    .shadow(color: SnapzyWelcomePalette.cobaltShadow.opacity(0.26), radius: 22, y: 5)
    .shadow(color: SnapzyWelcomePalette.cobaltShadow.opacity(0.12), radius: 6, y: 1)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(L10n.Onboarding.welcomeHeadline)
    .accessibilityAddTraits(.isHeader)
  }
}

// MARK: - Editorial Arrow Button

/// Clean, restrained macOS arrow pill matching Snapzy's white-and-cobalt identity:
/// - Rest: pure solid white pill with Snapzy cobalt arrow and a quiet grounded shadow.
/// - Hover: crisp inversion to deep velvety cobalt with pure white arrow gliding forward,
///   subtle elevation, and zero glossy domes, spotlights, or outer neon halos.
/// - Press: tight physical spring detent.
private struct SnapzyWelcomeArrowButton: View {
  let isRevealed: Bool
  let reduceMotion: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Color.clear
        .frame(width: 66, height: 38)
    }
    .buttonStyle(SnapzyWelcomeArrowPillStyle(reduceMotion: reduceMotion))
    .accessibilityLabel(Text(L10n.Onboarding.letsDoIt))
    .opacity(isRevealed ? 1 : 0)
    .blur(radius: reduceMotion ? 0 : (isRevealed ? 0 : 14))
    .scaleEffect(reduceMotion ? 1.0 : (isRevealed ? 1.0 : 0.88))
    .offset(y: reduceMotion ? 0 : (isRevealed ? 0 : 8))
    .animation(
      reduceMotion ? nil : .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.70),
      value: isRevealed
    )
    .allowsHitTesting(isRevealed)
  }
}

private struct SnapzyWelcomeArrowPillStyle: ButtonStyle {
  let reduceMotion: Bool

  func makeBody(configuration: Configuration) -> some View {
    SnapzyWelcomeArrowPillSurface(
      configuration: configuration,
      reduceMotion: reduceMotion
    )
  }
}

private struct SnapzyWelcomeArrowPillSurface: View {
  let configuration: ButtonStyleConfiguration
  let reduceMotion: Bool

  @State private var isHovered = false
  @State private var didPushCursor = false

  private static let buttonSize = CGSize(width: 66, height: 38)
  private let shape = Capsule(style: .continuous)

  private var isPressed: Bool {
    configuration.isPressed
  }

  private var isActive: Bool {
    isHovered || isPressed
  }

  private var fillColor: Color {
    if isPressed {
      return SnapzyWelcomePalette.buttonPressFill
    }
    return isHovered ? SnapzyWelcomePalette.buttonHoverFill : Color.white
  }

  private var arrowColor: Color {
    isActive ? Color.white : SnapzyWelcomePalette.brandCobalt.color
  }

  private var scale: CGFloat {
    guard !reduceMotion else { return 1.0 }
    if isPressed { return 0.955 }
    return isHovered ? 1.04 : 1.0
  }

  private var arrowOffset: CGFloat {
    guard !reduceMotion else { return 0 }
    if isPressed { return 4.0 }
    return isHovered ? 2.5 : 0
  }

  var body: some View {
    ZStack {
      shape
        .fill(fillColor)

      Image(systemName: "arrow.right")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(arrowColor)
        .offset(x: arrowOffset)
    }
    .frame(width: Self.buttonSize.width, height: Self.buttonSize.height)
    .overlay {
      shape.strokeBorder(
        isActive ? Color.white.opacity(0.14) : Color.black.opacity(0.06),
        lineWidth: 0.5
      )
      .allowsHitTesting(false)
    }
    .contentShape(shape)
    .shadow(
      color: SnapzyWelcomePalette.cobaltShadow.opacity(isPressed ? 0.22 : (isHovered ? 0.30 : 0.18)),
      radius: isPressed ? 5 : (isHovered ? 14 : 10),
      y: isPressed ? 2 : (isHovered ? 6 : 4)
    )
    .scaleEffect(scale)
    .animation(
      reduceMotion ? .easeInOut(duration: 0.14) : .spring(response: 0.26, dampingFraction: 0.78),
      value: isHovered
    )
    .animation(
      reduceMotion ? .easeInOut(duration: 0.08) : .spring(response: 0.16, dampingFraction: 0.84),
      value: isPressed
    )
    .onHover { hovering in
      if hovering && !didPushCursor {
        NSCursor.pointingHand.push()
        didPushCursor = true
      } else if !hovering && didPushCursor {
        NSCursor.pop()
        didPushCursor = false
      }
      if hovering && !isHovered {
        SnapzyOnboardingWelcomeAudio.shared.playHoverTick()
      }
      isHovered = hovering
    }
    .onDisappear {
      if didPushCursor {
        NSCursor.pop()
        didPushCursor = false
      }
    }
  }
}

// MARK: - Adaptive Close Button

/// Uses a subtle frosted deep-cobalt backing once the aurora floods in, so the close glyph stays
/// crisp and AA-legible even when an ice-white cloud glides behind the top-right corner.
private struct WelcomeCloseButton: View {
  let flooded: Bool
  let reduceMotion: Bool
  let action: () -> Void

  @State private var isHovered = false

  private var shape: RoundedRectangle {
    Radius.controlRect(forHeight: ControlMetrics.toolbarButton)
  }

  var body: some View {
    Button(action: action) {
      Image(systemName: "xmark")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(isHovered ? Color.white : Color.white.opacity(flooded ? 0.88 : 0.64))
        .frame(width: ControlMetrics.toolbarButton, height: ControlMetrics.toolbarButton)
        .background(
          shape
            .fill(
              flooded
                ? SnapzyWelcomePalette.cobaltShadow.opacity(isHovered ? 0.44 : 0.22)
                : (isHovered ? SnapzyGlassInk.fillHover : SnapzyGlassInk.fillRaised)
            )
            .overlay(
              shape.strokeBorder(
                Color.white.opacity(isHovered ? 0.40 : (flooded ? 0.26 : 0.12)),
                lineWidth: LiquidGlassTokens.specularLineWidth
              )
            )
        )
        .contentShape(shape)
    }
    .buttonStyle(.plain)
    .scaleEffect(!reduceMotion && isHovered ? 1.06 : 1.0)
    .animation(reduceMotion ? nil : SnapzyMotionPreferences.shared.spec(.hover).animation, value: isHovered)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: flooded)
    .onHover { hovering in
      isHovered = hovering
    }
    .accessibilityLabel(L10n.Onboarding.chromeCloseAccessibility)
  }
}
