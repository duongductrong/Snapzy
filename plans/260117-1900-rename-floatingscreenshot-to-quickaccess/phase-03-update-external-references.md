# Phase 03: Update External References

## Context
- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** [Phase 02](./phase-02-update-type-names.md)

## Overview
| Field | Value |
|-------|-------|
| Date | 2026-01-17 |
| Priority | High |
| Implementation Status | ⬜ Pending |
| Review Status | ⬜ Pending |

## Description
Update all references to renamed types in files outside the QuickAccess module.

## Related Code Files

### 1. ScreenCaptureViewModel.swift
**Path:** `ZapShot/Core/ScreenCaptureViewModel.swift`

**Changes:**
| Line | Old | New |
|------|-----|-----|
| 51 | `FloatingScreenshotManager.shared` | `QuickAccessManager.shared` |
| 97 | `var floatingPosition: FloatingPosition` | `var quickAccessPosition: QuickAccessPosition` |

**Full changes:**
```swift
// Line 51
private let floatingManager = FloatingScreenshotManager.shared
// →
private let quickAccessManager = QuickAccessManager.shared

// Line 97-100 (property)
var floatingPosition: FloatingPosition {
  get { floatingManager.position }
  set { floatingManager.setPosition(newValue) }
}
// →
var quickAccessPosition: QuickAccessPosition {
  get { quickAccessManager.position }
  set { quickAccessManager.setPosition(newValue) }
}

// Also update all references to floatingManager → quickAccessManager
```

### 2. QuickAccessSettingsView.swift
**Path:** `ZapShot/Features/Preferences/Tabs/QuickAccessSettingsView.swift`

**Changes:**
| Line | Old | New |
|------|-----|-----|
| 11 | `FloatingScreenshotManager.shared` | `QuickAccessManager.shared` |

### 3. AnnotateManager.swift
**Path:** `ZapShot/Features/Annotate/AnnotateManager.swift`

**Changes:**
| Line | Old | New |
|------|-----|-----|
| 23 | `func openAnnotation(for item: ScreenshotItem)` | `func openAnnotation(for item: QuickAccessItem)` |

### 4. AnnotateWindowController.swift
**Path:** `ZapShot/Features/Annotate/Window/AnnotateWindowController.swift`

**Changes:**
| Line | Old | New |
|------|-----|-----|
| 19 | `init(item: ScreenshotItem)` | `init(item: QuickAccessItem)` |

## Implementation Steps

### Step 1: Update ScreenCaptureViewModel.swift
```swift
// Replace all occurrences:
FloatingScreenshotManager → QuickAccessManager
floatingManager → quickAccessManager
FloatingPosition → QuickAccessPosition
floatingPosition → quickAccessPosition (property name)
```

### Step 2: Update QuickAccessSettingsView.swift
```swift
// Line 11
FloatingScreenshotManager.shared → QuickAccessManager.shared
```

### Step 3: Update AnnotateManager.swift
```swift
// Line 23
ScreenshotItem → QuickAccessItem
```

### Step 4: Update AnnotateWindowController.swift
```swift
// Line 19
ScreenshotItem → QuickAccessItem
```

## Todo List
- [ ] Update ScreenCaptureViewModel.swift references
- [ ] Update QuickAccessSettingsView.swift references
- [ ] Update AnnotateManager.swift references
- [ ] Update AnnotateWindowController.swift references

## Success Criteria
- [ ] All external files compile without errors
- [ ] No remaining references to old type names
- [ ] Property names consistent with new naming

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Missing reference | Medium | High | Grep for old names after changes |
| API breakage | Low | Low | Internal changes only, no public API |

## Security Considerations
None - pure rename operation.

## Next Steps
→ Proceed to [Phase 04: Update Xcode Project](./phase-04-update-xcode-project.md)
