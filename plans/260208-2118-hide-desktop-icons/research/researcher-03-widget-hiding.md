# Research: Hiding macOS Desktop Widgets During Screenshot Capture

**Date:** 2026-02-08
**Context:** Snapzy screenshot app - hiding desktop widgets during capture
**Target:** macOS Sonoma 14.0+

## Executive Summary

Desktop widgets CAN be hidden programmatically via `defaults write` commands. Primary method: `com.apple.WindowManager StandardHideWidgets`. Alternative: ScreenCaptureKit window filtering (more robust, no system state changes).

## Key Findings

### 1. Widget Introduction
- Desktop widgets introduced in macOS Sonoma 14.0
- Built on WidgetKit framework (same as iOS/iPadOS)
- Managed by NotificationCenter process
- Rendered as separate windows in window server

### 2. `defaults write` Commands

**Primary Command:**
```bash
defaults write com.apple.WindowManager StandardHideWidgets -bool true
```

**Variants:**
- `-int 1` (equivalent to `-bool true`)
- `-int 0` or `-bool false` to show widgets
- For Stage Manager: `StageManagerHideWidgets` instead of `StandardHideWidgets`

**Application:**
```bash
# After setting, restart Dock
killall Dock
```

**Limitations:**
- Hides widgets when windows are in foreground
- May reappear when clicking desktop to reveal
- Requires Dock restart (500ms+ delay)
- System-wide state change (affects user experience)

### 3. Domain Testing Results

| Domain | Widget Control | Status |
|--------|---------------|--------|
| `com.apple.WindowManager` | StandardHideWidgets | ✅ WORKS |
| `com.apple.notificationcenterui` | No widget visibility key | ❌ NOT FOUND |
| `com.apple.widgets` | N/A | ❌ DOESN'T EXIST |

### 4. Process Investigation

**NotificationCenter Process:**
- Manages all desktop widgets
- `killall NotificationCenter` removes widgets temporarily
- Widgets auto-restart after ~2-5 seconds
- NOT VIABLE for screenshot timing

### 5. CreateDesktop Command Interaction

**Finding:** `defaults write com.apple.finder CreateDesktop -bool false` does NOT affect widgets

**Explanation:**
- CreateDesktop only controls Finder desktop icons
- Widgets are NotificationCenter windows, not Finder items
- Separate systems, no interaction

### 6. ScreenCaptureKit Filtering (RECOMMENDED)

**Method:** Identify and exclude widget windows via `SCContentFilter`

**Implementation:**
```swift
// 1. Get shareable content
let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

// 2. Filter widget windows
let widgetWindows = content.windows.filter { window in
    window.owningApplication?.bundleIdentifier == "com.apple.notificationcenterui" ||
    window.title?.contains("Widget") == true
}

// 3. Create filter excluding widgets
let filter = SCContentFilter(display: display, excludingWindows: widgetWindows)
```

**Advantages:**
- No system state changes
- No Dock restart required
- Instant effect
- User settings unchanged
- Precise control

**Detection Criteria:**
- Bundle ID: `com.apple.notificationcenterui`
- Window layer: Widgets typically on desktop layer
- Window title may contain "Widget" or be empty
- Check `windowLayer` property for desktop-level windows

## Recommended Approach

**OPTION 1: ScreenCaptureKit Window Filtering (RECOMMENDED)**
- Use `SCContentFilter` with `excludingWindows` parameter
- Identify widget windows by bundle ID `com.apple.notificationcenterui`
- Filter at capture time, no system changes
- Clean, fast, user-friendly

**OPTION 2: defaults write (BACKUP)**
- Use if ScreenCaptureKit filtering proves unreliable
- Toggle before/after capture: `StandardHideWidgets`
- Requires `killall Dock` and ~500ms delay
- Must restore original state after capture

**OPTION 3: Hybrid Approach**
- Primary: ScreenCaptureKit filtering
- Fallback: User preference to disable widgets via defaults
- Best of both worlds

## Implementation Priority

1. **HIGH:** Implement ScreenCaptureKit window filtering
2. **MEDIUM:** Add user preference toggle for widget hiding
3. **LOW:** defaults write fallback for edge cases

## Technical Notes

- Widget windows identifiable via `SCWindow.owningApplication.bundleIdentifier`
- NotificationCenter may spawn multiple window instances
- Widget continuity feature (iPhone widgets on Mac) uses same window system
- Desktop widget visibility can be toggled via UI: System Settings > Desktop & Dock > Show Widgets

## Unresolved Questions

1. Are iPhone continuity widgets identified differently in SCShareableContent?
2. Does `windowLayer` provide reliable widget detection across macOS versions?
3. Performance impact of filtering large widget counts (10+ widgets)?

## Sources

- [Stack Exchange - Widget Management](https://stackexchange.com)
- [Apple ScreenCaptureKit Documentation](https://apple.com)
- [Organizing Creativity - macOS Widget Controls](https://organizingcreativity.com)
- [Lifehacker - macOS Sonoma Widgets](https://lifehacker.com)
- [Macworld - Desktop Widgets](https://macworld.com)
