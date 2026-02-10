# Cloud Feature - Swift Source Code Audit

**Date:** 2026-02-10
**Researcher:** Swift Source Code Analysis
**Scope:** All Cloud-related code in Snapzy macOS app

---

## Summary

**Total Cloud-related files found:** 3
**Actual Cloud functionality:** NONE (UI toggle only, no implementation)
**Risk assessment:** LOW (cosmetic feature removal)

---

## Findings

### 1. QuickAccessManager.swift
**Location:** `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/QuickAccess/QuickAccessManager.swift`

**Lines 59-63:** `showCloudUpload` property
```swift
@Published var showCloudUpload: Bool = true {
  didSet {
    UserDefaults.standard.set(showCloudUpload, forKey: Keys.showCloudUpload)
  }
}
```

**Line 83:** UserDefaults key definition
```swift
static let showCloudUpload = "floatingScreenshot.showCloudUpload"
```

**Lines 109-110:** Settings loader
```swift
showCloudUpload =
  UserDefaults.standard.object(forKey: Keys.showCloudUpload) as? Bool ?? true
```

**Purpose:** Stores user preference for showing/hiding cloud upload button
**Dependencies:** None - standalone boolean flag
**Usage:** Read by UI components, never used for actual cloud operations

---

### 2. QuickAccessSettingsView.swift
**Location:** `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Preferences/Tabs/QuickAccessSettingsView.swift`

**Lines 86-89:** UI toggle in preferences
```swift
SettingRow(icon: "cloud.fill", title: "Cloud Upload", description: "Show upload button on overlay") {
  Toggle("", isOn: $manager.showCloudUpload)
    .labelsHidden()
}
```

**Purpose:** Preference toggle to enable/disable cloud upload button visibility
**Dependencies:** Binds to `QuickAccessManager.shared.showCloudUpload`
**UI Section:** "Behaviors" section of Quick Access settings tab

---

### 3. PreferencesKeys.swift
**Location:** `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Preferences/PreferencesKeys.swift`

**Line 37:** Key definition (appears unused)
```swift
static let floatingShowCloudUpload = "floatingScreenshot.showCloudUpload"
```

**Purpose:** Duplicate/unused key constant
**Dependencies:** None - QuickAccessManager uses its own private Keys enum
**Note:** This constant is REDUNDANT - QuickAccessManager defines its own key

---

## No Cloud Implementation Found

**Critical Finding:** Despite the UI toggle, NO actual cloud functionality exists:

❌ No CloudKit imports or usage
❌ No iCloud/NSUbiquitousKeyValueStore references
❌ No CKContainer, CKDatabase, CKRecord usage
❌ No cloud upload/download logic
❌ No sync mechanisms
❌ No network requests to cloud services
❌ No cloud provider integrations

**Searched patterns:** cloud, CloudKit, iCloud, sync, remote storage, upload, download
**Files scanned:** 100+ Swift files across entire codebase

---

## Dependencies Analysis

### QuickAccessCardView.swift Investigation
**Location:** `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/QuickAccess/QuickAccessCardView.swift`

**Result:** NO references to `showCloudUpload` property
**Actions available:** Copy, Save, Delete, Edit - no cloud upload button exists in UI

### Other QuickAccess Components
- `QuickAccessStackView.swift` - No cloud references
- `QuickAccessPanel.swift` - No cloud references
- All other QuickAccess components - No cloud button implementation

---

## Removal Impact Assessment

### Files to Modify (3 total)

1. **QuickAccessManager.swift**
   - Remove: `showCloudUpload` @Published property (lines 59-63)
   - Remove: `Keys.showCloudUpload` constant (line 83)
   - Remove: Settings loader for `showCloudUpload` (lines 109-110)

2. **QuickAccessSettingsView.swift**
   - Remove: "Cloud Upload" SettingRow (lines 86-89)

3. **PreferencesKeys.swift**
   - Remove: `floatingShowCloudUpload` constant (line 37)

### UserDefaults Cleanup
- Key to purge: `"floatingScreenshot.showCloudUpload"`
- Migration: Optional - setting is cosmetic, no data loss

### Breaking Changes
**NONE** - No functionality loss since no cloud feature exists

---

## Technical Notes

- Property uses standard UserDefaults persistence
- Default value: `true` (would show button if implemented)
- No observers/listeners beyond SwiftUI bindings
- No related protocols, delegates, or managers
- Icon used: SF Symbol `"cloud.fill"`

---

## Conclusion

Cloud feature is **VESTIGIAL** - planned but never implemented. Removal requires only **3 file modifications** with **~10 lines deleted** total. Zero risk of breaking actual functionality.

**Recommendation:** Safe to remove immediately without migration strategy.

---

## Unresolved Questions

None - scope complete.
