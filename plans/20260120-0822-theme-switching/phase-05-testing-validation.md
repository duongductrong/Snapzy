# Phase 5: Testing & Validation

## Context

- [Plan Overview](./plan.md)
- [Phase 4: Settings UI](./phase-04-settings-ui.md)

## Overview

Comprehensive testing checklist for theme switching feature. Covers all UI components, persistence, and edge cases.

## Key Insights

1. Test all three modes: System, Light, Dark
2. Change system appearance to verify "System" mode follows it
3. Test all window types
4. Verify persistence across app restarts

## Requirements

- [x] All SwiftUI views respect theme
- [x] All NSWindow subclasses respect theme
- [x] Theme persists across app restarts
- [x] No visual regressions in either theme

## Testing Checklist

### Build Verification

- [ ] Project compiles without errors
- [ ] Project compiles without warnings (or only pre-existing warnings)
- [ ] App launches successfully

### Settings UI

- [ ] Open Preferences > General
- [ ] Appearance section visible
- [ ] Picker shows System, Light, Dark options
- [ ] Selecting each option changes picker state

### SwiftUI Scenes - Light Mode

- [ ] Set theme to "Light"
- [ ] MenuBarExtra menu appears in light mode
- [ ] Open Preferences - window appears in light mode
- [ ] Open Onboarding (via Restart Onboarding) - appears in light mode
- [ ] All text is readable
- [ ] All icons are visible

### SwiftUI Scenes - Dark Mode

- [ ] Set theme to "Dark"
- [ ] MenuBarExtra menu appears in dark mode
- [ ] Open Preferences - window appears in dark mode
- [ ] Open Onboarding - appears in dark mode
- [ ] All text is readable
- [ ] All icons are visible

### SwiftUI Scenes - System Mode

- [ ] Set theme to "System"
- [ ] Set macOS to Light Mode (System Preferences > Appearance)
- [ ] All SwiftUI scenes follow system (light)
- [ ] Set macOS to Dark Mode
- [ ] All SwiftUI scenes follow system (dark)

### AnnotateWindow

- [ ] Set theme to "Light"
- [ ] Capture screenshot and open annotation
- [ ] Window background is light
- [ ] Toolbar/tools are readable
- [ ] All annotation tools work correctly

- [ ] Set theme to "Dark"
- [ ] Open annotation window
- [ ] Window background is dark
- [ ] Toolbar/tools are readable

### VideoEditorWindow

- [ ] Set theme to "Light"
- [ ] Record video and open editor
- [ ] Window background is light
- [ ] Controls are readable

- [ ] Set theme to "Dark"
- [ ] Open video editor
- [ ] Window background is dark
- [ ] Controls are readable

### RecordingToolbarWindow

- [ ] Set theme to "Light"
- [ ] Start recording flow
- [ ] Pre-record toolbar appears correctly
- [ ] Recording status bar appears correctly

- [ ] Set theme to "Dark"
- [ ] Recording toolbar correct appearance

### AreaSelectionWindow

- [ ] Verify area selection still works in light mode
- [ ] Verify area selection still works in dark mode
- [ ] Crosshair visible in both modes
- [ ] Size indicator readable in both modes

### Persistence

- [ ] Set theme to "Light"
- [ ] Quit app completely (Cmd+Q)
- [ ] Relaunch app
- [ ] Theme is still "Light"

- [ ] Set theme to "Dark"
- [ ] Quit and relaunch
- [ ] Theme is still "Dark"

- [ ] Set theme to "System"
- [ ] Quit and relaunch
- [ ] Theme follows system preference

### Edge Cases

- [ ] Change theme while annotation window is open
- [ ] Change theme while preferences is open
- [ ] Rapidly toggle between themes
- [ ] Change system appearance while app running (System mode)

### Visual Regression Check

Light Mode:
- [ ] No black-on-black text
- [ ] No invisible icons
- [ ] Sufficient contrast on all elements
- [ ] Buttons have proper states (hover, pressed)

Dark Mode:
- [ ] No white-on-white text
- [ ] No invisible icons
- [ ] Sufficient contrast on all elements
- [ ] Buttons have proper states

### Performance

- [ ] No noticeable lag when changing theme
- [ ] No memory leaks (check Xcode Instruments if concerned)
- [ ] App responsiveness unchanged

## Test Commands

```bash
# Build project
cd /Users/duongductrong/Developer/ZapShot
xcodebuild -project ZapShot.xcodeproj -scheme ZapShot build

# Run app
open ZapShot.xcodeproj
# Press Cmd+R to run
```

## Known Limitations

1. Open windows may not update theme until reopened (acceptable)
2. Some hardcoded colors in annotation tools may not change (acceptable)
3. AreaSelectionWindow intentionally stays neutral

## Success Criteria

1. All checklist items pass
2. No crashes or errors
3. All three theme modes work correctly
4. Theme persists across restarts
5. No significant visual regressions

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Missed hardcoded colors | Medium | Low | Visual testing covers this |
| Annotation tools contrast | Medium | Medium | May need follow-up fixes |
| Performance degradation | Low | Medium | Performance testing |

## Security Considerations

- Testing phase has no security implications

## Completion

After all tests pass:
1. Update [plan.md](./plan.md) status to COMPLETE
2. Create commit with conventional message
3. Document any known issues or follow-up work

## Follow-up Work (if needed)

- [ ] Update hardcoded colors in annotation renderer
- [ ] Add theme-aware asset colors in Assets.xcassets
- [ ] Consider adding accent color customization
