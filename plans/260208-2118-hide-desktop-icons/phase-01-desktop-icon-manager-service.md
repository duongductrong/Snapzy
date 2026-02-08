# Phase 01: DesktopIconManager Service

**Parent Plan:** [plan.md](./plan.md)
**Dependencies:** None (new standalone service)
**Docs:** [system-architecture](../../docs/system-architecture.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-02-08 |
| Description | Core service to hide/show desktop icons via wallpaper overlay windows |
| Priority | High (blocker for phases 2-3) |
| Implementation Status | Pending |
| Review Status | Pending |

## Key Insights

- `NSWorkspace.shared.desktopImageURL(for:)` returns current wallpaper URL per screen
- Window level `CGWindowLevelForKey(.desktopWindow) + 1` sits above icons but below normal windows
- Must handle multi-monitor -- one overlay per `NSScreen`
- `NSWindow.StyleMask.borderless` with no shadow, not movable, ignores mouse events
- Must use `NSImageView` with `.scaleAxesIndependently` to fill entire screen
- Overlay windows must be excluded from screen capture via `window.sharingType = .none`

## Requirements

1. Singleton `DesktopIconManager.shared` following existing codebase pattern
2. `hideIcons()` -- create overlay windows covering all screens
3. `restoreIcons()` -- remove all overlay windows
4. `isHidden` read-only state property
5. Thread-safe, `@MainActor` annotated
6. Overlay windows excluded from ScreenCaptureKit capture
7. Handle screen configuration changes (displays connected/disconnected)

## Architecture

```
DesktopIconManager (singleton, @MainActor)
├── overlayWindows: [NSWindow]      // one per screen
├── isHidden: Bool                  // read-only state
├── hideIcons()                     // create overlays
├── restoreIcons()                  // close overlays
└── private createOverlayWindow(for: NSScreen) -> NSWindow
```

## Related Code Files

- `Snapzy/Core/Services/SystemWallpaperManager.swift` -- reference for singleton pattern, wallpaper URL fetching
- `Snapzy/Core/Services/PostCaptureActionHandler.swift` -- reference for service pattern

## Implementation Steps

### Step 1: Create `DesktopIconManager.swift`

File: `Snapzy/Core/Services/DesktopIconManager.swift`

```swift
//
//  DesktopIconManager.swift
//  Snapzy
//
//  Service to temporarily hide desktop icons using wallpaper overlay windows
//

import AppKit
import Foundation

@MainActor
final class DesktopIconManager {
  static let shared = DesktopIconManager()

  private var overlayWindows: [NSWindow] = []
  private(set) var isHidden = false

  private init() {}

  // MARK: - Public API

  /// Create wallpaper overlay windows on all screens to hide desktop icons
  func hideIcons() {
    guard !isHidden else { return }

    for screen in NSScreen.screens {
      let window = createOverlayWindow(for: screen)
      window.orderFrontRegardless()
      overlayWindows.append(window)
    }

    isHidden = true
  }

  /// Remove all overlay windows, restoring desktop icon visibility
  func restoreIcons() {
    guard isHidden else { return }

    for window in overlayWindows {
      window.orderOut(nil)
      window.close()
    }
    overlayWindows.removeAll()
    isHidden = false
  }

  // MARK: - Private

  private func createOverlayWindow(for screen: NSScreen) -> NSWindow {
    let window = NSWindow(
      contentRect: screen.frame,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )

    // Position above desktop icons, below everything else
    window.level = NSWindow.Level(
      rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1
    )

    window.isOpaque = true
    window.hasShadow = false
    window.ignoresMouseEvents = true
    window.collectionBehavior = [.canJoinAllSpaces, .stationary]
    window.backgroundColor = .black

    // Exclude from screen capture
    window.sharingType = .none

    // Load current wallpaper
    if let wallpaperURL = NSWorkspace.shared.desktopImageURL(for: screen),
       let image = NSImage(contentsOf: wallpaperURL) {
      let imageView = NSImageView(frame: screen.frame)
      imageView.image = image
      imageView.imageScaling = .scaleAxesIndependently
      imageView.autoresizingMask = [.width, .height]
      window.contentView = imageView
    }

    return window
  }
}
```

### Step 2: Key implementation details

1. **`window.sharingType = .none`** -- Critical. Prevents overlay from appearing in ScreenCaptureKit captures. Without this, the capture would show the overlay itself instead of the actual desktop.

2. **`window.ignoresMouseEvents = true`** -- Overlay is purely visual, clicks pass through to desktop/Finder.

3. **`collectionBehavior: [.canJoinAllSpaces, .stationary]`** -- Overlay visible on all Spaces/desktops and doesn't move with space switching.

4. **Window level `desktopWindow + 1`** -- Sits directly above desktop icons but below Dock, menu bar, and all app windows.

5. **`imageScaling = .scaleAxesIndependently`** -- Ensures wallpaper fills entire screen regardless of aspect ratio, matching macOS native behavior.

### Step 3: Edge cases to handle

- If `desktopImageURL` returns nil (rare), fall back to `NSColor.windowBackgroundColor`
- If screen configuration changes mid-capture, `restoreIcons()` still closes all windows safely
- Multiple rapid `hideIcons()` calls guarded by `isHidden` check

## Todo List

- [ ] Create `DesktopIconManager.swift` in `Snapzy/Core/Services/`
- [ ] Verify `window.sharingType = .none` excludes from ScreenCaptureKit
- [ ] Test multi-monitor wallpaper matching
- [ ] Test overlay appears above icons but below Dock/apps
- [ ] Test `restoreIcons()` cleanup is complete

## Success Criteria

1. `hideIcons()` creates overlay windows covering desktop icons on all screens
2. Overlays match current wallpaper per screen
3. Overlays do NOT appear in ScreenCaptureKit captures
4. `restoreIcons()` removes all overlays with no leaks
5. Mouse events pass through overlays
6. File under 200 lines

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| `sharingType = .none` not excluding from capture | High | Test immediately; fallback: use `CGWindowListCreateImage` with window exclusion |
| Wallpaper URL returns nil on some configs | Low | Fallback to solid background color |
| Dynamic wallpapers (time-based) mismatch | Low | Acceptable -- overlay is temporary (sub-second for screenshots) |
| Screen hotplug during capture | Low | `restoreIcons()` closes all existing windows regardless |

## Security Considerations

- No file system writes
- No shell commands
- No network access
- Only reads wallpaper URL (public API)
- No entitlements required beyond existing screen recording permission

## Next Steps

Proceed to [Phase 02: Preferences Integration](./phase-02-preferences-integration.md) to add the user-facing toggle.
