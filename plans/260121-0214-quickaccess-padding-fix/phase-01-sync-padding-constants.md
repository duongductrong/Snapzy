# Phase 01: Sync Padding Constants

## Context

- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** None
- **Docs:** [README.md](/README.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-21 |
| Description | Create shared layout constants, sync padding between Manager and StackView |
| Priority | Medium |
| Implementation Status | Completed |
| Review Status | Completed |

## Key Insights

1. `QuickAccessManager` calculates panel size using `containerPadding = 10`
2. `QuickAccessStackView` applies `.padding(10)` independently
3. Values must match or content overflows panel bounds
4. Shadow requires ~12pt clearance (radius 8 + y-offset 4)
5. Card dimensions also duplicated - should consolidate

## Requirements

- R1: Single source of truth for all QuickAccess layout constants
- R2: Padding increased to 12pt for shadow clearance
- R3: No visual regression in card stack behavior
- R4: Maintain existing animation and transition behavior

## Architecture

### New File: QuickAccessLayout.swift

```swift
// ZapShot/Features/QuickAccess/QuickAccessLayout.swift

import Foundation

/// Centralized layout constants for QuickAccess panel
enum QuickAccessLayout {
    static let cardWidth: CGFloat = 200
    static let cardHeight: CGFloat = 112
    static let cardSpacing: CGFloat = 8
    static let containerPadding: CGFloat = 12  // Increased for shadow clearance
}
```

### Modified: QuickAccessManager.swift

Remove private constants, reference shared layout:

```swift
// Remove lines 65-68:
// private let cardWidth: CGFloat = 200
// private let cardHeight: CGFloat = 112
// private let cardSpacing: CGFloat = 8
// private let containerPadding: CGFloat = 10

// Update calculatePanelSize():
private func calculatePanelSize() -> CGSize {
    let itemCount = max(1, items.count)
    let height = CGFloat(itemCount) * QuickAccessLayout.cardHeight
        + CGFloat(itemCount - 1) * QuickAccessLayout.cardSpacing
        + QuickAccessLayout.containerPadding * 2
    let width = QuickAccessLayout.cardWidth + QuickAccessLayout.containerPadding * 2
    return CGSize(width: width, height: height)
}
```

### Modified: QuickAccessStackView.swift

Remove private constants, reference shared layout:

```swift
// Remove lines 14-15:
// private let spacing: CGFloat = 8
// private let padding: CGFloat = 10

// Update body:
var body: some View {
    VStack(spacing: QuickAccessLayout.cardSpacing) {
        ForEach(manager.items) { item in
            // ... existing card code
        }
    }
    .padding(QuickAccessLayout.containerPadding)
    .animation(...)
}
```

## Related Code Files

| File | Purpose | Changes |
|------|---------|---------|
| `QuickAccessLayout.swift` | New shared constants | Create file |
| `QuickAccessManager.swift` | Panel size calculation | Remove private constants, use shared |
| `QuickAccessStackView.swift` | Stack container | Remove private constants, use shared |

## Implementation Steps

### Step 1: Create QuickAccessLayout.swift

1. Create new file at `ZapShot/Features/QuickAccess/QuickAccessLayout.swift`
2. Define `QuickAccessLayout` enum with static constants
3. Set `containerPadding = 12` for shadow clearance

### Step 2: Update QuickAccessManager.swift

1. Remove private constant declarations (lines 65-68)
2. Update `calculatePanelSize()` to use `QuickAccessLayout.*`
3. Verify `maxVisibleItems` remains as instance property (not layout-related)

### Step 3: Update QuickAccessStackView.swift

1. Remove private constant declarations (lines 14-15)
2. Update `VStack(spacing:)` to use `QuickAccessLayout.cardSpacing`
3. Update `.padding()` to use `QuickAccessLayout.containerPadding`

### Step 4: Verify Build

1. Build project, resolve any import issues
2. Ensure no duplicate symbol errors

### Step 5: Visual Testing

1. Test panel in all 4 positions (bottomRight, bottomLeft, topRight, topLeft)
2. Verify shadow visible at all edges
3. Confirm cards centered with equal padding
4. Test with 1, 3, and 5 cards

## Todo List

- [x] Create `QuickAccessLayout.swift` with shared constants
- [x] Update `QuickAccessManager.swift` to use shared constants
- [x] Update `QuickAccessStackView.swift` to use shared constants
- [x] Build and verify no compilation errors
- [x] Visual test all panel positions
- [x] Verify shadow clearance at edges

## Success Criteria

| Criterion | Verification Method |
|-----------|---------------------|
| Shadow not clipped | Visual inspection at all 4 positions |
| 12pt edge clearance | Measure in Xcode preview or runtime |
| Single source of truth | Code review - no duplicate constants |
| No regression | Compare before/after screenshots |

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Missed constant reference | Low | Low | Search codebase for magic numbers |
| Panel position calculation drift | Low | Medium | Test all positions post-change |
| Card view hardcoded dimensions | Low | Low | Review QuickAccessCardView for size refs |

## Security Considerations

- No security implications - purely UI layout change
- No user data or permissions affected

## Next Steps

After completion:
1. Consider extracting `QuickAccessCardView` dimensions if hardcoded
2. Document layout system in code comments
3. Mark phase complete in plan.md
