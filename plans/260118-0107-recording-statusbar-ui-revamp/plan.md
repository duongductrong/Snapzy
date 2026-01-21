# Recording Status Bar UI Revamp Plan

**Created:** 260118 | **Status:** Completed | **Progress:** 100%

## Objective
Revamp `RecordingStatusBarView` to be visually consistent with the already-revamped `RecordingToolbarView`, using shared constants, button styles, and Apple-native aesthetic.

## Current vs Target State

| Aspect | Current (StatusBar) | Target (match Toolbar) |
|--------|---------------------|------------------------|
| Spacing | 16pt | 12pt (ToolbarConstants.itemSpacing) |
| Padding | 20h/12v | 16h/12v (ToolbarConstants) |
| Corner radius | 10px | 14px (ToolbarConstants.toolbarCornerRadius) |
| Divider | Raw Divider | RecordingToolbarDivider |
| Pause button | `.bordered` style | ToolbarIconButton |
| Stop button | `.bordered` with red icon | Red ToolbarIconButton or StopButtonStyle |
| Shadow | radius 6, y: 3 | radius 8, y: 4 (match toolbar) |
| Accessibility | None | Add labels |

## Architecture

```
RecordingStatusBarView (revamped)
├── HStack(spacing: ToolbarConstants.itemSpacing)
│   ├── Recording indicator (pulsing red dot)
│   ├── Timer display (monospaced)
│   ├── RecordingToolbarDivider
│   ├── ToolbarIconButton (pause/play)
│   ├── RecordingToolbarDivider
│   └── StopButton (red styled)
├── .padding (ToolbarConstants)
├── .background(.ultraThinMaterial)
└── .clipShape(RoundedRectangle(14))
```

## Files to Modify
- `ZapShot/Features/Recording/RecordingStatusBarView.swift` - Main revamp

## Files to Reuse (no changes)
- `ZapShot/Features/Recording/Styles/RecordingToolbarStyles.swift` - ToolbarConstants, RecordingToolbarDivider
- `ZapShot/Features/Recording/Components/ToolbarIconButton.swift` - For pause/play button

## New Components (optional)
- `StopButtonStyle` in RecordingToolbarStyles.swift - Red variant of button style

## Implementation Steps

### Step 1: Update imports and spacing
- Use ToolbarConstants.itemSpacing instead of 16
- Use ToolbarConstants padding values

### Step 2: Replace Pause/Resume button
- Replace `.bordered` button with ToolbarIconButton
- Use "pause.fill" / "play.fill" icons

### Step 3: Style Stop button
- Create red-styled stop button matching Apple aesthetic
- Either ToolbarIconButton with red tint or new StopButtonStyle

### Step 4: Update container styling
- Corner radius to 14px
- Shadow to radius 8, y: 4
- Use RecordingToolbarDivider

### Step 5: Add accessibility
- Add accessibilityLabel to all controls
- Add accessibilityElement to container

## Success Criteria
1. StatusBar visually matches Toolbar aesthetic
2. Uses shared ToolbarConstants for consistency
3. Hover states on interactive buttons
4. VoiceOver accessibility labels
5. Recording indicator animation preserved
6. All existing functionality works (pause, resume, stop)

## Risk Assessment
| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking pause/resume | Medium | Test toggle behavior |
| Animation changes | Low | Preserve existing animation code |

## Estimated LOC
~40 lines changed in RecordingStatusBarView.swift
~10 lines added for StopButtonStyle (optional)
