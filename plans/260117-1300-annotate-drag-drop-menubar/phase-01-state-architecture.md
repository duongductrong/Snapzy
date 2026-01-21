# Phase 01: State Architecture

## Context

- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** None (foundation phase)
- **Docs:** README.md, development-rules.md

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-17 |
| Priority | High |
| Status | Pending |
| Estimated Effort | 1-1.5 hours |

Refactor `AnnotateState` to support optional/mutable source image, enabling empty initialization and later image loading via drag-drop.

## Key Insights

1. Current `sourceImage` and `sourceURL` are immutable `let` constants set at init
2. All image-dependent calculations (displayScale, imageOffset) reference `sourceImage.size`
3. Need graceful handling when image is nil - computed properties must not crash
4. Undo/redo stack unaffected - annotations independent of source image

## Requirements

1. Make `sourceImage` a `@Published var` with optional initial value
2. Make `sourceURL` a `@Published var` with optional initial value
3. Add `hasImage: Bool` computed property
4. Add `loadImage(from url: URL)` method with Retina scaling
5. Add `loadImage(_ image: NSImage, url: URL?)` method for direct NSImage loading
6. Handle nil image in all computed properties (imageWidth, imageHeight, etc.)
7. Reset annotations when new image loaded (optional - discuss with user)

## Architecture

```
AnnotateState
├── @Published var sourceImage: NSImage?    // Changed from let
├── @Published var sourceURL: URL?          // Changed from let
├── var hasImage: Bool { sourceImage != nil }
├── var imageWidth: CGFloat                 // Return 0 or placeholder if nil
├── var imageHeight: CGFloat                // Return 0 or placeholder if nil
├── func loadImage(from url: URL)           // New: Load with Retina scaling
└── func loadImage(_ image: NSImage, url: URL?) // New: Direct load
```

## Related Code Files

| File | Purpose |
|------|---------|
| `ZapShot/Features/Annotate/State/AnnotateState.swift` | Primary modification target |
| `ZapShot/Features/Annotate/Window/AnnotateWindowController.swift` | Contains `loadImageWithCorrectScale` to extract |

## Implementation Steps

### Step 1: Update sourceImage/sourceURL declarations

Change from:
```swift
let sourceImage: NSImage
let sourceURL: URL
```

To:
```swift
@Published var sourceImage: NSImage?
@Published var sourceURL: URL?
```

### Step 2: Add hasImage computed property

```swift
var hasImage: Bool { sourceImage != nil }
```

### Step 3: Update imageWidth/imageHeight

```swift
var imageWidth: CGFloat { sourceImage?.size.width ?? 400 }
var imageHeight: CGFloat { sourceImage?.size.height ?? 300 }
```

Default 400x300 provides reasonable placeholder canvas size.

### Step 4: Extract image loading logic

Move `loadImageWithCorrectScale` from AnnotateWindowController to AnnotateState (or shared utility):

```swift
func loadImage(from url: URL) {
    guard let image = Self.loadImageWithCorrectScale(from: url) else { return }
    self.sourceImage = image
    self.sourceURL = url
    // Optionally reset annotations
    // self.annotations.removeAll()
}

func loadImage(_ image: NSImage, url: URL? = nil) {
    self.sourceImage = image
    self.sourceURL = url
}

private static func loadImageWithCorrectScale(from url: URL) -> NSImage? {
    // Copy existing implementation from AnnotateWindowController
}
```

### Step 5: Add empty initializer

```swift
init() {
    self.sourceImage = nil
    self.sourceURL = nil
}

init(image: NSImage, url: URL) {
    self.sourceImage = image
    self.sourceURL = url
}
```

### Step 6: Update dependent computed properties

Ensure `displayScale`, `imageOffset` handle nil image gracefully.

## Todo

- [ ] Change sourceImage from let to @Published var optional
- [ ] Change sourceURL from let to @Published var optional
- [ ] Add hasImage computed property
- [ ] Update imageWidth/imageHeight with default fallbacks
- [ ] Add empty init()
- [ ] Extract loadImageWithCorrectScale as static method
- [ ] Add loadImage(from url:) method
- [ ] Add loadImage(_:url:) method
- [ ] Update displayScale to handle nil image
- [ ] Update imageOffset to handle nil image
- [ ] Test compilation

## Success Criteria

1. AnnotateState can be initialized without image
2. `hasImage` returns false when no image loaded
3. `loadImage(from:)` successfully loads image from URL
4. Existing init(image:url:) still works unchanged
5. No crashes when accessing imageWidth/imageHeight without image
6. All existing functionality preserved when image is present

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Breaking existing flows | Medium | High | Maintain existing init signature |
| Nil image crashes | Low | High | Add nil checks in all computed props |
| Memory leaks | Low | Medium | Use weak references where needed |

## Security Considerations

- Validate image files before loading (check magic bytes, not just extension)
- Limit maximum image dimensions to prevent memory exhaustion
- Sanitize file paths from dropped URLs

## Next Steps

After completion, proceed to [Phase 02: Window Management](./phase-02-window-management.md)
