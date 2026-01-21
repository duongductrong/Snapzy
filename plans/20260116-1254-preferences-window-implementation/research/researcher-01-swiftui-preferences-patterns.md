# SwiftUI macOS Preferences Window Patterns

## Overview
Research on best practices for implementing macOS Settings/Preferences windows in SwiftUI (2024-2026).

## 1. Settings Scene vs WindowGroup

### Settings Scene (Recommended for macOS 13+)
```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }

        Settings {
            PreferencesView()
        }
    }
}
```
- Auto-registers ⌘, keyboard shortcut
- Creates standard Preferences menu item
- Single window instance enforced

### WindowGroup Alternative (More Control)
```swift
WindowGroup(id: "preferences") {
    PreferencesView()
}
.windowResizability(.contentSize)
.windowStyle(.hiddenTitleBar)
.commandsRemoved()
```
- Use with `CommandGroup(replacing: .appSettings)` to override menu

## 2. TabView Styling for Settings

### Segmented Style (CleanShot X Style)
```swift
TabView {
    GeneralSettingsView()
        .tabItem { Label("General", systemImage: "gear") }

    ShortcutsSettingsView()
        .tabItem { Label("Shortcuts", systemImage: "keyboard") }
}
.tabViewStyle(.automatic) // Uses segmented on macOS
```

### Sidebar Adaptable (macOS 14+)
```swift
TabView {
    // tabs...
}
.tabViewStyle(.sidebarAdaptable)
```

## 3. @AppStorage for Persistence

```swift
struct GeneralSettingsView: View {
    @AppStorage("startAtLogin") private var startAtLogin = false
    @AppStorage("playSounds") private var playSounds = true
    @AppStorage("exportLocation") private var exportLocation = "Desktop"

    var body: some View {
        Form {
            Toggle("Start at login", isOn: $startAtLogin)
            Toggle("Play sounds", isOn: $playSounds)
        }
    }
}
```

## 4. Form and GroupBox Layout

```swift
Form {
    Section("Startup") {
        Toggle("Start at login", isOn: $startAtLogin)
        Toggle("Play sounds", isOn: $playSounds)
    }

    Section("Export") {
        Picker("Location", selection: $exportLocation) {
            Text("Desktop").tag("Desktop")
            Text("Documents").tag("Documents")
        }
    }
}
.formStyle(.grouped)
```

### GroupBox for Visual Grouping
```swift
GroupBox("Auto-close") {
    Toggle("Enable auto-close", isOn: $autoClose)
    if autoClose {
        Picker("Duration", selection: $duration) {
            // options
        }
    }
}
```

## 5. Launch at Login (SMAppService - macOS 13+)

```swift
import ServiceManagement

class LoginItemManager {
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update login item: \(error)")
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
```

## Key Recommendations

1. Use `Settings` scene for standard preferences behavior
2. Use segmented TabView style to match CleanShot X aesthetic
3. Leverage `@AppStorage` for simple preference persistence
4. Use `Form` with sections for organized layouts
5. Use `SMAppService` for launch at login (replaces deprecated LSSharedFileList)

## Sources
- [WWDC 2024 TabView Updates](https://developer.apple.com/videos/)
- [SerialCoder.dev SwiftUI Settings](https://serialcoder.dev)
- [Apple Developer Documentation](https://developer.apple.com)
