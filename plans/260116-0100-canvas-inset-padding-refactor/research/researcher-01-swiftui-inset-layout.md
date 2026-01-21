# SwiftUI Layout Patterns for Inset Padding

## Executive Summary

SwiftUI offers flexible layout capabilities through `GeometryReader` and modifier ordering. The "inset padding" behavior (fixed background, shrinking content) can be achieved by:
1. Fixed container using GeometryReader
2. Background fills container
3. Content sized as: `containerSize - (padding * 2)`

## Key Findings

### 1. GeometryReader Best Practices

```swift
GeometryReader { geometry in
    let availableWidth = geometry.size.width - (padding * 2)
    let availableHeight = geometry.size.height - (padding * 2)

    ZStack {
        // Background fills entire container
        backgroundView
            .frame(width: geometry.size.width, height: geometry.size.height)

        // Content shrinks with padding
        contentView
            .frame(width: availableWidth, height: availableHeight)
    }
}
```

### 2. Aspect Ratio Preservation

When shrinking content, maintain aspect ratio:

```swift
let imageAspectRatio = originalWidth / originalHeight
let availableWidth = containerWidth - (padding * 2)
let availableHeight = containerHeight - (padding * 2)

// Fit image within available space preserving aspect ratio
let scaleToFit = min(availableWidth / originalWidth, availableHeight / originalHeight)
let displayWidth = originalWidth * scaleToFit
let displayHeight = originalHeight * scaleToFit
```

### 3. Modifier Order Matters

- `padding()` before `background()` = inset padding (CSS border-box)
- `padding()` after `background()` = outset padding (CSS content-box)

### 4. CleanShot X Behavior Pattern

1. Container has fixed size based on viewport
2. Background always fills container 100%
3. Image calculates available space after padding
4. Image scales down with `.aspectRatio(contentMode: .fit)`

## Implementation Recommendation

```swift
struct InsetPaddingCanvas: View {
    let padding: CGFloat
    let image: NSImage

    var body: some View {
        GeometryReader { geo in
            let containerWidth = geo.size.width
            let containerHeight = geo.size.height
            let availableWidth = containerWidth - (padding * 2)
            let availableHeight = containerHeight - (padding * 2)

            ZStack {
                // Background fills 100% of container
                backgroundLayer
                    .frame(width: containerWidth, height: containerHeight)

                // Image shrinks to fit within padding
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: availableWidth, maxHeight: availableHeight)
            }
        }
    }
}
```

## Common Pitfalls

- Using fixed frame sizes instead of container-relative calculations
- Not accounting for aspect ratio when shrinking
- Applying zoom/scale before calculating available space

## References

- Apple SwiftUI Documentation
- SwiftUI Layout Protocol Reference
