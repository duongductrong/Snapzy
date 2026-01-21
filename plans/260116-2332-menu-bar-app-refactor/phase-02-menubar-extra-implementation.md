# Phase 02: MenuBarExtra Implementation

## Context Links

- [Plan Overview](./plan.md)
- [Phase 01: Info.plist Configuration](./phase-01-info-plist-configuration.md)
- [Phase 03: Window Management](./phase-03-window-management.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-16 |
| Description | Replace WindowGroup with MenuBarExtra scene for menu bar app |
| Priority | High |
| Implementation Status | Pending |
| Review Status | Not Started |

## Key Insights

- `MenuBarExtra` is available in macOS 13+ (Ventura)
- Use SF Symbols for menu bar icon (`camera.aperture` recommended)
- `@Environment(\.openSettings)` opens Settings scene
- `NSApp.terminate(nil)` for quit functionality
- Onboarding requires special WindowGroup with visibility control

## Requirements

1. Replace main WindowGroup with MenuBarExtra
2. Add menu items: Capture Area, Capture Fullscreen, Divider, Preferences, Quit
3. Handle onboarding flow via separate WindowGroup
4. Maintain keyboard shortcut functionality
5. Use ScreenCaptureViewModel for capture actions

## Architecture

```
Scene Structure:
┌─────────────────────────────────────────────────────────┐
│ ZapShotApp                                              │
├─────────────────────────────────────────────────────────┤
│ MenuBarExtra("ZapShot", systemImage: "camera.aperture") │
│   ├── Button: Capture Area                              │
│   ├── Button: Capture Fullscreen                        │
│   ├── Divider                                           │
│   ├── SettingsLink: Preferences...                      │
│   ├── Divider                                           │
│   └── Button: Quit ZapShot                              │
├─────────────────────────────────────────────────────────┤
│ WindowGroup(id: "onboarding") [conditional]             │
│   └── OnboardingFlowView                                │
├─────────────────────────────────────────────────────────┤
│ Settings                                                │
│   └── PreferencesView                                   │
└─────────────────────────────────────────────────────────┘
```

## Related Code Files

| File | Purpose |
|------|---------|
| `/ZapShot/App/ZapShotApp.swift` | Main app entry - complete refactor |
| `/ZapShot/Core/ScreenCaptureViewModel.swift` | Capture logic (no changes) |
| `/ZapShot/Features/Preferences/PreferencesView.swift` | Settings UI (no changes) |
| `/ZapShot/Features/Onboarding/OnboardingFlowView.swift` | Onboarding (no changes) |

## Implementation Steps

### Step 1: Create AppDelegate for Onboarding

Create an AppDelegate to handle onboarding window on launch:

```swift
class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    if !OnboardingFlowView.hasCompletedOnboarding {
      // Open onboarding window
      if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "onboarding" }) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
      }
    }
  }
}
```

### Step 2: Refactor ZapShotApp.swift

Complete replacement of the app structure.

### Step 3: Build and Test

1. Build project
2. Verify menu bar icon appears
3. Test all menu actions
4. Verify onboarding shows on first launch

## Complete Refactored ZapShotApp.swift

```swift
//
//  ZapShotApp.swift
//  ZapShot
//
//  Main app entry point - Menu Bar App
//

import SwiftUI

@main
struct ZapShotApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @StateObject private var viewModel = ScreenCaptureViewModel()
  @State private var showOnboarding = !OnboardingFlowView.hasCompletedOnboarding

  var body: some Scene {
    // Menu Bar
    MenuBarExtra("ZapShot", systemImage: "camera.aperture") {
      MenuBarContentView(viewModel: viewModel)
    }

    // Onboarding Window (shown only when needed)
    WindowGroup(id: "onboarding") {
      OnboardingFlowView(onComplete: {
        showOnboarding = false
        // Close onboarding window
        NSApp.windows
          .filter { $0.identifier?.rawValue == "onboarding" }
          .forEach { $0.close() }
      })
      .frame(width: 500, height: 450)
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
    .defaultSize(width: 500, height: 450)

    // Settings Window
    Settings {
      PreferencesView()
    }
  }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    // Show onboarding on first launch
    if !OnboardingFlowView.hasCompletedOnboarding {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        NSApp.activate(ignoringOtherApps: true)
        // Find and show onboarding window
        for window in NSApp.windows {
          if window.identifier?.rawValue.contains("onboarding") == true {
            window.makeKeyAndOrderFront(nil)
            break
          }
        }
      }
    }
  }
}

// MARK: - Menu Bar Content

struct MenuBarContentView: View {
  @ObservedObject var viewModel: ScreenCaptureViewModel

  var body: some View {
    Group {
      // Capture Actions
      Button {
        viewModel.captureArea()
      } label: {
        Label("Capture Area", systemImage: "crop")
      }
      .keyboardShortcut("4", modifiers: [.command, .shift])
      .disabled(!viewModel.hasPermission)

      Button {
        viewModel.captureFullscreen()
      } label: {
        Label("Capture Fullscreen", systemImage: "rectangle.dashed")
      }
      .keyboardShortcut("3", modifiers: [.command, .shift])
      .disabled(!viewModel.hasPermission)

      Divider()

      // Permission Status (if not granted)
      if !viewModel.hasPermission {
        Button {
          viewModel.requestPermission()
        } label: {
          Label("Grant Permission...", systemImage: "lock.shield")
        }

        Divider()
      }

      // Preferences
      SettingsLink {
        Label("Preferences...", systemImage: "gear")
      }
      .keyboardShortcut(",", modifiers: .command)

      Divider()

      // Quit
      Button {
        NSApp.terminate(nil)
      } label: {
        Label("Quit ZapShot", systemImage: "power")
      }
      .keyboardShortcut("q", modifiers: .command)
    }
  }
}
```

## Todo List

- [ ] Backup current ZapShotApp.swift
- [ ] Replace ZapShotApp.swift with refactored code
- [ ] Build project and fix any compilation errors
- [ ] Test menu bar icon appears
- [ ] Test Capture Area functionality
- [ ] Test Capture Fullscreen functionality
- [ ] Test Preferences opens correctly
- [ ] Test Quit terminates app
- [ ] Test onboarding shows on first launch
- [ ] Verify keyboard shortcuts work

## Success Criteria

1. **Menu Bar Icon**: Camera aperture icon visible in menu bar
2. **Capture Area**: Triggers area selection overlay
3. **Capture Fullscreen**: Captures entire screen
4. **Preferences**: Opens Settings window
5. **Quit**: Terminates application cleanly
6. **Onboarding**: Shows on first launch (when hasCompletedOnboarding is false)
7. **Permission Check**: Disabled capture buttons when no permission
8. **Keyboard Shortcuts**: Cmd+Shift+3/4 work from menu

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Onboarding window not showing | Medium | High | Use AppDelegate with delay |
| ViewModel not shared properly | Low | Medium | Use @StateObject at app level |
| Menu bar icon not appearing | Low | High | Verify LSUIElement is set |
| Capture fails from menu context | Low | Medium | Test hide/unhide behavior |

## Security Considerations

- Screen Recording permission still required
- No new permissions needed
- Existing security model maintained

## Next Steps

After completing this phase:
1. Proceed to [Phase 03: Window Management](./phase-03-window-management.md)
2. Refine window activation behavior
3. Handle edge cases for multi-window scenarios
