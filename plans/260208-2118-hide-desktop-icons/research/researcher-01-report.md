# Research Report: Hide Desktop Icons on macOS Programmatically

**Project:** Snapzy Screenshot App
**Date:** 2026-02-08
**Focus:** Programmatic desktop icon hiding for clean screenshots

---

## Executive Summary

No official AppKit/NSWorkspace API exists for hiding desktop icons. Primary method: `defaults write com.apple.finder CreateDesktop -bool false` + Finder restart. Major tradeoff: visual disruption vs. clean screenshot. Alternative: overlay approach or selective window capture.

---

## 1. macOS APIs for Hiding Desktop Icons

### Official APIs
- **None exist** - No documented AppKit/NSWorkspace method for desktop icon control
- `NSWorkspace.hideOtherApplications()` - hides apps, NOT desktop icons
- `NSWorkspace` desktop image methods - only wallpaper management, not icons

### Undocumented Method (Primary Approach)
```swift
// Hide icons
defaults write com.apple.finder CreateDesktop -bool false
killall Finder

// Show icons
defaults write com.apple.finder CreateDesktop -bool true
killall Finder
```

**Implementation in Swift:**
```swift
Process.launchedProcess(
    launchPath: "/usr/bin/defaults",
    arguments: ["write", "com.apple.finder", "CreateDesktop", "-bool", "false"]
)
Process.launchedProcess(
    launchPath: "/usr/bin/killall",
    arguments: ["Finder"]
)
```

### Private APIs
- StackExchange mentions Swift class watching notifications for hide/unhide
- No concrete implementation details found
- Risk: App Store rejection, future macOS breakage

---

## 2. How CleanShot X Implements This

**Features:**
- "Hide while capturing" setting (General tab)
- "Toggle Desktop Icons" keyboard shortcut (independent of capture)
- Seamless integration with screenshot workflow

**Likely Implementation:**
- Uses `defaults write` + `killall Finder` method
- Pre-hides icons before capture UI appears
- Timing optimization to minimize Finder restart visibility
- May cache/restore previous CreateDesktop state

**User Experience Focus:**
- Toggle available outside screenshot context (meetings, screen sharing)
- Clean, professional captures without manual cleanup

---

## 3. `defaults write` Approach - Deep Dive

### How It Works
- Modifies `~/Library/Preferences/com.apple.finder.plist`
- Sets `CreateDesktop` key to boolean false
- Finder reads this on launch to determine desktop rendering
- Requires Finder restart (`killall Finder`) to apply

### Limitations

**1. Visual Disruption (~1-2 seconds)**
- Finder quits, all Finder windows close briefly
- Desktop flashes/reloads
- Dock may flicker
- User sees the transition - NOT seamless

**2. Timing Issues**
- Must wait for Finder restart completion before screenshot
- No reliable callback/notification when Finder fully restarted
- Workaround: `sleep 1-2` or poll for Finder process

**3. Sandboxing Problems**
- Sandboxed apps cannot execute `/usr/bin/killall` or `/usr/bin/defaults`
- Error: "No such file or directory" or permission denied
- **Solution:** Disable app sandbox entitlement (risky for App Store)

**4. State Management**
- Must track previous `CreateDesktop` value to restore properly
- If app crashes mid-toggle, user's desktop stays hidden
- Need crash recovery mechanism

**5. macOS Version Compatibility**
- Undocumented preference - Apple can remove anytime
- Works on macOS 10.x through 14.x+ (as of 2026)
- No guarantee for future macOS versions

**6. Case Sensitivity**
- `killall Finder` (capital F) required
- `killall finder` fails silently

---

## 4. Alternative Approaches

### A. Wallpaper Overlay Window

**Concept:**
- Create fullscreen window above desktop (below dock/menubar)
- Set window background to current wallpaper image
- Covers desktop icons without Finder restart

**Implementation:**
```swift
// Pseudo-code
let overlayWindow = NSWindow(
    contentRect: NSScreen.main.frame,
    styleMask: .borderless,
    backing: .buffered,
    defer: false
)
overlayWindow.level = .init(Int(CGWindowLevelForKey(.desktopWindow)) + 1)
overlayWindow.backgroundColor = NSColor(patternImage: getWallpaperImage())
overlayWindow.ignoresMouseEvents = true
overlayWindow.orderFront(nil)
```

