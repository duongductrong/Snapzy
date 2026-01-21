# Phase 2: SwiftUI Integration

## Context

- [Plan Overview](./plan.md)
- [Phase 1: Core Theme Infrastructure](./phase-01-core-theme-infrastructure.md)
- [SwiftUI Theming Research](./research/researcher-01-swiftui-theming.md)

## Overview

Apply theme to all SwiftUI scenes: MenuBarExtra, WindowGroup (onboarding), and Settings. Use `.preferredColorScheme()` modifier at the scene/root level.

## Key Insights

1. Apply `.preferredColorScheme()` to each scene's root content
2. Use `@ObservedObject` with `ThemeManager.shared` for reactivity
3. MenuBarExtra content needs theme applied
4. Settings scene content needs theme applied
5. WindowGroup content needs theme applied

## Requirements

- [x] Theme applied to MenuBarExtra content
- [x] Theme applied to Onboarding WindowGroup
- [x] Theme applied to Settings/Preferences
- [x] All SwiftUI views respond to theme changes immediately

## Architecture

```
ZapShotApp
    |
    +-- MenuBarExtra
    |       +-- MenuBarContentView
    |               .preferredColorScheme(themeManager.systemAppearance)
    |
    +-- WindowGroup("onboarding")
    |       +-- OnboardingFlowView
    |               .preferredColorScheme(themeManager.systemAppearance)
    |
    +-- Settings
            +-- PreferencesView
                    .preferredColorScheme(themeManager.systemAppearance)
```

## Related Code Files

| File | Action | Purpose |
|------|--------|---------|
| `ZapShot/App/ZapShotApp.swift` | MODIFY | Add ThemeManager, apply to scenes |

## Implementation Steps

### Step 1: Modify ZapShotApp.swift

**File:** `ZapShot/App/ZapShotApp.swift`

Add `@ObservedObject` for ThemeManager and apply `.preferredColorScheme()` to each scene.

#### 1a. Add ThemeManager property (after line 21)

```swift
@ObservedObject private var themeManager = ThemeManager.shared
```

#### 1b. Update MenuBarExtra (around line 36-38)

Change from:
```swift
MenuBarExtra("ZapShot", systemImage: "camera.aperture") {
  MenuBarContentView(viewModel: viewModel, updater: updaterController.updater)
}
```

To:
```swift
MenuBarExtra("ZapShot", systemImage: "camera.aperture") {
  MenuBarContentView(viewModel: viewModel, updater: updaterController.updater)
    .preferredColorScheme(themeManager.systemAppearance)
}
```

#### 1c. Update Onboarding WindowGroup (around line 41-53)

Change from:
```swift
WindowGroup(id: "onboarding") {
  OnboardingFlowView(onComplete: {
    showOnboarding = false
    // Close onboarding window
    NSApp.windows
      .filter { $0.identifier?.rawValue.contains("onboarding") == true }
      .forEach { $0.close() }
  })
  .frame(width: 500, height: 450)
}
```

To:
```swift
WindowGroup(id: "onboarding") {
  OnboardingFlowView(onComplete: {
    showOnboarding = false
    // Close onboarding window
    NSApp.windows
      .filter { $0.identifier?.rawValue.contains("onboarding") == true }
      .forEach { $0.close() }
  })
  .frame(width: 500, height: 450)
  .preferredColorScheme(themeManager.systemAppearance)
}
```

#### 1d. Update Settings scene (around line 55-58)

Change from:
```swift
Settings {
  PreferencesView()
}
```

To:
```swift
Settings {
  PreferencesView()
    .preferredColorScheme(themeManager.systemAppearance)
}
```

### Complete Modified ZapShotApp.swift Structure

```swift
@main
struct ZapShotApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @StateObject private var viewModel = ScreenCaptureViewModel()
  @State private var showOnboarding = !OnboardingFlowView.hasCompletedOnboarding
  @ObservedObject private var themeManager = ThemeManager.shared  // ADD THIS

  // Sparkle updater controller
  private let updaterController: SPUStandardUpdaterController

  init() {
    updaterController = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
  }

  var body: some Scene {
    // Menu Bar
    MenuBarExtra("ZapShot", systemImage: "camera.aperture") {
      MenuBarContentView(viewModel: viewModel, updater: updaterController.updater)
        .preferredColorScheme(themeManager.systemAppearance)  // ADD THIS
    }

    // Onboarding Window (shown only when needed)
    WindowGroup(id: "onboarding") {
      OnboardingFlowView(onComplete: {
        showOnboarding = false
        NSApp.windows
          .filter { $0.identifier?.rawValue.contains("onboarding") == true }
          .forEach { $0.close() }
      })
      .frame(width: 500, height: 450)
      .preferredColorScheme(themeManager.systemAppearance)  // ADD THIS
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
    .defaultSize(width: 500, height: 450)

    // Settings Window
    Settings {
      PreferencesView()
        .preferredColorScheme(themeManager.systemAppearance)  // ADD THIS
    }
  }
}
```

## Todo List

- [x] Add `@ObservedObject private var themeManager = ThemeManager.shared`
- [x] Apply `.preferredColorScheme()` to MenuBarExtra content
- [x] Apply `.preferredColorScheme()` to WindowGroup content
- [x] Apply `.preferredColorScheme()` to Settings content
- [x] Verify build succeeds
- [x] Fix hardcoded colors in Annotate SwiftUI views (11 files updated)
- [x] Remove `.preferredColorScheme(.dark)` locks from Annotate views
- [x] Code review completed - see [report](./reports/260120-code-reviewer-theme-color-fixes-report.md)
- [ ] Test theme changes propagate to all SwiftUI views
- [ ] Optional: Replace hardcoded `.blue` selections with `.accentColor`

## Success Criteria

1. Project compiles without errors
2. MenuBarExtra respects theme preference
3. Onboarding window respects theme preference
4. Settings window respects theme preference
5. Theme changes apply immediately without app restart

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| @ObservedObject not updating | Low | High | Use shared singleton pattern |
| Scene-level modifier not working | Low | Medium | Apply to root view inside scene |

## Security Considerations

- No security implications for UI theming

## Next Steps

Proceed to [Phase 3: AppKit Window Integration](./phase-03-appkit-window-integration.md) to update NSWindow subclasses.
