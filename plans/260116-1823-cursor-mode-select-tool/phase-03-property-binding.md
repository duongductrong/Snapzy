# Phase 03: Property Binding

## Context Links
- [Main Plan](./plan.md)
- [Previous: Phase 02](./phase-02-hit-testing-enhancement.md)
- Related: `ZapShot/Features/Annotate/Views/AnnotateSidebarView.swift`
- Related: `ZapShot/Features/Annotate/State/AnnotateState.swift`

## Overview

| Field | Value |
|-------|-------|
| Date | 260116 |
| Description | Bidirectional property binding between sidebar and selected annotation |
| Priority | High |
| Status | Pending |
| Effort | 1 day |

## Key Insights

1. **TextStylingSection exists** - Already shows when `selectedTextAnnotation != nil`
2. **No general annotation panel** - Non-text annotations have no property UI when selected
3. **updateAnnotationProperties exists** - Supports fontSize, strokeColor, fillColor updates
4. **Need strokeWidth support** - Current method lacks strokeWidth parameter
5. **Bidirectional binding** - Sidebar must read AND write annotation properties

## Requirements

### Functional
- [ ] Show annotation properties section when any annotation selected
- [ ] Display current strokeColor of selected annotation
- [ ] Display current strokeWidth of selected annotation
- [ ] Display current fillColor of selected annotation (for shapes)
- [ ] Editing properties updates selected annotation immediately
- [ ] Deselecting hides annotation properties section

### Non-Functional
- [ ] Property changes trigger canvas redraw
- [ ] Smooth UI updates without flicker
- [ ] Consistent styling with existing sidebar sections

## Architecture

### Property Binding Flow

```
User selects annotation
       │
       ▼
AnnotateState.selectedAnnotationId set
       │
       ▼
Sidebar observes state, shows AnnotationPropertiesSection
       │
       ▼
Section reads properties from selectedAnnotation computed property
       │
       ▼
User changes color/width
       │
       ▼
Binding calls updateAnnotationProperties
       │
       ▼
Annotation updated, canvas redraws
```

### New Components

1. **AnnotationPropertiesSection** - New SwiftUI view for non-text annotation properties
2. **selectedAnnotation** computed property - Get any selected annotation (not just text)
3. **Extended updateAnnotationProperties** - Add strokeWidth parameter

## Related Code Files

| File | Change Type |
|------|-------------|
| `State/AnnotateState.swift` | Add computed property, extend update method |
| `Views/AnnotateSidebarView.swift` | Add AnnotationPropertiesSection |
| `Views/AnnotationPropertiesSection.swift` | New file - property editing UI |

## Implementation Steps

### Step 1: Add selectedAnnotation Computed Property

**File**: `ZapShot/Features/Annotate/State/AnnotateState.swift`

Add after `selectedTextAnnotation` (line ~269):

```swift
/// Get selected annotation (any type)
var selectedAnnotation: AnnotationItem? {
  guard let id = selectedAnnotationId else { return nil }
  return annotations.first { $0.id == id }
}
```

### Step 2: Extend updateAnnotationProperties Method

**File**: `ZapShot/Features/Annotate/State/AnnotateState.swift`

Update method signature (line ~210):

```swift
/// Update annotation properties (strokeWidth, fontSize, colors)
func updateAnnotationProperties(
  id: UUID,
  strokeWidth: CGFloat? = nil,
  fontSize: CGFloat? = nil,
  strokeColor: Color? = nil,
  fillColor: Color? = nil
) {
  guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }

  if let strokeWidth = strokeWidth {
    annotations[index].properties.strokeWidth = strokeWidth
  }
  if let fontSize = fontSize {
    annotations[index].properties.fontSize = fontSize
    // Recalculate bounds for new font size
    if case .text(let content) = annotations[index].type {
      annotations[index].bounds = calculateTextBounds(
        text: content,
        fontSize: fontSize,
        origin: annotations[index].bounds.origin
      )
    }
  }
  if let strokeColor = strokeColor {
    annotations[index].properties.strokeColor = strokeColor
  }
  if let fillColor = fillColor {
    annotations[index].properties.fillColor = fillColor
  }
}
```

### Step 3: Create AnnotationPropertiesSection

**File**: `ZapShot/Features/Annotate/Views/AnnotationPropertiesSection.swift` (new)

