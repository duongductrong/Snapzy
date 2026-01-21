# Phase 2: Updater Integration

## Context
- [Main Plan](./plan.md)
- [Phase 1: Sparkle Setup](./phase-01-sparkle-setup.md)
- [Implementation Research](./research/researcher-02-sparkle-implementation.md)

## Overview
| Field | Value |
|-------|-------|
| Date | 2026-01-18 |
| Description | Integrate SPUStandardUpdaterController in SwiftUI, add menu item and preferences |
| Priority | High |
| Status | Not Started |

## Key Insights
- SwiftUI apps require programmatic setup (no XIB/NIB)
- SPUStandardUpdaterController manages update lifecycle
- Must observe `canCheckForUpdates` to enable/disable button
- Sparkle auto-checks every 24h by default after first permission grant

## Requirements
1. Create SPUStandardUpdaterController instance in ZapShotApp
2. Add "Check for Updates..." button in MenuBarContentView
3. Create CheckForUpdatesView with proper state binding
4. Add update preferences in GeneralSettingsView

## Architecture
```
ZapShotApp
├── SPUStandardUpdaterController (initialized once)
│   └── SPUUpdater (accessed via .updater property)
│
├── MenuBarContentView
│   └── CheckForUpdatesView (uses SPUUpdater)
│
└── GeneralSettingsView
    └── UpdateSettingsSection (automatic checks toggle)
```

## Related Files
| File | Changes |
|------|---------|
| `ZapShot/App/ZapShotApp.swift` | Add updaterController, pass to views |
| `ZapShot/Features/Preferences/Tabs/GeneralSettingsView.swift` | Add Updates section |
| `ZapShot/Features/Updates/CheckForUpdatesView.swift` | New file |

## Implementation Steps

### Step 1: Create CheckForUpdatesView.swift
Create new file at `ZapShot/Features/Updates/CheckForUpdatesView.swift`:

```swift
//
//  CheckForUpdatesView.swift
//  ZapShot
//
//  SwiftUI view for "Check for Updates..." menu item
//

import SwiftUI
import Sparkle

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates...") {
            updater.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}
```

### Step 2: Update ZapShotApp.swift
Add SPUStandardUpdaterController to main app:

```swift
import SwiftUI
import Sparkle  // Add import

@main
struct ZapShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = ScreenCaptureViewModel()
    @State private var showOnboarding = !OnboardingFlowView.hasCompletedOnboarding

    // Add updater controller
    private let updaterController: SPUStandardUpdaterController

    init() {
        // Initialize updater - starts automatic update checks
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        MenuBarExtra("ZapShot", systemImage: "camera.aperture") {
            MenuBarContentView(
                viewModel: viewModel,
                updater: updaterController.updater  // Pass updater
            )
        }
        // ... rest unchanged
    }
}
```

### Step 3: Update MenuBarContentView
Add "Check for Updates..." menu item:

```swift
struct MenuBarContentView: View {
    @ObservedObject var viewModel: ScreenCaptureViewModel
    let updater: SPUUpdater  // Add property

    var body: some View {
        Group {
            // ... existing capture buttons ...

            Divider()

            // Check for Updates
            CheckForUpdatesView(updater: updater)

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

### Step 4: Add Update Settings in GeneralSettingsView
Add section to GeneralSettingsView:

```swift
import Sparkle  // Add import

struct GeneralSettingsView: View {
    // ... existing properties ...

    // Add updater binding for settings
    private let updater = SPUStandardUpdaterController(
        startingUpdater: false,  // Don't start another instance
        updaterDelegate: nil,
        userDriverDelegate: nil
    ).updater

    var body: some View {
        Form {
            // ... existing sections ...

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))

                Toggle("Automatically download updates", isOn: Binding(
                    get: { updater.automaticallyDownloadsUpdates },
                    set: { updater.automaticallyDownloadsUpdates = $0 }
                ))

                HStack {
                    Text("Last checked:")
                    Spacer()
                    if let lastCheck = updater.lastUpdateCheckDate {
                        Text(lastCheck, style: .relative)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Never")
                            .foregroundColor(.secondary)
                    }
                }
            }

            // ... existing Help section ...
        }
    }
}
```

### Step 5: Alternative - Shared Updater Controller
For cleaner architecture, create shared updater:

Create `ZapShot/Core/UpdaterManager.swift`:
```swift
import Sparkle

final class UpdaterManager {
    static let shared = UpdaterManager()

    let controller: SPUStandardUpdaterController
    var updater: SPUUpdater { controller.updater }

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
}
```

Then use `UpdaterManager.shared.updater` throughout app.

## Todo List
- [ ] Create `CheckForUpdatesView.swift`
- [ ] Add `import Sparkle` to ZapShotApp.swift
- [ ] Create SPUStandardUpdaterController in ZapShotApp
- [ ] Pass updater to MenuBarContentView
- [ ] Add CheckForUpdatesView to menu
- [ ] Add Updates section to GeneralSettingsView
- [ ] Test "Check for Updates..." button
- [ ] Test automatic check toggle

## Success Criteria
1. "Check for Updates..." appears in menu bar dropdown
2. Button disabled when update check in progress
3. Clicking triggers Sparkle update check UI
4. Preferences show update toggles
5. Automatic checks work after 24h (or manual trigger)

## Risk Assessment
| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Multiple updater instances | Medium | Medium | Use shared singleton |
| Button always disabled | High | Low | Verify Info.plist keys present |
| UI not appearing | Medium | Low | Check Console.app for Sparkle logs |

## Security Considerations
- Sparkle validates EdDSA signatures automatically
- Updates served over HTTPS only
- Code signing verified before installation

## Next Steps
After completing Phase 2:
1. Proceed to [Phase 3: Signing & Appcast](./phase-03-signing-appcast.md)
2. Set up appcast hosting and signing workflow
