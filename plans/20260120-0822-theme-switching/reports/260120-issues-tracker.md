# Theme Switching Implementation - Issues Tracker

**Last Updated:** 2026-01-20

---

## High Priority Issues

### [H1] Inconsistent ColorScheme Usage Across App
**Status:** 🔴 OPEN  
**Severity:** High  
**Impact:** MenuBarExtra, Onboarding, Recording toolbar won't update when switching to Auto mode

**Files to Fix:**
- [ ] `ZapShot/App/ZapShotApp.swift:39` - MenuBarExtra
- [ ] `ZapShot/App/ZapShotApp.swift:52` - Onboarding window  
- [ ] `ZapShot/App/ZapShotApp.swift:61` - Settings window
- [ ] `ZapShot/Features/Recording/RecordingToolbarWindow.swift:117`

**Change Required:**
```swift
// FROM:
.preferredColorScheme(themeManager.systemAppearance)

// TO:
.preferredColorScheme(themeManager.effectiveColorScheme)
```

**Estimated Time:** 10 minutes  
**Assigned To:** -

---

### [H2] AppKit Windows Not Listening to System Appearance Changes
**Status:** 🔴 OPEN  
**Severity:** High  
**Impact:** Windows stuck with theme from creation time, don't update when system changes

**Files to Fix:**
- [ ] `ZapShot/Features/Annotate/Window/AnnotateWindow.swift`
- [ ] `ZapShot/Features/VideoEditor/VideoEditorWindow.swift`

**Implementation Required:**
1. Add notification observer in init
2. Call `applyTheme()` when notification fires
3. Post notification from ThemeManager when system changes

**Estimated Time:** 30 minutes  
**Assigned To:** -

---

## Medium Priority Issues

### [M1] AppStorage didSet Redundant
**Status:** 🟡 OPEN  
**Severity:** Medium  
**Impact:** Redundant code, no functional issue

**File:** `ZapShot/Core/Theme/ThemeManager.swift:21-23`

**Change:**
```swift
// Remove didSet - @AppStorage handles objectWillChange automatically
@AppStorage(PreferencesKeys.appearanceMode)
var preferredAppearance: AppearanceMode = .system
```

**Estimated Time:** 5 minutes  
**Assigned To:** -

---

### [M2] Potential Race Condition in System Appearance Init
**Status:** 🟡 OPEN  
**Severity:** Medium  
**Impact:** Edge case if ThemeManager accessed very early in app lifecycle

**File:** `ZapShot/Core/Theme/ThemeManager.swift:33`

**Action:** Add defensive nil checks or defer initialization

**Estimated Time:** 10 minutes  
**Assigned To:** -

---

### [M3] Task Wrapper Unnecessary in Sink
**Status:** 🟡 OPEN  
**Severity:** Medium  
**Impact:** Adds unnecessary latency and allocation

**File:** `ZapShot/Core/Theme/ThemeManager.swift:39-42`

**Change:**
```swift
// FROM:
.sink { [weak self] _ in
    Task { @MainActor in
        self?.updateSystemAppearance()
    }
}

// TO:
.sink { [weak self] _ in
    self?.updateSystemAppearance()
}
```

**Estimated Time:** 5 minutes  
**Assigned To:** -

---

## Low Priority Issues

### [L1] Documentation Clarity
**Status:** 🟢 OPEN  
**Severity:** Low  
**Impact:** Code readability

**File:** `ZapShot/Core/Theme/ThemeManager.swift:66-67`

**Action:** Add usage examples to doc comments

**Estimated Time:** 10 minutes  
**Assigned To:** -

---

### [L2] Notification String Should Be Constant
**Status:** 🟢 OPEN  
**Severity:** Low  
**Impact:** Code maintainability

**File:** `ZapShot/Core/Theme/ThemeManager.swift:37`

**Action:** Extract to `extension Notification.Name`

**Estimated Time:** 5 minutes  
**Assigned To:** -

---

### [L3] PreferencesView Shared Instance Pattern
**Status:** 🟢 OPEN  
**Severity:** Low  
**Impact:** Code style preference

**File:** `ZapShot/Features/Preferences/PreferencesView.swift:11`

**Action:** Consider using `@EnvironmentObject` pattern

**Estimated Time:** 15 minutes  
**Assigned To:** -

---

## Issue Summary

| Priority | Open | Closed | Total |
|----------|------|--------|-------|
| High     | 2    | 0      | 2     |
| Medium   | 3    | 0      | 3     |
| Low      | 3    | 0      | 3     |
| **Total**| **8**| **0**  | **8** |

**Blocking Issues:** H1, H2 (must fix before marking complete)  
**Total Estimated Time:** ~90 minutes

---

## Notes

- Build currently succeeds with no errors/warnings
- Core implementation (ThemeManager) is solid
- Issues are integration and polish
- No security concerns identified
