# Phase 03: Window Management

## Context Links

- [Plan Overview](./plan.md)
- [Phase 01: Info.plist Configuration](./phase-01-info-plist-configuration.md)
- [Phase 02: MenuBarExtra Implementation](./phase-02-menubar-extra-implementation.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-16 |
| Description | Handle Settings window and onboarding window management for agent app |
| Priority | Medium |
| Implementation Status | Pending |
| Review Status | Not Started |

## Key Insights

- Agent apps require explicit window activation with `NSApp.activate(ignoringOtherApps: true)`
- `SettingsLink` automatically handles Settings window opening
- `@Environment(\.openWindow)` can open WindowGroup by id
- Windows need `makeKeyAndOrderFront` to bring to front
- Onboarding window should auto-close after completion

## Requirements

1. Settings window opens and activates properly from menu
2. Onboarding window shows on first launch with proper activation
3. Windows come to front when opened (not hidden behind other apps)
4. Clean window lifecycle management

## Architecture

```
Window Management Flow:
┌─────────────────────────────────────────────────────────┐
│ Menu Bar Click                                          │
├─────────────────────────────────────────────────────────┤
│ "Preferences..." → SettingsLink                         │
│   └── SwiftUI handles Settings scene automatically      │
│   └── NSApp.activate brings to front                    │
├─────────────────────────────────────────────────────────┤
│ App Launch (First Time)                                 │
│   └── AppDelegate.applicationDidFinishLaunching        │
│   └── Check hasCompletedOnboarding                      │
│   └── Activate app and show onboarding window           │
├─────────────────────────────────────────────────────────┤
│ Onboarding Complete                                     │
│   └── Set hasCompletedOnboarding = true                 │
│   └── Close onboarding window                           │
│   └── App continues as menu bar only                    │
└─────────────────────────────────────────────────────────┘
```

## Related Code Files

| File | Purpose |
|------|---------|
| `/ZapShot/App/ZapShotApp.swift` | Window scene definitions |
| `/ZapShot/Features/Onboarding/OnboardingFlowView.swift` | Onboarding UI |
| `/ZapShot/Features/Preferences/PreferencesView.swift` | Settings UI |

## Implementation Steps

### Step 1: Enhanced AppDelegate

```swift
class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    if !OnboardingFlowView.hasCompletedOnboarding {
      // Delay to ensure window is created
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        self.showOnboardingWindow()
      }
    }
  }

  private func showOnboardingWindow() {
    NSApp.activate(ignoringOtherApps: true)
    for window in NSApp.windows {
      if window.identifier?.rawValue.contains("onboarding") == true {
        window.makeKeyAndOrderFront(nil)
        window.center()
        return
      }
    }
  }
}
```

### Step 2: Window Activation Helper

Add utility for consistent window activation:

```swift
extension NSApplication {
  func activateAndShowWindow(identifier: String) {
    activate(ignoringOtherApps: true)
    for window in windows {
      if window.identifier?.rawValue.contains(identifier) == true {
        window.makeKeyAndOrderFront(nil)
        break
      }
    }
  }
}
```

### Step 3: Onboarding Completion Handler

```swift
OnboardingFlowView(onComplete: {
  // Mark completed
  UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")

  // Close all onboarding windows
  NSApp.windows
    .filter { $0.identifier?.rawValue.contains("onboarding") == true }
    .forEach { $0.close() }
})
```

## Todo List

- [ ] Implement AppDelegate with onboarding window handling
- [ ] Add window activation helper extension
- [ ] Test Settings window opens from menu
- [ ] Test onboarding window shows on first launch
- [ ] Test onboarding window closes after completion
- [ ] Verify windows come to front properly
- [ ] Test multi-monitor behavior

## Success Criteria

1. **Settings Activation**: Settings window appears in front of all other windows
2. **Onboarding First Launch**: Window shows centered and focused on first run
3. **Onboarding Dismiss**: Window closes cleanly after completion
4. **No Orphan Windows**: All windows close when appropriate
5. **Multi-Monitor**: Windows appear on active display

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Window not coming to front | Medium | Medium | Use activate + makeKeyAndOrderFront |
| Onboarding window not found | Low | High | Add delay for window creation |
| Multiple onboarding windows | Low | Low | Filter and close all matching |

## Security Considerations

- No security implications for window management
- User preferences stored in standard UserDefaults
- No sensitive data in window state

## Next Steps

After completing all phases:
1. Full integration testing
2. Test on clean install (onboarding flow)
3. Test after onboarding (menu bar only)
4. Verify all capture functionality works
5. Update documentation if needed
