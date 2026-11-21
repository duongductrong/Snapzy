//
//  SnapzyOnboardingCompletionCard.swift
//  Snapzy
//
//  Completion screen: the app mark, what just became possible, and the way out.
//

import AppKit
import SwiftUI

struct SnapzyOnboardingCompletionCard: View {
  var onFinish: () -> Void
  var onBack: (() -> Void)?

  /// The page arrives in beats instead of switching on as one block. This is the least-frequent
  /// screen in the flow, which is the one place a staged entrance is worth its length.
  @State private var hasAppeared = false

  var body: some View {
    VStack(spacing: SnapzySpace.giant) {
      hero
        .entrance(0, appeared: hasAppeared, step: 0.06)

      capabilitiesGrid
        .entrance(1, appeared: hasAppeared, step: 0.06)

      communityRow
        .entrance(2, appeared: hasAppeared, step: 0.06)

      primaryActionRow
        .entrance(3, appeared: hasAppeared, step: 0.06)
    }
    .frame(maxWidth: 760)
    .onAppear { hasAppeared = true }
  }

  // MARK: - Hero

  private var hero: some View {
    VStack(spacing: SnapzySpace.xxl) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 56, height: 56)
        .clipShape(Radius.rect(Radius.card))

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
        onContinue: onFinish
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
