# Implementation Plan: Fix Estimated Size Calculation

## Problem Summary

The estimated file size calculation has one remaining critical issue:
- **Trim changes do NOT trigger recalculation** - trimming video changes duration but estimate stays stale

## Current State (Already Implemented)

| Feature | Status | Location |
|---------|--------|----------|
| Background padding in formula | Done | L676-686 |
| Background change triggers | Done | L757-764 |
| Export settings triggers | Done | L766-772 |
| Trim change triggers | **MISSING** | L740-745 needs fix |

## Affected Files

| File | Purpose |
|------|---------|
| `ClaudeShot/Features/VideoEditor/State/VideoEditorState.swift` | Add trim triggers |

## Implementation Phases

| Phase | Description | Status | Document |
|-------|-------------|--------|----------|
| 01 | Verify Initial Calculation | Done | [phase-01](./phase-01-fix-initial-calculation.md) |
| 02 | Verify Background Padding | Done | [phase-02](./phase-02-include-background-padding.md) |
| 03 | Add Trim Change Triggers | **Pending** | [phase-03](./phase-03-add-change-triggers.md) |
| 04 | Build & Verify | Pending | [phase-04](./phase-04-build-and-verify.md) |

## Critical Fix Required

```swift
// VideoEditorState.swift L740-745
// CURRENT (missing recalculation):
Publishers.CombineLatest3($trimStart, $trimEnd, $isMuted)
  .dropFirst(3)
  .sink { [weak self] _, _, _ in
    self?.updateHasUnsavedChanges()
  }

// FIXED (add recalculation):
Publishers.CombineLatest3($trimStart, $trimEnd, $isMuted)
  .dropFirst(3)
  .sink { [weak self] _, _, _ in
    self?.updateHasUnsavedChanges()
    self?.recalculateEstimatedFileSize()  // ADD THIS
  }
```

## Success Criteria

- [x] Background padding included in dimension calculation
- [x] Background changes trigger recalculation
- [x] Export settings changes trigger recalculation
- [ ] Trim changes trigger recalculation
- [ ] Build succeeds with no errors

## Research References

- [researcher-01-state-estimation.md](./research/researcher-01-state-estimation.md)
- [researcher-02-export-pipeline.md](./research/researcher-02-export-pipeline.md)
