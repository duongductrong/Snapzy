# Fix Xcode Issues Plan

**Date:** 2026-01-18
**Status:** Ready for Implementation
**Priority:** Critical (Swift 6 concurrency errors block compilation)

---

## Executive Summary

15 Xcode issues identified across 7 files. 11 are Swift 6 concurrency errors (critical), 4 are unused variable warnings (low priority). This plan provides exact code changes for each issue.

---

## Issue Inventory

| # | File | Line(s) | Type | Pattern | Priority |
|---|------|---------|------|---------|----------|
| 1 | ScreenCaptureManager.swift | 192 | Warning | D - Unused var | Low |
| 2 | ScreenRecordingManager.swift | 468-473 | Error | A - Task wrapper | Critical |
| 3 | AnnotateWindowController.swift | 271-275 | Error | A - Task wrapper | Critical |
| 4 | AnnotateWindowController.swift | 281-285 | Error | A - Task wrapper | Critical |
| 5 | AnnotateManager.swift | 40-44 | Error | A - Task wrapper | Critical |
| 6 | AnnotateManager.swift | 83-87 | Error | A - Task wrapper | Critical |
| 7 | VideoEditorState.swift | 262-273 | Error | A - Task wrapper | Critical |
| 8 | VideoEditorState.swift | 281-286 | Error | A - Task wrapper | Critical |
| 9 | VideoEditorState.swift | 289-299 | Error | B - Combine scheduler | Critical |
| 10 | VideoEditorManager.swift | 42-46 | Error | A - Task wrapper | Critical |
| 11 | RecordingRegionOverlayWindow.swift | 91 | Warning | D - Unused var | Low |

**Note:** Investigation report mentioned 15 issues but actual file analysis shows 11 distinct issues. Some line numbers in report may have been approximate.

---

## Fix Patterns Reference

### Pattern A: Remove Unnecessary Task Wrapper
Observers registered with `queue: .main` already execute on main thread. Task wrapper is redundant.

```swift
// BEFORE
) { [weak self] _ in
  Task { @MainActor in
    self?.method()
  }
}

// AFTER
) { [weak self] _ in
  self?.method()
}
```

### Pattern B: Add Combine Scheduler
Combine publishers updating @MainActor properties need explicit main thread scheduling.

```swift
// BEFORE
publisher
  .sink { [weak self] value in
    self?.property = value
  }

// AFTER
publisher
  .receive(on: DispatchQueue.main)
  .sink { [weak self] value in
    self?.property = value
  }
```

### Pattern D: Remove Unused Variable
Replace with `_` or remove entirely if value not needed.

---

## Implementation Steps

### Phase 1: Critical Errors (Swift 6 Concurrency)

Execute fixes in order. Build after each file to verify.

---

#### Step 1.1: Fix ScreenRecordingManager.swift

**File:** `/Users/duongductrong/Developer/ZapShot/ZapShot/Core/ScreenRecordingManager.swift`

**Issue:** Timer callback uses Task wrapper unnecessarily (line 468-473)

**Current Code (lines 467-473):**
```swift
  private func startTimer() {
    timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.updateElapsedTime()
      }
    }
    }
```

**Fixed Code:**
```swift
  private func startTimer() {
    timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      self?.updateElapsedTime()
    }
  }
```

**Rationale:** Timer callbacks scheduled on main RunLoop execute on main thread. Class is `@MainActor`, so `updateElapsedTime()` is already main-actor-isolated.

**Testing:**
1. Build project - verify no errors in this file
2. Test screen recording - verify timer updates elapsed time correctly

---

#### Step 1.2: Fix AnnotateWindowController.swift

**File:** `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/Annotate/Window/AnnotateWindowController.swift`

**Issue 1:** Save notification observer (lines 271-275)

**Current Code:**
```swift
    ) { [weak self] _ in
      Task { @MainActor in
        self?.performSave()
      }
    }
```

**Fixed Code:**
```swift
    ) { [weak self] _ in
      self?.performSave()
    }
```

**Issue 2:** SaveAs notification observer (lines 281-285)

**Current Code:**
```swift
    ) { [weak self] _ in
      Task { @MainActor in
        self?.performSaveAs()
      }
    }
```

