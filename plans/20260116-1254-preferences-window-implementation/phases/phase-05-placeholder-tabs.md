# Phase 5: Placeholder Tabs Implementation

## Context

- [Main Plan](../plan.md)
- [Phase 4: Shortcuts Tab](./phase-04-shortcuts-tab.md)

## Overview

Create placeholder views for future tabs: Wallpaper, Recording, Cloud, Advanced.

## Key Insights

- Placeholders should indicate "Coming Soon" status
- Maintain consistent styling with other tabs
- Use meaningful icons and descriptions for each
- Easy to replace with real implementations later

## Requirements

1. Wallpaper tab - future background/frame customization
2. Recording tab - future screen recording settings
3. Cloud tab - future cloud upload integration
4. Advanced tab - future power-user settings

## Implementation

### PlaceholderSettingsView

```swift
// ZapShot/Features/Preferences/Tabs/PlaceholderSettingsView.swift
import SwiftUI

struct PlaceholderSettingsView: View {
    let title: String
    let icon: String
    let description: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(title)
                .font(.title2)
                .fontWeight(.medium)

            Text(description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Text("Coming Soon")
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Convenience initializers for each tab
extension PlaceholderSettingsView {
    static var wallpaper: PlaceholderSettingsView {
        PlaceholderSettingsView(
            title: "Wallpaper",
            icon: "photo.artframe",
            description: "Customize screenshot backgrounds, add frames, and apply visual effects."
        )
    }

    static var recording: PlaceholderSettingsView {
        PlaceholderSettingsView(
            title: "Recording",
            icon: "video.fill",
            description: "Configure screen recording quality, format, and audio settings."
        )
    }

    static var cloud: PlaceholderSettingsView {
        PlaceholderSettingsView(
            title: "Cloud",
            icon: "cloud.fill",
            description: "Connect cloud services for automatic screenshot uploads and sharing."
        )
    }

    static var advanced: PlaceholderSettingsView {
        PlaceholderSettingsView(
            title: "Advanced",
            icon: "slider.horizontal.3",
            description: "Fine-tune performance, file naming, and other power-user settings."
        )
    }
}
```

### Update PreferencesView

```swift
// Update PreferencesView.swift to use placeholders
TabView {
    GeneralSettingsView()
        .tabItem { Label("General", systemImage: "gear") }

    PlaceholderSettingsView.wallpaper
        .tabItem { Label("Wallpaper", systemImage: "photo") }

    ShortcutsSettingsView()
        .tabItem { Label("Shortcuts", systemImage: "keyboard") }

    QuickAccessSettingsView()
        .tabItem { Label("Quick Access", systemImage: "square.stack") }

    PlaceholderSettingsView.recording
        .tabItem { Label("Recording", systemImage: "video") }

    PlaceholderSettingsView.cloud
        .tabItem { Label("Cloud", systemImage: "cloud") }

    PlaceholderSettingsView.advanced
        .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
}
```

## Todo List

- [ ] Create PlaceholderSettingsView with static factory methods
- [ ] Update PreferencesView to use placeholder tabs
- [ ] Verify all 7 tabs display correctly
- [ ] Test tab switching performance

## Success Criteria

- [x] All placeholder tabs show appropriate icon and description
- [x] "Coming Soon" badge visible on each placeholder
- [x] Tab switching is smooth
- [x] Placeholders maintain consistent styling

## Next Steps

Proceed to [Phase 6: Integration](./phase-06-integration.md)
