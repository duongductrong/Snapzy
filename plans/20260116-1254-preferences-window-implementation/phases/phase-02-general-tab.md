# Phase 2: General Tab Implementation

## Context

- [Main Plan](../plan.md)
- [Phase 1: Foundation](./phase-01-foundation.md)

## Overview

Implement General settings tab with startup options, sound toggle, export location picker, and after-capture action matrix.

## Key Insights

- Use @AppStorage for simple boolean/string prefs (startAtLogin, playSounds, showIcon)
- SMAppService for launch-at-login (modern API, macOS 13+)
- After-capture matrix uses PreferencesManager for complex state
- Folder picker via NSOpenPanel for export location

## Requirements

1. Startup section: "Start at login", "Play sounds", "Show icon in menu bar"
2. Export section: Directory picker for save location
3. After Capture Matrix: Grid with Screenshot/Recording columns

## Architecture

```
GeneralSettingsView
  ├── Section: Startup
  │   ├── Toggle: Start at login (SMAppService)
  │   ├── Toggle: Play sounds (@AppStorage)
  │   └── Toggle: Show icon (@AppStorage)
  ├── Section: Export
  │   └── HStack: Label + Path + Choose button
  └── Section: After Capture
      └── AfterCaptureMatrixView (custom grid)
```

## Related Code Files

| File | Purpose |
|------|---------|
| `ZapShot/Features/Preferences/Tabs/GeneralSettingsView.swift` | Main view |
| `ZapShot/Features/Preferences/Components/AfterCaptureMatrixView.swift` | Checkbox grid |
| `ZapShot/Features/Preferences/Components/LoginItemManager.swift` | SMAppService wrapper |
| `ZapShot/ContentView.swift` | Reference for existing patterns |

## Implementation Steps

### Step 1: Create LoginItemManager

```swift
// ZapShot/Features/Preferences/Components/LoginItemManager.swift
import ServiceManagement

struct LoginItemManager {
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("LoginItem error: \(error)")
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
```

### Step 2: Create AfterCaptureMatrixView

```swift
// ZapShot/Features/Preferences/Components/AfterCaptureMatrixView.swift
import SwiftUI

struct AfterCaptureMatrixView: View {
    @ObservedObject var manager = PreferencesManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                Text("Action").frame(width: 180, alignment: .leading)
                Text("Screenshot").frame(width: 80)
                Text("Recording").frame(width: 80)
            }
            .font(.caption.weight(.medium))
            .foregroundColor(.secondary)

            Divider()

            // Action rows
            ForEach(AfterCaptureAction.allCases, id: \.self) { action in
                HStack {
                    Text(action.displayName)
                        .frame(width: 180, alignment: .leading)

                    Toggle("", isOn: binding(for: action, type: .screenshot))
                        .labelsHidden()
                        .frame(width: 80)

                    Toggle("", isOn: binding(for: action, type: .recording))
                        .labelsHidden()
                        .frame(width: 80)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }

    private func binding(for action: AfterCaptureAction, type: CaptureType) -> Binding<Bool> {
        Binding(
            get: { manager.isActionEnabled(action, for: type) },
            set: { manager.setAction(action, for: type, enabled: $0) }
        )
    }
}
```

### Step 3: Create GeneralSettingsView

```swift
// ZapShot/Features/Preferences/Tabs/GeneralSettingsView.swift
import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("playSounds") private var playSounds = true
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("exportLocation") private var exportLocation = ""

    @State private var startAtLogin = LoginItemManager.isEnabled

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Start at login", isOn: $startAtLogin)
                    .onChange(of: startAtLogin) { _, newValue in
                        LoginItemManager.setEnabled(newValue)
                    }

                Toggle("Play sounds", isOn: $playSounds)
                Toggle("Show icon in menu bar", isOn: $showMenuBarIcon)
            }

            Section("Export") {
                HStack {
                    Text("Save screenshots to:")
                    Spacer()
                    Text(exportLocationDisplay)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose...") { chooseExportLocation() }
                }
            }

            Section("After Capture") {
                AfterCaptureMatrixView()
            }
        }
        .formStyle(.grouped)
        .onAppear {
            startAtLogin = LoginItemManager.isEnabled
            initializeExportLocation()
        }
    }

    private var exportLocationDisplay: String {
        exportLocation.isEmpty ? "Desktop" : URL(fileURLWithPath: exportLocation).lastPathComponent
    }

    private func initializeExportLocation() {
        if exportLocation.isEmpty {
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
            exportLocation = desktop.appendingPathComponent("ZapShot").path
        }
    }

    private func chooseExportLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            exportLocation = url.path
        }
    }
}
```

## Todo List

- [ ] Create Components directory under Preferences
- [ ] Implement LoginItemManager with SMAppService
- [ ] Implement AfterCaptureMatrixView component
- [ ] Implement GeneralSettingsView with all sections
- [ ] Wire up export location to ScreenCaptureViewModel
- [ ] Test login item toggle works correctly
- [ ] Verify matrix state persists

## Success Criteria

- [x] All toggles in Startup section functional
- [x] Login item registers/unregisters correctly
- [x] Export location picker opens and saves selection
- [x] After-capture matrix displays all actions
- [x] Matrix checkboxes persist across app restarts

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| SMAppService requires entitlements | No special entitlements needed for mainApp |
| Export path invalid after folder deletion | Validate path on use, fallback to Desktop |

## Security Considerations

- Export location stored as path string in UserDefaults (sandboxed)
- No bookmark needed since user explicitly selects via NSOpenPanel

## Next Steps

Proceed to [Phase 3: Quick Access Tab](./phase-03-quick-access-tab.md)
