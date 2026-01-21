# Phase 3: Quick Access Tab Implementation

## Context

- [Main Plan](../plan.md)
- [Phase 2: General Tab](./phase-02-general-tab.md)

## Overview

Implement Quick Access settings for floating screenshot overlay - position, size, and behavior options.

## Key Insights

- FloatingScreenshotManager already has UserDefaults persistence for position, autoDismiss
- Can use @AppStorage directly since manager syncs from UserDefaults
- Add new settings: overlay size slider, drag & drop toggle, cloud upload toggle
- GroupBox for visual grouping of related behaviors

## Requirements

1. Position picker (Left/Right edge of screen)
2. Overlay Size slider (affects card dimensions)
3. Behaviors GroupBox:
   - Auto-close toggle with delay slider
   - Enable drag & drop toggle
   - Show cloud upload button toggle

## Architecture

```
QuickAccessSettingsView
  ├── Section: Position
  │   └── Picker: Left / Right
  ├── Section: Appearance
  │   └── Slider: Overlay Size (Small to Large)
  └── Section: Behaviors
      └── GroupBox
          ├── Toggle: Auto-close + Slider (conditional)
          ├── Toggle: Enable drag & drop
          └── Toggle: Show cloud upload button
```

## Related Code Files

| File | Purpose |
|------|---------|
| `ZapShot/Features/Preferences/Tabs/QuickAccessSettingsView.swift` | Settings view |
| `ZapShot/Features/FloatingScreenshot/FloatingScreenshotManager.swift` | Existing manager |
| `ZapShot/Features/FloatingScreenshot/FloatingPosition.swift` | Position enum |

## Implementation Steps

### Step 1: Extend FloatingPosition (if needed)

Current FloatingPosition has 4 corners. For Quick Access, simplify to Left/Right:

```swift
// Can add computed property or use existing
extension FloatingPosition {
    var isLeftSide: Bool {
        self == .topLeft || self == .bottomLeft
    }

    static func fromSide(_ isLeft: Bool, preferTop: Bool = false) -> FloatingPosition {
        if isLeft {
            return preferTop ? .topLeft : .bottomLeft
        } else {
            return preferTop ? .topRight : .bottomRight
        }
    }
}
```

### Step 2: Add new settings to FloatingScreenshotManager

```swift
// Add to FloatingScreenshotManager.swift
@Published var overlayScale: Double = 1.0 {
    didSet { UserDefaults.standard.set(overlayScale, forKey: Keys.overlayScale) }
}

@Published var dragDropEnabled: Bool = true {
    didSet { UserDefaults.standard.set(dragDropEnabled, forKey: Keys.dragDropEnabled) }
}

@Published var showCloudUpload: Bool = true {
    didSet { UserDefaults.standard.set(showCloudUpload, forKey: Keys.showCloudUpload) }
}

// Add to Keys enum
static let overlayScale = "floatingScreenshot.overlayScale"
static let dragDropEnabled = "floatingScreenshot.dragDropEnabled"
static let showCloudUpload = "floatingScreenshot.showCloudUpload"

// Update loadSettings()
overlayScale = UserDefaults.standard.object(forKey: Keys.overlayScale) as? Double ?? 1.0
dragDropEnabled = UserDefaults.standard.object(forKey: Keys.dragDropEnabled) as? Bool ?? true
showCloudUpload = UserDefaults.standard.object(forKey: Keys.showCloudUpload) as? Bool ?? true
```

### Step 3: Create QuickAccessSettingsView

```swift
// ZapShot/Features/Preferences/Tabs/QuickAccessSettingsView.swift
import SwiftUI

struct QuickAccessSettingsView: View {
    @ObservedObject private var manager = FloatingScreenshotManager.shared

    @State private var positionIsLeft: Bool = false

    var body: some View {
        Form {
            Section("Position") {
                Picker("Screen edge", selection: $positionIsLeft) {
                    Text("Left").tag(true)
                    Text("Right").tag(false)
                }
                .pickerStyle(.segmented)
                .onChange(of: positionIsLeft) { _, newValue in
                    manager.setPosition(newValue ? .bottomLeft : .bottomRight)
                }
            }

            Section("Appearance") {
                VStack(alignment: .leading) {
                    Text("Overlay Size")
                    HStack {
                        Text("Small")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: $manager.overlayScale, in: 0.75...1.5, step: 0.25)
                        Text("Large")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section("Behaviors") {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Auto-close overlay", isOn: $manager.autoDismissEnabled)

                        if manager.autoDismissEnabled {
                            HStack {
                                Text("Close after")
                                Slider(value: $manager.autoDismissDelay, in: 3...30, step: 1)
                                    .frame(width: 150)
                                Text("\(Int(manager.autoDismissDelay))s")
                                    .frame(width: 35)
                                    .monospacedDigit()
                            }
                            .padding(.leading, 20)
                        }

                        Divider()

                        Toggle("Enable drag & drop to apps", isOn: $manager.dragDropEnabled)

                        Toggle("Show cloud upload button", isOn: $manager.showCloudUpload)
                    }
                    .padding(4)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            positionIsLeft = manager.position.isLeftSide
        }
    }
}
```

## Todo List

- [ ] Add FloatingPosition extension for left/right helpers
- [ ] Add overlayScale, dragDropEnabled, showCloudUpload to FloatingScreenshotManager
- [ ] Update loadSettings() in FloatingScreenshotManager
- [ ] Implement QuickAccessSettingsView
- [ ] Wire overlay scale to card dimensions (FloatingCardView)
- [ ] Test position switching updates panel location
- [ ] Verify all settings persist

## Success Criteria

- [x] Position picker switches overlay between left/right edges
- [x] Overlay size slider adjusts card dimensions
- [x] Auto-close toggle shows/hides delay slider
- [x] All behavior toggles persist across restarts
- [x] Changes reflect immediately in floating overlay

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Scale affecting layout negatively | Test at min/max values, clamp range |
| Position change while cards visible | Update panel position live via panelController |

## Security Considerations

- No sensitive data, all settings are user preferences

## Next Steps

Proceed to [Phase 4: Shortcuts Tab](./phase-04-shortcuts-tab.md)
