# Phase 01: Vertical Tab Bar Implementation

## Context
- [Plan Overview](./plan.md)
- [Codebase Analysis](./reports/01-codebase-analysis.md)

## Overview
Replace horizontal `SegmentedTabButton` with vertical tab bar positioned on right edge of sidebar. Create reusable components for vertical tab navigation.

## Key Insights
- Current `SegmentedTabButton` already has hover/selected state logic - adapt for vertical
- Sidebar width 320px total; allocate ~64px for vertical tabs, ~256px for content
- Native SwiftUI TabView not suitable for vertical layout on macOS
- Animation duration `.easeInOut(duration: 0.15)` should be preserved

## Requirements
1. Vertical tab bar on RIGHT side of sidebar content
2. Each tab: icon above text, vertically stacked
3. Selected state: accent color background or left indicator bar
4. Hover state: subtle background highlight
5. Preserve auto-switch to Zoom when `selectedZoomId` changes
6. Smooth transition animations between tabs

## Architecture

### New Components
```
ClaudeShot/Features/VideoEditor/Views/
├── VerticalTabBar.swift (NEW)
│   ├── VerticalTabBar<Tab> - Generic vertical tab container
│   └── VerticalTabItem - Individual tab button
└── VideoEditorRightSidebar.swift (MODIFY)
```

### Component Design
```swift
// VerticalTabBar.swift
struct VerticalTabBar<Tab: Hashable>: View {
  @Binding var selection: Tab
  let tabs: [Tab]
  let label: (Tab) -> (icon: String, title: String)
}

struct VerticalTabItem: View {
  let icon: String
  let title: String
  let isSelected: Bool
  let action: () -> Void
}
```

### Layout Structure
```
HStack(spacing: 0) {
  // Content area (flexible width)
  tabContent
    .frame(maxWidth: .infinity)

  Divider()

  // Vertical tab bar (fixed width)
  VerticalTabBar(...)
    .frame(width: 64)
}
```

## Related Files
| File | Action | Description |
|------|--------|-------------|
| `VideoEditorRightSidebar.swift` | Modify | Replace horizontal tabs with vertical layout |
| `VerticalTabBar.swift` | Create | Reusable vertical tab bar component |
| `VideoEditorMainView.swift` | None | No changes needed (integration unchanged) |

## Implementation Steps

### Step 1: Create VerticalTabBar Component
1. Create `VerticalTabBar.swift` in `ClaudeShot/Features/VideoEditor/Views/`
2. Implement `VerticalTabItem` with:
   - VStack layout (icon above text)
   - Hover state tracking
   - Selected state styling (accent color or indicator)
   - Button action with animation
3. Implement `VerticalTabBar` container:
   - VStack with spacing for tab items
   - Flexible height alignment

### Step 2: Modify VideoEditorRightSidebar
1. Remove `sidebarHeader` (title + segmented control)
2. Replace body with HStack layout:
   - Left: content area with tab content
   - Divider
   - Right: VerticalTabBar
3. Keep `onChange(of: state.selectedZoomId)` logic unchanged
4. Adjust total sidebar width if needed (320px may remain same)

### Step 3: Style Refinements
1. Tab item dimensions: 64px width, ~60px height per item
2. Icon size: 16-18pt
3. Text size: 10-11pt, medium weight
4. Selected indicator: accent color background with rounded corners OR left edge bar
5. Hover: subtle background opacity change

### Step 4: Test & Verify
1. Verify tab switching animates smoothly
2. Confirm auto-switch to Zoom works
3. Check hover states render correctly
4. Verify content area scrolling unaffected

## Todo List
- [ ] Create `VerticalTabBar.swift` file
- [ ] Implement `VerticalTabItem` view with hover/selected states
- [ ] Implement `VerticalTabBar` container
- [ ] Modify `VideoEditorRightSidebar` layout to HStack
- [ ] Remove old `sidebarHeader` and `segmentedTabControl`
- [ ] Test tab switching functionality
- [ ] Test auto-switch on zoom selection
- [ ] Verify styling matches design spec

## Success Criteria
- Vertical tabs render on right edge of sidebar
- Icon + text stacked vertically in each tab
- Tab switching works with 0.15s animation
- Selected tab has clear visual indicator
- Hover states provide feedback
- Auto-switch to Zoom preserved
- No scrolling/layout regressions

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Layout overflow on small windows | Low | Medium | Test minimum window size |
| Animation jank | Low | Low | Use existing animation timing |
| Generic component complexity | Low | Low | Keep simple, extend later if needed |

## Security Considerations
- No security concerns; UI-only changes
- No network, file system, or sensitive data involved

## Next Steps
After completion:
1. Consider extracting `VerticalTabBar` to shared Components folder if reused elsewhere
2. May add keyboard navigation (up/down arrows) for accessibility
3. Consider adding tooltip on hover for longer tab names

## Unresolved Questions
- None identified
