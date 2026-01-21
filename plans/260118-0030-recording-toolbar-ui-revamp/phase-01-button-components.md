# Phase 01: Button Components

## Context Links
- [Main Plan](./plan.md)
- [Scout Report](./scout/scout-01-recording-files.md)
- Current: `ZapShot/Features/Recording/RecordingToolbarView.swift`
- Design System: `ZapShot/Features/Onboarding/DesignSystem/VSDesignSystem.swift`

## Overview
Create reusable button components matching Apple's native toolbar aesthetic: icon buttons with hover states, and a primary record button style.

## Key Insights
- Apple uses ~36x36pt rounded square containers for icon buttons
- Subtle background fill appears on hover (gray opacity ~0.1)
- Pressed state uses slightly darker fill (~0.15)
- Record button is blue with white icon/text, prominent styling
- SF Symbols at ~20-24pt, medium weight for consistency

## Requirements
1. `ToolbarIconButtonStyle` - reusable style for X close and other icons
2. `RecordButtonStyle` - blue primary CTA matching Apple aesthetic
3. Hover and pressed state animations
4. Consistent sizing and spacing constants

## Architecture

```swift
// ToolbarIconButton.swift
struct ToolbarIconButtonStyle: ButtonStyle {
    @State private var isHovered: Bool
    // 36x36 container, cornerRadius 8, hover fill
}

// RecordingToolbarStyles.swift
struct RecordButtonStyle: ButtonStyle {
    // Blue background, white foreground, ~80pt width
}

enum ToolbarConstants {
    static let iconButtonSize: CGFloat = 36
    static let iconSize: CGFloat = 20
    static let cornerRadius: CGFloat = 8
    static let toolbarCornerRadius: CGFloat = 14
}
```

## Related Code Files
| File | Purpose |
|------|---------|
| `VSDesignSystem.swift` | Reference for existing PrimaryButtonStyle pattern |
| `RecordingToolbarView.swift` | Will consume these new styles |

## Implementation Steps

### Step 1: Create ToolbarConstants
```swift
// In RecordingToolbarStyles.swift
enum ToolbarConstants {
    static let iconButtonSize: CGFloat = 36
    static let iconSize: CGFloat = 20
    static let buttonCornerRadius: CGFloat = 8
    static let toolbarCornerRadius: CGFloat = 14
    static let dividerHeight: CGFloat = 20
    static let itemSpacing: CGFloat = 12
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 12
}
```

### Step 2: Create ToolbarIconButtonStyle
```swift
struct ToolbarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: ToolbarConstants.iconSize, weight: .medium))
            .foregroundColor(.primary)
            .frame(width: ToolbarConstants.iconButtonSize,
                   height: ToolbarConstants.iconButtonSize)
            .background(
                RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.15 : 0))
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                // Handled via environment or @State wrapper
            }
    }
}
```

### Step 3: Create HoverableIconButton wrapper
```swift
struct ToolbarIconButton: View {
    let systemName: String
    let action: () -> Void
    let accessibilityLabel: String

    @State private var isHovered = false

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
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityLabel)
    }
}
```

### Step 4: Create RecordButtonStyle
```swift
struct RecordButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius)
                    .fill(Color.blue)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}
```

## Todo List
- [ ] Create `ZapShot/Features/Recording/Styles/RecordingToolbarStyles.swift`
- [ ] Define `ToolbarConstants` enum
- [ ] Implement `ToolbarIconButtonStyle`
- [ ] Create `ZapShot/Features/Recording/Components/ToolbarIconButton.swift`
- [ ] Implement `ToolbarIconButton` view with hover state
- [ ] Implement `RecordButtonStyle`
- [ ] Add SwiftUI previews for all components
- [ ] Test hover/pressed states visually

## Success Criteria
1. ToolbarIconButton renders at 36x36pt with centered icon
2. Hover state shows subtle gray background fill
3. Pressed state shows slightly darker fill
4. RecordButtonStyle produces blue button with white text
5. All components have accessibility labels
6. Previews render correctly in Xcode

## Risk Assessment
| Risk | Impact | Mitigation |
|------|--------|------------|
| onHover not working in NSWindow | Medium | Test in actual toolbar window context |
| Button sizing inconsistent | Low | Use explicit frame modifiers |
| Style conflicts with system | Low | Use `.buttonStyle(.plain)` as base |

## Security Considerations
- No security concerns for UI components
- No user data handling in button styles

## Next Steps
After completing Phase 01, proceed to [Phase 02: Toolbar Layout](./phase-02-toolbar-layout.md) to integrate these components into the revamped toolbar structure.
