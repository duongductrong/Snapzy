# Phase 4: Testing and Validation

## Overview
Comprehensive testing to ensure unified title bar implementation works correctly across all scenarios.

## Visual Testing

### Annotate Window
- [ ] Traffic lights visible in light mode
- [ ] Traffic lights visible in dark mode
- [ ] Traffic lights visible in system mode
- [ ] Background extends seamlessly to top edge
- [ ] No gaps or visual artifacts at window top
- [ ] Toolbar properly spaced from traffic lights (78px leading space)
- [ ] Sidebar toggle doesn't affect traffic light area
- [ ] Window resize maintains proper layout
- [ ] All toolbar buttons remain visible and accessible

### VideoEditor Window
- [ ] Traffic lights visible in light mode
- [ ] Traffic lights visible in dark mode
- [ ] Traffic lights visible in system mode
- [ ] Background extends seamlessly to top edge
- [ ] No gaps or visual artifacts at window top
- [ ] Title bar spacer (28px) properly positions content
- [ ] Video player not obscured by traffic lights
- [ ] Window resize maintains proper layout

## Functional Testing

### Window Interactions
- [ ] Close button works (Annotate)
- [ ] Close button works (VideoEditor)
- [ ] Minimize button works (both windows)
- [ ] Maximize/Zoom button works (both windows)
- [ ] Window drag by title bar area works
- [ ] Window drag by traffic light area works
- [ ] Double-click title bar area toggles maximize

### Content Interactions (Annotate)
- [ ] All toolbar buttons clickable
- [ ] Sidebar toggle functional
- [ ] Crop tool activation works
- [ ] Annotation tools selectable
- [ ] Undo/Redo buttons work
- [ ] Stroke size slider adjustable
- [ ] Save/Done buttons clickable
- [ ] Canvas interaction not affected

### Content Interactions (VideoEditor)
- [ ] Video player controls accessible
- [ ] Timeline scrubbing works
- [ ] Trim handles functional
- [ ] Playback controls work
- [ ] Info panel displays correctly
- [ ] Save/Cancel buttons clickable

## Theme Testing

### Theme Switching
- [ ] Light → Dark transition smooth (Annotate)
- [ ] Dark → Light transition smooth (Annotate)
- [ ] System mode follows macOS appearance (Annotate)
- [ ] Light → Dark transition smooth (VideoEditor)
- [ ] Dark → Light transition smooth (VideoEditor)
- [ ] System mode follows macOS appearance (VideoEditor)
- [ ] Traffic lights remain visible during theme switch
- [ ] No flicker during theme transitions

### Background Colors
- [ ] Annotate light mode: white 0.95 extends to top
- [ ] Annotate dark mode: white 0.12 extends to top
- [ ] VideoEditor light mode: white 0.95 extends to top
- [ ] VideoEditor dark mode: white 0.12 extends to top
- [ ] System mode uses correct semantic colors

## Edge Case Testing

### Display Configurations
- [ ] Works on built-in Retina display
- [ ] Works on external display (standard DPI)
- [ ] Works on external display (HiDPI/Retina)
- [ ] Works when moved between displays
- [ ] Scaling handled correctly on all displays

### Accessibility
- [ ] Works with "Reduce transparency" enabled
- [ ] Works with "Increase contrast" enabled
- [ ] Works with larger text sizes
- [ ] Traffic lights remain visible with accessibility settings

### Window States
- [ ] Works on fullscreen entry/exit
- [ ] Works after app restart
- [ ] Works with multiple windows open
- [ ] Works when window moved to different Space

## Performance Testing

- [ ] No performance degradation in Annotate
- [ ] No performance degradation in VideoEditor
- [ ] Window resize smooth and responsive
- [ ] Theme switching instant
- [ ] No memory leaks

## Regression Testing

- [ ] All existing Annotate features work
- [ ] All existing VideoEditor features work
- [ ] Export functionality unaffected
- [ ] File drag-drop still works
- [ ] Keyboard shortcuts functional
- [ ] Window lifecycle unchanged

## Known Issues / Limitations

Document any discovered issues:
- Issue 1: [Description]
- Issue 2: [Description]

## Success Criteria

All checkboxes must pass:
- ✅ Background extends seamlessly to window top edge
- ✅ Traffic lights visible and functional in all themes
- ✅ No content overlap with system buttons
- ✅ All existing functionality preserved
- ✅ No visual artifacts or rendering issues
- ✅ Performance remains optimal

## Rollback Trigger

If any critical issue found:
1. Remove `.fullSizeContentView` from both window classes
2. Remove `.ignoresSafeArea` from both main views
3. Remove safe area padding/spacers
4. Test rollback restores original behavior
