# Phase 01: Apply Design Tokens to VideoDetailsSidebarView

## Context

- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** None
- **Docs:** [DesignTokens.swift](../../ClaudeShot/Core/Theme/DesignTokens.swift)

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-28 |
| Description | Replace hardcoded values with design tokens |
| Priority | Low |
| Implementation Status | Pending |
| Review Status | Pending |

## Key Insights

1. Design tokens already exist in `DesignTokens.swift`:
   - `Spacing`: xs(4), sm(8), md(16), lg(24), xl(32)
   - `Typography`: labelSmall(10), labelMedium(11), sectionHeader(11 semibold), body(12)
   - `SidebarColors`: labelPrimary, labelSecondary, itemDefault, etc.
   - `Size`: radiusXs(4), radiusSm(6), radiusMd(8), radiusLg(12)

2. `SidebarSectionHeader` component exists in `AnnotateSidebarComponents.swift` - can be reused

3. Current `VideoDetailsSidebarView` has private `SidebarSection` struct that duplicates functionality

## Requirements

- Replace all hardcoded spacing values with `Spacing.*` tokens
- Replace inline font definitions with `Typography.*` tokens
- Replace color references with `SidebarColors.*` tokens
- Use existing `SidebarSectionHeader` instead of custom section header
- Match Divider styling pattern from AnnotateSidebarView

## Architecture

No architectural changes. Simple token substitution maintaining existing structure.

## Related Code Files

| File | Purpose | Changes |
|------|---------|---------|
| `VideoDetailsSidebarView.swift` | Target file | Apply tokens |
| `DesignTokens.swift` | Token definitions | Reference only |
| `AnnotateSidebarComponents.swift` | Reusable components | Import `SidebarSectionHeader` |

## Implementation Steps

### Step 1: Update Main View Spacing
**File:** `VideoDetailsSidebarView.swift:21-68`

| Current | Replace With |
|---------|--------------|
| `spacing: 16` | `spacing: Spacing.md` |
| `.padding(12)` | `.padding(Spacing.md)` |
| `Spacer(minLength: 20)` | `Spacer(minLength: Spacing.lg)` |

### Step 2: Update Header Section
**File:** `VideoDetailsSidebarView.swift:24-29`

| Current | Replace With |
|---------|--------------|
| `.font(.system(size: 13, weight: .semibold))` | `.font(Typography.sectionHeader)` |
| `ZoomColors.primary` | `SidebarColors.labelPrimary` or keep if intentional |

### Step 3: Update Divider Styling
**File:** `VideoDetailsSidebarView.swift:31`

| Current | Replace With |
|---------|--------------|
| `Divider()` | `Divider().background(Color(nsColor: .separatorColor))` |

### Step 4: Replace Private SidebarSection
**File:** `VideoDetailsSidebarView.swift:76-88`

Replace custom `SidebarSection` with reusable pattern:
- Use `SidebarSectionHeader(title:)` from `AnnotateSidebarComponents.swift`
- Keep VStack wrapper with `Spacing.sm` gap

### Step 5: Update DetailRow Typography
**File:** `VideoDetailsSidebarView.swift:91-107`

| Current | Replace With |
|---------|--------------|
| `.font(.system(size: 11))` | `.font(Typography.labelMedium)` |
| `.foregroundColor(.secondary)` | `.foregroundColor(SidebarColors.labelSecondary)` |
| `.foregroundColor(.primary)` | `.foregroundColor(SidebarColors.labelPrimary)` |

### Step 6: Update Section Spacing
**File:** `VideoDetailsSidebarView.swift:81`

| Current | Replace With |
|---------|--------------|
| `spacing: 8` | `spacing: Spacing.sm` |

## Todo List

- [ ] Update VStack spacing from 16 to Spacing.md
- [ ] Update padding from 12 to Spacing.md
- [ ] Update Spacer minLength from 20 to Spacing.lg
- [ ] Update header font to Typography.sectionHeader
- [ ] Add Divider background color styling
- [ ] Replace SidebarSection header with SidebarSectionHeader component
- [ ] Update SidebarSection spacing from 8 to Spacing.sm
- [ ] Update DetailRow label font to Typography.labelMedium
- [ ] Update DetailRow label color to SidebarColors.labelSecondary
- [ ] Update DetailRow value font to Typography.labelMedium
- [ ] Update DetailRow value color to SidebarColors.labelPrimary

## Success Criteria

- [ ] No hardcoded numeric spacing values remain
- [ ] No inline `.font(.system(size: X))` calls remain
- [ ] No direct `.foregroundColor(.primary/.secondary)` calls remain
- [ ] SidebarSectionHeader component reused
- [ ] Visual appearance unchanged
- [ ] Build succeeds without warnings

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Token values differ from hardcoded | Low | Low | Visual comparison before/after |
| Missing import for DesignTokens | Low | Low | Same module, should auto-resolve |

## Security Considerations

None - UI styling changes only.

## Next Steps

After implementation:
1. Build project to verify no errors
2. Visual comparison of sidebar before/after
3. Consider applying same pattern to other VideoEditor sidebar views