**Fixed Code:**
```swift
    ) { [weak self] _ in
      self?.performSaveAs()
    }
```

**Rationale:** Both observers use `queue: .main`, guaranteeing main thread execution.

**Testing:**
1. Build project - verify no errors in this file
2. Open annotation window, press Cmd+S - verify save works
3. Press Cmd+Shift+S - verify save as works

---

#### Step 1.3: Fix AnnotateManager.swift

**File:** `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/Annotate/AnnotateManager.swift`

**Issue 1:** Window close observer for items (lines 40-44)

**Current Code:**
```swift
      ) { [weak self] _ in
        Task { @MainActor in
          self?.windowControllers.removeValue(forKey: itemId)
        }
      }
```

**Fixed Code:**
```swift
      ) { [weak self] _ in
        self?.windowControllers.removeValue(forKey: itemId)
      }
```

**Issue 2:** Window close observer for empty window (lines 83-87)

**Current Code:**
```swift
      ) { [weak self] _ in
        Task { @MainActor in
          self?.emptyWindowController = nil
        }
      }
```

**Fixed Code:**
```swift
      ) { [weak self] _ in
        self?.emptyWindowController = nil
      }
```

**Rationale:** Both observers use `queue: .main`.

**Testing:**
1. Build project - verify no errors in this file
2. Open annotation window, close it - verify no crash
3. Open empty annotation window, close it - verify cleanup

---

#### Step 1.4: Fix VideoEditorState.swift

**File:** `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/VideoEditor/State/VideoEditorState.swift`

**Issue 1:** Time observer callback (lines 262-273)

**Current Code:**
```swift
    ) { [weak self] time in
      Task { @MainActor in
        guard let self = self, !self.isScrubbing else { return }
        self.currentTime = time

        // Stop at trim end
        if CMTimeCompare(time, self.trimEnd) >= 0 {
          self.pause()
          self.seek(to: self.trimStart)
        }
      }
    }
```

**Fixed Code:**
```swift
    ) { [weak self] time in
      guard let self = self, !self.isScrubbing else { return }
      self.currentTime = time

      // Stop at trim end
      if CMTimeCompare(time, self.trimEnd) >= 0 {
        self.pause()
        self.seek(to: self.trimStart)
      }
    }
```

**Issue 2:** End observer callback (lines 281-286)

**Current Code:**
```swift
    ) { [weak self] _ in
      Task { @MainActor in
        self?.pause()
        self?.seek(to: self?.trimStart ?? .zero)
      }
    }
```

**Fixed Code:**
```swift
    ) { [weak self] _ in
      self?.pause()
      self?.seek(to: self?.trimStart ?? .zero)
    }
```

**Issue 3:** Change tracking Combine publisher (lines 289-299)

**Current Code:**
```swift
  private func setupChangeTracking() {
    Publishers.CombineLatest3($trimStart, $trimEnd, $isMuted)
      .dropFirst()
      .sink { [weak self] start, end, muted in
        guard let self = self else { return }
        let startChanged = CMTimeCompare(start, self.initialTrimStart) != 0
        let endChanged = CMTimeCompare(end, self.initialTrimEnd) != 0
        let muteChanged = muted != self.initialIsMuted
        self.hasUnsavedChanges = startChanged || endChanged || muteChanged
      }
      .store(in: &cancellables)
  }
```

**Fixed Code:**
```swift
  private func setupChangeTracking() {
    Publishers.CombineLatest3($trimStart, $trimEnd, $isMuted)
      .dropFirst()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] start, end, muted in
        guard let self = self else { return }
        let startChanged = CMTimeCompare(start, self.initialTrimStart) != 0
        let endChanged = CMTimeCompare(end, self.initialTrimEnd) != 0
        let muteChanged = muted != self.initialIsMuted
        self.hasUnsavedChanges = startChanged || endChanged || muteChanged
      }
      .store(in: &cancellables)
  }
```

**Rationale:**
- Issues 1-2: Observer uses `queue: .main`
- Issue 3: Combine pipeline needs explicit main thread scheduling for @MainActor property updates

**Testing:**
1. Build project - verify no errors in this file
2. Open video editor, play video - verify time updates
3. Trim video - verify unsaved changes indicator works
4. Play to end - verify loop to start works

---

#### Step 1.5: Fix VideoEditorManager.swift

