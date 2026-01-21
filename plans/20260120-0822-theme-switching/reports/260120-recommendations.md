# Theme Switching Fix - Recommended Actions

**Date:** 2026-01-20
**Priority Order:** Critical → High → Medium → Low

---

## 🔴 CRITICAL - Fix Before Marking Complete

### 1. Update All SwiftUI Views to Use effectiveColorScheme

**Time:** 10 minutes  
**Files:** ZapShotApp.swift, RecordingToolbarWindow.swift

```swift
// ZapShotApp.swift - Line 39
MenuBarExtra("ZapShot", systemImage: "camera.aperture") {
    MenuBarContentView(viewModel: viewModel, updater: updaterController.updater)
        .preferredColorScheme(themeManager.effectiveColorScheme)  // Changed
}

// ZapShotApp.swift - Line 52
WindowGroup(id: "onboarding") {
    OnboardingFlowView(onComplete: { ... })
        .frame(width: 500, height: 450)
        .preferredColorScheme(themeManager.effectiveColorScheme)  // Changed
}

// ZapShotApp.swift - Line 61
Settings {
    PreferencesView()
        .preferredColorScheme(themeManager.effectiveColorScheme)  // Changed
}

// RecordingToolbarWindow.swift - Line 117
let themedView = view.preferredColorScheme(ThemeManager.shared.effectiveColorScheme)
```

**Why Critical:** Without this, the entire fix is ineffective - other windows still have the nil bug.

---

### 2. Add System Appearance Change Listeners to AppKit Windows

**Time:** 30 minutes  
**Files:** AnnotateWindow.swift, VideoEditorWindow.swift, ThemeManager.swift

**Step 1:** Update ThemeManager to post notifications

```swift
// ThemeManager.swift
extension Notification.Name {
    static let themeDidChange = Notification.Name("ThemeDidChange")
}

// In updateSystemAppearance()
private func updateSystemAppearance() {
    let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    if currentSystemIsDark != isDark {
        currentSystemIsDark = isDark
        NotificationCenter.default.post(name: .themeDidChange, object: nil)
    }
}

// Also post when user changes preference
@AppStorage(PreferencesKeys.appearanceMode)
var preferredAppearance: AppearanceMode = .system {
    didSet {
        NotificationCenter.default.post(name: .themeDidChange, object: nil)
    }
}
```

**Step 2:** Update AnnotateWindow

```swift
// AnnotateWindow.swift
init(contentRect: NSRect) {
    super.init(...)
    configure()
    observeThemeChanges()
}

private func observeThemeChanges() {
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(themeDidChange),
        name: .themeDidChange,
        object: nil
    )
}

@objc private func themeDidChange() {
    applyTheme()
}

deinit {
    NotificationCenter.default.removeObserver(self)
}
```

**Step 3:** Apply same pattern to VideoEditorWindow

**Why Critical:** AppKit windows currently frozen at creation-time theme - won't update when user or system changes appearance.

---

## 🟡 HIGH - Should Fix This Session

### 3. Remove Task Wrapper in Combine Sink

**Time:** 5 minutes  
**File:** ThemeManager.swift:39-42

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

**Why:** Already on MainActor, Task adds unnecessary overhead.

---

### 4. Extract Notification Name to Constant

**Time:** 5 minutes  
**File:** ThemeManager.swift:37

```swift
// Add at top of file
extension Notification.Name {
    static let appleInterfaceThemeChanged = Notification.Name("AppleInterfaceThemeChangedNotification")
}

// Use in publisher
.publisher(for: .appleInterfaceThemeChanged)
```

**Why:** Type safety, autocomplete, refactoring safety.

---

## 🟢 MEDIUM - Can Defer to Next Session

### 5. Remove Redundant objectWillChange.send()

**Time:** 5 minutes  
**File:** ThemeManager.swift:21-23

**Action:** Remove didSet block (verify no side effects first)

```swift
@AppStorage(PreferencesKeys.appearanceMode)
var preferredAppearance: AppearanceMode = .system
```

**Why:** @AppStorage automatically triggers objectWillChange.

---

### 6. Add Defensive Init for NSApp.effectiveAppearance

**Time:** 10 minutes  
**File:** ThemeManager.swift:33

```swift
private init() {
    // Defensive - NSApp might not be fully initialized
    let appearance = NSApp.effectiveAppearance
    currentSystemIsDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    
    // ... rest of init
}
```

**Why:** Edge case protection if ThemeManager accessed early in lifecycle.

---

## 📝 LOW - Polish Items

### 7. Improve Documentation

**Time:** 10 minutes  
**File:** ThemeManager.swift:66-77

Add usage examples and when to use each property.

---

### 8. Consider @EnvironmentObject Pattern

**Time:** 15 minutes  
**File:** PreferencesView.swift

Refactor to use environment injection instead of direct shared instance access.

---

## Testing Checklist

After fixing H1 and H2, verify:

- [ ] Build succeeds with no errors/warnings
- [ ] MenuBarExtra updates when switching to Auto mode
- [ ] Onboarding window updates when switching to Auto mode
- [ ] Preferences TabView updates immediately (already works)
- [ ] AnnotateWindow updates when system appearance changes
- [ ] VideoEditorWindow updates when system appearance changes
- [ ] No memory leaks (Instruments Leaks tool)
- [ ] Theme persists across app restarts

---

## Timeline

**Immediate (Critical):** 40 minutes  
**High Priority:** 10 minutes  
**Medium Priority:** 15 minutes  
**Low Priority:** 25 minutes  

**Total:** ~90 minutes for all items  
**Minimum for completion:** 40 minutes (Critical only)

---

## Next Steps

1. Fix Critical items (1 & 2)
2. Test thoroughly
3. Fix High priority items (3 & 4)
4. Build and test again
5. Update plan.md to mark phases complete
6. Generate final report
7. Consider Medium/Low items for follow-up PR

