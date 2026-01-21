# Scout Report: Sparkle 2 Integration Points

## Summary
ZapShot is a SwiftUI menu bar app for macOS 14.0+ with no existing update mechanism. Key integration points identified.

## Key Files Found

### App Entry & Delegate
- `ZapShot/App/ZapShotApp.swift` - Main @main entry, AppDelegate, MenuBarExtra
  - Uses `@NSApplicationDelegateAdaptor(AppDelegate.self)`
  - MenuBarContentView defines menu items
  - Settings scene uses `PreferencesView()`

### Preferences System
- `ZapShot/Features/Preferences/PreferencesView.swift` - Tabbed preferences (General, Shortcuts, QuickAccess, Recording, Advanced)
- `ZapShot/Features/Preferences/Tabs/GeneralSettingsView.swift` - Startup, sounds, export settings
- `ZapShot/Features/Preferences/PreferencesManager.swift`
- `ZapShot/Features/Preferences/PreferencesKeys.swift`

### Project Configuration
- `ZapShot.xcodeproj/project.pbxproj` - Xcode project file
- No Info.plist file found (uses `GENERATE_INFOPLIST_FILE = YES`)
- No Package.swift, Podfile, or Cartfile exists

## Integration Points for Sparkle 2

1. **Menu Bar** - Add "Check for Updates..." item in `MenuBarContentView`
2. **Preferences** - Add "Updates" tab or section in `GeneralSettingsView`
3. **AppDelegate** - Initialize SPUUpdater in `applicationDidFinishLaunching`
4. **Info.plist** - Need to create/configure for SUFeedURL, SUPublicEDKey
5. **Dependencies** - Add Sparkle via Swift Package Manager (preferred)

## Notes
- App uses SwiftUI throughout, no XIB/NIB files
- No existing update-related code found
- macOS 14.0+ requirement aligns well with Sparkle 2
