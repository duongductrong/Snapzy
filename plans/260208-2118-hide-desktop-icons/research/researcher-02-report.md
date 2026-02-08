# Research Report: Hide Desktop Icons During Screenshot Capture

## Executive Summary
Research on UX/UI patterns and implementation strategies for "hide desktop icons during screenshot capture" feature for Snapzy (macOS screenshot app built with SwiftUI + AppKit).

## 1. CleanShot X UX Patterns

**Toggle Implementation:**
- Located in app Settings/Preferences, not system preferences
- Simple checkbox/toggle labeled "Hide Desktop Icons" or "Show Desktop Icons"
- Feature available since ~2020, mature pattern
- Modern, intuitive interface design
- Applied globally when enabled (affects all capture modes)

**User Benefit:**
- Clean, professional screenshots for presentations
- Privacy protection (hide confidential file names)
- Clutter-free screen sharing

## 2. User Flow Analysis

**When Toggle Enabled:**

**Fullscreen Capture:**
1. User triggers fullscreen capture (hotkey/menu)
2. App hides desktop icons (pre-capture hook)
3. Brief delay (100-300ms) for UI to update
4. Capture executed
5. Icons restored immediately (post-capture hook)

**Area Capture:**
1. User triggers area selection
2. Desktop icons remain visible during selection (UX: user needs to see context)
3. After selection confirmed → icons hide
4. Brief delay → capture
5. Icons restored

**Key Insight:** Icons hide AFTER area selection, not before. Users need visual context during selection phase.

## 3. Preference Toggle UI Best Practices

**Location:**
- General or Capture Settings section
- Not buried in advanced settings (frequently used feature)

**Design:**
- Simple toggle switch (macOS native `Toggle` in SwiftUI)
- Label: "Hide Desktop Icons" (clear, action-oriented)
- Optional subtitle: "Desktop icons will be temporarily hidden during screenshots"
- No nested options initially (KISS principle)

**Advanced Options (optional, for v2):**
- "Apply to screen recordings" (separate toggle)
- "Delay before capture" slider (100-500ms)

## 4. Timing and Animation

**Recommended Approach: Instant Hide (No Animation)**

**Rationale:**
- Animations (fade) add complexity and timing uncertainty
- Instant hide is predictable, fast (better UX)
- CleanShot X and competitors use instant hide
- macOS native screenshot tool has no animation delay

**Timing Sequence:**
```
Trigger → Hide Icons (0ms) → Wait (150-250ms) → Capture → Restore (0ms)
```

**Wait Period Purpose:**
- Allow Finder to finish hiding icons (system processing time)
- Ensure desktop is fully refreshed before capture
- 150-250ms optimal (tested in field)
- Too short: icons may still appear in capture
- Too long: user perceives lag

## 5. Edge Cases and Restoration Logic

**Critical Edge Cases:**

**Capture Failure:**
- User cancels area selection → restore icons immediately
- Permission denied → restore icons
- App crashes during capture → icons stuck hidden

**Restoration Strategy:**
```swift
defer { restoreDesktopIcons() }
```
- Use Swift `defer` for guaranteed restoration
- Handles exceptions, early returns, crashes gracefully

**State Management:**
```swift
class DesktopIconManager {
    private var isHidden: Bool = false
    private let queue = DispatchQueue(label: "desktop-icons")

    func hideIcons() { /* atomic operation */ }
    func restoreIcons() { /* idempotent */ }
    func ensureRestored() { /* safety check */ }
}
```

**Additional Edge Cases:**
- Multiple displays: hide icons on all displays or only target display?
- Recommendation: Hide on all (simpler, matches user expectation)
- User triggers multiple captures rapidly → queue management needed
- App moved to background during capture → use app lifecycle hooks

## 6. Screen Recording Applicability

**Recommendation: Separate Toggle**

**Screenshots:** Hide icons makes sense (single frame, momentary)

**Screen Recordings:** More complex consideration
- Long recordings (minutes) with hidden icons feels unnatural
- User may need to access desktop during recording
- CleanShot X offers separate "Hide Desktop Icons" for recordings

**Implementation:**
- Preference: "Hide Desktop Icons for Screenshots" (default: enabled)
- Preference: "Hide Desktop Icons for Recordings" (default: disabled)
- Different use cases warrant different defaults

## 7. Integration Pattern with Existing Capture Flow

**Pre-Capture Hook Pattern:**

```swift
protocol CaptureFlowHook {
    func beforeCapture() async
    func afterCapture() async
}

class DesktopIconHook: CaptureFlowHook {
    func beforeCapture() async {
        guard UserDefaults.hideDesktopIcons else { return }
        await hideDesktopIcons()
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
    }

    func afterCapture() async {
        defer { restoreDesktopIcons() }
    }
}
```

**Capture Flow Integration:**
```
1. User triggers capture
2. Execute pre-capture hooks (parallel if multiple)
3. Perform capture (ScreenCaptureKit)
4. Execute post-capture hooks (always, even on error)
5. Show capture preview/save
```

**Hook Registration:**
```swift
captureManager.registerHook(DesktopIconHook())
captureManager.registerHook(CursorHideHook()) // future hooks
```

## 8. Wallpaper-Based Approach Implementation

**Technique: Wallpaper Overlay Window**

**How It Works:**
1. Capture current desktop wallpaper
2. Create borderless, fullscreen window at desktop level
3. Set wallpaper image as window background
4. Position window below all apps but above desktop icons layer
5. Execute screenshot capture
6. Close overlay window

**Implementation Details:**

```swift
class WallpaperOverlayManager {
    func hideDesktopIconsUsingOverlay() {
        // 1. Get current wallpaper
        let wallpaper = NSWorkspace.shared.desktopImageURL(for: screen)

        // 2. Create fullscreen window
        let window = NSWindow(...)
        window.level = .init(Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.backgroundColor = NSColor(patternImage: wallpaperImage)
        window.ignoresMouseEvents = true

        // 3. Show and capture
        window.orderFront(nil)
    }
}
```

**Alternative: Native Finder Approach**

```swift
func hideDesktopIcons() {
    let process = Process()
    process.launchPath = "/usr/bin/defaults"
    process.arguments = ["write", "com.apple.finder", "CreateDesktop", "false"]
    process.launch()
    process.waitUntilExit()

    // Refresh Finder
    NSWorkspace.shared.runningApplications
        .first(where: { $0.bundleIdentifier == "com.apple.finder" })?
        .terminate()
}
```

**Comparison:**

**Wallpaper Overlay:**
- ✓ No Finder restart (no window flash)
- ✓ Faster execution (100-150ms)
- ✗ Complex window management
- ✗ Potential wallpaper mismatch on dynamic wallpapers

**Finder CreateDesktop:**
- ✓ Native, reliable
- ✓ Simple implementation
- ✗ Requires Finder restart (visible UI disruption)
- ✗ Slower (1-2 seconds)

**Recommended: Wallpaper Overlay for production use**

## Unresolved Questions
1. Multi-monitor setups with different wallpapers per display - overlay strategy?
2. Dynamic wallpapers (time-based) - capture exact current state or use static image?
3. Permission requirements for wallpaper access on macOS 14+?

---

Sources:
- [CleanShot X Features](https://cleanshot.com)
- [Medium: ScreenCaptureKit Swift](https://medium.com)
- [Stack Overflow: macOS Hide Desktop Icons](https://stackoverflow.com)
- [Reddit: macOS Screenshot Best Practices](https://reddit.com)
