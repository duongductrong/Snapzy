# Phase 01: Create AdvancedSettingsView with Permissions Section

## Context
- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** None
- **Docs:** Existing Preferences tab patterns in `ClaudeShot/Features/Preferences/Tabs/`

## Overview
- **Date:** 260124
- **Description:** Create AdvancedSettingsView replacing placeholder, add Permissions section with status indicators and System Settings links
- **Priority:** Medium
- **Implementation Status:** Pending
- **Review Status:** Pending

## Key Insights
1. Existing tabs use `Form` + `.formStyle(.grouped)` + `Section` pattern
2. Permission check patterns already exist in `ScreenCaptureManager.swift` and `RecordingSettingsView.swift`
3. System Settings URL pattern: `x-apple.systempreferences:com.apple.preference.security?Privacy_XXX`
4. macOS reference image shows: Icon | Label | Spacer | Toggle/Status - adapt for permission display

## Requirements
1. Create `AdvancedSettingsView.swift` with Permissions section
2. Display 3 permissions: Screen Recording, Microphone, Accessibility
3. Each row: SF Symbol icon, permission name, status badge, "Open Settings" button
4. Status badge: green checkmark (granted), orange/red X (denied)
5. Refresh button to recheck permissions after user grants in System Settings
6. Replace placeholder in `PreferencesView.swift`

## Architecture

```
AdvancedSettingsView
├── Form (.formStyle(.grouped))
│   └── Section("Permissions")
│       ├── PermissionRowView (Screen Recording)
│       ├── PermissionRowView (Microphone)
│       ├── PermissionRowView (Accessibility)
│       └── Refresh Permissions Button
```

### PermissionRowView Layout
```
┌─────────────────────────────────────────────────────────────┐
│ 🎥  Screen Recording    [●Granted]    [Open Settings]       │
└─────────────────────────────────────────────────────────────┘
```

## Related Code Files
- `ClaudeShot/Features/Preferences/Tabs/GeneralSettingsView.swift` - UI pattern reference
- `ClaudeShot/Features/Preferences/Tabs/RecordingSettingsView.swift` - Microphone permission handling
- `ClaudeShot/Core/ScreenCaptureManager.swift` - Screen recording permission check
- `ClaudeShot/Features/Preferences/PreferencesView.swift` - Tab registration

## Implementation Steps

### Step 1: Create AdvancedSettingsView.swift
Location: `ClaudeShot/Features/Preferences/Tabs/AdvancedSettingsView.swift`

```swift
// Structure outline:
import SwiftUI
import AVFoundation
import ScreenCaptureKit

struct AdvancedSettingsView: View {
  @State private var screenRecordingGranted = false
  @State private var microphoneGranted = false
  @State private var accessibilityGranted = false

  var body: some View {
    Form {
      Section("Permissions") {
        // Permission rows
        // Refresh button
      }
    }
    .formStyle(.grouped)
    .onAppear { checkAllPermissions() }
  }
}
```

### Step 2: Implement Permission Checking Functions

```swift
// Screen Recording
private func checkScreenRecordingPermission() async {
  do {
    _ = try await SCShareableContent.current
    screenRecordingGranted = true
  } catch {
    screenRecordingGranted = false
  }
}

// Microphone
private func checkMicrophonePermission() {
  let status = AVCaptureDevice.authorizationStatus(for: .audio)
  microphoneGranted = (status == .authorized)
}

// Accessibility
private func checkAccessibilityPermission() {
  accessibilityGranted = AXIsProcessTrusted()
}
```

### Step 3: Create Permission Row Component

```swift
private func permissionRow(
  icon: String,
  name: String,
  isGranted: Bool,
  settingsURL: String
) -> some View {
  HStack {
    Image(systemName: icon)
      .foregroundColor(.secondary)
      .frame(width: 24)
    Text(name)
    Spacer()
    // Status badge
    HStack(spacing: 4) {
      Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
        .foregroundColor(isGranted ? .green : .orange)
      Text(isGranted ? "Granted" : "Not Granted")
        .font(.caption)
        .foregroundColor(.secondary)
    }
    Button("Open Settings") {
      if let url = URL(string: settingsURL) {
        NSWorkspace.shared.open(url)
      }
    }
    .buttonStyle(.bordered)
  }
}
```

### Step 4: System Settings URLs

```swift
private let screenRecordingURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
private let microphoneURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
private let accessibilityURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
```

### Step 5: Update PreferencesView.swift
Change line 33-34 from:
```swift
PlaceholderSettingsView.advanced
  .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
```
To:
```swift
AdvancedSettingsView()
  .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
```

## Todo List
- [ ] Create `AdvancedSettingsView.swift` file
- [ ] Implement permission state variables
- [ ] Implement `checkAllPermissions()` function
- [ ] Create `permissionRow` helper view
- [ ] Add Screen Recording row
- [ ] Add Microphone row
- [ ] Add Accessibility row
- [ ] Add Refresh button with recheck logic
- [ ] Update `PreferencesView.swift` to use new view
- [ ] Test permission status display
- [ ] Test System Settings navigation

## Success Criteria
- [ ] All 3 permissions display with correct icons
- [ ] Status badges accurately reflect current permission state
- [ ] "Open Settings" buttons open correct System Preferences panes
- [ ] Refresh button updates all permission states
- [ ] UI consistent with other Preferences tabs
- [ ] No build errors or warnings

## Risk Assessment
| Risk | Impact | Mitigation |
|------|--------|------------|
| Accessibility API requires import | Low | Import `ApplicationServices` for `AXIsProcessTrusted()` |
| Permission check async timing | Low | Use `Task` for async checks, update on main thread |

## Security Considerations
- No sensitive data handling
- Only reads permission status, no modification
- System Settings links use documented Apple URL schemes

## Next Steps
After implementation:
1. Build and test in Xcode
2. Verify all permission checks work correctly
3. Test System Settings navigation on macOS 14+
4. Consider adding more Advanced settings sections in future
