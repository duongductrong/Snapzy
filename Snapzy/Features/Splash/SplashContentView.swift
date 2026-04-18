//
//  SplashContentView.swift
//  Snapzy
//
//  Animated SwiftUI content for the splash overlay
//

import SwiftUI

// MARK: - Animation Phase

private enum SplashPhase {
  case idle, logoVisible, contentVisible, buttonVisible
}

// MARK: - SplashContentView

struct SplashContentView: View {
  let onContinue: (Bool) -> Void

  @State private var phase: SplashPhase = .idle
  @State private var doNotShowAgain = false

  // Computed animation properties
  private var logoOpacity: Double { phase == .idle ? 0 : 1 }
  private var logoScale: Double { phase == .idle ? 0.5 : 1.0 }
  private var logoOffset: CGFloat {
    switch phase {
    case .idle, .logoVisible: return 0
    case .contentVisible, .buttonVisible: return -20
    }
  }
  private var textOpacity: Double {
    switch phase {
    case .idle, .logoVisible: return 0
    case .contentVisible, .buttonVisible: return 1
    }
  }
  private var buttonOpacity: Double { phase == .buttonVisible ? 1 : 0 }

  var body: some View {
    ZStack {
      Color.clear

      VStack(spacing: 16) {
        Spacer()

        appLogo
          .opacity(logoOpacity)
          .scaleEffect(logoScale)
          .offset(y: logoOffset)

        welcomeText
          .opacity(textOpacity)
          .offset(y: logoOffset)

        continueButton
          .opacity(buttonOpacity)
          .offset(y: logoOffset)

        Spacer()
      }

      VStack {
        Spacer()
        supportedLanguagesInfo
          .opacity(textOpacity)
          .padding(.bottom, 28)
      }
    }
    .task { await startAnimationSequence() }
  }
}

// MARK: - Subviews

private extension SplashContentView {
  var supportedLanguageNames: String {
    let bundledLanguageIdentifiers = Set(Bundle.main.localizations)
    let names = AppLanguageOption.supported
      .filter { bundledLanguageIdentifiers.contains($0.identifier) }
      .map(\.displayName)
    return names.joined(separator: " · ")
  }

  var appLogo: some View {
    Image(nsImage: NSApp.applicationIconImage)
      .resizable()
      .aspectRatio(contentMode: .fit)
      .frame(width: 100, height: 100)
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 4)
  }

  var welcomeText: some View {
    VStack(spacing: 6) {
      Text(L10n.Splash.welcomeTitle)
        .font(.system(size: 22, weight: .bold))
        .foregroundStyle(VSDesignSystem.Colors.primary)

      Text(L10n.Splash.welcomeSubtitle)
        .font(.system(size: 14))
        .foregroundStyle(VSDesignSystem.Colors.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 380)
    }
  }

  var supportedLanguagesInfo: some View {
    VStack(spacing: 6) {
      HStack(spacing: 5) {
        Image(systemName: "globe")
          .font(.system(size: 11, weight: .medium))
        Text(verbatim: "Supported Languages")
          .font(.system(size: 11, weight: .medium))
      }
      .foregroundStyle(VSDesignSystem.Colors.quaternary)

      Text(verbatim: supportedLanguageNames)
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(VSDesignSystem.Colors.tertiary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)
    }
  }

  var continueButton: some View {
    VStack(spacing: 6) {
      Button(action: { onContinue(doNotShowAgain) }) {
        Text(L10n.Common.continueAction)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(VSDesignSystem.Colors.primary)
          .padding(.horizontal, 32)
          .padding(.vertical, 10)
          .background(
            Capsule().fill(VSDesignSystem.Colors.buttonFill)
          )
          .overlay(Capsule().stroke(VSDesignSystem.Colors.buttonStroke, lineWidth: 1))
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.return, modifiers: [])

      Text(L10n.Splash.pressEnter)
        .font(.system(size: 11))
        .foregroundStyle(VSDesignSystem.Colors.quaternary)

      Toggle(L10n.Splash.doNotShowAgain, isOn: $doNotShowAgain)
        .toggleStyle(.checkbox)
        .font(.system(size: 12))
        .foregroundStyle(VSDesignSystem.Colors.secondary)
        .padding(.top, 4)
    }
    .padding(.top, 4)
  }
}

// MARK: - Animation Sequence

private extension SplashContentView {

  func startAnimationSequence() async {
    // Phase 1: Logo appears at center
    try? await Task.sleep(for: .milliseconds(400))
    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
      phase = .logoVisible
    }

    // Phase 2: Logo shifts up, welcome text fades in
    try? await Task.sleep(for: .milliseconds(600))
    withAnimation(.easeOut(duration: 0.5)) {
      phase = .contentVisible
    }

    // Phase 3: Continue button fades in
    try? await Task.sleep(for: .milliseconds(400))
    withAnimation(.easeInOut(duration: 0.4)) {
      phase = .buttonVisible
    }
  }
}

#Preview {
  SplashContentView(onContinue: { _ in })
    .frame(width: 800, height: 600)
    .background(OnboardingSurfaceBackground())
}
