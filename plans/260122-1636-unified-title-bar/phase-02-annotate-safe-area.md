# Phase 2: Annotate Safe Area Handling

## Overview
Update Annotate SwiftUI views to handle safe area for traffic lights and extend background behind title bar.

## Implementation Steps

### 2.1 Update AnnotateMainView.swift

**File:** `ClaudeShot/Features/Annotate/Views/AnnotateMainView.swift`

**Location:** Line 15-43 (body var)

**Change:**
```swift
var body: some View {
  VStack(spacing: 0) {
    AnnotateToolbarView(state: state)
      .padding(.top, 8) // Add top padding for traffic lights

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
  .ignoresSafeArea(.all, edges: .top) // Extend background behind title bar
}
```

**Changes:**
1. Add `.padding(.top, 8)` to AnnotateToolbarView
2. Add `.ignoresSafeArea(.all, edges: .top)` to root VStack

**Explanation:**
- `.ignoresSafeArea` extends background to window top edge
- Top padding (8px) provides spacing for traffic lights

### 2.2 Update AnnotateToolbarView.swift

**File:** `ClaudeShot/Features/Annotate/Views/AnnotateToolbarView.swift`

**Location:** Line 14-48 (body var)

**Change:**
```swift
var body: some View {
  HStack(spacing: 8) {
    // Add spacer for traffic lights (macOS standard width ~78px)
    Spacer().frame(width: 78)

    // Left group: Capture tools
    captureToolsGroup

    ToolbarDivider()

    // Center group: Annotation tools
    annotationToolsGroup

    ToolbarDivider()

    // Undo/Redo
    undoRedoGroup

    ToolbarDivider()

    // Placeholder for video recording
    ToolbarButton(icon: "video", isSelected: false) {}
      .disabled(true)
      .opacity(0.5)

    Spacer()

    // Right group: Stroke size and actions
    strokeSizeSlider

    Spacer().frame(width: 16)

    actionButtons
  }
  .padding(.horizontal, 12)
  .padding(.vertical, 8)
  .background(Color(nsColor: .controlBackgroundColor))
}
```

**Changes:**
- Add `Spacer().frame(width: 78)` at start of HStack
- This reserves space for traffic light buttons

**Explanation:**
- 78px accommodates 3 traffic lights (20px each) + spacing
- Prevents toolbar buttons from overlapping traffic lights

## Testing Checklist

- [ ] Toolbar buttons don't overlap traffic lights
- [ ] Background extends to window top edge
- [ ] Traffic lights remain clickable
- [ ] Sidebar toggle animation works
- [ ] Theme switching works (light/dark/system)
- [ ] No visual gaps at top edge

## Dependencies
- Requires Phase 1 completed
- AnnotateWindow must have `.fullSizeContentView` enabled

## Next Phase
Phase 3: VideoEditor safe area handling
