# SwiftUI macOS Theme Switching Research Report

## Executive Summary

Best practices for implementing theme switching (auto/light/dark mode) in SwiftUI macOS apps. Primary approach: SwiftUI's environment variables + modifiers, `UserDefaults` persistence, and `Assets.xcassets` dynamic colors.

## Key Findings

### Core Components
- `@Environment(\.colorScheme)` - detect system appearance
- `.preferredColorScheme()` - enforce specific theme
- `@AppStorage` - persist user preference
- `ThemeManager` ObservableObject - state management

### Best Practices
1. **Dynamic Color Assets**: Define in `Assets.xcassets` with Light/Dark variants
2. **Theme Enum**: `system`, `light`, `dark` options
3. **Centralized Manager**: ObservableObject for theme state
4. **Root-level modifier**: Apply `.preferredColorScheme()` at app level

### Implementation Pattern

```swift
enum Appearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    var id: String { self.rawValue }
}

class ThemeManager: ObservableObject {
    @AppStorage("user_preferred_appearance") var preferredAppearance: Appearance = .system

    var systemAppearance: ColorScheme? {
        switch preferredAppearance {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
        }
    }
}

@main
struct YourApp: App {
    @StateObject private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.systemAppearance)
        }
    }
}
```

### Common Pitfalls
- Hardcoded colors without Light/Dark variants
- Not persisting preference with `@AppStorage`
- Over-complicating with `NSAppearance` in pure SwiftUI

## References
- [Apple: preferredColorScheme](https://developer.apple.com/documentation/swiftui/view/preferredcolorscheme(_:))
- [Apple: @AppStorage](https://developer.apple.com/documentation/swiftui/appstorage)
