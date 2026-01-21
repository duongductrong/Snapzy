# Phase 04: Polish and Accessibility

## Context Links
- [Main Plan](./plan.md)
- [Phase 03: Options Menu](./phase-03-options-menu.md)
- All components from Phases 01-03

## Overview
Final polish pass: subtle animations, comprehensive accessibility labels, visual refinements, and testing checklist to ensure production-ready quality.

## Key Insights
- Apple uses subtle spring animations for hover states
- All interactive elements need VoiceOver labels
- Keyboard navigation should work (Tab, Enter, Escape)
- Visual consistency check across light/dark modes

## Requirements
1. Add smooth hover/press animations
2. Comprehensive accessibility labels for VoiceOver
3. Keyboard shortcut hints where applicable
4. Light/dark mode testing
5. Final visual polish and consistency

## Architecture
No new files. Enhancements to existing components from Phases 01-03.

## Related Code Files
| File | Purpose |
|------|---------|
| `ToolbarIconButton.swift` | Add animation, accessibility |
| `ToolbarOptionsMenu.swift` | Add accessibility |
| `RecordingToolbarStyles.swift` | Animation constants |
| `RecordingToolbarView.swift` | Overall accessibility |

## Implementation Steps

### Step 1: Add animation constants
```swift
// In RecordingToolbarStyles.swift
extension ToolbarConstants {
    static let hoverAnimation: Animation = .easeInOut(duration: 0.15)
    static let pressAnimation: Animation = .easeInOut(duration: 0.1)
}
```

### Step 2: Enhance ToolbarIconButton with animation
```swift
struct ToolbarIconButton: View {
    // ... existing properties

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: ToolbarConstants.iconSize, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: ToolbarConstants.iconButtonSize,
                       height: ToolbarConstants.iconButtonSize)
                .background(
                    RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius)
                        .fill(Color.primary.opacity(isHovered ? 0.1 : 0))
                )
                .animation(ToolbarConstants.hoverAnimation, value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double-tap to activate")
    }
}
```

### Step 3: Add accessibility to RecordingToolbarView
```swift
var body: some View {
    HStack(spacing: ToolbarConstants.itemSpacing) {
        // ... existing layout
    }
    // ... existing modifiers
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Recording toolbar")
}
```

### Step 4: Enhance Record button accessibility
```swift
Button(action: onRecord) {
    Label("Record", systemImage: "record.circle.fill")
}
.buttonStyle(RecordButtonStyle())
.accessibilityLabel("Start recording")
.accessibilityHint("Begins screen recording with current settings")
```

### Step 5: Add keyboard shortcuts (optional enhancement)
```swift
// In RecordingToolbarView
.onKeyPress(.escape) {
    onCancel()
    return .handled
}
.onKeyPress(.return) {
    onRecord()
    return .handled
}
```

### Step 6: Options menu accessibility
```swift
// In ToolbarOptionsMenu
Menu { ... } label: { menuLabel }
    .accessibilityLabel("Recording options")
    .accessibilityHint("Opens menu to change format, quality, and audio settings")
```

## Todo List
- [ ] Add animation constants to ToolbarConstants
- [ ] Add hover animation to ToolbarIconButton
- [ ] Add press animation to RecordButtonStyle
- [ ] Add accessibilityLabel to close button
- [ ] Add accessibilityLabel to record button
- [ ] Add accessibilityLabel to options menu
- [ ] Add accessibilityHint where helpful
- [ ] Test VoiceOver navigation
- [ ] Test keyboard navigation (Tab, Enter, Escape)
- [ ] Test light mode appearance
- [ ] Test dark mode appearance
- [ ] Verify toolbar positioning in floating window
- [ ] Final visual review against Apple reference

## Success Criteria
1. Hover states animate smoothly (0.15s ease)
2. All buttons have VoiceOver labels
3. VoiceOver can navigate entire toolbar
4. Escape key triggers cancel
5. Enter/Return key triggers record
6. Consistent appearance in light/dark modes
7. No visual regressions from current implementation

## Testing Checklist
```
[ ] Open toolbar via screen recording flow
[ ] Hover over X button - see background appear
[ ] Click X button - onCancel fires
[ ] Hover over Options - see background change
[ ] Click Options - menu opens
[ ] Select different format - checkmark moves
[ ] Select different quality - checkmark moves
[ ] Toggle audio - state changes
[ ] Hover over Record - opacity change on press
[ ] Click Record - onRecord fires
[ ] Enable VoiceOver - navigate all elements
[ ] Press Escape - toolbar cancels
[ ] Press Enter - recording starts
[ ] Test in light mode
[ ] Test in dark mode
```

## Risk Assessment
| Risk | Impact | Mitigation |
|------|--------|------------|
| Animation jank | Low | Use simple easeInOut |
| VoiceOver not reading | Medium | Test with actual VoiceOver |
| Keyboard events not captured | Low | Ensure window is key window |

## Security Considerations
- No security concerns for polish phase
- Accessibility improvements only

## Final Deliverables Summary

### New Files Created
```
ZapShot/Features/Recording/
├── Components/
│   ├── ToolbarIconButton.swift (~40 LOC)
│   └── ToolbarOptionsMenu.swift (~70 LOC)
└── Styles/
    └── RecordingToolbarStyles.swift (~50 LOC)
```

### Modified Files
```
ZapShot/Features/Recording/RecordingToolbarView.swift (revamped)
ZapShot/Features/Recording/RecordingToolbarWindow.swift (new bindings)
ZapShot/Core/ScreenRecordingManager.swift (displayName on VideoQuality)
```

## Next Steps
After completing Phase 04:
1. Run full test checklist
2. Code review via code-reviewer agent
3. Update plan.md status to "Completed"
4. Commit with message: "feat(recording): revamp toolbar UI to match Apple aesthetic"
