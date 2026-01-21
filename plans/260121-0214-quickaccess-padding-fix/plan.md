# QuickAccess Padding Overflow Fix

**Created:** 2026-01-21
**Status:** Completed
**Priority:** Medium

## Problem Statement

Panel size calculation uses duplicated padding constants causing overflow:
- `QuickAccessManager.containerPadding = 10` (line 68)
- `QuickAccessStackView.padding = 10` (line 15)

Increasing StackView padding causes cards to overflow panel bounds. Shadow (radius 8 + y offset 4 = ~12pt) gets clipped at edges.

## Root Cause

No single source of truth for container padding. Manager calculates panel size independently from StackView's actual padding usage.

## Solution Approach

Create shared `QuickAccessLayout` constants struct. Both Manager and StackView reference same values. Increase padding to 12pt for shadow clearance.

## Phases

| Phase | Description | Status |
|-------|-------------|--------|
| 01 | Sync padding constants with shared layout config | Completed |

## Success Criteria

- [x] Shadow not clipped at panel edges
- [x] Cards have ~12pt clearance from container edges
- [x] Single source of truth for layout constants
- [x] No visual regression in card positioning

## Files Affected

- `ZapShot/Features/QuickAccess/QuickAccessManager.swift`
- `ZapShot/Features/QuickAccess/QuickAccessStackView.swift`
- `ZapShot/Features/QuickAccess/QuickAccessLayout.swift` (new)

## Risk Assessment

- **Low**: Change is isolated to QuickAccess module
- **Mitigation**: Visual testing on all screen positions

## References

- [Phase 01: Sync Padding Constants](./phase-01-sync-padding-constants.md)
