# Phase 01: Unified View Modifiers

## Context
- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** None
- **Docs:** N/A

## Overview
| Field | Value |
|-------|-------|
| Date | 2026-01-26 |
| Description | Create WindowSpacingConfiguration and unified SwiftUI View modifiers |
| Priority | Medium |
| Implementation Status | Pending |
| Review Status | Awaiting Review |

## Key Insights
1. Current spacing inconsistent across window areas:
   - Toolbar: h:12, v:8, spacing:8, height:44
   - BottomBar: h:16, v:10, spacing:12/16
   - Content: h:16, top:8, bottom:12
2. Need unified configuration covering all three areas
3. Rename `ToolbarSpacingConfiguration` → `WindowSpacingConfiguration`
4. Rename file `NSWindow+ToolbarSpacing.swift` → `NSWindow+WindowSpacing.swift`

## Requirements
1. Create `WindowSpacingConfiguration` with toolbar, content, bottom bar values
2. Create unified View modifiers with `.window*()` prefix
3. Add View extensions to CornerRadius and TrafficLights files
4. All modifiers have sensible defaults, accept optional custom values

## Architecture

### WindowSpacingConfiguration
```swift
struct WindowSpacingConfiguration {
  // Toolbar
  var toolbarHeight: CGFloat = 44
  var toolbarHPadding: CGFloat = 12
  var toolbarVPadding: CGFloat = 8
  var toolbarItemSpacing: CGFloat = 8

  // Content
  var contentHPadding: CGFloat = 16
  var contentTopPadding: CGFloat = 12
  var contentBottomPadding: CGFloat = 12

  // Bottom Bar
  var bottomBarHeight: CGFloat = 44
  var bottomBarHPadding: CGFloat = 16
  var bottomBarVPadding: CGFloat = 10
  var bottomBarItemSpacing: CGFloat = 12

  // Traffic Lights
  var trafficLightsGap: CGFloat = 12

  // Corner Radius
  var cornerRadius: CGFloat = 24

  static let `default` = WindowSpacingConfiguration()
}
```

### View Modifiers API
| Modifier | Purpose | Default |
|----------|---------|---------|
| `.windowToolbar()` | Toolbar height + padding | h:44, p:12/8 |
| `.windowToolbarHeight()` | Toolbar height only | 44 |
| `.windowToolbarPadding()` | Toolbar padding only | h:12, v:8 |
| `.windowBottomBar()` | Bottom bar height + padding | h:44, p:16/10 |
| `.windowBottomBarHeight()` | Bottom bar height only | 44 |
| `.windowBottomBarPadding()` | Bottom bar padding only | h:16, v:10 |
| `.windowContent()` | Content area insets | h:16, t:12, b:12 |
| `.windowContentPadding()` | Content padding only | h:16, t:12, b:12 |
| `.windowTrafficLightsInset()` | Leading space for traffic lights | ~78 |
| `.windowCornerRadius()` | Corner radius clip | 24 |

## Related Code Files
| File | Current State | Action |
|------|---------------|--------|
| `NSWindow+ToolbarSpacing.swift` | Has partial View extensions | Rename, expand to WindowSpacing |
| `NSWindow+CornerRadius.swift` | NSWindow only | Add View extension |
| `NSWindow+TrafficLights.swift` | NSWindow only | Add View extension |

## Implementation Steps

### Step 1: Rename and expand NSWindow+ToolbarSpacing.swift
```bash
mv NSWindow+ToolbarSpacing.swift NSWindow+WindowSpacing.swift
```

Update content with `WindowSpacingConfiguration` struct containing all spacing values.

### Step 2: Add View modifiers to NSWindow+WindowSpacing.swift
```swift
extension View {
  // Toolbar
  func windowToolbar(_ config: WindowSpacingConfiguration = .default) -> some View {
    self
      .frame(height: config.toolbarHeight)
      .padding(.horizontal, config.toolbarHPadding)
      .padding(.vertical, config.toolbarVPadding)
  }

  func windowToolbarHeight(_ height: CGFloat = WindowSpacingConfiguration.default.toolbarHeight) -> some View {
    self.frame(height: height)
  }

  func windowToolbarPadding(_ config: WindowSpacingConfiguration = .default) -> some View {
    self
      .padding(.horizontal, config.toolbarHPadding)
      .padding(.vertical, config.toolbarVPadding)
  }

  // Bottom Bar
  func windowBottomBar(_ config: WindowSpacingConfiguration = .default) -> some View {
    self
      .frame(height: config.bottomBarHeight)
      .padding(.horizontal, config.bottomBarHPadding)
      .padding(.vertical, config.bottomBarVPadding)
  }

  func windowBottomBarPadding(_ config: WindowSpacingConfiguration = .default) -> some View {
    self
      .padding(.horizontal, config.bottomBarHPadding)
      .padding(.vertical, config.bottomBarVPadding)
  }

  // Content
  func windowContent(_ config: WindowSpacingConfiguration = .default) -> some View {
    self.padding(EdgeInsets(
      top: config.contentTopPadding,
      leading: config.contentHPadding,
      bottom: config.contentBottomPadding,
      trailing: config.contentHPadding
    ))
  }

  // Traffic Lights
  func windowTrafficLightsInset(_ config: WindowSpacingConfiguration = .default) -> some View {
    let width = TrafficLightConfiguration.default.horizontalOffset +
                (3 * 14) +
                (2 * TrafficLightConfiguration.default.buttonSpacing) +
                config.trafficLightsGap
    return self.padding(.leading, width)
  }
}
```

### Step 3: Add View extension to NSWindow+CornerRadius.swift
```swift
import SwiftUI

extension View {
  func windowCornerRadius(_ radius: CGFloat = NSWindow.defaultCornerRadius) -> some View {
    self.clipShape(RoundedRectangle(cornerRadius: radius))
  }
}
```

### Step 4: Add View extension to NSWindow+TrafficLights.swift
```swift
import SwiftUI

extension View {
  func windowTrafficLightsInset(_ config: TrafficLightConfiguration = .default) -> some View {
    let width = config.horizontalOffset + (3 * 14) + (2 * config.buttonSpacing)
    return self.padding(.leading, width)
  }
}
```

## Todo List
- [ ] Rename NSWindow+ToolbarSpacing.swift → NSWindow+WindowSpacing.swift
- [ ] Create WindowSpacingConfiguration struct
- [ ] Add toolbar View modifiers
- [ ] Add bottom bar View modifiers
- [ ] Add content View modifiers
- [ ] Add traffic lights View modifier
- [ ] Add View extension to NSWindow+CornerRadius.swift
- [ ] Update NSWindow+TrafficLights.swift (already has View extension in WindowSpacing)
- [ ] Remove old ToolbarSpacingConfiguration references
- [ ] Test compilation

## Success Criteria
- [ ] WindowSpacingConfiguration covers all three areas
- [ ] All modifiers use `.window*()` naming
- [ ] Default values work without args
- [ ] Custom values passable via config parameter
- [ ] Code compiles without warnings

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Breaking existing code | Medium | Low | Update all usage sites in Phase 02 |
| Naming conflicts | Low | Low | `.window` prefix avoids SwiftUI conflicts |

## Security Considerations
- None - UI styling only

## Next Steps
Proceed to Phase 02: Update all usage sites to new API
