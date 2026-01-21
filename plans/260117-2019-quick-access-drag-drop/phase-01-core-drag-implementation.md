# Phase 01: Core Drag Implementation

## Context Links

- **Parent Plan**: [plan.md](./plan.md)
- **Dependencies**: None
- **Related Docs**: SwiftUI Draggable, NSItemProvider

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-17 |
| Description | Add drag & drop functionality to QuickAccessCardView |
| Priority | High |
| Status | Completed |
| Estimated Effort | 2-3 hours |

## Key Insights

1. **SwiftUI `.draggable()` modifier** works with `Transferable` protocol or `NSItemProvider`
2. **NSItemProvider** is preferred for file URLs - provides better external app compatibility
3. **UTType** declarations needed: `.image`, `.movie`, `.fileURL` for maximum compatibility
4. **Drag preview** can be customized with `.draggable(item) { PreviewView() }` syntax
5. **Conditional drag**: Use `.draggable()` only when `dragDropEnabled` is true
6. **NSPanel compatibility**: SwiftUI drag works inside NSHostingView without issues

## Requirements

### Functional
- FR-01: Drag screenshot cards to external apps (Finder, Slack, Discord, Facebook)
- FR-02: Drag video cards to external apps
- FR-03: Show thumbnail as drag preview
- FR-04: Respect `dragDropEnabled` setting

### Non-Functional
- NFR-01: No noticeable lag when initiating drag
- NFR-02: Drag should not interfere with hover/click interactions

## Architecture

### Data Flow

```
User drags card
    |
    v
QuickAccessCardView.draggable()
    |
    v
NSItemProvider created with file URL
    |
    v
External app receives file
```

### UTType Strategy

| Item Type | Primary UTType | Fallback UTTypes |
|-----------|---------------|------------------|
| Screenshot | `.png` / `.jpeg` | `.image`, `.fileURL` |
| Video | `.movie` / `.mpeg4Movie` | `.fileURL` |

## Related Code Files

| File | Purpose |
|------|---------|
| `ZapShot/Features/QuickAccess/QuickAccessCardView.swift` | Main view to modify |
| `ZapShot/Features/QuickAccess/QuickAccessItem.swift` | Data model (read-only) |
| `ZapShot/Features/QuickAccess/QuickAccessManager.swift` | `dragDropEnabled` setting |

## Implementation Steps

### Step 1: Add Transferable Extension for QuickAccessItem

Create extension to provide drag data:

```swift
// In QuickAccessCardView.swift or new file

import UniformTypeIdentifiers

extension QuickAccessItem {
  /// Creates NSItemProvider for drag & drop
  func dragItemProvider() -> NSItemProvider {
    let provider = NSItemProvider()

    // Register file URL as primary representation
    provider.registerFileRepresentation(
      forTypeIdentifier: UTType.fileURL.identifier,
      visibility: .all
    ) { completion in
      completion(self.url, false, nil)
      return nil
    }

    // For screenshots, also register as image
    if !isVideo {
      provider.registerFileRepresentation(
        forTypeIdentifier: UTType.image.identifier,
        visibility: .all
      ) { completion in
        completion(self.url, false, nil)
        return nil
      }
    }

    // For videos, register as movie
    if isVideo {
      provider.registerFileRepresentation(
        forTypeIdentifier: UTType.movie.identifier,
        visibility: .all
      ) { completion in
        completion(self.url, false, nil)
        return nil
      }
    }

    return provider
  }
}
```

### Step 2: Add Draggable Modifier to Card

Modify `QuickAccessCardView.swift` body:

```swift
var body: some View {
  ZStack(alignment: .center) {
    // ... existing content ...
  }
  .frame(width: cardWidth, height: cardHeight)
  // ... existing modifiers ...
  .if(manager.dragDropEnabled) { view in
    view.draggable(item.dragItemProvider()) {
      // Drag preview
      Image(nsImage: item.thumbnail)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: cardWidth * 0.8, height: cardHeight * 0.8)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .shadow(radius: 4)
    }
  }
}
```

### Step 3: Add Conditional View Extension (if not exists)

```swift
extension View {
  @ViewBuilder
  func `if`<Transform: View>(
    _ condition: Bool,
    transform: (Self) -> Transform
  ) -> some View {
    if condition {
      transform(self)
    } else {
      self
    }
  }
}
```

### Step 4: Import UniformTypeIdentifiers

Add import at top of `QuickAccessCardView.swift`:

```swift
import UniformTypeIdentifiers
```

## Todo List

- [ ] Add `import UniformTypeIdentifiers` to QuickAccessCardView.swift
- [ ] Create `dragItemProvider()` extension method on QuickAccessItem
- [ ] Add conditional View extension if not already present
- [ ] Add `.draggable()` modifier to card view with thumbnail preview
- [ ] Test drag to Finder
- [ ] Test drag to Slack/Discord
- [ ] Test drag to Facebook Messenger
- [ ] Test with `dragDropEnabled = false`
- [ ] Verify hover/click interactions still work

## Success Criteria

| Criteria | Verification Method |
|----------|---------------------|
| Screenshots draggable to Finder | Manual test: drag to Finder window |
| Screenshots draggable to Slack | Manual test: drag to Slack chat |
| Videos draggable to Finder | Manual test: drag video card to Finder |
| Drag preview shows thumbnail | Visual inspection during drag |
| Setting respected | Toggle setting off, verify drag disabled |
| No interaction regressions | Verify hover, click, double-click still work |

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Some apps reject drag | Medium | Low | Provide multiple UTType representations |
| Drag interferes with hover | Low | Medium | Test interaction priority |
| Large files cause lag | Low | Low | File URL reference, not data copy |

## Security Considerations

- **File access**: Only exposing files already saved to disk by the app
- **No sensitive data**: Drag provides file URL, not raw image data in memory
- **Sandbox**: Respects macOS app sandbox (files in app-accessible locations)

## Next Steps

After implementation:
1. User acceptance testing with multiple external apps
2. Consider adding drag-out animation feedback
3. Document in user guide if needed
