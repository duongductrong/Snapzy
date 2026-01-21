# Code Review: Swift 6 Concurrency Fixes

**Review Date:** 2026-01-18
**Reviewer:** Code Review Agent
**Status:** NEEDS_WORK

---

## Scope

### Files Modified (6 files)
1. `ScreenRecordingManager.swift` - Timer callback Task removal (lines 468-473)
2. `AnnotateWindowController.swift` - NotificationCenter observer Task removal (lines 271-285)
3. `AnnotateManager.swift` - Window close observer Task removal (lines 40-44, 83-87)
4. `VideoEditorState.swift` - Observer Task removal + Combine pipeline fix (lines 262-299)
5. `VideoEditorManager.swift` - MainActor.assumeIsolated usage (lines 42-46)
6. `ScreenCaptureManager.swift` - Unused variable removal (lines 191-200)

### Build Status
- **Result:** BUILD SUCCEEDED
- **Errors:** 0
- **Warnings:** 48 (Swift 6 concurrency warnings remain)

---

## Overall Assessment

**Status:** NEEDS_WORK

Fixes address user-reported issues but **incomplete Swift 6 concurrency compliance**. Build succeeds but 48 warnings remain across modified files. Fixes show inconsistent patterns - some use proper solutions (Combine `.receive(on:)`), others create new violations (notification observers without isolation).

---

## Critical Issues

### 1. ScreenRecordingManager.swift - Unsafe Timer Callback (Line 468-470)

**Issue:** Timer callback calls MainActor-isolated method `updateElapsedTime()` from non-isolated context.

```swift
// CURRENT (INCORRECT)
timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
  self?.updateElapsedTime()  // ⚠️ Main actor violation
}
```

**Problem:** Removed Task wrapper but callback is nonisolated while `updateElapsedTime()` is MainActor-isolated.

**Fix Required:**
```swift
timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
  Task { @MainActor in
    self?.updateElapsedTime()
  }
}
```

**Impact:** Runtime crash potential when timer fires on background thread.

---

### 2. AnnotateWindowController.swift - Notification Observer Isolation (Lines 267-282)

**Issue:** NotificationCenter observers call MainActor methods from nonisolated closures despite `.main` queue.

```swift
// CURRENT (INCORRECT)
NotificationCenter.default.addObserver(
  forName: .annotateSave,
  object: window,
  queue: .main  // ⚠️ Not sufficient for Swift 6
) { [weak self] _ in
  self?.performSave()  // ⚠️ Main actor violation
}
```

**Problem:** `.main` queue ≠ MainActor isolation in Swift 6. Closure is Sendable but not MainActor-isolated.

**Fix Required:**
```swift
NotificationCenter.default.addObserver(
  forName: .annotateSave,
  object: window,
  queue: .main
) { [weak self] _ in
  Task { @MainActor in
    self?.performSave()
  }
}
```

**Impact:** 4 warnings (2 notifications × 2 methods each).

---

### 3. AnnotateManager.swift - Sendable Closure Violations (Lines 40-42, 82)

**Issue:** MainActor properties mutated from Sendable closures without isolation.

```swift
// CURRENT (INCORRECT)
NotificationCenter.default.addObserver(
  forName: NSWindow.willCloseNotification,
  object: window,
  queue: .main
) { [weak self] _ in
  self?.windowControllers.removeValue(forKey: itemId)  // ⚠️ Main actor mutation
}
```

**Problem:** `windowControllers` is MainActor-isolated but mutated from Sendable closure.

**Fix Required:**
```swift
NotificationCenter.default.addObserver(
  forName: NSWindow.willCloseNotification,
  object: window,
  queue: .main
) { [weak self] _ in
  Task { @MainActor in
    self?.windowControllers.removeValue(forKey: itemId)
  }
}
```

**Impact:** 2 warnings (both window trackers).

---

### 4. VideoEditorState.swift - Observer Closures Not Isolated (Lines 257-283)

**Issue:** AVPlayer time observer and notification observer access MainActor state without isolation.

