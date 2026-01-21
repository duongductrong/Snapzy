# Phase 03: Drag-Drop Implementation

## Context

- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** [Phase 01](./phase-01-state-architecture.md), [Phase 02](./phase-02-window-management.md)
- **Docs:** README.md, development-rules.md

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-17 |
| Priority | High |
| Status | Pending |
| Estimated Effort | 1.5-2 hours |

Implement drag-and-drop support in AnnotateCanvasView to accept external image files.

## Key Insights

1. SwiftUI `onDrop` modifier works with UTType identifiers
2. Need to handle both file URLs and image pasteboard data
3. Drop zone overlay only visible when no image loaded
4. macOS uses NSItemProvider for drop data extraction
5. Support formats: PNG, JPG, JPEG, GIF, TIFF, BMP, HEIC

## Requirements

1. Create AnnotateDropZoneView component for empty state
2. Add drag-drop support to AnnotateCanvasView
3. Validate dropped files against supported image formats
4. Load dropped image into AnnotateState
5. Show visual feedback during drag hover
6. Display error for unsupported file types
7. Handle multiple file drop (use first valid image)

## Architecture

```
AnnotateCanvasView
├── body
│   ├── if state.hasImage -> existing canvas content
│   └── else -> AnnotateDropZoneView
├── onDrop(of: supportedTypes, delegate: DropDelegate)
└── DropDelegate: handles drag states and validation

AnnotateDropZoneView
├── Drop zone visual (dashed border, icon, text)
├── Drag hover state (highlight)
└── Instructions text

ImageDropDelegate (or inline)
├── validateDrop(info:) -> Bool
├── performDrop(info:) -> Bool
└── dropEntered/dropExited for visual feedback
```

## Supported UTTypes

```swift
import UniformTypeIdentifiers

static let supportedImageTypes: [UTType] = [
    .png,
    .jpeg,
    .gif,
    .tiff,
    .bmp,
    .heic
]
```

## Related Code Files

| File | Purpose |
|------|---------|
| `ZapShot/Features/Annotate/Views/AnnotateCanvasView.swift` | Add drop support |
| `ZapShot/Features/Annotate/Views/AnnotateDropZoneView.swift` | New: drop zone UI |
| `ZapShot/Features/Annotate/State/AnnotateState.swift` | loadImage method |

## Implementation Steps

### Step 1: Create AnnotateDropZoneView

```swift
// AnnotateDropZoneView.swift

import SwiftUI

struct AnnotateDropZoneView: View {
    @Binding var isDragOver: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundColor(isDragOver ? .accentColor : .secondary)

            Text("Drop an image here")
                .font(.title2)
                .fontWeight(.medium)

            Text("or capture a screenshot to annotate")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach(["PNG", "JPG", "GIF", "HEIC"], id: \.self) { format in
                    Text(format)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .foregroundColor(isDragOver ? .accentColor : .secondary.opacity(0.5))
                .padding(40)
        )
        .background(Color(white: 0.08))
        .animation(.easeInOut(duration: 0.2), value: isDragOver)
    }
}
```

### Step 2: Add drop state to AnnotateCanvasView

```swift
struct AnnotateCanvasView: View {
    @ObservedObject var state: AnnotateState
    @State private var isDragOver = false

    // ... rest of implementation
}
```

### Step 3: Update body to show drop zone when no image

```swift
var body: some View {
    GeometryReader { geometry in
        ZStack {
            Color(white: 0.08)

            if state.hasImage {
                canvasContent(in: geometry.size)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                AnnotateDropZoneView(isDragOver: $isDragOver)
            }
        }
        .onScrollWheelZoom { delta in
            guard state.hasImage else { return }
            let newZoom = state.zoomLevel + delta * 0.1
            state.zoomLevel = min(max(newZoom, 0.25), 3.0)
        }
        .onDrop(of: Self.supportedImageTypes, isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
    }
}
```

### Step 4: Define supported types and drop handler

```swift
import UniformTypeIdentifiers

extension AnnotateCanvasView {
    static let supportedImageTypes: [UTType] = [
        .png, .jpeg, .gif, .tiff, .bmp, .heic
    ]

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        // Find first provider that can load a file URL
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, error in
                    guard error == nil,
                          let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else {
                        return
                    }

                    // Validate file type
                    guard Self.isValidImageFile(url: url) else {
                        // TODO: Show error toast
                        return
                    }

                    Task { @MainActor in
                        state.loadImage(from: url)
                    }
                }
                return true
            }
        }
        return false
    }

    static func isValidImageFile(url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return supportedImageTypes.contains { type.conforms(to: $0) }
    }
}
```

### Step 5: Alternative - handle NSImage directly from pasteboard

Some drops provide image data directly:

```swift
private func handleDrop(providers: [NSItemProvider]) -> Bool {
    for provider in providers {
        // Try file URL first
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            // ... existing file URL handling
            return true
        }

        // Try loading image data directly
        for imageType in Self.supportedImageTypes {
            if provider.hasItemConformingToTypeIdentifier(imageType.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: imageType.identifier) { data, error in
                    guard let data = data,
                          let image = NSImage(data: data) else { return }

                    Task { @MainActor in
                        state.loadImage(image, url: nil)
                    }
                }
                return true
            }
        }
    }
    return false
}
```

### Step 6: Add error feedback (optional enhancement)

```swift
@State private var showDropError = false
@State private var dropErrorMessage = ""

// In body, add overlay:
.overlay(alignment: .bottom) {
    if showDropError {
        Text(dropErrorMessage)
            .padding()
            .background(Color.red.opacity(0.9))
            .cornerRadius(8)
            .padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// In handleDrop, on validation failure:
Task { @MainActor in
    dropErrorMessage = "Unsupported file format"
    showDropError = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        showDropError = false
    }
}
```

## Todo

- [ ] Create AnnotateDropZoneView.swift file
- [ ] Add isDragOver state to AnnotateCanvasView
- [ ] Import UniformTypeIdentifiers
- [ ] Define supportedImageTypes array
- [ ] Implement handleDrop method
- [ ] Add isValidImageFile validation
- [ ] Update body to conditionally show drop zone
- [ ] Add onDrop modifier to canvas
- [ ] Disable zoom when no image
- [ ] Add visual hover feedback
- [ ] Add error feedback for invalid files
- [ ] Test with various image formats
- [ ] Test drag from Finder
- [ ] Test drag from browser

## Success Criteria

1. Empty annotation window shows drop zone with instructions
2. Dragging file over canvas shows visual highlight
3. Dropping valid image loads it into canvas
4. All annotation tools work on dropped image
5. Dropping unsupported file shows error message
6. Dropping multiple files uses first valid image
7. Works with files from Finder, browser, other apps

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| UTType compatibility issues | Low | Medium | Test all declared formats |
| Large image memory issues | Medium | Medium | Add size validation |
| Async loading race conditions | Low | Low | Use MainActor for state updates |
| Drop not detected | Low | High | Test with various drag sources |

## Security Considerations

- Validate file is actually an image, not just by extension
- Consider sandboxing implications for file access
- Don't persist dropped file URLs without user consent
- Limit maximum image dimensions (e.g., 8192x8192)

## Next Steps

After completion, proceed to [Phase 04: Menubar Integration](./phase-04-menubar-integration.md)
