# Implementation Code Snippets

Code snippets for Phase 01 drag gesture implementation.

## State Variables

```swift
// In QuickAccessCardView
@State private var dragOffset: CGSize = .zero
@State private var isDismissing: Bool = false
```

## Computed Properties

```swift
private var isSwipeRightGesture: Bool {
  let threshold: CGFloat = 50
  let angle = atan2(dragOffset.height, dragOffset.width)
  let isRightDirection = abs(angle) < .pi / 4 // within ±45°
  return dragOffset.width > threshold && isRightDirection
}

private var dismissProgress: CGFloat {
  min(max(dragOffset.width, 0) / 150, 1.0)
}
```

## Drag Gesture

```swift
private var swipeDismissGesture: some Gesture {
  DragGesture(minimumDistance: 10)
    .onChanged { value in
      let angle = atan2(value.translation.height, value.translation.width)
      let isRightish = abs(angle) < .pi / 4 && value.translation.width > 0

      if isRightish {
        dragOffset = value.translation
      }
    }
    .onEnded { value in
      if isSwipeRightGesture {
        dismissWithSlideAnimation()
      } else if value.translation.width < 10 {
        // Non-right drag - let .onDrag handle
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
          dragOffset = .zero
        }
      } else {
        // Snap back - threshold not met
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
          dragOffset = .zero
        }
      }
    }
}
```

## Dismiss Animation

```swift
private func dismissWithSlideAnimation() {
  isDismissing = true

  // Phase 1: Slide out right
  withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
    dragOffset = CGSize(width: cardWidth + 50, height: 0)
  }

  // Phase 2: Remove after slide
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
    manager.removeScreenshot(id: item.id)
  }
}
```

## Body Modifiers

```swift
var body: some View {
  ZStack(alignment: .center) {
    // ... existing content
  }
  .frame(width: cardWidth, height: cardHeight)
  // Dismiss visual feedback
  .offset(x: dragOffset.width)
  .opacity(1 - dismissProgress * 0.5)
  .background(
    RoundedRectangle(cornerRadius: cornerRadius)
      .fill(Color.red.opacity(isSwipeRightGesture ? 0.3 : 0))
      .animation(.easeInOut(duration: 0.15), value: isSwipeRightGesture)
  )
  // ... existing modifiers
  .gesture(swipeDismissGesture)
  .if(manager.dragDropEnabled && !isDismissing) { view in
    view.onDrag {
      item.dragItemProvider()
    } preview: {
      dragPreview
    }
  }
}
```

## Stack Collapse (Existing)

Already in `QuickAccessManager.removeScreenshot`:

```swift
withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
  items.removeAll { $0.id == id }
}
```

## Gesture Priority (If Needed)

```swift
.gesture(swipeDismissGesture)
.onDrag { ... } // lower priority

// Or use high priority:
.highPriorityGesture(swipeDismissGesture)
```
