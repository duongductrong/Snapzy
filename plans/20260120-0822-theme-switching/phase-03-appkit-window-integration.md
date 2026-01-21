# Phase 3: AppKit Window Integration

## Context

- [Plan Overview](./plan.md)
- [Phase 2: SwiftUI Integration](./phase-02-swiftui-integration.md)
- [macOS Theming Research](./research/researcher-02-macos-theming.md)

## Overview

Update custom NSWindow subclasses to respect user's theme preference instead of hardcoding dark mode. Key change: replace `NSAppearance(named: .darkAqua)` with `ThemeManager.shared.nsAppearance`.

## Key Insights

1. `AnnotateWindow` and `VideoEditorWindow` currently hardcode `.darkAqua`
2. `RecordingToolbarWindow` is borderless, uses SwiftUI content - theme via SwiftUI
3. `AreaSelectionWindow` is overlay - should remain theme-neutral
4. Set `window.appearance = nil` to follow system (when user selects "System")
5. Background colors may need adjustment for light mode

## Requirements

- [x] AnnotateWindow respects theme preference
- [x] VideoEditorWindow respects theme preference
- [x] RecordingToolbarWindow SwiftUI content themed
- [x] AreaSelectionWindow remains theme-neutral (no changes needed)
- [x] Dynamic background colors for light/dark modes

## Architecture

```
ThemeManager.shared.nsAppearance
    |
    +-- AnnotateWindow.appearance = nsAppearance
    +-- VideoEditorWindow.appearance = nsAppearance

ThemeManager.shared.systemAppearance
    |
    +-- RecordingToolbarWindow SwiftUI content
```

## Related Code Files

| File | Action | Purpose |
|------|--------|---------|
| `ZapShot/Features/Annotate/Window/AnnotateWindow.swift` | MODIFY | Use ThemeManager |
| `ZapShot/Features/VideoEditor/VideoEditorWindow.swift` | MODIFY | Use ThemeManager |
| `ZapShot/Features/Recording/RecordingToolbarWindow.swift` | MODIFY | Apply theme to SwiftUI |
| `ZapShot/Core/AreaSelectionWindow.swift` | NO CHANGE | Remains theme-neutral |

## Implementation Steps

### Step 1: Update AnnotateWindow

**File:** `ZapShot/Features/Annotate/Window/AnnotateWindow.swift`

#### 1a. Update configure() method (lines 30-37)

Change from:
```swift
private func configure() {
  appearance = NSAppearance(named: .darkAqua)
  titlebarAppearsTransparent = true
  titleVisibility = .hidden
  backgroundColor = NSColor(white: 0.12, alpha: 1)
  minSize = NSSize(width: 800, height: 600)
  isReleasedWhenClosed = false
  center()
}
```

To:
```swift
private func configure() {
  applyTheme()
  titlebarAppearsTransparent = true
  titleVisibility = .hidden
  minSize = NSSize(width: 800, height: 600)
  isReleasedWhenClosed = false
  center()
}

/// Apply current theme from ThemeManager
func applyTheme() {
  let themeManager = ThemeManager.shared
  appearance = themeManager.nsAppearance

  // Dynamic background based on appearance
  if themeManager.preferredAppearance == .light {
    backgroundColor = NSColor(white: 0.95, alpha: 1)
  } else if themeManager.preferredAppearance == .dark {
    backgroundColor = NSColor(white: 0.12, alpha: 1)
  } else {
    // System: use semantic color
    backgroundColor = NSColor.windowBackgroundColor
  }
}
```

### Step 2: Update VideoEditorWindow

**File:** `ZapShot/Features/VideoEditor/VideoEditorWindow.swift`

#### 2a. Update configure() method (lines 23-30)

Change from:
```swift
private func configure() {
  appearance = NSAppearance(named: .darkAqua)
  titlebarAppearsTransparent = true
  titleVisibility = .hidden
  backgroundColor = NSColor(white: 0.12, alpha: 1)
  minSize = NSSize(width: 400, height: 300)
  isReleasedWhenClosed = false
  center()
}
```

To:
```swift
private func configure() {
  applyTheme()
  titlebarAppearsTransparent = true
  titleVisibility = .hidden
  minSize = NSSize(width: 400, height: 300)
  isReleasedWhenClosed = false
  center()
}

/// Apply current theme from ThemeManager
func applyTheme() {
  let themeManager = ThemeManager.shared
  appearance = themeManager.nsAppearance

  // Dynamic background based on appearance
  if themeManager.preferredAppearance == .light {
    backgroundColor = NSColor(white: 0.95, alpha: 1)
  } else if themeManager.preferredAppearance == .dark {
    backgroundColor = NSColor(white: 0.12, alpha: 1)
  } else {
    // System: use semantic color
    backgroundColor = NSColor.windowBackgroundColor
  }
}
```

### Step 3: Update RecordingToolbarWindow

**File:** `ZapShot/Features/Recording/RecordingToolbarWindow.swift`

The RecordingToolbarWindow uses SwiftUI views via NSHostingView. Apply theme to the SwiftUI content.

#### 3a. Update setContent() method (lines 116-123)

Change from:
```swift
private func setContent(_ view: AnyView) {
  let hosting = NSHostingView(rootView: view)
  hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
  contentView = hosting
  hostingView = hosting

  setContentSize(hosting.fittingSize)
}
```

To:
```swift
private func setContent(_ view: AnyView) {
  let themedView = view.preferredColorScheme(ThemeManager.shared.systemAppearance)
  let hosting = NSHostingView(rootView: AnyView(themedView))
  hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
  contentView = hosting
  hostingView = hosting

  setContentSize(hosting.fittingSize)
}
```

#### 3b. Add import if needed

Ensure `import SwiftUI` is present (already at line 9).

### Step 4: AreaSelectionWindow - No Changes

**File:** `ZapShot/Core/AreaSelectionWindow.swift`

This window is a fullscreen overlay for area selection. It uses fixed colors (dim overlay, white crosshair) that work in both light and dark modes. No changes needed.

### Optional: Theme Change Observer

If windows need to update when theme changes while open, add observer in window classes:

```swift
// In init or configure:
NotificationCenter.default.addObserver(
  self,
  selector: #selector(handleThemeChange),
  name: UserDefaults.didChangeNotification,
  object: nil
)

@objc private func handleThemeChange() {
  applyTheme()
}
```

This is optional - windows typically get theme on creation. New windows will use current theme.

## Todo List

- [ ] Update AnnotateWindow.configure() to use ThemeManager
- [ ] Add applyTheme() method to AnnotateWindow
- [ ] Update VideoEditorWindow.configure() to use ThemeManager
- [ ] Add applyTheme() method to VideoEditorWindow
- [ ] Update RecordingToolbarWindow.setContent() for themed SwiftUI
- [ ] Verify AreaSelectionWindow needs no changes
- [ ] Verify build succeeds
- [ ] Test window appearances match theme

## Success Criteria

1. Project compiles without errors
2. AnnotateWindow uses theme preference
3. VideoEditorWindow uses theme preference
4. RecordingToolbarWindow SwiftUI content themed
5. AreaSelectionWindow still works correctly
6. Windows look correct in light, dark, and system modes

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Background color contrast issues | Medium | Medium | Test all tools in light mode |
| Toolbar readability in light mode | Medium | Medium | Use semantic colors |
| Existing dark-mode-only assets | Low | High | Check for hardcoded colors |

## Security Considerations

- No security implications for window theming

## Next Steps

Proceed to [Phase 4: Settings UI](./phase-04-settings-ui.md) to add theme picker to preferences.
