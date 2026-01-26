# NSWindow+ToolbarSpacing Extension Plan

## Overview
Create a reusable NSWindow extension for consistent toolbar spacing configuration that integrates with existing corner radius and traffic light positioning extensions.

**Created:** 2026-01-26
**Status:** Planning
**Priority:** Medium

## Context
- `NSWindow+CornerRadius.swift` - 24pt default corner radius
- `NSWindow+TrafficLights.swift` - Traffic light positioning with `TrafficLightConfiguration`
- Both `VideoEditorWindow` and `AnnotateWindow` use these extensions
- Toolbars currently use hardcoded values (e.g., `padding(.horizontal, 12)`, `height: 44`)

## Problem Statement
Windows with custom corner radius and repositioned traffic lights need consistent toolbar spacing. Currently, toolbar padding/spacing values are scattered across SwiftUI views without centralized configuration.

## Solution
Create `NSWindow+ToolbarSpacing.swift` with:
1. `ToolbarSpacingConfiguration` struct - centralized spacing values
2. NSWindow extension methods for applying/calculating toolbar layout

## Phases

| Phase | Description | Status |
|-------|-------------|--------|
| [Phase 01](./phase-01-toolbar-spacing-extension.md) | Create ToolbarSpacingConfiguration and NSWindow extension | Pending |

## Success Criteria
- [ ] Single source of truth for toolbar spacing values
- [ ] Harmonizes with existing TrafficLightConfiguration values
- [ ] Follows existing code patterns in Core/
- [ ] Easy to apply in VideoEditorWindow and AnnotateWindow

## Files to Create
- `ClaudeShot/Core/NSWindow+ToolbarSpacing.swift`

## Files to Update (Optional)
- `ClaudeShot/Features/VideoEditor/Views/VideoEditorToolbarView.swift`
- `ClaudeShot/Features/Annotate/Views/AnnotateToolbarView.swift`
