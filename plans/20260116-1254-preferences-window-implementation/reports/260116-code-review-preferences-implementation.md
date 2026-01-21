# Code Review: Preferences Window Implementation

## Scope

**Files Reviewed:**
- ZapShot/App/ZapShotApp.swift
- ZapShot/Features/Preferences/PreferencesView.swift
- ZapShot/Features/Preferences/PreferencesManager.swift
- ZapShot/Features/Preferences/PreferencesKeys.swift
- ZapShot/Features/Preferences/Tabs/GeneralSettingsView.swift
- ZapShot/Features/Preferences/Tabs/QuickAccessSettingsView.swift
- ZapShot/Features/Preferences/Tabs/ShortcutsSettingsView.swift
- ZapShot/Features/Preferences/Tabs/PlaceholderSettingsView.swift
- ZapShot/Features/Preferences/Components/LoginItemManager.swift
- ZapShot/Features/Preferences/Components/AfterCaptureMatrixView.swift
- ZapShot/ContentView.swift
- ZapShot/Core/ScreenCaptureViewModel.swift
- ZapShot/Features/FloatingScreenshot/FloatingPosition.swift
- ZapShot/Features/FloatingScreenshot/FloatingScreenshotManager.swift

**Review Focus:** Recent changes, critical issues only

**Build Status:** ✅ SUCCESS (Swift 6.2.3, macOS 26.0)

## Overall Assessment

**Code Quality:** Good - Clean SwiftUI patterns, proper state management, modern Swift concurrency
**Architecture:** Solid - Clear separation of concerns, reusable components
**Memory Safety:** Good - Proper weak delegate references, no obvious retain cycles in reviewed code
**Thread Safety:** Good - Consistent @MainActor usage on ObservableObject classes

## Critical Issues

### 1. Force Unwrap Risk - Desktop Directory Access

**File:** `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/Preferences/Tabs/GeneralSettingsView.swift:64`

```swift
let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
```

**Issue:** Force unwrap will crash if Desktop directory unavailable (rare but possible in sandboxed/restricted environments)

**Impact:** Potential app crash on initialization

**Fix:**
```swift
private func initializeExportLocation() {
  if exportLocation.isEmpty {
    guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
      // Fallback to user's home directory
      exportLocation = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("ZapShot").path
      return
    }
    exportLocation = desktop.appendingPathComponent("ZapShot").path
  }
}
```

## High Priority Findings

### 2. Missing Weak Self in FloatingScreenshotManager

**File:** `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/FloatingScreenshot/FloatingScreenshotManager.swift:120-123`

```swift
$items
  .receive(on: DispatchQueue.main)
  .sink { [weak self] items in
    self?.updatePanelSize()
  }
  .store(in: &cancellables)
```

**Issue:** Already uses `[weak self]` correctly ✅ - No issue found

### 3. Missing Weak Self in ScreenCaptureViewModel

**File:** `/Users/duongductrong/Developer/ZapShot/ZapShot/Core/ScreenCaptureViewModel.swift:72-80`

```swift
captureManager.captureCompletedPublisher
  .receive(on: DispatchQueue.main)
  .sink { [weak self] url in
    guard self?.floatingManager.isEnabled == true else { return }
    Task {
      await self?.floatingManager.addScreenshot(url: url)
    }
  }
  .store(in: &cancellables)
```

**Status:** ✅ Properly uses `[weak self]` - No retain cycle risk

### 4. Event Monitor Memory Leak Risk

**File:** `/Users/duongductrong/Developer/ZapShot/ZapShot/Core/ShortcutRecorderView.swift:41-58`

**Issue:** Event monitor stored as `@State private var eventMonitor: Any?` could leak if view deallocates while recording

**Impact:** Memory leak if user navigates away during shortcut recording

**Recommendation:** Add `.onDisappear` cleanup:
```swift
var body: some View {
  // ... existing code
  .onDisappear {
    stopRecording()
  }
}
```

## Medium Priority Improvements

### 5. Error Handling - LoginItemManager

**File:** `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/Preferences/Components/LoginItemManager.swift:14-24`

**Current:**
```swift
static func setEnabled(_ enabled: Bool) {
  do {
    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
  } catch {
    print("LoginItemManager: Failed to update login item - \(error.localizedDescription)")
  }
}
```

**Issue:** Silent failure - user has no feedback if login item registration fails

**Recommendation:** Return `Result<Void, Error>` and show alert in UI:
```swift
static func setEnabled(_ enabled: Bool) -> Result<Void, Error> {
  do {
    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
    return .success(())
  } catch {
    return .failure(error)
  }
}
```

Then in GeneralSettingsView:
```swift
.onChange(of: startAtLogin) { _, newValue in
  let result = LoginItemManager.setEnabled(newValue)
  if case .failure(let error) = result {
    // Show alert to user
    startAtLogin = !newValue // Revert toggle
  }
}
```

### 6. Race Condition - Area Selection

**File:** `/Users/duongductrong/Developer/ZapShot/ZapShot/Core/ScreenCaptureViewModel.swift:171-220`

**Status:** ✅ Already has double-check protection at line 184:
```swift
guard self.areaSelectionController == nil else { return }
```

Good defensive programming - prevents race condition.

### 7. Accessibility - Missing Labels

**Files:** Multiple views in Preferences

