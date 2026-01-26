# Phase 5: Export Functionality

## Context

- **Parent Plan**: [plan.md](./plan.md)
- **Dependencies**: [Phase 1](./phase-01-core-state-and-models.md), [Phase 2](./phase-02-3d-rendering-engine.md), [Phase 4](./phase-04-ui-components.md)
- **Research**: [Image Export](./research/researcher-02-image-export.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-27 |
| Description | High-quality export using ImageRenderer at 2x/3x scale |
| Priority | High |
| Status | `[ ]` Not Started |

## Key Insights

- ImageRenderer captures 3D transforms correctly
- Use explicit scale (2.0-3.0) for high-res export
- NSBitmapImageRep for PNG encoding
- Export includes background, shadow, and all effects

## Requirements

1. Export at 2x and 3x resolution options
2. PNG format with transparency support
3. Save As, Copy to Clipboard, Share options
4. Progress indicator for large exports

## Architecture

```swift
// MockupExporter.swift
struct MockupExporter {
    static func renderFinalImage(state: MockupState, scale: CGFloat = 2.0) -> NSImage?
    static func saveAs(state: MockupState, scale: CGFloat) async throws -> URL?
    static func copyToClipboard(state: MockupState, scale: CGFloat) async
    static func share(state: MockupState, scale: CGFloat, from view: NSView) async
}

// Export flow
func renderFinalImage(state: MockupState, scale: CGFloat) -> NSImage? {
    let exportView = MockupExportView(state: state)  // Simplified view for export
    let renderer = ImageRenderer(content: exportView)
    renderer.scale = scale
    return renderer.nsImage
}
```

## Related Files

| File | Purpose |
|------|---------|
| `Features/Annotate/Export/AnnotateExporter.swift` | Export pattern reference |
| Research: Image Export | ImageRenderer and NSBitmapImageRep techniques |

## Implementation Steps

### Step 1: Create MockupExporter
- [ ] Create `Features/Annotate/Mockup/Rendering/MockupExporter.swift`
- [ ] Add static methods matching AnnotateExporter pattern
- [ ] Import necessary frameworks (SwiftUI, AppKit, UniformTypeIdentifiers)

### Step 2: Implement renderFinalImage
- [ ] Create export-specific view (no UI chrome)
- [ ] Apply all transforms from MockupState
- [ ] Include background rendering
- [ ] Use ImageRenderer with scale parameter
- [ ] Return NSImage

### Step 3: Implement saveAs
- [ ] Show NSSavePanel with PNG file type
- [ ] Default filename: "mockup-{timestamp}.png"
- [ ] Convert NSImage to PNG via NSBitmapImageRep
- [ ] Write to selected URL
- [ ] Return saved URL for confirmation

### Step 4: Implement copyToClipboard
- [ ] Render image at specified scale
- [ ] Use NSPasteboard.general
- [ ] Clear and set PNG data
- [ ] Show confirmation (optional toast)

### Step 5: Implement share
- [ ] Render image to temporary file
- [ ] Use NSSharingServicePicker
- [ ] Clean up temp file after share completes

### Step 6: Add scale selection UI
- [ ] Export dropdown with 1x, 2x, 3x options
- [ ] Show estimated dimensions before export
- [ ] Remember last used scale preference

### Step 7: Add progress handling
- [ ] Show progress indicator for large images
- [ ] Run export on background thread
- [ ] Update UI on main thread

## Todo

- [ ] MockupExporter.swift created
- [ ] renderFinalImage working
- [ ] saveAs with NSSavePanel
- [ ] copyToClipboard working
- [ ] share functionality
- [ ] Scale selection in UI
- [ ] Progress indicator

## Success Criteria

- Exported images match preview exactly
- 3x export produces high-resolution output
- PNG transparency preserved
- No quality loss in export
- Share works with all macOS share targets

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Large image memory issues | Limit max export size, use autorelease |
| ImageRenderer limitations | Fallback to CGContext if needed |
| Slow export on complex images | Background thread, progress UI |

## Security Considerations

- Validate export path permissions
- Clean up temporary files after share

## Next Steps

Proceed to [Phase 6: Integration and Testing](./phase-06-integration-and-testing.md)
