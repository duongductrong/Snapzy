# Phase 1: Window Configuration Updates

## Overview
Add `.fullSizeContentView` to NSWindow styleMask for both Annotate and VideoEditor windows to enable content drawing behind title bar.

## Implementation Steps

### 1.1 Update AnnotateWindow.swift

**File:** `ClaudeShot/Features/Annotate/Window/AnnotateWindow.swift`

**Location:** Line 23-30 (configure method)

**Change:**
```swift
private func configure() {
  applyTheme()

  // Enable full-size content view
  styleMask.insert(.fullSizeContentView)

  titlebarAppearsTransparent = true
  titleVisibility = .hidden
  minSize = NSSize(width: 800, height: 600)
  isReleasedWhenClosed = false
  center()
}
```

**Explanation:**
- Add single line: `styleMask.insert(.fullSizeContentView)`
- Placed after `applyTheme()`, before existing transparency settings
- Enables content to extend into title bar area

### 1.2 Update VideoEditorWindow.swift

**File:** `ClaudeShot/Features/VideoEditor/VideoEditorWindow.swift`

**Location:** Line 23-30 (configure method)

**Change:**
```swift
private func configure() {
  applyTheme()

  // Enable full-size content view
  styleMask.insert(.fullSizeContentView)

  titlebarAppearsTransparent = true
  titleVisibility = .hidden
  minSize = NSSize(width: 400, height: 300)
  isReleasedWhenClosed = false
  center()
}
```

**Explanation:**
- Identical change to AnnotateWindow
- Add `styleMask.insert(.fullSizeContentView)`
- Maintains consistency across both window types

## Validation

After changes, verify:
- Windows compile without errors
- Windows open without visual artifacts
- Traffic lights remain visible
- Title bar area shows window background color

## Dependencies
None - this phase is independent and can be implemented first.

## Next Phase
Phase 2: SwiftUI view updates for safe area handling