```swift
// CURRENT (INCORRECT)
timeObserver = player.addPeriodicTimeObserver(
  forInterval: interval,
  queue: .main
) { [weak self] time in
  guard let self = self, !self.isScrubbing else { return }  // ⚠️ Main actor access
  self.currentTime = time  // ⚠️ Main actor mutation

  if CMTimeCompare(time, self.trimEnd) >= 0 {  // ⚠️ Main actor access
    self.pause()  // ⚠️ Main actor call
    self.seek(to: self.trimStart)  // ⚠️ Main actor call
  }
}
```

**Problem:** Closure accesses 5+ MainActor properties/methods without isolation despite `.main` queue.

**Fix Required:**
```swift
timeObserver = player.addPeriodicTimeObserver(
  forInterval: interval,
  queue: .main
) { [weak self] time in
  Task { @MainActor [weak self] in
    guard let self = self, !self.isScrubbing else { return }
    self.currentTime = time

    if CMTimeCompare(time, self.trimEnd) >= 0 {
      self.pause()
      self.seek(to: self.trimStart)
    }
  }
}
```

**Impact:** 18 warnings (6 violations × 3 locations × duplicated warnings).

---

### 5. VideoEditorManager.swift - MainActor.assumeIsolated Usage

**Status:** CORRECT but risky pattern.

```swift
// CURRENT (RISKY)
let observer = NotificationCenter.default.addObserver(
  forName: NSWindow.willCloseNotification,
  object: window,
  queue: .main
) { [weak self] _ in
  MainActor.assumeIsolated {
    self?.cleanupWindow(for: itemId)
  }
}
```

**Analysis:**
- **Correct:** `.main` queue guarantees MainActor execution
- **Risky:** `assumeIsolated` crashes if assumption violated
- **Better:** Use Task { @MainActor in } for safety

**Recommendation:** Replace with Task wrapper for consistency.

---

### 6. ScreenCaptureManager.swift - Unused Variables

**Status:** INCOMPLETE

```swift
// Line 191 - Still present
let totalScreenHeight = NSScreen.screens.map { $0.frame.maxY }.max() ?? 0  // ⚠️ Unused
```

**Problem:** User claims removed but variable still exists in code and triggers warning.

**Fix Required:** Remove line 191 entirely or prefix with underscore if intentional.

---

## High Priority Findings

### Pattern Inconsistency

**Issue:** Three different approaches to same problem:

1. **Task wrapper removed** (ScreenRecordingManager, AnnotateWindowController, AnnotateManager) - INCORRECT
2. **Combine .receive(on:)** (VideoEditorState lines 288) - CORRECT
3. **MainActor.assumeIsolated** (VideoEditorManager) - RISKY

**Recommendation:** Standardize on Task { @MainActor in } for notification/timer callbacks.

---

### RecordingSession Isolation Unknown

**Issue:** `ScreenRecordingManager` calls `session.appendVideoSample()` from nonisolated context (line 505).

```swift
// Extension is nonisolated
extension ScreenRecordingManager: SCStreamOutput {
  nonisolated func stream(...) {
    session.appendVideoSample(sampleBuffer)  // ⚠️ What isolation?
  }
}
```

**Missing Info:** RecordingSession.swift not reviewed. If methods are MainActor-isolated, this is CRITICAL BUG.

**Action Required:** Review RecordingSession.swift isolation declarations.

---

## Medium Priority Improvements

### 1. Combine Usage in VideoEditorState

**Status:** CORRECT implementation (lines 286-296).

```swift
Publishers.CombineLatest3($trimStart, $trimEnd, $isMuted)
  .dropFirst()
  .receive(on: DispatchQueue.main)  // ✅ Correct
  .sink { [weak self] start, end, muted in
    guard let self = self else { return }
    // MainActor-isolated work
  }
```

**Analysis:** Proper pattern for Combine publishers. Should be template for other fixes.

---

### 2. Observer Cleanup Patterns

**Issue:** Inconsistent observer management across files.

