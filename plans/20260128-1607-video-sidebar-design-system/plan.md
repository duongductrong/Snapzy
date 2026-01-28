# Video Sidebar Design System Alignment

**Created:** 2026-01-28
**Status:** Pending Review
**Priority:** Low
**Complexity:** Simple

## Overview

Update `VideoDetailsSidebarView.swift` to use centralized design tokens from `DesignTokens.swift`, matching patterns established in `AnnotateSidebarView.swift`.

## Current State

- `VideoDetailsSidebarView.swift` uses hardcoded values for spacing, typography, and colors
- `AnnotateSidebarView.swift` uses design tokens (`Spacing`, `Typography`, `SidebarColors`, `Size`)
- Design tokens defined in `ClaudeShot/Core/Theme/DesignTokens.swift`

## Implementation Phases

| Phase | Description | Status | Progress |
|-------|-------------|--------|----------|
| 01 | Update VideoDetailsSidebarView with design tokens | Pending | 0% |

## Key Files

- **Target:** [VideoDetailsSidebarView.swift](../../ClaudeShot/Features/VideoEditor/Views/VideoDetailsSidebarView.swift)
- **Reference:** [AnnotateSidebarView.swift](../../ClaudeShot/Features/Annotate/Views/AnnotateSidebarView.swift)
- **Tokens:** [DesignTokens.swift](../../ClaudeShot/Core/Theme/DesignTokens.swift)
- **Components:** [AnnotateSidebarComponents.swift](../../ClaudeShot/Features/Annotate/Views/AnnotateSidebarComponents.swift)

## Phase Files

- [Phase 01: Apply Design Tokens](./phase-01-apply-design-tokens.md)

## Success Criteria

- All hardcoded spacing replaced with `Spacing.*` tokens
- All hardcoded fonts replaced with `Typography.*` tokens
- All hardcoded colors replaced with `SidebarColors.*` tokens
- Reuse `SidebarSectionHeader` component
- Divider styling matches AnnotateSidebarView pattern