**Issue:** Some toggles use `.labelsHidden()` without explicit accessibility labels

**Example:** `AfterCaptureMatrixView.swift:36-42`

**Recommendation:**
```swift
Toggle("", isOn: binding(for: action, type: .screenshot))
  .labelsHidden()
  .accessibilityLabel("\(action.displayName) for Screenshot")
```

## Low Priority Suggestions

### 8. Magic Numbers - Panel Sizing

**File:** `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/FloatingScreenshot/FloatingScreenshotManager.swift:64-68`

```swift
let maxVisibleItems = 5
private let cardWidth: CGFloat = 200
private let cardHeight: CGFloat = 112
private let cardSpacing: CGFloat = 8
private let containerPadding: CGFloat = 10
```

**Status:** ✅ Already extracted as named constants - Good practice

### 9. Hardcoded Frame Dimensions

**File:** `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/Preferences/PreferencesView.swift:34`

```swift
.frame(width: 550, height: 450)
```

**Recommendation:** Extract to constants for maintainability:
```swift
private enum Layout {
  static let windowWidth: CGFloat = 550
  static let windowHeight: CGFloat = 450
}
```

## Positive Observations

1. **Excellent State Management** - Proper use of `@AppStorage`, `@Published`, and centralized `PreferencesManager` singleton
2. **Thread Safety** - Consistent `@MainActor` annotations on all `ObservableObject` classes
3. **Memory Management** - Proper `weak var delegate` in `KeyboardShortcutManager`
4. **Code Organization** - Clean file structure, clear component separation
5. **Modern Swift** - Uses Swift 6.2.3 features, proper optionals handling (mostly)
6. **Build Success** - No compilation errors, type-safe code
7. **Reusable Components** - `PlaceholderSettingsView` with factory methods, `AfterCaptureMatrixView` generic matrix
8. **UserDefaults Encapsulation** - Centralized `PreferencesKeys` enum prevents typos

## Security Considerations

✅ **No secrets in code** - No hardcoded credentials or API keys
✅ **Proper entitlements** - Uses `SMAppService` (requires proper entitlements)
✅ **File access** - Uses standard macOS APIs (`NSOpenPanel`) for directory selection
✅ **No SQL injection** - No database queries
✅ **No XSS risks** - Native macOS app, no web views in reviewed code

## Performance

✅ **No obvious bottlenecks** - Lightweight state management
✅ **Efficient rendering** - Proper SwiftUI bindings, no excessive recomputations
✅ **Async operations** - Proper use of `Task` for background work
⚠️ **Combine subscriptions** - All properly stored in `cancellables`, cleaned up automatically

## Recommended Actions

1. **[CRITICAL]** Fix force unwrap in `GeneralSettingsView.swift:64` (Desktop directory)
2. **[HIGH]** Add `.onDisappear` cleanup to `ShortcutRecorderView` to prevent event monitor leak
3. **[MEDIUM]** Improve error handling in `LoginItemManager` with user feedback
4. **[MEDIUM]** Add accessibility labels to matrix toggles in `AfterCaptureMatrixView`
5. **[LOW]** Extract magic numbers for preferences window dimensions

## Metrics

- **Type Safety:** Excellent - No `as!` casts, minimal force unwraps (1 found)
- **Test Coverage:** Not reviewed (no test files in scope)
- **@MainActor Coverage:** 100% on ObservableObject classes
- **Build Status:** ✅ Clean build, no warnings in reviewed modules
- **LOC Reviewed:** ~1,200 lines across 14 files
- **Critical Issues:** 1 (force unwrap)
- **High Priority:** 1 (event monitor cleanup)
- **Medium Priority:** 2 (error handling, accessibility)

## Task Completeness Verification

**Plan Reference:** `/Users/duongductrong/Developer/ZapShot/plans/20260116-1254-preferences-window-implementation/plan.md`

**Implementation Status:**

✅ Phase 1 - Foundation (Settings scene, PreferencesManager, tab structure)
✅ Phase 2 - General tab (Startup, sounds, export, after-capture matrix)
✅ Phase 3 - Quick Access tab (Position, behaviors, overlay settings)
✅ Phase 4 - Shortcuts tab (Recorder integration, shortcuts management)
✅ Phase 5 - Placeholder tabs (Wallpaper, Recording, Cloud, Advanced)
✅ Phase 6 - Integration (App integration via ZapShotApp.swift)

**Success Criteria:**
✅ Preferences opens via Cmd+, (Settings scene auto-registers)
✅ All settings persist (UserDefaults + @AppStorage)
✅ Shortcuts tab works with KeyboardShortcutManager
✅ Launch at login toggles (SMAppService integration)
⚠️ ContentView settings partially migrated (some settings still in ContentView, but accessible)

**TODO Items:** None found in reviewed code

**Remaining Work:**
- Fix critical force unwrap issue
- Add event monitor cleanup
- Consider UX improvements for error feedback

## Unresolved Questions

1. Are there any automated tests for the Preferences window? (No test files found in review scope)
2. Should the "Show icon in menu bar" toggle have immediate effect, or require app restart?
3. What happens if SMAppService fails to register on older macOS versions? (Requires macOS 13+)
4. Is there a plan to implement the placeholder tabs (Wallpaper, Recording, Cloud, Advanced)?
