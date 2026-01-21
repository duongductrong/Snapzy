# Phase 1: Foundation - Settings Scene & PreferencesManager

## Context

- [Main Plan](../plan.md)
- [SwiftUI Preferences Research](../research/researcher-01-swiftui-preferences-patterns.md)

## Overview

Establish Settings scene in app entry point, create PreferencesManager for centralized state, and build root TabView container.

## Key Insights

- `Settings` scene auto-registers Cmd+, shortcut and creates standard menu item
- Segmented TabView style matches CleanShot X aesthetic
- PreferencesManager handles complex state (after-capture matrix) while simple prefs use @AppStorage

## Requirements

1. Add Settings scene to ZapShotApp
2. Create PreferencesManager singleton for shared state
3. Build PreferencesView with 7-tab TabView
4. Define AfterCaptureAction enum and matrix state

## Architecture

```swift
// PreferencesManager - Singleton for complex prefs
@MainActor
final class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()

    // After-capture matrix: [ActionType: [CaptureType: Bool]]
    @Published var afterCaptureActions: [AfterCaptureAction: [CaptureType: Bool]]

    // Methods to update and persist matrix
}

// Enums
enum AfterCaptureAction: String, CaseIterable, Codable {
    case showQuickAccess, copyFile, save, uploadCloud
}

enum CaptureType: String, CaseIterable, Codable {
    case screenshot, recording
}
```

## Related Code Files

| File | Purpose |
|------|---------|
| `ZapShot/App/ZapShotApp.swift` | Add Settings scene |
| `ZapShot/Features/Preferences/PreferencesView.swift` | Root TabView |
| `ZapShot/Features/Preferences/PreferencesManager.swift` | State singleton |

## Implementation Steps

### Step 1: Create PreferencesManager

```swift
// ZapShot/Features/Preferences/PreferencesManager.swift
import Foundation

enum AfterCaptureAction: String, CaseIterable, Codable {
    case showQuickAccess = "showQuickAccess"
    case copyFile = "copyFile"
    case save = "save"
    case uploadCloud = "uploadCloud"

    var displayName: String {
        switch self {
        case .showQuickAccess: return "Show Quick Access Overlay"
        case .copyFile: return "Copy file"
        case .save: return "Save"
        case .uploadCloud: return "Upload to Cloud"
        }
    }
}

enum CaptureType: String, CaseIterable, Codable {
    case screenshot, recording
}

@MainActor
final class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()

    @Published var afterCaptureActions: [AfterCaptureAction: [CaptureType: Bool]] = [:]

    private let key = "afterCaptureActions"

    private init() {
        loadAfterCaptureActions()
    }

    func setAction(_ action: AfterCaptureAction, for type: CaptureType, enabled: Bool) {
        afterCaptureActions[action, default: [:]][type] = enabled
        saveAfterCaptureActions()
    }

    func isActionEnabled(_ action: AfterCaptureAction, for type: CaptureType) -> Bool {
        afterCaptureActions[action]?[type] ?? defaultValue(for: action, type: type)
    }

    private func defaultValue(for action: AfterCaptureAction, type: CaptureType) -> Bool {
        action == .showQuickAccess || action == .save
    }

    private func saveAfterCaptureActions() {
        // Encode to JSON and save to UserDefaults
    }

    private func loadAfterCaptureActions() {
        // Load from UserDefaults and decode
    }
}
```

### Step 2: Create PreferencesView

```swift
// ZapShot/Features/Preferences/PreferencesView.swift
import SwiftUI

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }

            Text("Wallpaper").tabItem { Label("Wallpaper", systemImage: "photo") }

            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }

            QuickAccessSettingsView()
                .tabItem { Label("Quick Access", systemImage: "square.stack") }

            Text("Recording").tabItem { Label("Recording", systemImage: "video") }

            Text("Cloud").tabItem { Label("Cloud", systemImage: "cloud") }

            Text("Advanced").tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 500, height: 400)
    }
}
```

### Step 3: Update ZapShotApp

```swift
// ZapShot/App/ZapShotApp.swift
import SwiftUI

@main
struct ZapShotApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Settings {
            PreferencesView()
        }
    }
}
```

## Todo List

- [ ] Create Preferences feature directory structure
- [ ] Implement PreferencesManager with after-capture matrix
- [ ] Create PreferencesView with TabView and placeholder tabs
- [ ] Add Settings scene to ZapShotApp
- [ ] Verify Cmd+, opens Preferences window
- [ ] Test that Preferences menu item appears in app menu

## Success Criteria

- [x] Settings scene registered in app
- [x] Cmd+, keyboard shortcut opens Preferences
- [x] Preferences menu item visible in app menu
- [x] TabView displays with 7 tabs
- [x] PreferencesManager singleton accessible

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| macOS version compatibility | Require macOS 13+ in deployment target |
| Tab count causing layout issues | Use fixed frame size, test all tabs |

## Security Considerations

- No sensitive data in PreferencesManager
- UserDefaults storage is app-sandboxed

## Next Steps

Proceed to [Phase 2: General Tab](./phase-02-general-tab.md)
