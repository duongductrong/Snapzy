//
//  SnapzyOnboardingCompletionCard.swift
//  Snapzy
//
//  Celebratory completion view with Dark Liquid Glass aesthetics, clean logo presentation,
//  monochrome capability cards showcase, ecosystem links, and consistent action bar button.
//

import AppKit
import SwiftUI

struct SnapzyOnboardingCompletionCard: View {
  var onFinish: () -> Void
  var onBack: (() -> Void)? = nil

  @State private var hasAppeared = false

  var body: some View {
    VStack(spacing: 22) {
      Spacer(minLength: 8)

      // 1. Clean Logo (no border, no check, no shadow)
      heroLogo
        .opacity(hasAppeared ? 1 : 0)

      // 2. Headline & Description (monochrome simple palette)
      headerSection
        .opacity(hasAppeared ? 1 : 0)

      // 3. Core Capabilities (monochrome 4-card glass grid)
      capabilitiesGrid
        .opacity(hasAppeared ? 1 : 0)

      // 4. Community & Open Source Row (monochrome pills)
      communityRow
        .opacity(hasAppeared ? 1 : 0)

      // 5. Primary Action Button (same style as previous onboarding steps)
      primaryActionRow
        .opacity(hasAppeared ? 1 : 0)

      Spacer(minLength: 8)
    }
    .frame(maxWidth: 900)
    .onAppear {
      withAnimation(SnapzyMotionPreferences.shared.spec(.morph).animation) {
        hasAppeared = true
      }
    }
  }

  // MARK: - Hero Logo

  private var heroLogo: some View {
    Image(nsImage: NSApp.applicationIconImage)
      .resizable()
      .aspectRatio(contentMode: .fit)
      .frame(width: 56, height: 56)
      .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
  }

  // MARK: - Header Section

  private var headerSection: some View {
    VStack(spacing: 8) {
      SnapzyOnboardingOverline(L10n.Onboarding.completionCardOverline)

      Text(L10n.Onboarding.completionCardTitle)
        .font(.system(size: 28, weight: .bold))
        .tracking(-0.5)
        .foregroundStyle(SnapzyGlassInk.primary)

      Text(L10n.Onboarding.completionCardSubtitle)
        .font(.system(size: SnapzyOnboardingType.lede))
        .foregroundStyle(SnapzyGlassInk.body)
        .multilineTextAlignment(.center)
        .lineSpacing(3)
        .frame(maxWidth: 580)
    }
  }

  // MARK: - Capabilities Grid

  private var capabilitiesGrid: some View {
    HStack(spacing: 12) {
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
    .frame(maxWidth: 880)
  }

  // MARK: - Community Links

  private var communityRow: some View {
    HStack(spacing: 12) {
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
    .padding(.vertical, 2)
  }

  // MARK: - Primary Action

  private var primaryActionRow: some View {
    VStack(spacing: 10) {
      SnapzyOnboardingActionBar(
        continueTitle: L10n.Onboarding.completionStartUsing,
        continueKey: "\u{21A9}",
        isContinueEnabled: true,
        onContinue: onFinish
      )

      if let onBack {
        Button(action: onBack) {
          Text(L10n.Onboarding.completionReviewHint)
            .font(.system(size: 11))
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

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        // Monochrome glass icon container matching previous steps
        Image(systemName: icon)
          .font(.system(size: 13))
          .foregroundStyle(SnapzyGlassInk.body)
          .frame(width: 26, height: 26)
          .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
              .fill(Color.white.opacity(0.08))
          )

        Spacer(minLength: 0)

        SnapzyKeycapChip(label: shortcut, emphasis: isHovered)
      }

      Text(title)
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(SnapzyGlassInk.primary)

      Text(detail)
        .font(.system(size: 11))
        .foregroundStyle(SnapzyGlassInk.muted)
        .lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: 0)
    }
    .padding(14)
    .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: SnapzyRadius.card + 1, style: .continuous)
        .fill(Color.white.opacity(isHovered ? 0.065 : 0.04))
        .overlay(
          RoundedRectangle(cornerRadius: SnapzyRadius.card + 1, style: .continuous)
            .strokeBorder(
              Color.white.opacity(isHovered ? 0.16 : 0.08),
              lineWidth: 0.5
            )
        )
    )
    .onHover { hovering in
      withAnimation(SnapzyMotionPreferences.shared.spec(.hover).animation) {
        isHovered = hovering
      }
    }
  }
}

// MARK: - Community Link Pill

private struct CommunityLinkPill: View {
  var title: String
  var icon: String
  var url: String

  @State private var isHovered = false

  var body: some View {
    Button {
      if let targetURL = URL(string: url) {
        NSWorkspace.shared.open(targetURL)
      }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: 10.5))
          .foregroundStyle(SnapzyGlassInk.muted)

        Text(title)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(isHovered ? SnapzyGlassInk.primary : SnapzyGlassInk.body)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(
        Capsule()
          .fill(Color.white.opacity(isHovered ? 0.09 : 0.04))
          .overlay(
            Capsule()
              .strokeBorder(Color.white.opacity(isHovered ? 0.14 : 0.07), lineWidth: 0.5)
          )
      )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(SnapzyMotionPreferences.shared.spec(.hover).animation) {
        isHovered = hovering
      }
    }
  }
}
