# Phase 03: Add Trim Change Triggers

## Context Links

- **Parent Plan**: [plan.md](./plan.md)
- **Dependencies**: Phase 01, 02
- **Research**: [researcher-01-state-estimation.md](./research/researcher-01-state-estimation.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-29 |
| Description | Add trim change triggers to recalculate estimated file size |
| Priority | **Critical** |
| Implementation Status | **Pending** |
| Review Status | Pending |

## Key Insights

1. **CRITICAL GAP**: Trim changes (`$trimStart`, `$trimEnd`) update unsaved changes but do NOT trigger `recalculateEstimatedFileSize()`
2. Location: `VideoEditorState.swift` L740-745
3. Background triggers at L757-764 already work correctly
4. Trim ratio is used in formula (L668-669) but stale when trim changes

## Requirements

- Recalculate estimated size when `trimStart` changes
- Recalculate estimated size when `trimEnd` changes
- Maintain existing unsaved changes tracking

## Architecture

```
setupChangeTracking() (L738-773)
    ├── Existing: $trimStart, $trimEnd, $isMuted → updateHasUnsavedChanges() ONLY
    │                                              ↑ MISSING recalculation
    ├── Existing: $backgroundStyle, etc → updateHasUnsavedChanges() + recalculateEstimatedFileSize() ✓
    └── Existing: $exportSettings → recalculateEstimatedFileSize() ✓
```

## Related Code Files

| File | Lines | Purpose |
|------|-------|---------|
| `VideoEditorState.swift` | 738-745 | Trim tracking (NEEDS FIX) |
| `VideoEditorState.swift` | 757-764 | Background tracking (reference) |
| `VideoEditorState.swift` | 668-669 | Trim ratio used in calculation |

## Implementation Steps

### Step 1: Modify Trim Change Handler

**File**: `/Users/duongductrong/Developer/ZapShot/ClaudeShot/Features/VideoEditor/State/VideoEditorState.swift`

**Location**: Lines 738-745

**Current Code**:
```swift
private func setupChangeTracking() {
  // Track trim and mute changes
  Publishers.CombineLatest3($trimStart, $trimEnd, $isMuted)
    .dropFirst(3)
    .sink { [weak self] _, _, _ in
      self?.updateHasUnsavedChanges()
    }
    .store(in: &cancellables)
```

**Replace With**:
```swift
private func setupChangeTracking() {
  // Track trim and mute changes
  Publishers.CombineLatest3($trimStart, $trimEnd, $isMuted)
    .dropFirst(3)
    .sink { [weak self] _, _, _ in
      self?.updateHasUnsavedChanges()
      self?.recalculateEstimatedFileSize()
    }
    .store(in: &cancellables)
```

**Change**: Add single line `self?.recalculateEstimatedFileSize()` after `updateHasUnsavedChanges()`

### Step 2: Optional Debounce for Performance

If trim slider causes performance issues, add debounce:

```swift
Publishers.CombineLatest3($trimStart, $trimEnd, $isMuted)
  .dropFirst(3)
  .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
  .sink { [weak self] _, _, _ in
    self?.updateHasUnsavedChanges()
    self?.recalculateEstimatedFileSize()
  }
  .store(in: &cancellables)
```

**Note**: Only add debounce if performance issues observed during testing.

## Todo List

- [ ] Add `recalculateEstimatedFileSize()` to trim change handler at L743
- [ ] Test trim slider updates estimation in real-time
- [ ] Verify no duplicate calculations
- [ ] (Optional) Add debounce if performance issues

## Success Criteria

| Criteria | Validation |
|----------|------------|
| Trim start change updates estimate | Drag left trim handle, size decreases |
| Trim end change updates estimate | Drag right trim handle, size decreases |
| Mute change updates estimate | Toggle mute, size slightly decreases (0.9x) |
| No performance lag | Smooth slider interaction |

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Excessive recalculations | Low | Minor lag | Add debounce if needed |
| Breaking unsaved changes tracking | Very Low | Medium | Single line addition, minimal risk |

## Security Considerations

None - internal state management only.

## Next Steps

After completing this phase, proceed to [Phase 04: Build and Verify](./phase-04-build-and-verify.md).
