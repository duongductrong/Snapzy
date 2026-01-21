# Phase 02: WelcomeView Implementation

## Context

- **Parent Plan:** [plan.md](../plan.md)
- **Dependencies:** Phase 01 (VSDesignSystem)
- **Related Docs:** SwiftUI layout patterns

## Overview

| Field | Value |
|-------|-------|
| Date | 260116 |
| Description | Implement WelcomeView with app icon, title, subtitle, and primary CTA |
| Priority | High |
| Status | Pending |

## Requirements

1. Centered VStack layout
2. App icon placeholder (80x80) - use system image or app icon
3. Title: "Welcome to ZapShot" using heading typography
4. Subtitle: descriptive text using body typography
5. Primary button: "Let's do it!" with action callback

## Architecture

```swift
struct WelcomeView: View {
  let onContinue: () -> Void
  // Centered VStack with icon, title, subtitle, button
}
```

## Related Files

- `ZapShot/Features/Onboarding/DesignSystem/VSDesignSystem.swift`

## Implementation

### Step 1: Create WelcomeView.swift

**File:** `ZapShot/Features/Onboarding/Views/WelcomeView.swift`

```swift
//
//  WelcomeView.swift
//  ZapShot
//
//  Welcome screen for onboarding flow
//

import SwiftUI

struct WelcomeView: View {
  let onContinue: () -> Void

  var body: some View {
    VStack(spacing: 24) {
      Spacer()

      // App Icon
      Image(systemName: "camera.viewfinder")
        .font(.system(size: 60))
        .foregroundColor(.blue)
        .frame(width: 80, height: 80)
        .background(
          RoundedRectangle(cornerRadius: 18)
            .fill(Color.blue.opacity(0.1))
        )

      // Title
      Text("Welcome to ZapShot")
        .vsHeading()

      // Subtitle
      Text("Capture, annotate, and share screenshots with ease. Let's get you set up in just a few steps.")
        .vsBody()
        .multilineTextAlignment(.center)
        .frame(maxWidth: 300)

      Spacer()

      // Primary CTA
      Button("Let's do it!") {
        onContinue()
      }
      .buttonStyle(VSDesignSystem.PrimaryButtonStyle())

      Spacer()
        .frame(height: 40)
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

#Preview {
  WelcomeView(onContinue: {})
    .frame(width: 500, height: 400)
}
```

## Todo

- [ ] Create Views directory under Onboarding
- [ ] Create WelcomeView.swift
- [ ] Apply VSDesignSystem typography and button styles
- [ ] Add preview for visual verification
- [ ] Verify compilation

## Success Criteria

- [ ] WelcomeView displays centered content
- [ ] App icon renders at 80x80
- [ ] Title uses heading typography
- [ ] Subtitle uses body typography with secondary color
- [ ] Button triggers onContinue callback
- [ ] Code compiles without errors
