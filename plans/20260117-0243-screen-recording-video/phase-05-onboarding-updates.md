# Phase 5: Onboarding Updates

## Context Links
- [Main Plan](./plan.md)
- [Codebase Analysis](./scout/scout-01-codebase-analysis.md)

## Overview
Update onboarding flow to mention screen recording feature and the Cmd+Shift+5 shortcut.

## Requirements
- R1: Mention recording in WelcomeView or add feature highlight
- R2: Add Cmd+Shift+5 to ShortcutsView alongside existing shortcuts
- R3: Keep changes minimal to preserve existing flow

## Related Code Files

### Modify
| File | Changes |
|------|---------|
| `ZapShot/Features/Onboarding/Views/WelcomeView.swift` | Add recording mention |
| `ZapShot/Features/Onboarding/Views/ShortcutsView.swift` | Add recording shortcut |

## Implementation Steps

### Step 1: Read existing onboarding views
Need to check current WelcomeView and ShortcutsView content.

### Step 2: Update WelcomeView
Add recording to feature list if present, or update subtitle:

```swift
// Update subtitle or feature list to include:
Text("Capture screenshots and record screen videos with ease.")
```

### Step 3: Update ShortcutsView
Add recording shortcut to the list of shortcuts displayed:

```swift
// Add to shortcuts list:
ShortcutRow(
    shortcut: "⌘⇧5",
    action: "Record Screen",
    description: "Start screen recording"
)
```

### Step 4: Ensure shortcuts step mentions all three
Update any copy that lists shortcuts to include:
- ⌘⇧3 - Capture Fullscreen
- ⌘⇧4 - Capture Area
- ⌘⇧5 - Record Screen

## Todo List
- [ ] Read WelcomeView.swift current content
- [ ] Read ShortcutsView.swift current content
- [ ] Update WelcomeView to mention recording
- [ ] Update ShortcutsView to show ⌘⇧5
- [ ] Test onboarding flow still works

## Success Criteria
1. WelcomeView mentions recording capability
2. ShortcutsView shows all three shortcuts including ⌘⇧5
3. Onboarding flow completes without errors
4. No visual regressions

## Risk Assessment
| Risk | Impact | Mitigation |
|------|--------|------------|
| Layout breaking with new content | Low | Keep additions minimal |
| Missing localization | Low | Use same pattern as existing text |
