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
  let onContinue: () -> Void

  @State private var phase: SplashPhase = .idle

  // Computed animation properties
  private var logoOpacity: Double { phase == .idle ? 0 : 1 }
  private var logoScale: Double { phase == .idle ? 0.5 : 1.0 }
  private var logoOffset: CGFloat {
    switch phase {
    case .idle, .logoVisible: return 0
    case .contentVisible, .buttonVisible: return -40
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

      VStack(spacing: 20) {
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
    }
    .task { await startAnimationSequence() }
  }
}

// MARK: - Subviews

private extension SplashContentView {

  var appLogo: some View {
    Image(nsImage: NSApp.applicationIconImage)
      .resizable()
      .aspectRatio(contentMode: .fit)
      .frame(width: 120, height: 120)
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 6)
  }

  var welcomeText: some View {
    VStack(spacing: 8) {
      Text("Welcome to Snapzy")
        .font(.system(size: 28, weight: .bold))
        .foregroundStyle(VSDesignSystem.Colors.primary)
      Text("Screenshot & recording, simplified.")
        .font(.system(size: 16))
        .foregroundStyle(VSDesignSystem.Colors.secondary)
    }
  }

  var continueButton: some View {
    VStack(spacing: 6) {
      Button(action: onContinue) {
        Text("Continue")
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

      Text("Press Enter ↵")
        .font(.system(size: 11))
        .foregroundStyle(VSDesignSystem.Colors.quaternary)
    }
    .padding(.top, 8)
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
  SplashContentView(onContinue: {})
    .frame(width: 800, height: 600)
    .background(.black.opacity(0.5))
}
