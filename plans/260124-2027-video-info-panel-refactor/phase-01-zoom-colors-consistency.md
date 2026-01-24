# Phase 01: Zoom Colors Consistency

## Context

- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** None
- **Docs:** ZoomColors enum in ZoomBlockView.swift

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-24 |
| Description | Replace hardcoded `.purple` with `ZoomColors.primary` |
| Priority | High |
| Implementation Status | Pending |
| Review Status | Not Started |

## Key Insights

- VideoControlsView uses hardcoded `.purple` (lines 70-78, 108)
- ExportProgressOverlay uses `.purple` for icon and gradient (lines 25, 46-47)
- ZoomColors.primary uses system accent color: `Color(NSColor.controlAccentColor)`
- Consistent colors improve visual coherence

## Requirements

1. Replace all `.purple` in VideoControlsView with `ZoomColors.primary`
2. Replace `.purple` in ExportProgressOverlay with `ZoomColors.primary`
3. Maintain same opacity values

## Architecture

No architectural changes. Direct color constant replacements.

## Related Code Files

| File | Purpose |
|------|---------|
| `ClaudeShot/Features/VideoEditor/Views/VideoControlsView.swift` | Zoom count indicator, add zoom button |
| `ClaudeShot/Features/VideoEditor/Views/ExportProgressOverlay.swift` | Export icon, progress gradient |
| `ClaudeShot/Features/VideoEditor/Views/Zoom/ZoomBlockView.swift` | ZoomColors enum definition |

## Implementation Steps

1. Open VideoControlsView.swift
2. Line 70: `.foregroundColor(.purple)` -> `.foregroundColor(ZoomColors.primary)`
3. Line 74: `.foregroundColor(.purple)` -> `.foregroundColor(ZoomColors.primary)`
4. Line 78: `Color.purple.opacity(0.15)` -> `ZoomColors.primary.opacity(0.15)`
5. Line 108: `Color.purple.opacity(0.2)` -> `ZoomColors.primary.opacity(0.2)`
6. Open ExportProgressOverlay.swift
7. Line 25: `.foregroundColor(.purple)` -> `.foregroundColor(ZoomColors.primary)`
8. Lines 46-47: `colors: [.purple, .blue]` -> `colors: [ZoomColors.primary, .blue]`

## Todo

- [ ] Update VideoControlsView zoom count indicator colors
- [ ] Update VideoControlsView add zoom button background
- [ ] Update ExportProgressOverlay icon color
- [ ] Update ExportProgressOverlay gradient colors
- [ ] Verify visual consistency

## Success Criteria

- No hardcoded `.purple` in VideoControlsView or ExportProgressOverlay
- All zoom-related UI uses ZoomColors.primary
- Visual appearance matches system accent color

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Color mismatch | Low | Low | Use exact same opacity values |

## Security Considerations

None - UI cosmetic changes only.

## Next Steps

Proceed to Phase 02: Add Resolution to Toolbar
