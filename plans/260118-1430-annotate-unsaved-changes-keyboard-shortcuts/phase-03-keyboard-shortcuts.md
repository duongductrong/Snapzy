# Phase 03: Keyboard Shortcuts

**Status:** Completed
**File:** `ZapShot/Features/Annotate/Window/AnnotateWindow.swift`

## Objective

Add Cmd+S and Cmd+Shift+S keyboard shortcuts for save operations.

## Current State Analysis

- `AnnotateWindow` is minimal (35 lines), handles styling only
- No current keyboard event handling
- Need to communicate with `AnnotateWindowController` for save actions

## Approach

Override `performKeyEquivalent(with:)` in `AnnotateWindow` to capture key events. Use NotificationCenter to trigger save actions (decoupled from controller).

## Implementation

### Step 1: Define Notification Names

Add to `AnnotateWindow.swift` before class declaration:

```swift
// MARK: - Notifications

extension Notification.Name {
  static let annotateSave = Notification.Name("annotateSave")
  static let annotateSaveAs = Notification.Name("annotateSaveAs")
}
```

### Step 2: Override performKeyEquivalent

```swift
// Add inside AnnotateWindow class, after canBecomeMain

override func performKeyEquivalent(with event: NSEvent) -> Bool {
  guard event.type == .keyDown else {
    return super.performKeyEquivalent(with: event)
  }

  let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

  // Cmd+S - Save (Done action)
  if event.keyCode == 1 && flags == .command {  // 's' key
    NotificationCenter.default.post(name: .annotateSave, object: self)
    return true
  }

  // Cmd+Shift+S - Save As
  if event.keyCode == 1 && flags == [.command, .shift] {
    NotificationCenter.default.post(name: .annotateSaveAs, object: self)
    return true
  }

  return super.performKeyEquivalent(with: event)
}
```

### Step 3: Full Updated File

```swift
//
//  AnnotateWindow.swift
//  ZapShot
//
//  Dark mode annotation window with proper styling
//

import AppKit

// MARK: - Notifications

extension Notification.Name {
  static let annotateSave = Notification.Name("annotateSave")
  static let annotateSaveAs = Notification.Name("annotateSaveAs")
}

/// Custom NSWindow for annotation editing with dark mode appearance
final class AnnotateWindow: NSWindow {

  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    configure()
  }

  private func configure() {
    appearance = NSAppearance(named: .darkAqua)
    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    backgroundColor = NSColor(white: 0.12, alpha: 1)
    minSize = NSSize(width: 800, height: 600)
    isReleasedWhenClosed = false
    center()
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard event.type == .keyDown else {
      return super.performKeyEquivalent(with: event)
    }

    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

    // Cmd+S - Save (Done action)
    if event.keyCode == 1 && flags == .command {
      NotificationCenter.default.post(name: .annotateSave, object: self)
      return true
    }

    // Cmd+Shift+S - Save As
    if event.keyCode == 1 && flags == [.command, .shift] {
      NotificationCenter.default.post(name: .annotateSaveAs, object: self)
      return true
    }

    return super.performKeyEquivalent(with: event)
  }
}
```

## Notes

- Key code 1 = 's' on US keyboard layout
- `.deviceIndependentFlagsMask` filters out irrelevant modifier bits
- Notifications posted with `self` (window) as object for scoping
- Controller will subscribe to notifications in Phase 04

## Verification

1. Focus annotation window
2. Press Cmd+S -> notification should fire (verify via observer in Phase 04)
3. Press Cmd+Shift+S -> notification should fire
4. Other keys should pass through to normal handling
