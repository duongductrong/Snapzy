# High-Quality Image Export Techniques - macOS SwiftUI/AppKit

## 1. ImageRenderer API (SwiftUI)

### Overview
Modern approach introduced in WWDC '22 for converting SwiftUI views to images. Preferred over legacy UIKit/AppKit wrapping methods.

### Scale Factors & Resolution
```swift
import SwiftUI

let renderer = ImageRenderer(content: myView)

// Set scale for Retina displays
renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0  // Dynamic scale
// Or explicit: 1.0 (@1x), 2.0 (@2x), 3.0 (@3x)

let nsImage = renderer.nsImage
let cgImage = renderer.cgImage
```

### Key Limitations
- **Cannot render AppKit views**: WKWebView, custom NSView subclasses show placeholders only
- **macOS display diversity**: Users adjust display scaling dynamically - avoid hardcoding 2x/3x, use `backingScaleFactor` instead
- **Performance**: High `rasterizationScale` on complex views is computationally expensive
- **SwiftUI-only**: Renders declarative SwiftUI content exclusively

### Best Practices
- Query actual screen scale: `NSScreen.main?.backingScaleFactor`
- For export: Use explicit high scale (2.0-3.0) regardless of display
- `proposedSize`: Set to `.zero` for intrinsic size or explicit dimensions

---

## 2. NSBitmapImageRep (AppKit)

### High-Quality Export Pattern
```swift
import AppKit

func exportToPNG(image: NSImage, quality: CGFloat = 1.0) -> Data? {
    guard let tiffData = image.tiffRepresentation,
          let bitmapRep = NSBitmapImageRep(data: tiffData) else {
        return nil
    }

    return bitmapRep.representation(
        using: .png,
        properties: [.compressionFactor: quality]  // 0.0-1.0 (1.0 = least compression)
    )
}
```

### Advanced: CGImageDestination for DPI Control
```swift
import ImageIO

func exportWithDPI(image: NSImage, dpi: Int, url: URL) throws {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw ExportError.creationFailed
    }

    let properties: [CFString: Any] = [
        kCGImagePropertyDPIHeight: dpi,
        kCGImagePropertyDPIWidth: dpi,
        kCGImageDestinationLossyCompressionQuality: 1.0  // For JPEG
    ]

    CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
    CGImageDestinationFinalize(destination)
}
```

### Caveats
- **Metadata loss**: EXIF, GPS data stripped during tiffRepresentation conversion
- **Multi-page images**: Animated GIF frames lost
- Apple recommends Core Graphics for direct bitmap manipulation (non-premultiplied data)

---

## 3. CGContext Rendering

### High-Quality Pattern
```swift
import CoreGraphics

func renderViewToImage(view: NSView, scale: CGFloat = 2.0) -> NSImage? {
    let size = view.bounds.size
    let scaledSize = CGSize(width: size.width * scale, height: size.height * scale)

    // Create bitmap context
    guard let context = CGContext(
        data: nil,
        width: Int(scaledSize.width),
        height: Int(scaledSize.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Scale context
    context.scaleBy(x: scale, y: scale)

    // Render layer (not view) for better fidelity
    view.layer?.render(in: context)

    guard let cgImage = context.makeImage() else { return nil }
    return NSImage(cgImage: cgImage, size: size)
}
```

### Anti-aliasing & Quality Tips
- **Render layers**: Use `view.layer.render(in:)` instead of view drawing
- **Size alignment**: View size should be multiple of `contentsScale` to avoid interpolation artifacts
- **Transform scales**: Avoid odd-numbered scale transforms
- **Context interpolation**: Set `context.interpolationQuality = .high`

---

## 4. Exporting 3D Transformed Views

