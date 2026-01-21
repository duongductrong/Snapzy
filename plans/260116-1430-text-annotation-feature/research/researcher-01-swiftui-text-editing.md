# Research: SwiftUI Text Editing for macOS Annotations

**Date:** 2026-01-16

## 1. Inline Text Editing in Hybrid Apps

SwiftUI `TextField` works for basic input. For precise overlay positioning in annotation tools, integrate AppKit's `NSTextField` via `NSViewRepresentable`.

Pattern: Display text non-editably, use tap gesture to show TextField.

## 2. NSTextField vs SwiftUI TextField

| Aspect | SwiftUI TextField | NSTextField |
|--------|------------------|-------------|
| Integration | Native SwiftUI | NSViewRepresentable |
| Control | Limited | Full (TextKit2 access) |
| Positioning | Easy in ZStack | Manual frame control |
| Focus | @FocusState | becomeFirstResponder |

**Recommendation:** Use SwiftUI TextField in overlay for simplicity. NSTextField only if advanced text layout needed.

## 3. Double-Click Detection in NSView

```swift
override func mouseDown(with event: NSEvent) {
  if event.clickCount == 2 {
    // Enter edit mode
    handleDoubleClick(at: event.locationInWindow)
  } else {
    // Single click - select
    handleSingleClick(at: event.locationInWindow)
  }
}
```

## 4. Focus Management

```swift
// SwiftUI side
@FocusState private var isTextFieldFocused: Bool

TextField("", text: $editingText)
  .focused($isTextFieldFocused)
  .onSubmit { commitEdit() }
  .onExitCommand { cancelEdit() }

// Set focus when entering edit mode
isTextFieldFocused = true
```

## 5. Best Practices for Text Annotation

1. Use ZStack to layer edit TextField over canvas
2. Position overlay using GeometryReader + coordinate conversion
3. Temporary state for edits until commit (Enter) or cancel (Escape)
4. Auto-size bounds based on text content
5. Scale font size with displayScale for consistent visual size

## Code Pattern for Overlay

```swift
ZStack {
  CanvasDrawingView(state: state, displayScale: scale)

  if let editingId = state.editingTextAnnotationId,
     let annotation = state.annotations.first(where: { $0.id == editingId }) {
    TextEditOverlay(
      annotation: annotation,
      scale: scale,
      offset: imageOffset,
      onCommit: { text in
        state.updateAnnotationText(id: editingId, text: text)
        state.editingTextAnnotationId = nil
      }
    )
  }
}
```
