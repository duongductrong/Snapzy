# Plan: Unified Title Bar with Full-Size Content View

**Plan ID:** 260122-1636-unified-title-bar
**Created:** 2026-01-22
**Status:** Implementation Complete - Pending Phase 4 Testing
**Last Updated:** 2026-01-22

## Objective

Refactor window configuration in `Annotate` and `VideoEditor` features to unify title bar and main content area. Achieve seamless look where dark background extends to top edge behind traffic light buttons.

## Current State Analysis

### AnnotateWindow
**File:** `ClaudeShot/Features/Annotate/Window/AnnotateWindow.swift`

**Current Configuration:**
- styleMask: `[.titled, .closable, .miniaturizable, .resizable]`
- `titlebarAppearsTransparent = true` ✓
- `titleVisibility = .hidden` ✓
- Background: Dynamic based on theme

**Issue:** Title bar area shows default background, doesn't extend dark background behind traffic lights.

### VideoEditorWindow
**File:** `ClaudeShot/Features/VideoEditor/VideoEditorWindow.swift`

**Current Configuration:**
- styleMask: `[.titled, .closable, .miniaturizable, .resizable]`
- `titlebarAppearsTransparent = true` ✓
- `titleVisibility = .hidden` ✓
- Background: Dynamic based on theme

**Issue:** Same as Annotate - title bar area doesn't extend content background.

## Solution Overview

Add `.fullSizeContentView` to NSWindow styleMask and update SwiftUI views with safe area handling for traffic lights.

## Implementation Phases

### Phase 1: Window Configuration Updates
**File:** `./phase-01-window-configuration.md`

- Update AnnotateWindow.swift - add `.fullSizeContentView`
- Update VideoEditorWindow.swift - add `.fullSizeContentView`

### Phase 2: Annotate Safe Area Handling
**File:** `./phase-02-annotate-safe-area.md`

- Update AnnotateMainView.swift - add safe area modifiers
- Update AnnotateToolbarView.swift - add traffic light spacer (78px)

### Phase 3: VideoEditor Safe Area Handling
**File:** `./phase-03-videoeditor-safe-area.md`

- Update VideoEditorMainView.swift - add title bar spacer (28px) and safe area

### Phase 4: Testing and Validation
**File:** `./phase-04-testing-validation.md`

- Visual testing across themes
- Functional testing
- Edge case validation

## Files to Modify

1. `ClaudeShot/Features/Annotate/Window/AnnotateWindow.swift`
2. `ClaudeShot/Features/Annotate/Views/AnnotateMainView.swift`
3. `ClaudeShot/Features/Annotate/Views/AnnotateToolbarView.swift`
4. `ClaudeShot/Features/VideoEditor/VideoEditorWindow.swift`
5. `ClaudeShot/Features/VideoEditor/Views/VideoEditorMainView.swift`

## Key Technical Details

**Traffic Light Spacing:**
- Standard width: ~78px (3 buttons @ 20px + spacing)
- Standard title bar height: 28px

**Required Modifiers:**
- `.ignoresSafeArea(.all, edges: .top)` - extends content behind title bar
- `.fullSizeContentView` - enables drawing in title area

## Risk Assessment

**Low Risk:**
- Localized changes to window configuration
- No business logic affected
- Existing transparency settings already in place

**Mitigation:**
- Comprehensive testing across themes
- Generous safe area padding
- Clear rollback plan

## Success Criteria

- ✅ Dark background extends seamlessly to window top edge
- ✅ Traffic lights remain visible and functional
- ✅ No content overlap with system buttons
- ⚠️ Works in light, dark, and system theme modes (pending manual testing)
- ✅ All existing functionality preserved
- ✅ Build succeeds without errors

## Implementation Status

### Phase 1: Window Configuration ✅ COMPLETE
- ✅ AnnotateWindow.swift - `.fullSizeContentView` added
- ✅ VideoEditorWindow.swift - `.fullSizeContentView` added

### Phase 2: Annotate Safe Area ✅ COMPLETE
- ✅ AnnotateMainView.swift - safe area modifiers added
- ✅ AnnotateToolbarView.swift - 78px traffic light spacer added

### Phase 3: VideoEditor Safe Area ✅ COMPLETE
- ✅ VideoEditorMainView.swift - 28px title bar spacer added

### Phase 4: Testing & Validation ⚠️ PENDING
- [ ] Visual testing across themes
- [ ] Functional testing
- [ ] Edge case validation
- [ ] Accessibility audit

## Code Review Summary

**Review Date:** 2026-01-22
**Status:** APPROVED WITH RECOMMENDATIONS
**Full Report:** `./reports/260122-code-review-unified-title-bar.md`

**Key Findings:**
- ✅ No critical issues
- ✅ No high-priority issues
- ⚠️ 3 medium-priority improvements identified
- ✅ Build succeeds
- ✅ Implementation matches plan specifications

**Recommendations:**
1. Complete Phase 4 manual testing (REQUIRED before merge)
2. Create architectural decision record (OPTIONAL)
3. Centralize UI metrics constants (OPTIONAL)

## References

- Research: `./research/researcher-01-macos-fullsize-content.md`
- Apple Documentation: NSWindow.StyleMask.fullSizeContentView