### SwiftUI 3D Modifiers
```swift
// Method 1: rotation3DEffect
Text("3D Text")
    .rotation3DEffect(
        .degrees(45),
        axis: (x: 1.0, y: 1.0, z: 0.0),
        anchor: .center,
        perspective: 0.5  // Lower = more dramatic perspective
    )

// Method 2: projectionEffect with CATransform3D
import QuartzCore

var transform = CATransform3DIdentity
transform.m34 = -1.0 / 500.0  // Perspective (negative for depth)
transform = CATransform3DRotate(transform, .pi / 4, 0, 1, 0)

Text("Projected")
    .projectionEffect(ProjectionTransform(transform))
```

### Export with Transformations
```swift
import SwiftUI

struct ExportTransformedView {
    func exportAs PNG() {
        let view = Text("Export Me!")
            .font(.largeTitle)
            .padding(50)
            .background(Color.red)
            .rotation3DEffect(.degrees(45), axis: (x: 1, y: 1, z: 0))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3.0  // High resolution

        guard let nsImage = renderer.nsImage else { return }
        saveImage(nsImage)
    }
}
```

### Key Insight
- SwiftUI applies transformations internally during render
- ImageRenderer captures final transformed output correctly
- No need to manually apply CATransform3D to exported bitmap
- `.projectionEffect()` gives explicit control over transform matrix

---

## 5. Format Selection & Compression

### PNG (Lossless)
**Best for**: UI exports, transparency, sharp edges

```swift
// Native API (35% compression)
bitmapRep.representation(using: .png, properties: [.compressionFactor: 1.0])

// Better: Use external tools for 70-90% reduction
// - ImageOptim (GUI app, 96.5% max compression)
// - pngquant (CLI, lossy color quantization)
// - optipng (CLI, lossless, 5-20% compression)
```

**Compression settings**:
- `.compressionFactor`: 0.0 (max compression) to 1.0 (min compression)
- Native macOS APIs offer poor PNG compression
- Use third-party tools post-export for optimal size

### TIFF (Archival Quality)
**Best for**: Print production, no quality loss required

```swift
bitmapRep.representation(using: .tiff, properties: [
    .compressionMethod: NSBitmapImageRep.TIFFCompression.lzw  // Lossless
])
```

**Size reduction strategies**:
- Reduce dimensions to exact reproduction size
- Use LZW compression (lossless, minimal gain)
- JPEG compression within TIFF (lossy but controllable)
- Most effective: Match resolution to output requirements (e.g., 300 DPI for print)

### JPEG (Lossy, smallest size)
```swift
bitmapRep.representation(using: .jpeg, properties: [
    .compressionFactor: 0.9  // 0.0 (low quality) to 1.0 (high quality)
])
```

---

## Recommended Workflow

```swift
import SwiftUI
import AppKit

func exportHighQuality(view: some View, url: URL, scale: CGFloat = 3.0) throws {
    // 1. Render SwiftUI view
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale

    guard let nsImage = renderer.nsImage else {
        throw ExportError.renderFailed
    }

    // 2. Convert to bitmap with high quality
    guard let tiffData = nsImage.tiffRepresentation,
          let bitmapRep = NSBitmapImageRep(data: tiffData) else {
        throw ExportError.conversionFailed
    }

    // 3. Export as PNG (lossless)
    guard let pngData = bitmapRep.representation(using: .png, properties: [
        .compressionFactor: 1.0
    ]) else {
        throw ExportError.encodingFailed
    }

    // 4. Write to file
    try pngData.write(to: url)

    // 5. Optional: Post-process with ImageOptim/pngquant for smaller size
}
```

---

## Sources

- [Apple Developer - ImageRenderer](https://apple.com)
- [Stack Overflow - ImageRenderer Scale Factors](https://stackoverflow.com)
- [Apple Developer - NSBitmapImageRep](https://apple.com)
- [Pol Piella - Image Export](https://polpiella.dev)
- [SwiftUI Lab - ImageRenderer](https://swiftui-lab.com)
- [Apple Developer - CGContext](https://apple.com)
- [Medium - High Performance Drawing](https://medium.com)
- [Dev.to - PNG Compression Comparison](https://dev.to)
- [Stack Overflow - 3D Transforms](https://stackoverflow.com)