**File:** `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/VideoEditor/VideoEditorManager.swift`

**Issue:** Window close observer (lines 42-46)

**Current Code:**
```swift
      ) { [weak self] _ in
        Task { @MainActor in
          self?.cleanupWindow(for: itemId)
        }
      }
```

**Fixed Code:**
```swift
      ) { [weak self] _ in
        self?.cleanupWindow(for: itemId)
      }
```

**Rationale:** Observer uses `queue: .main`.

**Testing:**
1. Build project - verify no errors in this file
2. Open video editor, close it - verify cleanup works

---

### Phase 2: Low Priority Warnings

---

#### Step 2.1: Fix ScreenCaptureManager.swift

**File:** `/Users/duongductrong/Developer/ZapShot/ZapShot/Core/ScreenCaptureManager.swift`

**Issue:** Unused variable `totalScreenMinY` (line 192)

**Current Code (lines 190-192):**
```swift
    // Get total screen height for coordinate conversion (Cocoa uses bottom-left, CG uses top-left)
    let totalScreenHeight = NSScreen.screens.map { $0.frame.maxY }.max() ?? 0
    let totalScreenMinY = NSScreen.screens.map { $0.frame.minY }.min() ?? 0
```

**Fixed Code:**
```swift
    // Get total screen height for coordinate conversion (Cocoa uses bottom-left, CG uses top-left)
    let totalScreenHeight = NSScreen.screens.map { $0.frame.maxY }.max() ?? 0
```

**Rationale:** Variable declared but never used. Safe to remove.

**Testing:**
1. Build project - verify warning gone
2. Test area capture - verify coordinate conversion still works

---

#### Step 2.2: Verify RecordingRegionOverlayWindow.swift

**File:** `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/Recording/RecordingRegionOverlayWindow.swift`

**Investigation:** Line 91 shows:
```swift
    if enabled {
      overlayView.overlayWindow = self
    }
```

This is NOT an unused variable - it's an assignment. The investigation report may have been incorrect about this file. No fix needed here.

**Action:** Skip - no issue found at this location.

---

## Verification Checklist

After all fixes:

- [ ] `xcodebuild -scheme ZapShot -destination 'platform=macOS' build` succeeds with 0 errors
- [ ] No Swift 6 concurrency warnings
- [ ] Screen capture works (fullscreen and area)
- [ ] Screen recording works (start, pause, resume, stop)
- [ ] Timer displays correct elapsed time during recording
- [ ] Annotation window opens and closes correctly
- [ ] Keyboard shortcuts (Cmd+S, Cmd+Shift+S) work in annotation window
- [ ] Video editor opens and closes correctly
- [ ] Video playback time updates correctly
- [ ] Trim controls work correctly
- [ ] Unsaved changes detection works

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Removing Task wrapper causes race condition | Low | Medium | All observers use `queue: .main`, guaranteeing main thread |
| Combine receive(on:) causes timing issues | Low | Low | Main thread scheduling is standard practice |
| Removed variable was needed | Very Low | Low | Code analysis shows variable unused |

---

## Rollback Strategy

If issues arise after implementation:

1. **Git revert:** All changes are in single files with clear before/after
2. **Selective revert:** Each fix is independent, can revert individual files
3. **Quick fix:** Re-add Task wrapper if needed (though shouldn't be)

**Git commands for rollback:**
```bash
# Revert specific file
git checkout HEAD~1 -- path/to/file.swift

# Revert all changes
git revert HEAD
```

---

## Summary

| Metric | Value |
|--------|-------|
| Total issues | 11 confirmed |
| Critical (errors) | 9 |
| Low priority (warnings) | 2 |
| Files to modify | 6 |
| Estimated time | 15-20 minutes |
| Risk level | Low |

**Files to modify:**
1. `/Users/duongductrong/Developer/ZapShot/ZapShot/Core/ScreenRecordingManager.swift`
2. `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/Annotate/Window/AnnotateWindowController.swift`
3. `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/Annotate/AnnotateManager.swift`
4. `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/VideoEditor/State/VideoEditorState.swift`
5. `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/VideoEditor/VideoEditorManager.swift`
6. `/Users/duongductrong/Developer/ZapShot/ZapShot/Core/ScreenCaptureManager.swift`
