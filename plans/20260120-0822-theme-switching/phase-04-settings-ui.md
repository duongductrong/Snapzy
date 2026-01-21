# Phase 4: Settings UI

## Context

- [Plan Overview](./plan.md)
- [Phase 3: AppKit Window Integration](./phase-03-appkit-window-integration.md)
- [Codebase Structure](./scout/scout-01-codebase-structure.md)

## Overview

Add theme picker UI to GeneralSettingsView. Use SwiftUI Picker with segmented style for system/light/dark options.

## Key Insights

1. GeneralSettingsView uses Form with grouped style
2. Add "Appearance" section near top (after Startup)
3. Picker with `.pickerStyle(.segmented)` matches macOS preferences
4. Bind directly to `ThemeManager.shared.preferredAppearance`

## Requirements

- [x] Add "Appearance" section to GeneralSettingsView
- [x] Segmented picker with System/Light/Dark options
- [x] Changes apply immediately
- [x] Consistent with existing preferences UI style

## Architecture

```
GeneralSettingsView
    |
    +-- Section("Startup") - existing
    |
    +-- Section("Appearance") - NEW
    |       +-- Picker (segmented)
    |               options: AppearanceMode.allCases
    |               binding: themeManager.preferredAppearance
    |
    +-- Section("Storage") - existing
    +-- ... other sections
```

## Related Code Files

| File | Action | Purpose |
|------|--------|---------|
| `ZapShot/Features/Preferences/Tabs/GeneralSettingsView.swift` | MODIFY | Add theme picker |

## Implementation Steps

### Step 1: Add ThemeManager Property

**File:** `ZapShot/Features/Preferences/Tabs/GeneralSettingsView.swift`

Add after line 14 (after `@Environment(\.openWindow)`):

```swift
@ObservedObject private var themeManager = ThemeManager.shared
```

### Step 2: Add Appearance Section

Insert new section after "Startup" section (after line 38, before "Storage" section):

```swift
Section("Appearance") {
  Picker("Theme", selection: $themeManager.preferredAppearance) {
    ForEach(AppearanceMode.allCases) { mode in
      Text(mode.displayName).tag(mode)
    }
  }
  .pickerStyle(.segmented)
}
```

### Complete Modified GeneralSettingsView Body

```swift
var body: some View {
  Form {
    Section("Startup") {
      Toggle("Start at login", isOn: $startAtLogin)
        .onChange(of: startAtLogin) { _, newValue in
          LoginItemManager.setEnabled(newValue)
        }

      Toggle("Play sounds", isOn: $playSounds)
    }

    // NEW SECTION
    Section("Appearance") {
      Picker("Theme", selection: $themeManager.preferredAppearance) {
        ForEach(AppearanceMode.allCases) { mode in
          Text(mode.displayName).tag(mode)
        }
      }
      .pickerStyle(.segmented)
    }

    Section("Storage") {
      HStack {
        Text("Save screenshots & recordings to:")
        Spacer()
        Text(exportLocationDisplay)
          .foregroundColor(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(maxWidth: 200)
        Button("Choose...") {
          chooseExportLocation()
        }
      }
    }

    Section("Post-Capture Actions") {
      AfterCaptureMatrixView()
    }

    Section("Help") {
      Button("Restart Onboarding...") {
        restartOnboarding()
      }
      .foregroundColor(.accentColor)
    }

    Section("Software Updates") {
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
  }
  .formStyle(.grouped)
  .onAppear {
    startAtLogin = LoginItemManager.isEnabled
    initializeExportLocation()
  }
}
```

### Alternative: Inline Picker (if segmented too wide)

If segmented style looks too wide, use inline picker:

```swift
Section("Appearance") {
  Picker("Theme", selection: $themeManager.preferredAppearance) {
    ForEach(AppearanceMode.allCases) { mode in
      Text(mode.displayName).tag(mode)
    }
  }
}
```

This shows as dropdown menu, which is also standard macOS behavior.

## Todo List

- [ ] Add `@ObservedObject private var themeManager = ThemeManager.shared`
- [ ] Add "Appearance" section with Picker
- [ ] Test segmented picker appearance
- [ ] Verify theme changes apply immediately
- [ ] Verify build succeeds

## Success Criteria

1. Project compiles without errors
2. Appearance section visible in General settings
3. Three options shown: System, Light, Dark
4. Selection persists after closing preferences
5. Theme changes apply immediately to all windows

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Picker binding issues | Low | Medium | Use @ObservedObject properly |
| Segmented style too wide | Low | Low | Switch to inline style |

## Security Considerations

- No security implications for UI settings

## Next Steps

Proceed to [Phase 5: Testing & Validation](./phase-05-testing-validation.md) to verify implementation.
