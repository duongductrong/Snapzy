# Scout Report: ZapShot Codebase Structure for Theme Switching

## 1. Main App Entry Point
- `/ZapShot/App/ZapShotApp.swift` - Main entry, MenuBarExtra, WindowGroups, AppDelegate

## 2. Existing Theme/Appearance Code
Currently no centralized theme manager. Color usage scattered across:
- `Features/QuickAccess/QuickAccessCardView.swift`
- `Features/Annotate/Canvas/AnnotationRenderer.swift`
- `Features/Annotate/Window/AnnotateWindow.swift`
- `Features/Recording/RecordingToolbarView.swift`
- `Features/Onboarding/DesignSystem/VSDesignSystem.swift` - potential design system

## 3. Preferences/Settings
- `Features/Preferences/PreferencesView.swift` - main preferences view
- `Features/Preferences/PreferencesKeys.swift` - preference keys
- `Features/Preferences/PreferencesManager.swift` - preference logic
- Settings tabs: General, Shortcuts, QuickAccess, Recording, About

## 4. UI Components Needing Theme Support
- `Features/Preferences/PreferencesView.swift`
- `Features/Onboarding/OnboardingFlowView.swift`
- `Features/Annotate/Views/AnnotateCanvasView.swift`
- `Features/Recording/RecordingToolbarView.swift`
- `Features/QuickAccess/QuickAccessCardView.swift`
- `ContentView.swift`

## 5. AppKit/NSWindow Usage
- `ZapShotApp.swift` - NSApplicationDelegateAdaptor, NSApp.windows manipulation
- `AppDelegate` - window management for onboarding
- `Features/Annotate/Window/AnnotateWindow.swift` - custom window class

## Key Files for Theme Implementation
1. `ZapShotApp.swift` - apply theme at app level
2. `PreferencesManager.swift` - store theme preference
3. `PreferencesKeys.swift` - add theme key
4. `GeneralSettingsView.swift` - add theme picker UI
5. All custom NSWindow subclasses - apply window appearance
