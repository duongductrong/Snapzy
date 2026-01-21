# Recording Toolbar UI Revamp Plan

**Created:** 260118 | **Status:** Completed | **Progress:** 100%

## Objective
Revamp `RecordingToolbarView` to match Apple's native macOS recording toolbar aesthetic with icon-based buttons, Options dropdown, and polished material design.

## Current State Analysis
| Aspect | Current | Target (Apple-style) |
|--------|---------|---------------------|
| Cancel | Text button | X icon button (xmark) |
| Record | Red `.borderedProminent` | Blue primary CTA |
| Format | Segmented picker (MOV/MP4) | Options dropdown menu |
| Layout | HStack with divider | [X] \| [Options v] \| [Record] |
| Corner radius | 12px | 14px |
| Background | `.ultraThinMaterial` | Keep (correct) |

## Architecture Overview
```
RecordingToolbarView.swift (revamped)
├── CloseButton (X icon, left)
├── Divider
├── OptionsMenuButton (dropdown: format, quality, audio)
├── Divider
└── RecordButton (blue primary CTA)

New Components:
├── ToolbarIconButton.swift (reusable icon button style)
├── ToolbarOptionsMenu.swift (dropdown menu component)
└── RecordingToolbarStyles.swift (consolidated button styles)
```

## Phases

| Phase | Description | Status | Est. LOC |
|-------|-------------|--------|----------|
| 01 | Button Components | Pending | ~80 |
| 02 | Toolbar Layout | Pending | ~60 |
| 03 | Options Menu | Pending | ~70 |
| 04 | Polish & Accessibility | Pending | ~40 |

## Key Design Specs (from Apple reference)
- Icon size: ~24pt SF Symbols, medium weight
- Button container: ~36x36pt rounded square, subtle fill on hover
- Dividers: 1pt vertical, 20pt height, secondary color
- Spacing: 12-16pt between elements
- Corner radius: 14px overall
- Record button: Blue fill, white text/icon, ~80pt width

## Files to Modify
- `ZapShot/Features/Recording/RecordingToolbarView.swift` - Main revamp
- `ZapShot/Features/Recording/RecordingToolbarWindow.swift` - Add quality/audio bindings

## Files to Create
- `ZapShot/Features/Recording/Components/ToolbarIconButton.swift`
- `ZapShot/Features/Recording/Components/ToolbarOptionsMenu.swift`
- `ZapShot/Features/Recording/Styles/RecordingToolbarStyles.swift`

## Dependencies
- SF Symbols: xmark, chevron.down, record.circle.fill
- VideoFormat enum (exists)
- VideoQuality enum (exists)
- captureAudio option (exists in ScreenRecordingManager)

## Success Criteria
1. Visual match to Apple's native toolbar aesthetic
2. All existing functionality preserved (format, record, cancel)
3. New Options dropdown with format, quality, audio toggle
4. Hover/pressed states on all interactive elements
5. VoiceOver accessibility labels

## Risk Assessment
| Risk | Mitigation |
|------|------------|
| Breaking existing callbacks | Keep onRecord/onCancel/onStop interface |
| Window sizing issues | Test with NSHostingView.fittingSize |
| Menu positioning | Use native SwiftUI Menu for proper placement |

## Phase Files
- [Phase 01: Button Components](./phase-01-button-components.md)
- [Phase 02: Toolbar Layout](./phase-02-toolbar-layout.md)
- [Phase 03: Options Menu](./phase-03-options-menu.md)
- [Phase 04: Polish](./phase-04-polish.md)
