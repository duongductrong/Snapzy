# Phase 6: Integration and Testing

## Context

- **Parent Plan**: [plan.md](./plan.md)
- **Dependencies**: All previous phases (1-5)
- **Scout**: [Annotate Module](./scout/scout-01-annotate-module.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-27 |
| Description | Integrate with Annotate workflow and comprehensive testing |
| Priority | Medium |
| Status | `[ ]` Not Started |

## Key Insights

- Can integrate as new tool in Annotate OR standalone feature
- Follow AnnotateManager pattern for window management if standalone
- Reuse existing keyboard shortcuts pattern
- Test on various image sizes and aspect ratios

## Requirements

1. Integration with Annotate workflow or standalone access
2. Keyboard shortcuts for common actions
3. Performance testing with large images
4. Edge case handling

## Architecture

```swift
// Option A: Standalone MockupManager (recommended for MVP)
@MainActor
final class MockupManager {
    static let shared = MockupManager()
    private var windowController: MockupWindowController?

    func openMockup(for image: NSImage)
    func openMockup(from url: URL)
    func close()
}

// Option B: Integration with Annotate
// Add "Mockup" tool to AnnotationToolType enum
// Show MockupSidebarView when tool selected
```

## Related Files

| File | Purpose |
|------|---------|
| `Features/Annotate/AnnotateManager.swift` | Window management pattern |
| `Features/Annotate/Window/AnnotateWindow.swift` | Window configuration |

## Implementation Steps

### Step 1: Create MockupManager (if standalone)
- [ ] Create `Features/Annotate/Mockup/MockupManager.swift`
- [ ] Singleton pattern with window tracking
- [ ] openMockup methods for image/URL
- [ ] Close and cleanup methods

### Step 2: Create MockupWindow and Controller
- [ ] Create `Features/Annotate/Mockup/Window/MockupWindow.swift`
- [ ] Configure window style (titled, closable, resizable)
- [ ] Set minimum size 800x600
- [ ] Create MockupWindowController

### Step 3: Add entry points
- [ ] Menu item: Edit > Create Mockup
- [ ] Context menu in Quick Access for screenshots
- [ ] Keyboard shortcut: Cmd+Shift+M
- [ ] Drag-drop support in main window

### Step 4: Add keyboard shortcuts
- [ ] Cmd+S: Save
- [ ] Cmd+Shift+C: Copy to clipboard
- [ ] Cmd+Z/Cmd+Shift+Z: Undo/Redo
- [ ] Escape: Close
- [ ] 1-9: Quick preset selection

### Step 5: Performance testing
- [ ] Test with 4K images (3840x2160)
- [ ] Test with ultra-wide screenshots
- [ ] Measure frame rate during slider drag
- [ ] Profile memory usage during export

### Step 6: Edge case testing
- [ ] Very small images (<100px)
- [ ] Very large images (>8K)
- [ ] Extreme rotation values
- [ ] Rapid preset switching
- [ ] Memory pressure scenarios

### Step 7: Polish and refinement
- [ ] Loading states for image processing
- [ ] Error handling with user feedback
- [ ] Accessibility labels
- [ ] Localization strings

## Todo

- [ ] MockupManager.swift (if standalone)
- [ ] Window configuration
- [ ] Menu/keyboard integration
- [ ] Performance validated
- [ ] Edge cases handled
- [ ] Error handling complete

## Success Criteria

- Feature accessible from menu and keyboard
- Opens quickly (<500ms)
- Handles all image sizes gracefully
- No crashes on edge cases
- Memory stable during extended use

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Integration conflicts with Annotate | Start standalone, integrate later |
| Performance regression | Profile before/after, set benchmarks |
| Missing edge cases | Comprehensive test matrix |

## Security Considerations

- Validate all file paths from drag-drop
- Handle sandboxed file access correctly
- Clean up temporary files

## Test Matrix

| Test Case | Expected Result |
|-----------|-----------------|
| Open 4K PNG | Loads in <1s, smooth preview |
| Apply all presets | Each applies correctly |
| Export at 3x | High-quality output |
| Undo 10 times | All changes revert |
| Drag-drop image | Loads and displays |
| Extreme rotation | No visual artifacts |

## Next Steps

- Deploy to TestFlight for user feedback
- Gather usage analytics
- Iterate based on feedback
