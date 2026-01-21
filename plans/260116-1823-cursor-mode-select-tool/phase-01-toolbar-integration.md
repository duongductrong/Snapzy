# Phase 01: Toolbar Integration

## Context Links
- [Main Plan](./plan.md)
- Related: `ZapShot/Features/Annotate/Views/AnnotateToolbarView.swift`
- Related: `ZapShot/Features/Annotate/State/AnnotationToolType.swift`

## Overview

| Field | Value |
|-------|-------|
| Date | 260116 |
| Description | Add selection tool button to annotation toolbar |
| Priority | High |
| Status | Pending |
| Effort | 0.5 day |

## Key Insights

1. **Selection tool already defined** - `.selection` exists in `AnnotationToolType` with icon "arrow.up.left" and shortcut "v"
2. **Missing from toolbar array** - `drawingTools` array in `AnnotateToolbarView` excludes `.selection`
3. **Default tool is selection** - `AnnotateState.selectedTool` defaults to `.selection`, so toolbar should reflect this
4. **Logical placement** - Selection should appear FIRST in tool group (standard UI convention)

## Requirements

### Functional
- [ ] Selection tool button visible in toolbar
- [ ] Button shows selected state when `.selection` is active
- [ ] Clicking button switches to selection mode
- [ ] Tool works with existing keyboard shortcut "V"

### Non-Functional
- [ ] Consistent visual style with other toolbar buttons
- [ ] Selection button positioned before drawing tools (left-most)

## Architecture

No new architecture needed. Simple array modification.

```
Current:  [.rectangle, .oval, .arrow, .line, .text, .highlighter, .blur, .counter, .pencil]
Proposed: [.selection, .rectangle, .oval, .arrow, .line, .text, .highlighter, .blur, .counter, .pencil]
```

## Related Code Files

| File | Lines | Change Type |
|------|-------|-------------|
| `Views/AnnotateToolbarView.swift` | 90-92 | Modify `drawingTools` array |

## Implementation Steps

### Step 1: Update drawingTools Array
**File**: `ZapShot/Features/Annotate/Views/AnnotateToolbarView.swift`

```swift
// Before (line 90-92)
private var drawingTools: [AnnotationToolType] {
  [.rectangle, .oval, .arrow, .line, .text, .highlighter, .blur, .counter, .pencil]
}

// After
private var drawingTools: [AnnotationToolType] {
  [.selection, .rectangle, .oval, .arrow, .line, .text, .highlighter, .blur, .counter, .pencil]
}
```

### Step 2: Verify Visual Appearance
- Build and run app
- Confirm selection tool (arrow icon) appears first in annotation tools group
- Confirm button highlights when selection mode active (default state)
- Confirm switching tools works correctly

### Step 3: Test Keyboard Shortcut
- Press "V" key while canvas focused
- Verify tool switches to selection mode
- Verify toolbar button state updates

## Todo List

- [ ] Add `.selection` to `drawingTools` array as first element
- [ ] Build and verify icon appears correctly
- [ ] Test click to activate selection mode
- [ ] Test keyboard shortcut "V" activates selection
- [ ] Verify default state shows selection as active

## Success Criteria

1. Selection tool button visible as first tool in annotation group
2. Button shows selected (highlighted) state when selection mode active
3. Clicking button activates selection mode
4. Keyboard shortcut "V" works to activate selection
5. No visual glitches or layout issues

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Icon not displaying | Low | Low | Icon "arrow.up.left" is standard SF Symbol |
| Layout shift | Low | Low | Toolbar uses HStack with flexible spacing |

## Security Considerations

None - UI-only change with no data handling.

## Next Steps

After completing this phase:
1. Proceed to [Phase 02: Hit Testing Enhancement](./phase-02-hit-testing-enhancement.md)
2. Selection mode will be accessible but hit testing improvements needed for accurate selection
