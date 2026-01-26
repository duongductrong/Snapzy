# Phase 02: Update Usage Sites

## Context
- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** Phase 01 (Unified View Modifiers)
- **Docs:** N/A

## Overview
| Field | Value |
|-------|-------|
| Date | 2026-01-26 |
| Description | Update all views to use new unified window modifiers |
| Priority | Medium |
| Implementation Status | Pending |
| Review Status | Awaiting Review |

## Requirements
1. Replace hardcoded spacing values with new modifiers
2. Remove old helper properties (spacing, trafficConfig, trafficLightsWidth)
3. Ensure consistent look across all window areas

## Files to Update

### VideoEditorToolbarView.swift
**Before:**
```swift
private let spacing = ToolbarSpacingConfiguration.default

var body: some View {
  HStack(spacing: 0) { ... }
  .frame(height: spacing.toolbarHeight)
  .padding(.horizontal, spacing.leadingPadding)
}
```

**After:**
```swift
var body: some View {
  HStack(spacing: WindowSpacingConfiguration.default.toolbarItemSpacing) { ... }
  .windowToolbar()
}
```

### AnnotateToolbarView.swift
**Before:**
```swift
private let spacing = ToolbarSpacingConfiguration.default
private let trafficConfig = TrafficLightConfiguration.default
private var trafficLightsWidth: CGFloat { ... }

var body: some View {
  HStack(spacing: spacing.itemSpacing) {
    Spacer().frame(width: trafficLightsWidth)
    ...
  }
  .padding(.horizontal, spacing.leadingPadding)
  .padding(.vertical, spacing.verticalPadding)
}
```

**After:**
```swift
var body: some View {
  HStack(spacing: WindowSpacingConfiguration.default.toolbarItemSpacing) { ... }
  .windowTrafficLightsInset()
  .windowToolbarPadding()
}
```

### AnnotateBottomBarView.swift
**Before:**
```swift
var body: some View {
  HStack(spacing: 16) { ... }
  .padding(.horizontal, 16)
  .padding(.vertical, 10)
}
```

**After:**
```swift
var body: some View {
  HStack(spacing: WindowSpacingConfiguration.default.bottomBarItemSpacing) { ... }
  .windowBottomBarPadding()
}
```

### VideoEditorMainView.swift
**Before:**
```swift
VideoTimelineView(state: state)
  .padding(.horizontal, 16)
  .padding(.top, 12)
  .padding(.bottom, 12)
```

**After:**
```swift
VideoTimelineView(state: state)
  .windowContent()
```

## Todo List
- [ ] Update VideoEditorToolbarView.swift
- [ ] Update AnnotateToolbarView.swift
- [ ] Update AnnotateBottomBarView.swift
- [ ] Update VideoEditorMainView.swift
- [ ] Remove unused helper properties
- [ ] Test UI consistency
- [ ] Verify compilation

## Success Criteria
- [ ] No hardcoded spacing values in view files
- [ ] All views use `.window*()` modifiers
- [ ] UI looks consistent across toolbar, content, bottom bar
- [ ] Code compiles without warnings
