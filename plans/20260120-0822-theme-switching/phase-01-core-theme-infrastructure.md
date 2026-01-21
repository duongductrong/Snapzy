# Phase 1: Core Theme Infrastructure

## Context

- [Plan Overview](./plan.md)
- [SwiftUI Theming Research](./research/researcher-01-swiftui-theming.md)
- [macOS Theming Research](./research/researcher-02-macos-theming.md)

## Overview

Create foundational theme management: `AppearanceMode` enum, `ThemeManager` ObservableObject, and preference key. This phase establishes the single source of truth for theme state.

## Key Insights

1. Use `@AppStorage` for automatic UserDefaults persistence
2. `ColorScheme?` where `nil` means follow system
3. `NSAppearance?` where `nil` means follow system
4. Singleton pattern for AppKit window access

## Requirements

- [x] `AppearanceMode` enum with system/light/dark cases
- [x] `ThemeManager` as shared ObservableObject
- [x] Add preference key to `PreferencesKeys.swift`
- [x] Provide both SwiftUI `ColorScheme?` and AppKit `NSAppearance?`

## Architecture

```
AppearanceMode (enum)
    - system, light, dark
    - RawRepresentable<String> for @AppStorage

ThemeManager (ObservableObject, @MainActor)
    - @AppStorage preferredAppearance
    - systemAppearance: ColorScheme? (computed)
    - nsAppearance: NSAppearance? (computed)
    - static shared instance
```

## Related Code Files

| File | Action | Purpose |
|------|--------|---------|
| `ZapShot/Features/Preferences/PreferencesKeys.swift` | MODIFY | Add `appearanceMode` key |
| `ZapShot/Core/Theme/AppearanceMode.swift` | CREATE | Define appearance enum |
| `ZapShot/Core/Theme/ThemeManager.swift` | CREATE | Theme state management |

## Implementation Steps

### Step 1: Add Preference Key

**File:** `ZapShot/Features/Preferences/PreferencesKeys.swift`

Add after line 16 (after `exportLocation`):

```swift
  // Appearance
  static let appearanceMode = "appearanceMode"
```

### Step 2: Create AppearanceMode Enum

**File:** `ZapShot/Core/Theme/AppearanceMode.swift` (NEW)

```swift
//
//  AppearanceMode.swift
//  ZapShot
//
//  User appearance preference: system, light, or dark
//

import Foundation

/// User preference for app appearance
enum AppearanceMode: String, CaseIterable, Identifiable {
  case system = "System"
  case light = "Light"
  case dark = "Dark"

  var id: String { rawValue }

  /// Display name for UI
  var displayName: String { rawValue }
}
```

### Step 3: Create ThemeManager

**File:** `ZapShot/Core/Theme/ThemeManager.swift` (NEW)

```swift
//
//  ThemeManager.swift
//  ZapShot
//
//  Centralized theme state management for SwiftUI and AppKit
//

import AppKit
import SwiftUI

/// Manages app-wide appearance/theme state
@MainActor
final class ThemeManager: ObservableObject {

  static let shared = ThemeManager()

  /// User's preferred appearance mode, persisted to UserDefaults
  @AppStorage(PreferencesKeys.appearanceMode)
  var preferredAppearance: AppearanceMode = .system {
    didSet {
      objectWillChange.send()
    }
  }

  private init() {}

  // MARK: - SwiftUI

  /// ColorScheme for SwiftUI's .preferredColorScheme() modifier
  /// Returns nil to follow system appearance
  var systemAppearance: ColorScheme? {
    switch preferredAppearance {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
  }

  // MARK: - AppKit

  /// NSAppearance for NSWindow.appearance property
  /// Returns nil to follow system appearance
  var nsAppearance: NSAppearance? {
    switch preferredAppearance {
    case .system: return nil
    case .light: return NSAppearance(named: .aqua)
    case .dark: return NSAppearance(named: .darkAqua)
    }
  }
}

// MARK: - AppearanceMode RawRepresentable Extension

extension AppearanceMode: RawRepresentable {
  // Already RawRepresentable via String raw value
}
```

### Step 4: Create Theme Directory

Create directory structure:
```
ZapShot/Core/Theme/
├── AppearanceMode.swift
└── ThemeManager.swift
```

## Todo List

- [ ] Add `appearanceMode` key to PreferencesKeys.swift
- [ ] Create `ZapShot/Core/Theme/` directory
- [ ] Create AppearanceMode.swift
- [ ] Create ThemeManager.swift
- [ ] Add files to Xcode project
- [ ] Verify build succeeds

## Success Criteria

1. Project compiles without errors
2. `ThemeManager.shared` accessible from any file
3. `@AppStorage` correctly persists preference
4. Both `systemAppearance` and `nsAppearance` return correct values

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| @AppStorage type mismatch | Low | Medium | Use String RawRepresentable |
| Singleton threading issues | Low | Low | @MainActor annotation |

## Security Considerations

- No sensitive data stored
- UserDefaults storage is appropriate for UI preferences

## Next Steps

Proceed to [Phase 2: SwiftUI Integration](./phase-02-swiftui-integration.md) to apply theme to SwiftUI scenes.
