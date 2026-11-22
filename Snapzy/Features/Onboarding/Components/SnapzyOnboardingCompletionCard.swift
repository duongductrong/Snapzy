//
//  SnapzyOnboardingCompletionCard.swift
//  Snapzy
//
//  Completion screen: the app mark, what just became possible, and the way out.
//

import AppKit
import SwiftUI

struct SnapzyOnboardingCompletionCard: View {
  var externalLaunchTrigger: Int = 0
  var onBeginLaunch: () -> Void = {}
  var onFinish: (_ iconWindowFrame: CGRect?) -> Void
  var onBack: (() -> Void)?

  /// The page arrives in beats instead of switching on as one block. This is the least-frequent
  /// screen in the flow, which is the one place a staged entrance is worth its length.
  @State private var hasAppeared = false
  @State private var isLaunching = false
  @State private var didHandOffIcon = false
  @State private var iconWindowFrame: CGRect?
  @Environment(\.accessibilityReduceMotion) private var envReduceMotion

  private var reduceMotion: Bool {
    SnapzyMotionPreferences.shared.reduceMotion || envReduceMotion
  }

  var body: some View {
    VStack(spacing: SnapzySpace.giant) {
      hero
        .entrance(0, appeared: hasAppeared, step: 0.06)

      capabilitiesGrid
        .entrance(1, appeared: hasAppeared, step: 0.06)
        .opacity(isLaunching ? 0 : 1)
        .scaleEffect(isLaunching && !reduceMotion ? 0.97 : 1.0)
        .offset(y: isLaunching && !reduceMotion ? 14 : 0)
        .animation(reduceMotion ? nil : .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.24), value: isLaunching)

      communityRow
        .entrance(2, appeared: hasAppeared, step: 0.06)
        .opacity(isLaunching ? 0 : 1)
        .offset(y: isLaunching && !reduceMotion ? 12 : 0)
        .animation(reduceMotion ? nil : .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.22), value: isLaunching)

