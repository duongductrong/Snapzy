# Phase 03: Options Menu

## Context Links
- [Main Plan](./plan.md)
- [Phase 02: Toolbar Layout](./phase-02-toolbar-layout.md)
- Enums: `ZapShot/Core/ScreenRecordingManager.swift` (VideoFormat, VideoQuality)

## Overview
Implement the Options dropdown menu with format selection, quality selection, and audio capture toggle matching Apple's native menu styling.

## Key Insights
- Apple uses native Menu with chevron.down indicator
- Menu sections separated by Divider
- Checkmarks indicate current selection
- Toggle for boolean options (audio capture)
- Menu label shows "Options" with subtle chevron

## Requirements
1. Create `ToolbarOptionsMenu` component
2. Format section: MOV, MP4 with checkmark for selected
3. Quality section: High, Medium, Low with checkmark
4. Audio section: Toggle for "Capture Audio"
5. Hover state on menu button
6. Native macOS menu appearance

## Architecture

```swift
ToolbarOptionsMenu
├── Menu
│   ├── Section "Format"
│   │   ├── Button "MOV" (checkmark if selected)
│   │   └── Button "MP4" (checkmark if selected)
│   ├── Divider
│   ├── Section "Quality"
│   │   ├── Button "High"
│   │   ├── Button "Medium"
│   │   └── Button "Low"
│   ├── Divider
│   └── Toggle "Capture Audio"
└── Label: "Options" + chevron.down
```

## Related Code Files
| File | Purpose |
|------|---------|
| `ScreenRecordingManager.swift` | VideoFormat, VideoQuality enums |
| `RecordingToolbarView.swift` | Parent view consuming this menu |
| `RecordingToolbarStyles.swift` | ToolbarConstants |

## Implementation Steps

### Step 1: Create ToolbarOptionsMenu.swift
```swift
// ZapShot/Features/Recording/Components/ToolbarOptionsMenu.swift

import SwiftUI

struct ToolbarOptionsMenu: View {
    @Binding var selectedFormat: VideoFormat
    @Binding var selectedQuality: VideoQuality
    @Binding var captureAudio: Bool

    @State private var isHovered = false

    var body: some View {
        Menu {
            // Format section
            Section("Format") {
                ForEach(VideoFormat.allCases, id: \.self) { format in
                    Button {
                        selectedFormat = format
                    } label: {
                        HStack {
                            Text(format.displayName)
                            if selectedFormat == format {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            // Quality section
            Section("Quality") {
                ForEach(VideoQuality.allCases, id: \.self) { quality in
                    Button {
                        selectedQuality = quality
                    } label: {
                        HStack {
                            Text(quality.displayName)
                            if selectedQuality == quality {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            // Audio toggle
            Toggle("Capture Audio", isOn: $captureAudio)

        } label: {
            menuLabel
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .onHover { isHovered = $0 }
    }

    private var menuLabel: some View {
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
                .fill(Color.primary.opacity(isHovered ? 0.1 : 0.05))
        )
    }
}
```

### Step 2: Add displayName to VideoQuality
```swift
// Add to VideoQuality enum in ScreenRecordingManager.swift
var displayName: String {
    switch self {
    case .high: return "High"
    case .medium: return "Medium"
    case .low: return "Low"
    }
}
```

### Step 3: Add Preview
```swift
#Preview {
    ToolbarOptionsMenu(
        selectedFormat: .constant(.mov),
        selectedQuality: .constant(.high),
        captureAudio: .constant(true)
    )
    .padding()
    .background(.ultraThinMaterial)
}
```

## Todo List
- [ ] Create `ToolbarOptionsMenu.swift` in Components folder
- [ ] Add displayName property to VideoQuality enum
- [ ] Implement format selection with checkmarks
- [ ] Implement quality selection with checkmarks
- [ ] Implement audio capture toggle
- [ ] Add hover state to menu button
- [ ] Add preview for testing
- [ ] Replace placeholder in RecordingToolbarView
- [ ] Test menu opens and selections work

## Success Criteria
1. Menu opens on click showing all options
2. Format section shows MOV/MP4 with checkmark on selected
3. Quality section shows High/Medium/Low with checkmark
4. Audio toggle works correctly
5. Hover state visible on menu button
6. Selections persist and sync with bindings

## Risk Assessment
| Risk | Impact | Mitigation |
|------|--------|------------|
| Menu positioning in floating window | Medium | Use native Menu, system handles |
| Toggle not styled correctly | Low | SwiftUI Toggle works in Menu |
| Checkmark alignment | Low | Use HStack with Spacer |

## Security Considerations
- No security concerns, local UI state only
- Audio permission already handled by ScreenRecordingManager

## Next Steps
After completing Phase 03, proceed to [Phase 04: Polish](./phase-04-polish.md) for animations, accessibility, and final refinements.