**Pros:**
- No Finder restart needed - instant
- Works in sandboxed apps
- Seamless user experience
- Reversible immediately

**Cons:**
- Must detect current wallpaper(s) per display
- Multi-monitor complexity (different wallpapers)
- Doesn't hide widgets/Stacks (they render above desktop)
- Dynamic wallpapers (time-based) require continuous update
- Wallpaper positioning/scaling must match exactly

### B. CGWindow API Selective Capture

**Concept:**
- Use `CGWindowListCreateImageFromArray()` to capture specific windows only
- Exclude desktop window (`kCGWindowLayer == kCGDesktopWindowLevel`)
- Composite desktop wallpaper as background

**Implementation:**
```swift
// Get window list
let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
// Filter out desktop window
let filteredWindows = // exclude desktop layer windows
// Capture
CGWindowListCreateImageFromArray(bounds, windowIDArray, .boundsIgnoreFraming)
```

**Pros:**
- No Finder manipulation needed
- Captures exactly what user sees minus desktop icons
- Works in sandbox

**Cons:**
- Complex window filtering logic
- May miss some window layers
- Wallpaper compositing required
- Requires Screen Recording permission

### C. `chflags hidden` Approach

**Command:**
```bash
chflags hidden ~/Desktop/*
chflags nohidden ~/Desktop/*  # restore
```

**Pros:**
- No Finder restart needed
- Desktop items still accessible (just invisible)

**Cons:**
- **Sandboxing blocker** - cannot access `~/Desktop/` from sandboxed app
- Must iterate each file individually (slow for many files)
- User's items remain hidden after capture (bad UX)
- Doesn't affect desktop widgets/Stacks

**Verdict:** Not viable for sandboxed apps

---

## 5. Timing Considerations

### Optimal Sequence (defaults write method)

```
1. Read current CreateDesktop value (for restore)
2. Write CreateDesktop = false
3. killall Finder
4. Wait 1.5-2s (or poll for Finder process)
5. Trigger screenshot capture
6. Capture completes
7. Write CreateDesktop = <previous value>
8. killall Finder
9. Wait 1.5-2s
```

**Total overhead:** ~3-4 seconds (2 Finder restarts)

### Pre-hiding Strategy (CleanShot X likely approach)

```
User triggers capture hotkey
↓
Immediately hide icons + restart Finder (async)
↓
While Finder restarting, prepare capture UI
↓
Finder ready → Show capture UI → User selects area
↓
Capture → Restore icons asynchronously
```

**Benefit:** User doesn't wait for Finder restart, happens during UI load

### Polling for Finder Readiness

```swift
func waitForFinder() async {
    while true {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["Finder"]
        task.launch()
        task.waitUntilExit()

        if task.terminationStatus == 0 { // Finder running
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s grace
            break
        }
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
    }
}
```

---

## 6. macOS Permission Requirements

### Required Permissions
1. **Screen Recording** (already required for Snapzy) - captures screen content
2. **No additional permissions** for `defaults write` + `killall Finder`

### Sandboxing Impact
- **App Sandbox = NO** required for `defaults`/`killall` approach
- Blocks App Store distribution (or requires special entitlement)
- Alternative: Use overlay approach (sandbox-friendly)

### Entitlements Needed (if disabling sandbox)
```xml
<key>com.apple.security.app-sandbox</key>
<false/>
```

**Risk:** App Store rejection without strong justification

---

## 7. Edge Cases & Gotchas

### Multiple Monitors
- `CreateDesktop = false` hides icons on **ALL displays**
- Overlay approach requires separate window per display
- Must enumerate `NSScreen.screens` and create overlay for each

### Desktop Widgets & Stacks
- **Stacks** (macOS Sonoma+) - still visible with `CreateDesktop = false` ❌
- **Widgets** (macOS Sonoma+) - still visible ❌
- **Workaround:** None for `defaults` method; overlay may cover them

