//
//  SnapzyOnboardingCompletionCard.swift
//  Snapzy
//
//  Celebratory completion view with quick reference shortcuts and community/sponsor links.
//

import SwiftUI

struct SnapzyOnboardingCompletionCard: View {
  var onFinish: () -> Void

  var body: some View {
    VStack(spacing: 24) {
      Spacer()

      // Success Icon
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 54))
        .foregroundStyle(Color.green)
        .shadow(color: Color.green.opacity(0.35), radius: 16, y: 4)

      VStack(spacing: 6) {
        Text("You're All Set!")
          .font(.system(size: 28, weight: .bold))
          .foregroundStyle(SnapzyGlassInk.primary)

        Text("Snapzy is ready in your menu bar. Take your first capture anytime.")
          .font(.system(size: SnapzyOnboardingType.lede))
          .foregroundStyle(SnapzyGlassInk.body)
          .multilineTextAlignment(.center)
      }

      // Quick Reference Row
      HStack(spacing: SnapzySpace.xl) {
        summaryPill("⇧⌘4", title: "Area Capture")
        summaryPill("⇧⌘3", title: "Fullscreen")
        summaryPill("⇧⌘5", title: "Recording")
        summaryPill("⌘,", title: "Preferences")
      }
      .padding(.vertical, 8)

      // Sponsor & Community Card
      HStack(spacing: SnapzySpace.xxl) {
        linkButton("Star on GitHub", icon: "star.fill", url: "https://github.com/duongductrong/Snapzy")
        linkButton("Join Discord", icon: "bubble.left.and.bubble.right.fill", url: "https://discord.gg/xkWDAuJkZu")
        linkButton("Sponsor Project", icon: "heart.fill", url: "https://github.com/sponsors/duongductrong")
      }
      .padding(.vertical, 4)

      // Finish Button
      Button(action: onFinish) {
        HStack(spacing: 6) {
          Text("Start Using Snapzy")
            .font(.system(size: 14, weight: .semibold))
          SnapzyKeycapChip(label: "⏎", emphasis: true)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
        .background(
          Capsule()
            .fill(Color.blue.opacity(0.85))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.75))
        )
        .shadow(color: Color.blue.opacity(0.4), radius: 12, y: 4)
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.defaultAction)
      .padding(.top, 8)

      Spacer()
    }
    .frame(maxWidth: 640)
    .padding(32)
  }

  private func summaryPill(_ key: String, title: String) -> some View {
    HStack(spacing: 6) {
      SnapzyKeycapChip(label: key, emphasis: true)
      Text(title)
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(SnapzyGlassInk.body)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(Color.white.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
    )
  }

  private func linkButton(_ title: String, icon: String, url: String) -> some View {
    Button {
      if let targetURL = URL(string: url) {
        NSWorkspace.shared.open(targetURL)
      }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: 11))
          .foregroundStyle(Color.yellow.opacity(0.9))
        Text(title)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(SnapzyGlassInk.body)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(
        Capsule()
          .fill(Color.white.opacity(0.08))
          .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
      )
    }
    .buttonStyle(.plain)
  }
}
