# Phase 01: Info.plist Agent Configuration

## Context Links

- [Plan Overview](./plan.md)
- [Phase 02: MenuBarExtra Implementation](./phase-02-menubar-extra-implementation.md)
- [Phase 03: Window Management](./phase-03-window-management.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-16 |
| Description | Configure ZapShot as an agent (LSUIElement) application |
| Priority | High |
| Implementation Status | Pending |
| Review Status | Not Started |

## Key Insights

- `LSUIElement` (Application is agent) = YES hides app from Dock and Cmd+Tab
- Agent apps can still display windows when needed
- Configuration done via Xcode project settings or direct plist editing
- No code changes required for this phase

## Requirements

1. Add `Application is agent (UIElement)` key to Info.plist
2. Set value to `YES` (boolean true)
3. Verify app no longer appears in Dock after build

## Architecture

```
Info.plist Configuration:
┌─────────────────────────────────────────┐
│ Key: LSUIElement                        │
│ Type: Boolean                           │
│ Value: YES                              │
└─────────────────────────────────────────┘

Result:
- No Dock icon
- No Cmd+Tab entry
- Menu bar presence only (after Phase 02)
- Windows still functional
```

## Related Code Files

| File | Purpose |
|------|---------|
| `ZapShot.xcodeproj/project.pbxproj` | Xcode project configuration |
| Info.plist (embedded) | App configuration (managed by Xcode) |

## Implementation Steps

### Step 1: Open Xcode Project Settings

1. Open `ZapShot.xcodeproj` in Xcode
2. Select ZapShot target in the project navigator
3. Go to "Info" tab

### Step 2: Add LSUIElement Key

1. Click "+" button to add new key
2. Select "Application is agent (UIElement)" from dropdown
   - Or manually type `LSUIElement`
3. Set type to `Boolean`
4. Set value to `YES`

### Step 3: Alternative - Direct Plist Edit

If using raw plist, add:

```xml
<key>LSUIElement</key>
<true/>
```

### Step 4: Build and Verify

1. Clean build folder (Cmd+Shift+K)
2. Build project (Cmd+B)
3. Run app and verify:
   - No icon in Dock
   - No entry in Cmd+Tab switcher
   - App process visible in Activity Monitor

## Todo List

- [ ] Open Xcode project settings
- [ ] Navigate to Info tab for ZapShot target
- [ ] Add LSUIElement key with value YES
- [ ] Clean and rebuild project
- [ ] Verify Dock icon is hidden
- [ ] Test app still launches correctly

## Success Criteria

1. **No Dock Icon**: App does not appear in macOS Dock
2. **No Cmd+Tab**: App not visible in application switcher
3. **Process Running**: App process visible in Activity Monitor
4. **Build Success**: Project compiles without errors
5. **Windows Work**: Existing windows can still be displayed programmatically

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Xcode caching old plist | Low | Low | Clean build folder |
| Key not recognized | Very Low | Medium | Use exact key name `LSUIElement` |

## Security Considerations

- No security implications for this configuration change
- App permissions remain unchanged
- Screen Recording permission still required

## Next Steps

After completing this phase:
1. Proceed to [Phase 02: MenuBarExtra Implementation](./phase-02-menubar-extra-implementation.md)
2. Implement MenuBarExtra scene in ZapShotApp.swift
3. App will then have menu bar presence instead of window
