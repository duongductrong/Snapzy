# Phase 04: Testing & Edge Cases

## Objective

Verify refactored canvas behavior and handle edge cases.

## Test Matrix

### Visual Tests

| Test | Steps | Expected |
|------|-------|----------|
| Background fill | Set padding 0, 50, 100 | Background size unchanged |
| Image shrink | Increase padding | Image visibly smaller |
| Aspect ratio | Various image sizes | Image never distorted |
| Alignment | Change imageAlignment | Image repositions correctly |
| Zoom | Cmd+scroll | Zooms around center |
| Corner radius | Set radius with padding | Applies to both bg and image |

### Annotation Tests

| Test | Steps | Expected |
|------|-------|----------|
| Draw rectangle | Draw at padding=0, change to 50 | Annotation stays on image |
| Draw arrow | Draw arrow, change padding | Arrow endpoints stay correct |
| Draw path | Draw freehand, change padding | Path follows image |
| Select annotation | Click on annotation | Selects correctly |
| Drag annotation | Drag after padding change | Moves smoothly |
| Resize annotation | Resize handles work | Resizes correctly |

### Export Tests

| Test | Steps | Expected |
|------|-------|----------|
| Export no padding | Export with padding=0 | Same as source size |
| Export with padding | Export with padding=50 | Source size + 100px |
| Annotation position | Draw, export, compare | Annotation at same relative position |
| Copy to clipboard | Copy, paste in Preview | Correct output |

## Edge Cases to Handle

### 1. Minimum Image Size

Prevent image from becoming too small:

```swift
// In AnnotateState.displayScale()
let minImageSize: CGFloat = 100
let scale = min(scaleX, scaleY, 1.0)
let resultWidth = imageWidth * scale
let resultHeight = imageHeight * scale

if resultWidth < minImageSize || resultHeight < minImageSize {
    // Clamp padding to allow minimum size
    // Or show warning to user
}
```

### 2. Container Too Small

Handle window resize making container very small:

```swift
// Guard against division by zero or negative values
let imageAreaWidth = max(availableWidth - padding * 2, 1)
let imageAreaHeight = max(availableHeight - padding * 2, 1)
```

### 3. Zero Display Scale

Prevent division by zero in coordinate transforms:

```swift
private func displayToImage(_ point: CGPoint) -> CGPoint {
    guard displayScale > 0 else { return point }
    // ...
}
```

### 4. Annotations Outside Image

When padding increases, some annotations may appear to be outside visible image area - this is acceptable since annotations are stored in image coordinates.

## Regression Checklist

- [ ] All annotation tools work (selection, pencil, highlighter, shapes, text, arrow, counter)
- [ ] Undo/redo works correctly
- [ ] Delete annotation works
- [ ] Background styles all render correctly (gradient, solid, wallpaper, blurred)
- [ ] Shadow renders correctly
- [ ] Export to file works
- [ ] Copy to clipboard works
- [ ] Share works

## Performance Considerations

- Coordinate transformations are O(1) - no performance concern
- Drawing with scale transform is native CGContext operation - efficient
- No additional redraws triggered by refactor

## Rollback Plan

If issues discovered:
1. Revert `AnnotateCanvasView.swift` changes
2. Revert `CanvasDrawingView.swift` changes
3. Remove new properties from `AnnotateState.swift`

All changes are isolated to these three files.
