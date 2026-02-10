# Phase 2: Splash Content View (SwiftUI Animations)

**Status:** Pending
**Plan:** [plan.md](./plan.md)
**Depends on:** [Phase 1](./phase-01-splash-window.md)

## Context Links

- [OnboardingFlowView.swift](/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Onboarding/OnboardingFlowView.swift) - Existing onboarding flow
- [WelcomeView.swift](/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Onboarding/Views/WelcomeView.swift) - Design reference for welcome screen

## Overview

SwiftUI view with a phased animation sequence: logo appears (scale+fade) -> logo shifts up -> welcome text fades in -> continue button fades in. Uses an enum-driven phase state with `Task.sleep` for sequencing.

## Key Insights

- Phase-based enum state is simplest pattern for sequential animations
- `withAnimation(.spring(...))` for logo pop, `.easeOut` for position shift, `.easeInOut` for text/button fade
- Background must be transparent (`Color.clear`) so the NSVisualEffectView blur shows through
- App icon can be loaded via `NSImage(named: "AppIcon")` wrapped in SwiftUI `Image(nsImage:)`

## Requirements

1. Four animation phases: idle -> logoVisible -> contentVisible -> buttonVisible
2. Logo: app icon, ~80pt, scale from 0.5 to 1.0 with spring, then shift up ~40pt
3. Welcome text: "Welcome to Snapzy" title + subtitle, fade in below logo
4. Continue button: styled pill button, fade in last
5. Transparent background throughout
6. Total animation duration ~2s
7. `onContinue` callback when button tapped

## Architecture

```swift
enum SplashPhase {
  case idle          // nothing visible
  case logoVisible   // logo appears center
  case contentVisible // logo shifts up, text fades in
  case buttonVisible  // button fades in
}
```

State drives opacity/offset/scale per element via computed properties.

## Related Code Files

| File | Relevance |
|------|-----------|
| `Snapzy/Features/Onboarding/Views/WelcomeView.swift` | Visual design reference |
| `Snapzy/Features/Onboarding/DesignSystem/VSDesignSystem.swift` | Design tokens |

## Implementation Steps

### Step 1: Create SplashContentView (~150 lines)

File: `Snapzy/Features/Splash/SplashContentView.swift`

```swift
import SwiftUI

// MARK: - Animation Phase

enum SplashPhase {
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
      Color.clear // transparent background

      VStack(spacing: 20) {
        Spacer()

        // App logo
        appLogo
          .opacity(logoOpacity)
          .scaleEffect(logoScale)
          .offset(y: logoOffset)

        // Welcome text
        welcomeText
          .opacity(textOpacity)
          .offset(y: logoOffset)

        // Continue button
        continueButton
          .opacity(buttonOpacity)
          .offset(y: logoOffset)

        Spacer()
      }
    }
    .task { await startAnimationSequence() }
  }

  // MARK: - Subviews

  private var appLogo: some View {
    Image(nsImage: NSApp.applicationIconImage)
      .resizable()
      .aspectRatio(contentMode: .fit)
      .frame(width: 80, height: 80)
      .clipShape(RoundedRectangle(cornerRadius: 18))
  }

  private var welcomeText: some View {
    VStack(spacing: 8) {
      Text("Welcome to Snapzy")
        .font(.system(size: 28, weight: .bold))
        .foregroundStyle(.white)
      Text("Screenshot & recording, simplified.")
        .font(.system(size: 16))
        .foregroundStyle(.white.opacity(0.7))
    }
  }

  private var continueButton: some View {
    Button(action: onContinue) {
      Text("Continue")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 32)
        .padding(.vertical, 10)
        .background(
          Capsule().fill(.white.opacity(0.2))
        )
        .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1))
    }
    .buttonStyle(.plain)
    .padding(.top, 8)
  }

  // MARK: - Animation Sequence

  private func startAnimationSequence() async {
    // Phase 1: Logo appears
    try? await Task.sleep(for: .milliseconds(400))
    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
      phase = .logoVisible
    }

    // Phase 2: Logo shifts up, text fades in
    try? await Task.sleep(for: .milliseconds(600))
    withAnimation(.easeOut(duration: 0.5)) {
      phase = .contentVisible
    }

    // Phase 3: Button fades in
    try? await Task.sleep(for: .milliseconds(400))
    withAnimation(.easeInOut(duration: 0.4)) {
      phase = .buttonVisible
    }
  }
}
```

## Todo List

- [ ] Create `Snapzy/Features/Splash/SplashContentView.swift`
- [ ] Implement `SplashPhase` enum
- [ ] Build view layout with logo, text, button
- [ ] Implement `startAnimationSequence()` with Task.sleep
- [ ] Verify transparent background renders correctly over blur
- [ ] Test animation timing feels natural (~2s total)

## Success Criteria

- [x] Logo pops in with spring animation
- [x] Logo smoothly shifts up after appearing
- [x] Welcome text fades in below logo
- [x] Continue button appears last
- [x] Button tap triggers `onContinue` callback
- [x] Background fully transparent (blur shows through)
- [x] File stays under 150 lines

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Text unreadable over blur | Low | White text on dark blur material has good contrast |
| Animation feels laggy | Low | Spring + easeOut are GPU-accelerated in SwiftUI |
| Task.sleep cancelled early | Low | `try?` ignores cancellation; phases just skip |

## Next Steps

Proceed to [Phase 3](./phase-03-app-integration.md) to wire splash into AppDelegate launch flow.
