# FloatingScreenshot Feature - Implementation Plan

**Created**: 260115
**Status**: Planning
**Priority**: High

## Summary

Implement floating screenshot cards that appear after capture, displaying previews above other windows with hover-activated copy/save buttons. Cards stack vertically (oldest top, newest bottom) with configurable screen position.

## Phases

| # | Phase | Status | File |
|---|-------|--------|------|
| 1 | Floating Window Infrastructure | `pending` | [phase-01-floating-window-infrastructure.md](./phase-01-floating-window-infrastructure.md) |
| 2 | Screenshot Stack Manager | `pending` | [phase-02-screenshot-stack-manager.md](./phase-02-screenshot-stack-manager.md) |
| 3 | Floating Card UI | `pending` | [phase-03-floating-card-ui.md](./phase-03-floating-card-ui.md) |
| 4 | Integration | `pending` | [phase-04-integration.md](./phase-04-integration.md) |

## Architecture Overview

```
+------------------+     notifies      +-------------------------+
| ScreenCapture    |------------------>| FloatingScreenshot      |
| Manager          |                   | Manager                 |
+------------------+                   +-------------------------+
                                              |
                                              | manages
                                              v
+------------------+     hosts         +-------------------------+
| FloatingPanel    |<------------------| FloatingStackView       |
| Controller       |   NSHostingView   | (SwiftUI)               |
+------------------+                   +-------------------------+
        |                                     |
        | NSPanel                             | contains
        | .floating level                     v
        | .nonactivatingPanel          +-------------------------+
        v                              | FloatingCardView        |
+------------------+                   | - thumbnail             |
| Screen Position  |                   | - hover buttons         |
| (configurable)   |                   +-------------------------+
+------------------+

Data Flow:
1. ScreenCaptureManager completes capture -> saves image -> notifies
2. FloatingScreenshotManager receives URL -> generates thumbnail -> adds to stack
3. FloatingStackView updates -> animates new card in
4. User hovers card -> buttons appear (copy/save/dismiss)
5. Auto-dismiss after timeout OR manual dismiss
```

## File Structure

```
ZapShot/Features/FloatingScreenshot/
├── FloatingPanelController.swift      # NSPanel wrapper
├── FloatingScreenshotManager.swift    # State management
├── FloatingCardView.swift             # Card UI component
├── FloatingStackView.swift            # Stack container
├── FloatingPosition.swift             # Position enum
└── ScreenshotItem.swift               # Data model
```

## Key Decisions

1. **NSPanel over NSWindow** - non-activating, stays above other windows
2. **SwiftUI in NSHostingView** - modern UI with animations inside AppKit panel
3. **ObservableObject pattern** - reactive state for stack management
4. **Thumbnail generation** - downscaled images for memory efficiency
5. **Max 5 visible cards** - older cards collapse/auto-dismiss

## Dependencies

- Existing: `ScreenCaptureManager`, `ContentView`, `ScreenCaptureViewModel`
- New: None (uses native AppKit/SwiftUI)

## Risks

| Risk | Mitigation |
|------|------------|
| Memory with many screenshots | Thumbnail generation, auto-dismiss timer |
| Panel stealing focus | `.nonactivatingPanel` + `orderFrontRegardless()` |
| Multi-monitor positioning | Use `NSScreen.main` with fallback |