      primaryActionRow
        .entrance(3, appeared: hasAppeared, step: 0.06)
        .opacity(isLaunching ? 0 : 1)
        .scaleEffect(isLaunching && !reduceMotion ? 0.96 : 1.0)
        .offset(y: isLaunching && !reduceMotion ? 10 : 0)
        .animation(reduceMotion ? nil : .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.20), value: isLaunching)
    }
    .frame(maxWidth: 760)
    .allowsHitTesting(!isLaunching)
    .onAppear { hasAppeared = true }
    .onChange(of: externalLaunchTrigger) { _ in
      triggerLaunch()
    }
  }

  // MARK: - Hero

  private var hero: some View {
    VStack(spacing: SnapzySpace.xxl) {
      ZStack {
        // Minimalist Leica-inspired precision viewfinder brackets that briefly frame the icon
        // right before it ascends to the macOS menu bar (pure hairline vector, zero glow).
        CompletionViewfinderBrackets()
          .stroke(
            Color.white.opacity(isLaunching && !didHandOffIcon ? 0.72 : 0),
            style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)
          )
          .frame(width: 72, height: 72)
          .scaleEffect(isLaunching ? 1.0 : 1.24)
          .animation(
            reduceMotion ? nil : .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.22),
            value: isLaunching
          )

        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 56, height: 56)
          .clipShape(Radius.rect(Radius.card))
          .scaleEffect(isLaunching && !reduceMotion ? 1.08 : 1.0)
          .opacity(didHandOffIcon ? 0 : 1)
          .animation(
            reduceMotion ? nil : .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.22),
            value: isLaunching
          )
          .background(
            GeometryReader { geo in
              Color.clear
                .onAppear { iconWindowFrame = geo.frame(in: .global) }
                .onChange(of: geo.frame(in: .global)) { newFrame in
                  if newFrame.width > 0 && newFrame.height > 0 && !isLaunching {
                    iconWindowFrame = newFrame
                  }
                }
            }
          )
      }
      .frame(width: 56, height: 56)

      VStack(spacing: SnapzySpace.lg) {
        SnapzyOnboardingOverline(L10n.Onboarding.completionCardOverline)

        Text(L10n.Onboarding.completionCardTitle)
          .font(.system(size: SnapzyOnboardingType.title, weight: .bold))
          .tracking(SnapzyOnboardingType.displayTracking + 0.2)
          .foregroundStyle(SnapzyGlassInk.primary)

        Text(L10n.Onboarding.completionCardSubtitle)
          .font(.system(size: SnapzyOnboardingType.lede))
          .foregroundStyle(SnapzyGlassInk.body)
          .multilineTextAlignment(.center)
          .lineSpacing(5)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: 580)
      }
      .opacity(isLaunching ? 0 : 1)
      .offset(y: isLaunching && !reduceMotion ? 10 : 0)
      .animation(reduceMotion ? nil : .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.22), value: isLaunching)
    }
  }

  private func triggerLaunch() {
    guard !isLaunching else { return }
    isLaunching = true
    onBeginLaunch()
    SnapzyOnboardingWelcomeAudio.shared.playCompletionChime()

    if reduceMotion {
      didHandOffIcon = true
      onFinish(iconWindowFrame)
      return
    }

    Task { @MainActor in
      // Hold one crisp 220ms framing beat as the cards release and viewfinder brackets lock on,
      // then hand the icon seamlessly to the desktop overlay for its 120fps ascent to the menu bar.
      try? await Task.sleep(for: .milliseconds(220))
      didHandOffIcon = true
      onFinish(iconWindowFrame)
    }
  }

  // MARK: - Capabilities

  /// Two across instead of four: at a quarter of the window width every description wrapped to
  /// three ragged lines, which turned the summary into a wall of cards. Half that many columns
  /// gives each one a single clean line of prose.
  private var capabilitiesGrid: some View {
    VStack(spacing: SnapzySpace.lg) {
      HStack(spacing: SnapzySpace.lg) {
        CapabilityCard(
          icon: "camera.viewfinder",
          shortcut: "⇧⌘4",
          title: L10n.Onboarding.completionAreaCaptureTitle,
          detail: L10n.Onboarding.completionAreaCaptureDetail
        )

        CapabilityCard(
          icon: "record.circle",
          shortcut: "⇧⌘5",
          title: L10n.Onboarding.completionScreenRecordingTitle,
          detail: L10n.Onboarding.completionScreenRecordingDetail
        )
      }

      HStack(spacing: SnapzySpace.lg) {
        CapabilityCard(
          icon: "text.viewfinder",
          shortcut: "⇧⌘2",
          title: L10n.Onboarding.completionOcrTitle,
          detail: L10n.Onboarding.completionOcrDetail
        )

        CapabilityCard(
          icon: "menubar.rectangle",
          shortcut: "⌘,",
          title: L10n.Onboarding.completionMenubarHubTitle,
          detail: L10n.Onboarding.completionMenubarHubDetail
        )
      }
    }
  }

  // MARK: - Community Links

  private var communityRow: some View {
    HStack(spacing: SnapzySpace.lg) {
      CommunityLinkPill(
        title: L10n.Onboarding.completionStarGithub,
        icon: "star.fill",
        url: "https://github.com/duongductrong/Snapzy"
      )

      CommunityLinkPill(
        title: L10n.Onboarding.completionJoinDiscord,
        icon: "bubble.left.and.bubble.right.fill",
        url: "https://discord.gg/xkWDAuJkZu"
      )

      CommunityLinkPill(
        title: L10n.Onboarding.completionSponsorProject,
        icon: "heart.fill",
        url: "https://github.com/sponsors/duongductrong"
      )
    }
  }

  // MARK: - Primary Action

  private var primaryActionRow: some View {
    VStack(spacing: SnapzySpace.xl) {
      SnapzyOnboardingActionBar(
        continueTitle: L10n.Onboarding.completionStartUsing,
        continueKey: "\u{21A9}",
        isContinueEnabled: true,
        isHinted: true,
        onContinue: triggerLaunch
      )

      if let onBack {
        Button(action: onBack) {
          Text(L10n.Onboarding.completionReviewHint)
            .font(.system(size: SnapzyOnboardingType.caption))
            .foregroundStyle(SnapzyGlassInk.faint)
        }
        .buttonStyle(.plain)
      }
    }
  }
}

