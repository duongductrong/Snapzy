# Phase 01: ThemeManager Integration

## Context
- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** None
- **Reference:** `ZapShot/Features/Preferences/Tabs/GeneralSettingsView.swift`

## Overview
| Field | Value |
|-------|-------|
| Date | 2026-01-21 |
| Description | Add ThemeManager integration to AnnotateMainView for consistent theme propagation |
| Priority | Medium |
| Implementation Status | Not Started |
| Review Status | Pending |

## Key Insights
1. AnnotateMainView lacks ThemeManager observation - child views don't receive SwiftUI color scheme context
2. Preferences uses `@ObservedObject private var themeManager = ThemeManager.shared` + `.preferredColorScheme()` pattern
3. Semantic NSColor values are already correct - just need theme context propagation
4. Single file change provides complete fix due to SwiftUI's environment inheritance

## Requirements
- R1: Annotate views must respect user's appearance preference (light/dark/system)
- R2: Theme changes must reflect immediately without window restart
- R3: Consistent visual appearance between Annotate and Preferences

## Architecture
```
ThemeManager.shared
       │
       ▼
AnnotateMainView (.preferredColorScheme)
       │
       ├── AnnotateToolbarView
       ├── AnnotateSidebarView
       ├── AnnotateCanvasView
       └── AnnotateBottomBarView
```
Color scheme context flows down via SwiftUI environment.

## Related Code Files
| File | Purpose |
|------|---------|
| `ZapShot/Features/Annotate/Views/AnnotateMainView.swift` | **Target file** - add ThemeManager |
| `ZapShot/Core/Theme/ThemeManager.swift` | Theme state provider |
| `ZapShot/Features/Annotate/Window/AnnotateWindow.swift` | AppKit window theming (already integrated) |

## Implementation Steps

### Step 1: Add ThemeManager property
Add `@ObservedObject` property to observe theme changes:
```swift
@ObservedObject private var themeManager = ThemeManager.shared
```

### Step 2: Apply preferredColorScheme modifier
Add modifier to root VStack for theme propagation:
```swift
.preferredColorScheme(themeManager.systemAppearance)
```

### Step 3: Complete implementation
Final AnnotateMainView.swift:
```swift
import SwiftUI

struct AnnotateMainView: View {
  @StateObject var state: AnnotateState
  @ObservedObject private var themeManager = ThemeManager.shared

  var body: some View {
    VStack(spacing: 0) {
      AnnotateToolbarView(state: state)

      Divider()
        .background(Color(nsColor: .separatorColor))

      HStack(spacing: 0) {
        if state.showSidebar {
          AnnotateSidebarView(state: state)
            .frame(width: 240)
            .transition(.move(edge: .leading))

          Divider()
            .background(Color.white.opacity(0.1))
        }

        AnnotateCanvasView(state: state)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

      Divider()
        .background(Color(nsColor: .separatorColor))

      AnnotateBottomBarView(state: state)
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .preferredColorScheme(themeManager.systemAppearance)
  }
}
```

## Todo List
- [ ] Add ThemeManager property to AnnotateMainView
- [ ] Add .preferredColorScheme modifier
- [ ] Build and verify no compile errors
- [ ] Test theme switching in Preferences
- [ ] Verify visual consistency with Preferences window

## Success Criteria
- [ ] Annotate toolbar/sidebar/bottom bar colors match Preferences
- [ ] Switching appearance in Preferences immediately updates Annotate window
- [ ] System appearance changes (when set to "Auto") reflect in Annotate
- [ ] No compile warnings or errors
- [ ] No visual regressions

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Color mismatch persists | Low | Medium | Verify NSColor semantic colors are appropriate |
| Performance impact | Very Low | Low | ThemeManager uses efficient @Published pattern |

## Security Considerations
None - UI-only change with no data handling.

## Next Steps
1. Implement changes in AnnotateMainView.swift
2. Build project
3. Manual testing: switch themes in Preferences, verify Annotate reflects changes
4. Code review
