# Phase 3: VideoEditor Safe Area Handling

## Overview
Update VideoEditor SwiftUI views to handle safe area for traffic lights and extend background behind title bar.

## Implementation Steps

### 3.1 Update VideoEditorMainView.swift

**File:** `ClaudeShot/Features/VideoEditor/Views/VideoEditorMainView.swift`

**Location:** Line 17-57 (body var)

**Change:**
```swift
var body: some View {
  VStack(spacing: 0) {
    // Add safe area spacer for traffic lights
    Color.clear
      .frame(height: 28) // Standard macOS title bar height

    // Video player
    VideoPlayerSection(player: state.player)
      .frame(minHeight: 200)

    // Timeline with frame previews and trim handles
    VideoTimelineView(state: state)
      .padding(.horizontal, 16)
      .padding(.top, 12)

    // Playback controls
    VideoControlsView(state: state)
      .padding(.horizontal, 16)
      .padding(.top, 8)

    // Info panel
    VideoInfoPanel(state: state)
      .padding(.horizontal, 16)
      .padding(.top, 12)

    Spacer(minLength: 0)

    // Divider
    Divider()

    // Footer actions
    VideoEditorActionsView(
      state: state,
      onSave: { onSave?() },
      onSaveAs: { onSaveAs?() },
      onCancel: { onCancel?() }
    )
  }
  .frame(maxWidth: .infinity, maxHeight: .infinity)
  .background(Color(NSColor.windowBackgroundColor))
  .ignoresSafeArea(.all, edges: .top) // Extend background behind title bar
  .task {
    await state.loadMetadata()
    await state.extractFrames()
  }
}
```

**Changes:**
1. Add `Color.clear.frame(height: 28)` at top of VStack
2. Add `.ignoresSafeArea(.all, edges: .top)` to root VStack

**Explanation:**
- Clear spacer (28px) reserves space for title bar area
- Height matches standard macOS title bar
- `.ignoresSafeArea` extends background to window top
- Video player starts below traffic lights

## Testing Checklist

- [ ] Background extends to window top edge
- [ ] Traffic lights visible and clickable
- [ ] Video player not obscured by traffic lights
- [ ] Timeline controls remain accessible
- [ ] Footer actions properly positioned
- [ ] Theme switching works (light/dark/system)
- [ ] Window resize behaves correctly
- [ ] No content overlap with system buttons

## Dependencies
- Requires Phase 1 completed
- VideoEditorWindow must have `.fullSizeContentView` enabled

## Next Phase
Phase 4: Testing and validation