### Finder Restart Side Effects
- Closes all open Finder windows (File browser windows)
- Interrupts file operations (copy/move in progress)
- User experience degradation during meetings/presentations
- AirDrop transfers may interrupt

### User Desktop State
- If app crashes between hide/restore, desktop stays hidden
- **Must implement crash recovery:** On app launch, check if CreateDesktop was previously modified
- Store toggle state in UserDefaults/app state

### Mission Control Integration
- Desktop icons hidden in Mission Control view too
- User might notice if they trigger Mission Control during capture

### Accessibility
- VoiceOver users - desktop icons disappear from accessibility tree
- Screen readers may announce "Desktop has no items"

---

## Recommended Implementation Strategy

### For Snapzy (macOS 14.0+, ScreenCaptureKit)

**Phase 1: Overlay Approach (Safe, Sandboxed)**
- Create fullscreen overlay window per display
- Fetch current wallpaper via `NSWorkspace.desktopImageURL(for:)`
- Display before capture UI, hide after capture
- **Pros:** Instant, no Finder restart, App Store safe
- **Cons:** Widgets/Stacks still visible

**Phase 2: Hybrid Approach**
- Check if app is sandboxed (`ProcessInfo.environment["APP_SANDBOX_CONTAINER_ID"]`)
- If NOT sandboxed: offer "Complete Hide" mode (defaults write method)
- If sandboxed: use overlay only
- User setting: "Hide Desktop Icons" → "Overlay Only" vs "Complete (requires permissions)"

**Phase 3: Future - ScreenCaptureKit Integration**
- Investigate `SCContentFilter` for excluding desktop windows
- May support desktop icon filtering in future macOS versions

---

## Code Example: Full Implementation

```swift
class DesktopIconManager {
    private var previousCreateDesktopValue: Bool?

    func hideIcons() async throws {
        // Read current value
        let readTask = Process()
        readTask.launchPath = "/usr/bin/defaults"
        readTask.arguments = ["read", "com.apple.finder", "CreateDesktop"]
        let pipe = Pipe()
        readTask.standardOutput = pipe
        readTask.launch()
        readTask.waitUntilExit()

        if readTask.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            previousCreateDesktopValue = (output == "1")
        }

        // Write false
        let writeTask = Process()
        writeTask.launchPath = "/usr/bin/defaults"
        writeTask.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", "false"]
        writeTask.launch()
        writeTask.waitUntilExit()

        // Restart Finder
        let killTask = Process()
        killTask.launchPath = "/usr/bin/killall"
        killTask.arguments = ["Finder"]
        killTask.launch()
        killTask.waitUntilExit()

        // Wait for Finder restart
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
    }

    func showIcons() async throws {
        let valueToRestore = previousCreateDesktopValue ?? true

        let writeTask = Process()
        writeTask.launchPath = "/usr/bin/defaults"
        writeTask.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", String(valueToRestore)]
        writeTask.launch()
        writeTask.waitUntilExit()

        let killTask = Process()
        killTask.launchPath = "/usr/bin/killall"
        killTask.arguments = ["Finder"]
        killTask.launch()
        killTask.waitUntilExit()

        try await Task.sleep(nanoseconds: 1_500_000_000)
    }
}
```

---

## Unresolved Questions

1. Does ScreenCaptureKit (`SCContentFilter`) support desktop icon exclusion in macOS 14+?
2. Can we detect Finder restart completion via NSWorkspace notifications?
3. How does CleanShot X minimize visible Finder restart disruption?
4. Are there private APIs in `Finder.framework` for desktop icon control?
5. Do Stacks/Widgets have separate visibility controls we can leverage?

---

## References

- [StackOverflow: Hide desktop items programmatically](https://stackoverflow.com)
- [Command Line Fu: Hide desktop icons](https://commandlinefu.com)
- [Eclectic Light: macOS defaults](https://eclecticlight.co)
- [The Sweet Setup: CleanShot X features](https://thesweetsetup.com)
- [Medium: Hide desktop icons macOS](https://medium.com)
- [Apple Developer: NSWorkspace Documentation](https://apple.com)