- AnnotateWindowController: No explicit removal (relies on object parameter)
- AnnotateManager: No explicit removal
- VideoEditorState: Proper removal in deinit (lines 108-109)
- VideoEditorManager: Proper tracking in dictionary (lines 18, 69-71)

**Recommendation:** Ensure all observers properly removed to prevent leaks.

---

## Low Priority Suggestions

### 1. Duplicate Warnings in Build Output

**Observation:** Same warnings repeated 3-5 times for VideoEditorState (lines 263-281).

**Cause:** Likely multiple build passes or compiler internal duplication.

**Impact:** Cosmetic - no code issue.

---

### 2. RecordingRegionOverlayWindow Warning

**File:** Not in user's list but appears in build output.

```
RecordingRegionOverlayWindow.swift:288:37: warning: immutable value 'overlayWindow' was never used
```

**Recommendation:** Add to fix list for completeness.

---

## Positive Observations

### 1. Proper MainActor Class Annotations

All manager classes properly annotated with `@MainActor`:
- ScreenRecordingManager (line 96)
- AnnotateWindowController (line 14)
- AnnotateManager (line 12)
- VideoEditorState (line 13)
- VideoEditorManager (line 12)

### 2. Weak Self Pattern

All closures properly use `[weak self]` to prevent retain cycles.

### 3. Build Success

No errors - app compiles and runs despite warnings.

---

## Recommended Actions

### Priority 1 (Critical - Must Fix)

1. **ScreenRecordingManager.swift line 469:** Wrap `updateElapsedTime()` in Task { @MainActor in }
2. **VideoEditorState.swift lines 262-271:** Wrap time observer closure in Task { @MainActor in }
3. **VideoEditorState.swift lines 279-282:** Wrap end observer closure in Task { @MainActor in }
4. **AnnotateManager.swift lines 40-42:** Wrap mutation in Task { @MainActor in }
5. **AnnotateManager.swift lines 82:** Wrap mutation in Task { @MainActor in }

### Priority 2 (High - Should Fix)

6. **AnnotateWindowController.swift lines 271-273:** Wrap `performSave()` in Task { @MainActor in }
7. **AnnotateWindowController.swift lines 279-281:** Wrap `performSaveAs()` in Task { @MainActor in }
8. **ScreenCaptureManager.swift line 191:** Remove `totalScreenHeight` declaration
9. **VideoEditorManager.swift lines 42-46:** Replace `assumeIsolated` with Task wrapper
10. **RecordingSession.swift:** Review isolation (not in current scope but flagged)

### Priority 3 (Medium - Nice to Have)

11. Standardize observer cleanup patterns
12. Add code comments documenting concurrency patterns
13. Consider extracting notification observer helper with proper isolation

---

## Metrics

- **Files Modified:** 6
- **Lines Changed:** ~40
- **Warnings Resolved:** 0 (user claimed 15, but new warnings introduced)
- **Warnings Remaining:** 48
- **Critical Issues:** 5
- **High Priority Issues:** 5
- **Build Status:** SUCCESS (with warnings)
- **Swift 6 Compliance:** INCOMPLETE

---

## Verification Steps

1. Build with strict concurrency checking enabled
2. Run static analyzer
3. Test all notification/timer callbacks under thread sanitizer
4. Verify no crashes in production with async operations
5. Code review RecordingSession.swift for isolation

---

## Summary

Fixes partially address symptoms but miss root cause - Swift 6 requires explicit MainActor isolation for Sendable closures regardless of dispatch queue. Removing Task wrappers without adding proper isolation attributes creates violations. VideoEditorState's Combine pipeline shows correct pattern - use as template. Build succeeds but warnings indicate runtime safety issues under strict concurrency.

**Recommendation:** Apply Priority 1 and 2 fixes before merging. Consider this intermediate state, not production-ready.

---

## Unresolved Questions

1. Is RecordingSession thread-safe for nonisolated calls from SCStreamOutput?
2. Are there automated tests covering concurrent scenarios?
3. What is project's Swift concurrency checking level (minimal/targeted/complete)?
4. Should assumeIsolated be avoided project-wide as risky pattern?
5. Why were Task wrappers removed if they were correct solutions?