// MARK: - Capability Card

private struct CapabilityCard: View {
  var icon: String
  var shortcut: String
  var title: String
  var detail: String

  @State private var isHovered = false

  private var shape: RoundedRectangle {
    Radius.rect(SnapzyRadius.card)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: SnapzySpace.lg) {
      HStack {
        Image(systemName: icon)
          .font(.system(size: 13))
          .foregroundStyle(SnapzyGlassInk.body)
          .frame(width: 26, height: 26)
          .background(Radius.rect(Radius.tile).fill(SnapzyGlassInk.fillRaised))
          .accessibilityHidden(true)

        Spacer(minLength: 0)

        SnapzyKeycapChip(label: shortcut, emphasis: isHovered)
      }

      VStack(alignment: .leading, spacing: SnapzySpace.xxs) {
        Text(title)
          .font(.system(size: SnapzyOnboardingType.body, weight: .semibold))
          .foregroundStyle(SnapzyGlassInk.primary)

        Text(detail)
          .font(.system(size: SnapzyOnboardingType.caption))
          .foregroundStyle(SnapzyGlassInk.muted)
          .lineSpacing(4)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(SnapzySpace.xxl)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(shape.fill(isHovered ? SnapzyGlassInk.fillHover : SnapzyGlassInk.fillQuiet))
    .overlay(
      shape.strokeBorder(
        isHovered ? SnapzyGlassInk.hairlineStrong : SnapzyGlassInk.hairline,
        lineWidth: SnapzySurfaceGlass.specularLineWidth
      )
    )
    .onHover { hovering in
      withAnimation(SnapzyMotionPreferences.shared.spec(.hover).animation) { isHovered = hovering }
    }
  }
}

// MARK: - Community Link Pill

private struct CommunityLinkPill: View {
  var title: String
  var icon: String
  var url: String

  @State private var isHovered = false

  private var shape: Capsule {
    Capsule(style: .continuous)
  }

  var body: some View {
    Button {
      if let targetURL = URL(string: url) {
        NSWorkspace.shared.open(targetURL)
      }
    } label: {
      HStack(spacing: SnapzySpace.sm) {
        Image(systemName: icon)
          .font(.system(size: 10.5))
          .foregroundStyle(isHovered ? SnapzyGlassInk.body : SnapzyGlassInk.muted)
          .accessibilityHidden(true)

        Text(title)
          .font(.system(size: SnapzyOnboardingType.caption, weight: .medium))
          .foregroundStyle(isHovered ? SnapzyGlassInk.primary : SnapzyGlassInk.body)
      }
      .padding(.horizontal, SnapzySpace.xl)
      .frame(height: 30)
      .background(shape.fill(isHovered ? SnapzyGlassInk.fillHover : SnapzyGlassInk.fillQuiet))
      .overlay(
        shape.strokeBorder(
          isHovered ? SnapzyGlassInk.hairlineStrong : SnapzyGlassInk.hairline,
          lineWidth: SnapzySurfaceGlass.specularLineWidth
        )
      )
      .contentShape(shape)
    }
    .buttonStyle(.plain)
      .onHover { hovering in
        withAnimation(SnapzyMotionPreferences.shared.spec(.hover).animation) { isHovered = hovering }
      }
  }
}

/// Crisp 4-corner optical viewfinder brackets framing the app icon right before it ascends to the
/// macOS menu bar. Pure hairline vector geometry, zero glow.
private struct CompletionViewfinderBrackets: Shape {
  func path(in rect: CGRect) -> Path {
    let arm: CGFloat = 12
    let r: CGFloat = 6
    var path = Path()

    // Top-leading
    path.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
    path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))

    // Top-trailing
    path.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
    path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))

    // Bottom-trailing
    path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
    path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))

    // Bottom-leading
    path.move(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
    path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm))

    return path
  }
}
