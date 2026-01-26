# Phase 01: Toolbar Spacing Extension

## Context
- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** NSWindow+CornerRadius.swift, NSWindow+TrafficLights.swift
- **Docs:** N/A

## Overview
| Field | Value |
|-------|-------|
| Date | 2026-01-26 |
| Description | Create ToolbarSpacingConfiguration struct and NSWindow extension |
| Priority | Medium |
| Implementation Status | Pending |
| Review Status | Awaiting Review |

## Key Insights
1. `TrafficLightConfiguration` uses: horizontalOffset(12), buttonSpacing(8), toolbarItemHeight(28)
2. `VideoEditorToolbarView` uses: height(44), padding(.horizontal, 12), spacing(8)
3. Traffic lights end at approximately `12 + 3*(14) + 2*(8) = 70px` from left edge
4. Corner radius (24pt) requires content inset consideration

## Requirements
1. Create `ToolbarSpacingConfiguration` struct with toolbar layout values
2. Create NSWindow extension method to calculate available toolbar width
3. Provide static default that harmonizes with TrafficLightConfiguration
4. Follow existing code patterns (same file structure, documentation style)

## Architecture
```
ToolbarSpacingConfiguration
├── leadingPadding: CGFloat     // Space after traffic lights (~82pt)
├── trailingPadding: CGFloat    // Right edge spacing (12pt)
├── itemSpacing: CGFloat        // Between toolbar items (8pt)
├── verticalPadding: CGFloat    // Top/bottom padding (8pt)
├── toolbarHeight: CGFloat      // Standard toolbar height (44pt)
└── contentInsets: NSEdgeInsets // Main content area insets

NSWindow Extension
├── applyToolbarSpacing(config:) -> Void
├── availableToolbarWidth(config:) -> CGFloat
└── trafficLightsEndX() -> CGFloat
```

## Related Code Files
| File | Purpose |
|------|---------|
| `ClaudeShot/Core/NSWindow+CornerRadius.swift` | Corner radius extension (reference) |
| `ClaudeShot/Core/NSWindow+TrafficLights.swift` | Traffic lights extension (reference) |
| `ClaudeShot/Features/VideoEditor/VideoEditorWindow.swift` | Uses both extensions |
| `ClaudeShot/Features/Annotate/Window/AnnotateWindow.swift` | Uses both extensions |
| `ClaudeShot/Features/VideoEditor/Views/VideoEditorToolbarView.swift` | Current toolbar implementation |

## Implementation Steps

### Step 1: Create ToolbarSpacingConfiguration struct
```swift
struct ToolbarSpacingConfiguration {
  var leadingPadding: CGFloat = 82    // After traffic lights
  var trailingPadding: CGFloat = 12   // Right edge
  var itemSpacing: CGFloat = 8        // Between items
  var verticalPadding: CGFloat = 8    // Top/bottom
  var toolbarHeight: CGFloat = 44     // Standard height
  var contentTopInset: CGFloat = 52   // Below toolbar (44 + 8)

  static let `default` = ToolbarSpacingConfiguration()
}
```

### Step 2: Create NSWindow extension
```swift
extension NSWindow {
  /// Calculate X position where traffic lights end
  func trafficLightsEndX(config: TrafficLightConfiguration = .default) -> CGFloat {
    guard let zoomButton = standardWindowButton(.zoomButton) else { return 70 }
    return zoomButton.frame.maxX
  }

  /// Calculate available toolbar width after traffic lights
  func availableToolbarWidth(
    toolbarConfig: ToolbarSpacingConfiguration = .default,
    trafficConfig: TrafficLightConfiguration = .default
  ) -> CGFloat {
    let trafficEnd = trafficLightsEndX(config: trafficConfig)
    return frame.width - trafficEnd - toolbarConfig.leadingPadding - toolbarConfig.trailingPadding
  }
}
```

### Step 3: Add documentation comments
Follow existing pattern from NSWindow+CornerRadius.swift and NSWindow+TrafficLights.swift

## Todo List
- [ ] Create `ClaudeShot/Core/NSWindow+ToolbarSpacing.swift`
- [ ] Define `ToolbarSpacingConfiguration` struct with default values
- [ ] Implement `trafficLightsEndX()` method
- [ ] Implement `availableToolbarWidth()` method
- [ ] Add documentation comments
- [ ] Test with VideoEditorWindow

## Success Criteria
- [ ] File follows existing Core/ extension patterns
- [ ] Default values harmonize with TrafficLightConfiguration
- [ ] Methods correctly calculate toolbar dimensions
- [ ] Code compiles without warnings

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Values don't match existing layouts | Low | Low | Derive from current hardcoded values |
| Traffic light width varies by macOS version | Low | Medium | Use dynamic calculation via standardWindowButton |

## Security Considerations
- No security concerns - UI layout only

## Next Steps
After implementation:
1. Optionally update VideoEditorToolbarView to use configuration values
2. Optionally update AnnotateToolbarView to use configuration values
