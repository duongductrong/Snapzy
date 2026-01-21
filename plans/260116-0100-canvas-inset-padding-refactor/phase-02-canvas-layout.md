# Phase 02: Canvas Layout Refactor

## Objective

Refactor `AnnotateCanvasView` to use inset padding logic where background fills container and image shrinks.

## File: `AnnotateCanvasView.swift`

### Current Logic (lines 31-55)

```swift
private func canvasContent(in containerSize: CGSize) -> some View {
    let scale = calculateFitScale(containerSize: containerSize)
    // Background GROWS with padding (wrong)
    let bgWidth = (displayImageWidth + state.padding * 2) * scale
    let bgHeight = (displayImageHeight + state.padding * 2) * scale
    // Image stays same size
    let imgWidth = displayImageWidth * scale
    let imgHeight = displayImageHeight * scale
    ...
}
```

### New Logic

```swift
private func canvasContent(in containerSize: CGSize) -> some View {
    let margin: CGFloat = 40

    // Container fills available space (minus margin)
    let containerWidth = containerSize.width - margin * 2
    let containerHeight = containerSize.height - margin * 2

    // Background always fills container 100%
    let bgWidth = containerWidth
    let bgHeight = containerHeight

    // Image shrinks to fit within padding
    let scale = state.displayScale(for: containerSize, margin: margin)
    let imgWidth = state.imageWidth * scale
    let imgHeight = state.imageHeight * scale

    // Calculate image offset based on alignment
    let imageDisplaySize = CGSize(width: imgWidth, height: imgHeight)
    let offset = state.imageOffset(for: containerSize, imageDisplaySize: imageDisplaySize, margin: margin)

    return ZStack {
        // Background layer fills container
        backgroundLayer(width: bgWidth, height: bgHeight, scale: 1.0)

        // Image positioned within padding area
        imageLayer(width: imgWidth, height: imgHeight, scale: scale)
            .offset(x: offset.x, y: offset.y)

        // Drawing canvas matches image position
        CanvasDrawingView(state: state, displayScale: scale)
            .frame(width: imgWidth, height: imgHeight)
            .offset(x: offset.x, y: offset.y)
    }
    .scaleEffect(state.zoomLevel)
}
```

### Remove Old Method

Delete `calculateFitScale` method (lines 57-70) - replaced by `state.displayScale()`.

### Update Background Layer

Modify `backgroundLayer` to use corner radius without scale multiplication:

```swift
// Line 92: Change from
.cornerRadius(state.cornerRadius * scale)
// To
.cornerRadius(state.cornerRadius)
```

Apply same change to all corner radius usages in `backgroundLayer`.

### Update Image Layer

```swift
private func imageLayer(width: CGFloat, height: CGFloat, scale: CGFloat) -> some View {
    Image(nsImage: state.sourceImage)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: width, height: height)
        .cornerRadius(state.cornerRadius) // Remove * scale
        .shadow(
            color: .black.opacity(state.backgroundStyle != .none ? state.shadowIntensity : 0),
            radius: 15,  // Remove * scale
            x: 0,
            y: 8  // Remove * scale
        )
}
```

### Remove Unused Properties

Delete `displayImageWidth` and `displayImageHeight` computed properties (lines 74-81) - now accessed via `state.imageWidth` and `state.imageHeight`.

## Validation

- [ ] Background fills available space regardless of padding
- [ ] Image shrinks as padding increases
- [ ] Image stays centered (or aligned per `imageAlignment`)
- [ ] Corner radius and shadow render correctly
- [ ] Zoom still works

## Visual Test Cases

1. Padding = 0: Image fills container
2. Padding = 50: Image visibly smaller, background unchanged
3. Padding = 100: Image even smaller, background still fills container
4. Change alignment: Image repositions within padding area
