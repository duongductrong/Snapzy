# Floating Animation Optimization Plan

## Overview
| Field | Value |
|-------|-------|
| Created | 2026-01-16 |
| Status | Ready for Review |
| Priority | High |
| Estimated Effort | Small (2 phases, ~4 files) |

## Problem Statement
Floating screenshot stack animations are laggy and delayed due to:
1. Duplicate animation triggers (double `withAnimation` calls)
2. Blocking main thread operations in action handlers
3. Competing animation systems (SwiftUI vs AppKit)
4. Individual card appearance state causing stagger

## Solution Summary
Consolidate all animations to single source of truth, move blocking operations async, provide immediate visual feedback on user actions.

## Implementation Phases

| Phase | Name | Status | Progress | Link |
|-------|------|--------|----------|------|
| 01 | Animation Consolidation | Completed | 100% | [phase-01-animation-consolidation.md](./phase-01-animation-consolidation.md) |
| 02 | Async Action Handlers | Completed | 100% | [phase-02-async-action-handlers.md](./phase-02-async-action-handlers.md) |

## Files to Modify

| File | Phase | Changes |
|------|-------|---------|
| FloatingStackView.swift | 01 | Remove withAnimation wrappers, update transition |
| FloatingCardView.swift | 01 | Remove appeared state and onAppear animation |
| FloatingScreenshotManager.swift | 01, 02 | Centralize animation, async action handlers |
| FloatingPanelController.swift | 01 | Disable AppKit panel animation |

## Key Changes Summary

### Phase 01: Animation Consolidation
- Remove duplicate `withAnimation` calls from FloatingStackView callbacks
- Remove `appeared` state from FloatingCardView (use transition instead)
- Centralize animation in manager's `removeScreenshot()`
- Disable `animate: true` in FloatingPanelController
- Use `.animation` modifier with full items array for proper tracking

### Phase 02: Async Action Handlers
- Refactor `copyToClipboard()` to remove card immediately, copy async
- Refactor `openInFinder()` to remove card immediately, reveal async
- Capture URL before removal to avoid race condition
- Result: < 16ms response time on action clicks

## Success Criteria
1. No animation lag on add/remove operations
2. Immediate visual response on Copy/Save/Dismiss clicks
3. Smooth animations during rapid operations
4. Panel resizes without AppKit animation conflict

## Dependencies
- None (self-contained UI optimization)

## Risks
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Animation timing feels off | Medium | Low | Tune spring parameters |
| Clipboard race condition | Low | Low | Capture URL before removal |
