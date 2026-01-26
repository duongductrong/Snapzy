# Unified Window View Modifiers Plan

## Overview
Consolidate NSWindow extensions into a unified SwiftUI View modifier system with consistent naming, default values, and optional customization. Covers toolbar, content area, and bottom bar spacing.

**Created:** 2026-01-26
**Status:** Planning
**Priority:** Medium

## Context
Current state:
- `NSWindow+CornerRadius.swift` - NSWindow extension only (no SwiftUI)
- `NSWindow+TrafficLights.swift` - NSWindow extension only (no SwiftUI)
- `NSWindow+ToolbarSpacing.swift` - Has both NSWindow + SwiftUI View extensions
- Hardcoded spacing values scattered across toolbar, content, and bottom bar views

## Problem Statement
1. Inconsistent API patterns across window extensions
2. Spacing values differ between toolbar (h:12, v:8) and bottom bar (h:16, v:10)
3. Content area uses yet another set of values (h:16, top:8, bottom:12)
4. No single source of truth for window layout spacing

## Solution
Create `WindowSpacingConfiguration` struct and unified View modifier API:
- `.windowToolbar()` - Toolbar frame + padding
- `.windowBottomBar()` - Bottom bar frame + padding
- `.windowContent()` - Content area insets
- `.windowTrafficLightsInset()` - Traffic light spacing
- `.windowCornerRadius()` - Corner radius styling

## Phases

| Phase | Description | Status |
|-------|-------------|--------|
| [Phase 01](./phase-01-unified-view-modifiers.md) | Create WindowSpacingConfiguration and View modifiers | Pending |
| [Phase 02](./phase-02-update-usage-sites.md) | Update all usage sites to new API | Pending |

## Files to Modify
| File | Change |
|------|--------|
| `ClaudeShot/Core/NSWindow+ToolbarSpacing.swift` | Rename to NSWindow+WindowSpacing.swift, expand config |
| `ClaudeShot/Core/NSWindow+CornerRadius.swift` | Add SwiftUI View extension |
| `ClaudeShot/Core/NSWindow+TrafficLights.swift` | Add SwiftUI View extension |
| `ClaudeShot/Features/VideoEditor/Views/VideoEditorToolbarView.swift` | Use new modifiers |
| `ClaudeShot/Features/VideoEditor/Views/VideoEditorMainView.swift` | Use new modifiers |
| `ClaudeShot/Features/Annotate/Views/AnnotateToolbarView.swift` | Use new modifiers |
| `ClaudeShot/Features/Annotate/Views/AnnotateBottomBarView.swift` | Use new modifiers |
| `ClaudeShot/Features/Annotate/Views/AnnotateMainView.swift` | Use new modifiers |

## Success Criteria
- [ ] Single `WindowSpacingConfiguration` covers toolbar, content, bottom bar
- [ ] All window styling available via `.window*()` View modifiers
- [ ] Consistent naming convention across all modifiers
- [ ] Default values built-in, optional customization via args
- [ ] All usage sites updated to new API
- [ ] No hardcoded spacing values in view files
