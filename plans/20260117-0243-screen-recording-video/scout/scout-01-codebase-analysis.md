# Scout Report: ZapShot Codebase Analysis for Screen Recording

## Summary
Analyzed ZapShot codebase for screen recording implementation. Found existing ScreenCaptureKit integration, area selection system, keyboard shortcuts, preferences structure, and onboarding flow.

## Key Files Found

### 1. Screen Capture Core
| File | Purpose |
|------|---------|
| `ZapShot/Core/ScreenCaptureManager.swift` | Main capture manager using ScreenCaptureKit (SCShareableContent, SCContentFilter, SCStreamConfiguration, SCScreenshotManager). Handles permissions, fullscreen/area capture, image saving. |
| `ZapShot/Core/ScreenCaptureViewModel.swift` | ViewModel for screen capture UI state |

**Key APIs Used:**
- `SCShareableContent.current` - get available displays
- `SCContentFilter` - filter by display
- `SCStreamConfiguration` - configure capture dimensions, pixel format
- `SCScreenshotManager.captureImage()` - single frame capture

**Reusable Patterns:**
- Permission checking via `SCShareableContent.current`
- Display enumeration
- Image saving with `CGImageDestination`

### 2. Area Selection System
| File | Purpose |
|------|---------|
| `ZapShot/Core/AreaSelectionWindow.swift` | Full overlay system for area selection |

**Components:**
- `AreaSelectionController` - manages overlay windows across all screens, handles completion callbacks
- `AreaSelectionWindow` - borderless NSWindow covering screen
- `AreaSelectionOverlayView` - draws dimming, crosshair, selection rect, size indicator

**Reusable for Recording:**
- Same area selection flow can trigger recording instead of screenshot
- Overlay system supports multi-monitor
- Escape key handling already implemented

### 3. Keyboard Shortcuts
| File | Purpose |
|------|---------|
| `ZapShot/Core/KeyboardShortcutManager.swift` | Global hotkey registration using Carbon APIs |

**Current Shortcuts:**
- `⌘⇧3` - Capture Fullscreen (default)
- `⌘⇧4` - Capture Area (default)
- **`⌘⇧5` available for recording**

**Key Types:**
- `ShortcutConfig` - keyCode + modifiers, Codable, displayString
- `ShortcutAction` - enum (captureFullscreen, captureArea) - **needs recordVideo case**
- `KeyboardShortcutDelegate` - protocol for handling triggers

**Extension Points:**
- Add `recordVideo` to `ShortcutAction` enum
- Add `recordingShortcut` property (default `⌘⇧5`)
- Register third hotkey in `registerShortcuts()`

### 4. Preferences Structure
| File | Purpose |
|------|---------|
| `ZapShot/Features/Preferences/PreferencesView.swift` | Main preferences TabView |
| `ZapShot/Features/Preferences/Tabs/PlaceholderSettingsView.swift` | Placeholder for Recording tab |
| `ZapShot/Features/Preferences/Tabs/GeneralSettingsView.swift` | General settings with export location |
| `ZapShot/Features/Preferences/PreferencesKeys.swift` | UserDefaults keys |

**Current Tabs:**
1. General
2. Shortcuts
3. Quick Access
4. Recording (placeholder - "Coming Soon")
5. Advanced (placeholder)

**Recording Tab Needs:**
- Video format picker (.mov, .mp4)
- Frame rate option
- Audio toggle (system/mic)
- Quality setting
- Save location (can reuse `exportLocation` or add `recordingExportLocation`)

### 5. Onboarding Flow
| File | Purpose |
|------|---------|
| `ZapShot/Features/Onboarding/OnboardingFlowView.swift` | Main onboarding coordinator |

**Current Steps:**
1. `WelcomeView` - intro
2. `PermissionsView` - screen recording permission
3. `ShortcutsView` - enable keyboard shortcuts

**Extension for Recording:**
- Add recording info to WelcomeView or new step
- Mention `⌘⇧5` shortcut in ShortcutsView

### 6. Menu Bar
| File | Purpose |
|------|---------|
| `ZapShot/App/ZapShotApp.swift` | Main app with MenuBarExtra |

**Current Menu Items:**
- Capture Area (⌘⇧4)
- Capture Fullscreen (⌘⇧3)
- Grant Permission
- Preferences (⌘,)
- Quit (⌘Q)

**Add:**
- "Record Screen" with ⌘⇧5 shortcut
- Divider between capture and record

### 7. Export/Save
| File | Purpose |
|------|---------|
| `ZapShot/Features/Preferences/Tabs/GeneralSettingsView.swift` | Export location picker |
| `ZapShot/Features/Annotate/Services/AnnotateExporter.swift` | Image export service |

**Current Export:**
- `PreferencesKeys.exportLocation` - user-selected directory
- Default: `~/Desktop/ZapShot`
- Format support: PNG, JPEG, TIFF (images only)

**For Recording:**
- Can reuse same export location or add separate `recordingExportLocation`
- Need new `VideoFormat` enum (.mov, .mp4)
- Need `RecordingExporter` service

## Architecture Recommendations

### New Files Needed
```
ZapShot/
├── Core/
│   ├── ScreenRecordingManager.swift    # SCStream-based recording
│   └── RecordingControlWindow.swift    # Floating toolbar
├── Features/
│   ├── Recording/
│   │   ├── RecordingSettingsView.swift # Preferences tab
│   │   ├── RecordingToolbarView.swift  # Bottom control bar
│   │   └── RecordingTimerView.swift    # Timer display
│   └── Preferences/Tabs/
│       └── RecordingSettingsView.swift # Replace placeholder
```

### Integration Points
1. **KeyboardShortcutManager** - add `.recordVideo` action
2. **ScreenCaptureViewModel** - add `startRecording()`, `stopRecording()`
3. **MenuBarContentView** - add Record Screen button
4. **OnboardingFlowView** - mention recording feature
5. **PreferencesView** - replace Recording placeholder

## Unresolved Questions
1. Should recording use same export location as screenshots or separate?
2. Audio capture: system audio only, mic only, or both?
3. Show cursor during recording - same toggle as screenshots or separate?