```swift
//
//  AnnotationPropertiesSection.swift
//  ZapShot
//
//  Sidebar section for editing selected annotation properties
//

import SwiftUI

/// Property editing section for selected annotations
struct AnnotationPropertiesSection: View {
  @ObservedObject var state: AnnotateState

  private var annotation: AnnotationItem? {
    state.selectedAnnotation
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SidebarSectionHeader(title: "Annotation")

      // Stroke color
      strokeColorPicker

      // Stroke width (for non-text)
      if !isTextAnnotation {
        strokeWidthSlider
      }

      // Fill color (for shapes)
      if supportsFilllColor {
        fillColorPicker
      }
    }
  }

  // MARK: - Computed Properties

  private var isTextAnnotation: Bool {
    guard let ann = annotation else { return false }
    if case .text = ann.type { return true }
    return false
  }

  private var supportsFilllColor: Bool {
    guard let ann = annotation else { return false }
    switch ann.type {
    case .rectangle, .oval: return true
    default: return false
    }
  }

  // MARK: - Subviews

  private var strokeColorPicker: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Color")
        .font(.system(size: 10))
        .foregroundColor(.white.opacity(0.6))

      ColorPickerRow(
        selectedColor: strokeColorBinding,
        colors: [.red, .orange, .yellow, .green, .blue, .purple, .white, .black]
      )
    }
  }

  private var strokeWidthSlider: some View {
    CompactSliderRow(
      label: "Stroke",
      value: strokeWidthBinding,
      range: 1...20
    )
  }

  private var fillColorPicker: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Fill")
        .font(.system(size: 10))
        .foregroundColor(.white.opacity(0.6))

      ColorPickerRow(
        selectedColor: fillColorBinding,
        colors: [.clear, .red, .orange, .yellow, .green, .blue, .purple, .white]
      )
    }
  }

  // MARK: - Bindings

  private var strokeColorBinding: Binding<Color> {
    Binding(
      get: { annotation?.properties.strokeColor ?? .red },
      set: { newColor in
        guard let id = state.selectedAnnotationId else { return }
        state.updateAnnotationProperties(id: id, strokeColor: newColor)
      }
    )
  }

  private var strokeWidthBinding: Binding<CGFloat> {
    Binding(
      get: { annotation?.properties.strokeWidth ?? 3 },
      set: { newWidth in
        guard let id = state.selectedAnnotationId else { return }
        state.updateAnnotationProperties(id: id, strokeWidth: newWidth)
      }
    )
  }

  private var fillColorBinding: Binding<Color> {
    Binding(
      get: { annotation?.properties.fillColor ?? .clear },
      set: { newColor in
        guard let id = state.selectedAnnotationId else { return }
        state.updateAnnotationProperties(id: id, fillColor: newColor)
      }
    )
  }
}

// MARK: - Supporting Views

struct ColorPickerRow: View {
  @Binding var selectedColor: Color
  let colors: [Color]

  var body: some View {
    HStack(spacing: 4) {
      ForEach(colors, id: \.self) { color in
        Button {
          selectedColor = color
        } label: {
          colorSwatch(color)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func colorSwatch(_ color: Color) -> some View {
    ZStack {
      if color == .clear {
        // Show "none" indicator for clear
        Circle()
          .stroke(Color.white.opacity(0.3), lineWidth: 1)
          .frame(width: 20, height: 20)
        Image(systemName: "xmark")
          .font(.system(size: 8))
          .foregroundColor(.white.opacity(0.5))
      } else {
        Circle()
          .fill(color)
          .frame(width: 20, height: 20)
          .overlay(
            Circle()
              .stroke(
                selectedColor == color ? Color.white : Color.white.opacity(0.2),
                lineWidth: selectedColor == color ? 2 : 1
              )
          )
      }
    }
  }
}
```

### Step 4: Integrate into AnnotateSidebarView

**File**: `ZapShot/Features/Annotate/Views/AnnotateSidebarView.swift`

Update body to show properties section (after ratioSection, around line 35):

```swift
// Text styling section (shown when text annotation is selected)
if state.selectedTextAnnotation != nil {
  Divider().background(Color.white.opacity(0.1))
  TextStylingSection(state: state)
}
// General annotation properties (non-text selected)
else if state.selectedAnnotation != nil {
  Divider().background(Color.white.opacity(0.1))
  AnnotationPropertiesSection(state: state)
}
```

## Todo List

- [ ] Add `selectedAnnotation` computed property to AnnotateState
- [ ] Extend `updateAnnotationProperties` with strokeWidth parameter
- [ ] Create `AnnotationPropertiesSection.swift` view
- [ ] Create `ColorPickerRow` component
- [ ] Integrate properties section into AnnotateSidebarView
- [ ] Test stroke color changes on selected annotation
- [ ] Test stroke width changes on selected annotation
- [ ] Test fill color changes on rectangles/ovals
- [ ] Verify text annotations still use TextStylingSection
- [ ] Verify deselection hides properties section

## Success Criteria

1. Selecting any annotation shows properties in sidebar
2. Stroke color picker updates annotation color immediately
3. Stroke width slider updates annotation thickness
4. Fill color picker works for rectangles and ovals
5. Text annotations show TextStylingSection (not AnnotationPropertiesSection)
6. Deselecting hides properties section
7. Canvas redraws on property changes

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Binding update lag | Low | Low | SwiftUI handles reactivity |
| Color comparison issues | Medium | Low | Use Color directly, not string |
| Missing canvas redraw | Low | Medium | @Published triggers view updates |

## Security Considerations

None - UI state management only.

## Next Steps

After completing this phase:
1. Proceed to [Phase 04: UX Enhancements](./phase-04-ux-enhancements.md)
2. Core selection/editing complete; polish with keyboard shortcuts and cursors
