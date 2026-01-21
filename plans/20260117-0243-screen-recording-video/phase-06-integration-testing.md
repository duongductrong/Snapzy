# Phase 6: Integration Testing

## Context Links
- [Main Plan](./plan.md)
- [Phase 1: Core Recording Engine](./phase-01-core-recording-engine.md)
- [Phase 2: Keyboard Shortcut Integration](./phase-02-keyboard-shortcut-integration.md)
- [Phase 3: Recording UI Components](./phase-03-recording-ui-components.md)

## Overview
Final integration, end-to-end testing, and polish. Verify all components work together.

## Requirements
- R1: Complete flow works from shortcut to saved video
- R2: Menu bar recording works
- R3: Preferences apply to recording
- R4: Multi-monitor support
- R5: Error handling and edge cases

## Test Scenarios

### Scenario 1: Basic Recording Flow
```
1. Press ⌘⇧5
2. Select area on screen
3. Click Record
4. Wait 5 seconds
5. Click Stop
Expected: Video saved to export location, opened in Finder
```

### Scenario 2: Menu Bar Recording
```
1. Click menu bar icon
2. Click "Record Screen"
3. Select area
4. Record and stop
Expected: Same as Scenario 1
```

### Scenario 3: Pause/Resume
```
1. Start recording
2. Click Pause after 3 seconds
3. Wait 2 seconds
4. Click Resume
5. Wait 3 seconds
6. Stop
Expected: Video is ~6 seconds (not 8), pause gap excluded
```

### Scenario 4: Cancel Recording
```
1. Start area selection
2. Select area
3. Click Cancel (before Record)
Expected: Toolbar closes, no file created

1. Start recording
2. Press Escape or force quit
Expected: Partial file cleaned up
```

### Scenario 5: Format Selection
```
1. Open Preferences > Recording
2. Select MP4 format
3. Start and complete recording
Expected: Output file is .mp4

1. Change to MOV
2. Record again
Expected: Output file is .mov
```

### Scenario 6: Audio Capture
```
1. Enable system audio in preferences
2. Play audio during recording
3. Stop and play video
Expected: Audio present in video

1. Disable system audio
2. Record
Expected: No audio track in video
```

### Scenario 7: Multi-Monitor
```
1. Connect second display
2. Press ⌘⇧5
3. Select area spanning both displays
Expected: Error or constrain to single display

1. Select area on secondary display
2. Record
Expected: Recording captures secondary display correctly
```

### Scenario 8: Permission Denied
```
1. Revoke screen recording permission
2. Try to record
Expected: Permission prompt or error message
```

### Scenario 9: Long Recording
```
1. Record for 10+ minutes
2. Stop
Expected: File saves correctly, no memory issues
```

### Scenario 10: Rapid Actions
```
1. Start recording
2. Quickly pause/resume multiple times
3. Stop
Expected: No crashes, video plays correctly
```

## Integration Checklist

### Keyboard Shortcuts
- [ ] ⌘⇧5 triggers recording
- [ ] Shortcut works when app not focused
- [ ] Shortcut customizable in preferences
- [ ] No conflict with system shortcuts

### Menu Bar
- [ ] "Record Screen" menu item visible
- [ ] Shows ⌘⇧5 hint
- [ ] Disabled when no permission
- [ ] Icon changes during recording (optional)

### Area Selection
- [ ] Works on all connected displays
- [ ] Escape cancels selection
- [ ] Minimum selection size enforced
- [ ] Crosshair visible during selection

### Recording Toolbar
- [ ] Appears below selected area
- [ ] Format picker works
- [ ] Record button starts recording
- [ ] Cancel closes without recording

### Recording Status Bar
- [ ] Timer counts up
- [ ] Pause/Resume toggles correctly
- [ ] Stop saves video
- [ ] Indicator pulses during recording

### Preferences
- [ ] Format setting applies
- [ ] FPS setting applies
- [ ] Quality setting applies
- [ ] Audio toggles work

### Output
- [ ] Video playable in QuickTime
- [ ] Correct resolution (Retina)
- [ ] Audio synced if enabled
- [ ] File opens in Finder after save

## Bug Fixes and Polish

### Known Issues to Check
1. Toolbar positioning on small selection near screen edge
2. Timer accuracy during pause/resume
3. Memory usage during long recordings
4. CPU usage optimization

### Polish Items
- [ ] Add recording sound effect (optional)
- [ ] Add completion notification
- [ ] Smooth toolbar animations
- [ ] Keyboard shortcut for stop (⌘.)

## Todo List
- [ ] Test Scenario 1: Basic Recording Flow
- [ ] Test Scenario 2: Menu Bar Recording
- [ ] Test Scenario 3: Pause/Resume
- [ ] Test Scenario 4: Cancel Recording
- [ ] Test Scenario 5: Format Selection
- [ ] Test Scenario 6: Audio Capture
- [ ] Test Scenario 7: Multi-Monitor
- [ ] Test Scenario 8: Permission Denied
- [ ] Test Scenario 9: Long Recording
- [ ] Test Scenario 10: Rapid Actions
- [ ] Complete integration checklist
- [ ] Fix any discovered bugs
- [ ] Polish and optimize

## Success Criteria
1. All test scenarios pass
2. No crashes during normal usage
3. Memory stable during long recordings
4. Video output matches selected area exactly
5. Audio in sync with video

## Risk Assessment
| Risk | Impact | Mitigation |
|------|--------|------------|
| Audio sync issues | High | Test thoroughly, adjust timing |
| Memory leaks | High | Profile with Instruments |
| Multi-monitor edge cases | Medium | Test all configurations |
| Permission state changes | Low | Handle gracefully |
