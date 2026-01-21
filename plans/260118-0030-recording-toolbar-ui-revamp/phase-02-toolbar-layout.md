# Phase 02: Toolbar Layout

## Context Links
- [Main Plan](./plan.md)
- [Phase 01: Button Components](./phase-01-button-components.md)
- Current: `ZapShot/Features/Recording/RecordingToolbarView.swift`
- Window: `ZapShot/Features/Recording/RecordingToolbarWindow.swift`

## Overview
Restructure `RecordingToolbarView` to match Apple's native toolbar layout: close button on left, options in center, record button on right, with proper dividers and spacing.

## Key Insights
- Apple layout: `[X close] | [Options v] | [Record]`
- Dividers are subtle vertical lines (~1pt, secondary color)
- Overall corner radius is 14px (current is 12)
- Horizontal padding ~16pt, vertical ~12pt
- Shadow is subtle, offset slightly downward

## Requirements
1. Replace text "Cancel" with X icon button
2. Remove segmented picker (moved to Options menu in Phase 03)
3. Add placeholder for Options button (implemented in Phase 03)
4. Restyle Record button to blue primary CTA
5. Update corner radius to 14px
6. Proper divider styling between groups

## Architecture

```
RecordingToolbarView
├── HStack(spacing: 12)
│   ├── ToolbarIconButton(xmark) → onCancel
│   ├── ToolbarDivider
│   ├── OptionsMenuButton (placeholder, Phase 03)
│   ├── ToolbarDivider
│   └── RecordButton → onRecord
├── .padding (16h, 12v)
├── .background(.ultraThinMaterial)
└── .clipShape(RoundedRectangle(14))
```

## Related Code Files
| File | Purpose |
|------|---------|
| `RecordingToolbarView.swift` | Main file to modify |
| `RecordingToolbarWindow.swift` | May need binding updates |
| `RecordingToolbarStyles.swift` | Constants and styles (Phase 01) |
| `ToolbarIconButton.swift` | Close button component (Phase 01) |

## Implementation Steps

### Step 1: Create ToolbarDivider component
```swift
// In RecordingToolbarStyles.swift or inline
struct ToolbarDivider: View {
    var body: some View {
        Divider()
            .frame(height: ToolbarConstants.dividerHeight)
    }
}
```

### Step 2: Update RecordingToolbarView structure
```swift
struct RecordingToolbarView: View {
    @Binding var selectedFormat: VideoFormat
    @Binding var selectedQuality: VideoQuality
    @Binding var captureAudio: Bool
    let onRecord: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: ToolbarConstants.itemSpacing) {
            // Close button
            ToolbarIconButton(
                systemName: "xmark",
                action: onCancel,
                accessibilityLabel: "Cancel recording"
            )

            ToolbarDivider()

            // Options menu (placeholder - Phase 03)
            ToolbarOptionsMenu(
                selectedFormat: $selectedFormat,
                selectedQuality: $selectedQuality,
                captureAudio: $captureAudio
            )

            ToolbarDivider()

            // Record button
            Button(action: onRecord) {
                Label("Record", systemImage: "record.circle.fill")
            }
            .buttonStyle(RecordButtonStyle())
        }
        .padding(.horizontal, ToolbarConstants.horizontalPadding)
        .padding(.vertical, ToolbarConstants.verticalPadding)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ToolbarConstants.toolbarCornerRadius))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}
```

### Step 3: Temporary Options placeholder (until Phase 03)
```swift
// Temporary placeholder until ToolbarOptionsMenu is implemented
struct ToolbarOptionsMenuPlaceholder: View {
    @Binding var selectedFormat: VideoFormat

    var body: some View {
        Menu {
            ForEach(VideoFormat.allCases, id: \.self) { format in
                Button(format.displayName) {
                    selectedFormat = format
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("Options")
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius)
                    .fill(Color.primary.opacity(0.05))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }
}
```

### Step 4: Update RecordingToolbarWindow bindings
```swift
// Add new state properties
var selectedQuality: VideoQuality = .high
var captureAudio: Bool = true

// Update showPreRecordToolbar()
func showPreRecordToolbar() {
    mode = .preRecord

    let formatBinding = Binding<VideoFormat>(
        get: { [weak self] in self?.selectedFormat ?? .mov },
        set: { [weak self] in self?.selectedFormat = $0 }
    )
    let qualityBinding = Binding<VideoQuality>(
        get: { [weak self] in self?.selectedQuality ?? .high },
        set: { [weak self] in self?.selectedQuality = $0 }
    )
    let audioBinding = Binding<Bool>(
        get: { [weak self] in self?.captureAudio ?? true },
        set: { [weak self] in self?.captureAudio = $0 }
    )

    let view = RecordingToolbarView(
        selectedFormat: formatBinding,
        selectedQuality: qualityBinding,
        captureAudio: audioBinding,
        onRecord: { [weak self] in self?.onRecord?() },
        onCancel: { [weak self] in self?.onCancel?() }
    )

    setContent(AnyView(view))
    positionBelowRect(anchorRect)
}
```

### Step 5: Update Preview
```swift
#Preview {
    RecordingToolbarView(
        selectedFormat: .constant(.mov),
        selectedQuality: .constant(.high),
        captureAudio: .constant(true),
        onRecord: {},
        onCancel: {}
    )
    .padding()
}
```

## Todo List
- [ ] Add ToolbarDivider to RecordingToolbarStyles.swift
- [ ] Replace Cancel text button with ToolbarIconButton(xmark)
- [ ] Remove segmented Picker from RecordingToolbarView
- [ ] Add temporary ToolbarOptionsMenuPlaceholder
- [ ] Replace Record button style with RecordButtonStyle
- [ ] Update corner radius to 14px
- [ ] Update padding to 16h/12v
- [ ] Add selectedQuality and captureAudio bindings to view
- [ ] Update RecordingToolbarWindow with new bindings
- [ ] Update Preview with new bindings
- [ ] Test toolbar renders correctly in window

## Success Criteria
1. Close button renders as X icon on left
2. Dividers visible between button groups
3. Record button is blue with white icon/text
4. Toolbar has 14px corner radius
5. Options placeholder displays "Options v"
6. All callbacks (onRecord, onCancel) still work
7. Toolbar positions correctly below selection rect

## Risk Assessment
| Risk | Impact | Mitigation |
|------|--------|------------|
| Window sizing changes | Medium | Call setContentSize after layout |
| Bindings not syncing | Medium | Test with actual RecordingToolbarWindow |
| Menu not appearing | Low | Use .menuStyle(.borderlessButton) |

## Security Considerations
- No security concerns for layout changes
- Bindings are local UI state only

## Next Steps
After completing Phase 02, proceed to [Phase 03: Options Menu](./phase-03-options-menu.md) to implement the full dropdown menu with format, quality, and audio options.
