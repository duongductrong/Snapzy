# Phase 04: Menubar Integration

## Context

- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** [Phase 01](./phase-01-state-architecture.md), [Phase 02](./phase-02-window-management.md)
- **Docs:** README.md, development-rules.md

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-17 |
| Priority | Medium |
| Status | Pending |
| Estimated Effort | 30 minutes |

Add "Open Annotate" menu item to menubar that opens empty annotation window.

## Key Insights

1. MenuBarContentView in ZapShotApp.swift handles all menu items
2. Menu organized: Capture actions -> Recording -> Permissions -> Settings -> Quit
3. Annotate option fits logically after capture actions or in new Tools section
4. No permission required for opening empty annotate window

## Requirements

1. Add "Open Annotate" button to MenuBarContentView
2. Position after Recording section (new Tools divider)
3. Add keyboard shortcut (Cmd+Shift+A suggested)
4. Wire to AnnotateManager.shared.openEmptyAnnotation()
5. No disabled state needed (always available)

## Architecture

```
MenuBarContentView
├── Capture Area (Cmd+Shift+4)
├── Capture Fullscreen (Cmd+Shift+3)
├── ---
├── Record Screen (Cmd+Shift+5)
├── ---
├── Open Annotate (Cmd+Shift+A)  <- NEW
├── ---
├── [Grant Permission if needed]
├── ---
├── Preferences
├── ---
└── Quit
```

## Related Code Files

| File | Purpose |
|------|---------|
| `ZapShot/App/ZapShotApp.swift` | MenuBarContentView modification |
| `ZapShot/Features/Annotate/AnnotateManager.swift` | openEmptyAnnotation() call |

## Implementation Steps

### Step 1: Update MenuBarContentView

Add after Recording section:

```swift
struct MenuBarContentView: View {
    @ObservedObject var viewModel: ScreenCaptureViewModel

    var body: some View {
        Group {
            // Capture Actions
            Button {
                viewModel.captureArea()
            } label: {
                Label("Capture Area", systemImage: "crop")
            }
            .keyboardShortcut("4", modifiers: [.command, .shift])
            .disabled(!viewModel.hasPermission)

            Button {
                viewModel.captureFullscreen()
            } label: {
                Label("Capture Fullscreen", systemImage: "rectangle.dashed")
            }
            .keyboardShortcut("3", modifiers: [.command, .shift])
            .disabled(!viewModel.hasPermission)

            Divider()

            // Recording
            Button {
                viewModel.startRecordingFlow()
            } label: {
                Label("Record Screen", systemImage: "record.circle")
            }
            .keyboardShortcut("5", modifiers: [.command, .shift])
            .disabled(!viewModel.hasPermission)

            Divider()

            // Tools - NEW SECTION
            Button {
                AnnotateManager.shared.openEmptyAnnotation()
            } label: {
                Label("Open Annotate", systemImage: "pencil.and.outline")
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])

            Divider()

            // ... rest of menu (permissions, settings, quit)
        }
    }
}
```

### Step 2: Choose appropriate SF Symbol

Options for "Open Annotate":
- `pencil.and.outline` - pencil with shape outline
- `scribble.variable` - freeform drawing
- `photo.on.rectangle` - image editing
- `rectangle.and.pencil.and.ellipsis` - annotations

Recommended: `pencil.and.outline` for clarity

### Step 3: Verify keyboard shortcut doesn't conflict

Check existing shortcuts:
- Cmd+Shift+3: Capture Fullscreen
- Cmd+Shift+4: Capture Area
- Cmd+Shift+5: Record Screen
- Cmd+Shift+A: Available - use for Annotate

### Step 4: Test activation behavior

Ensure clicking menu item:
1. Opens annotation window
2. Activates app (brings to foreground)
3. Works even when app is in background

## Todo

- [ ] Add "Open Annotate" button after Recording section
- [ ] Add Divider before new button
- [ ] Use "pencil.and.outline" SF Symbol
- [ ] Add Cmd+Shift+A keyboard shortcut
- [ ] Wire to AnnotateManager.shared.openEmptyAnnotation()
- [ ] Test menu item appears correctly
- [ ] Test keyboard shortcut works
- [ ] Test window opens and activates

## Success Criteria

1. "Open Annotate" visible in menubar between Recording and Permissions
2. Shows pencil icon matching app's visual style
3. Cmd+Shift+A opens annotation window from anywhere
4. Menu item always enabled (no permission required)
5. Clicking opens empty annotation window with drop zone
6. Works when app is in background

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Shortcut conflict with other apps | Low | Low | Use app-specific shortcut |
| Menu crowding | Low | Low | Logical grouping with dividers |

## Security Considerations

- No additional security concerns for this phase

## Integration Testing

After all phases complete, verify full flow:

1. Click "Open Annotate" in menubar
2. Empty window opens with drop zone
3. Drag image from Finder onto canvas
4. Image loads successfully
5. Draw annotations on image
6. Export works correctly
7. Close window
8. Repeat with keyboard shortcut

## Next Steps

After completion, all phases are done. Perform integration testing and update plan.md status to Complete.
