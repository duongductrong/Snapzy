# Phase 03: User-Facing String Updates

**Parent Plan:** [plan.md](./plan.md)
**Dependencies:** [Phase 01](./phase-01-directory-renames.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 260122 |
| Priority | High |
| Status | Pending |
| Estimated Effort | 15 minutes |

## Description

Update user-visible text strings that display "ZapShot" to show "ClaudeShot" instead. These appear in welcome screens, permission dialogs, and about views.

## Key Insights

- 5 files contain user-facing ZapShot strings
- 8 specific string instances need updating
- Some are simple replacements, some need context review
- GitHub URL decision needed (keep or update?)

## Requirements

1. Update all user-visible "ZapShot" strings to "ClaudeShot"
2. Maintain consistent casing (ClaudeShot vs Claude Shot)
3. Update any ZapShot URLs if repository is renamed

## Related Files

| File | Path | Changes |
|------|------|---------|
| ContentView.swift | `ClaudeShot/ContentView.swift` | Line 17 |
| WelcomeView.swift | `ClaudeShot/Features/Onboarding/Views/WelcomeView.swift` | Line 28 |
| PermissionsView.swift | `ClaudeShot/Features/Onboarding/Views/PermissionsView.swift` | Line 30 |
| ShortcutsView.swift | `ClaudeShot/Features/Onboarding/Views/ShortcutsView.swift` | Line 33 |
| AboutSettingsView.swift | `ClaudeShot/Features/Preferences/Views/AboutSettingsView.swift` | Lines 38, 58 |

## Implementation Steps

### Step 1: ContentView.swift
```swift
// Line 17: Change
Text("ZapShot")
// To
Text("ClaudeShot")
```

### Step 2: WelcomeView.swift
```swift
// Line 28: Change
"Welcome to ZapShot"
// To
"Welcome to ClaudeShot"
```

### Step 3: PermissionsView.swift
```swift
// Line 30: Change
"ZapShot needs access..."
// To
"ClaudeShot needs access..."
```

### Step 4: ShortcutsView.swift
```swift
// Line 33: Change
"...to ZapShot?"
// To
"...to ClaudeShot?"
```

### Step 5: AboutSettingsView.swift
```swift
// Line 38: Change app name display
"ZapShot" → "ClaudeShot"

// Line 58: Update GitHub URL (if repo renamed)
"https://github.com/duongductrong/ZapShot"
// To (if applicable)
"https://github.com/duongductrong/ClaudeShot"
```

### Step 6: Verify all changes
```bash
cd /Users/duongductrong/Developer/ZapShot
grep -r "ZapShot" ClaudeShot --include="*.swift" | grep -v "^ClaudeShot.*:.*//.*ZapShot"
```

## Todo List

- [ ] Update ContentView.swift
- [ ] Update WelcomeView.swift
- [ ] Update PermissionsView.swift
- [ ] Update ShortcutsView.swift
- [ ] Update AboutSettingsView.swift (app name)
- [ ] Decide on GitHub URL update
- [ ] Verify no user-visible ZapShot strings remain

## Success Criteria

1. Welcome screen shows "Welcome to ClaudeShot"
2. Permission dialogs reference "ClaudeShot"
3. About view shows "ClaudeShot" as app name
4. No user-visible "ZapShot" text in app

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Missed string | Low | Medium | Search after changes |
| Broken URL | Medium | Low | Verify URL works |
| Inconsistent casing | Low | Low | Use "ClaudeShot" consistently |

## Unresolved Questions

1. Will GitHub repository be renamed from `ZapShot` to `ClaudeShot`?
   - If yes: Update URL in AboutSettingsView
   - If no: Keep existing URL

## Rollback Plan

```bash
git checkout -- ClaudeShot/ContentView.swift
git checkout -- ClaudeShot/Features/Onboarding/Views/
git checkout -- ClaudeShot/Features/Preferences/Views/AboutSettingsView.swift
```
