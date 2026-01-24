# Advanced Settings - Permissions Section

## Overview
Add a Permissions section to the Advanced Settings tab, replacing the placeholder view with a functional settings panel that displays permission statuses and provides quick access to System Settings.

**Created:** 260124
**Priority:** Medium
**Complexity:** Low-Medium

## Implementation Phases

| Phase | Description | Status | Progress |
|-------|-------------|--------|----------|
| 01 | Create AdvancedSettingsView with Permissions section | Complete | 100% |

## Key Files

### To Create
- `ClaudeShot/Features/Preferences/Tabs/AdvancedSettingsView.swift`

### To Modify
- `ClaudeShot/Features/Preferences/PreferencesView.swift` (line 33-34)

## Permissions to Display

| Permission | API | System Settings URL | Required |
|------------|-----|---------------------|----------|
| Screen Recording | `SCShareableContent.current` | `Privacy_ScreenCapture` | Yes |
| Microphone | `AVCaptureDevice.authorizationStatus(for: .audio)` | `Privacy_Microphone` | No |
| Accessibility | `AXIsProcessTrusted()` | `Privacy_Accessibility` | No |

## UI Pattern
Following existing codebase patterns:
- `Form` with `.formStyle(.grouped)`
- `Section("Permissions")` container
- Row layout: Icon | Label | Spacer | Status Badge | Open Settings Button

## Phase Files
- [Phase 01: Create AdvancedSettingsView](./phase-01-create-advanced-settings-view.md)

## Success Criteria
- [x] Permissions section displays all 3 permissions
- [x] Status badges show correct granted/denied state
- [x] "Open Settings" buttons navigate to correct System Preferences panes
- [x] Refresh button updates permission states
- [x] UI follows existing Preferences tab patterns
