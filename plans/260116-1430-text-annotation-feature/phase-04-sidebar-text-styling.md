# Phase 04: Sidebar Text Styling

**Parent Plan:** [plan.md](./plan.md)
**Date:** 2026-01-16
**Priority:** Medium
**Status:** Pending
**Review Status:** Pending

## Overview

Add text-specific styling controls to the sidebar. When a text annotation is selected, show font size slider, text color picker, and background color picker.

## Dependencies

- [Phase 03: Text Rendering Enhancement](./phase-03-text-rendering-enhancement.md)

## Key Insights

- Sidebar currently shows background/padding controls
- Need conditional section when text annotation selected
- Reuse existing ColorSwatchGrid component for colors
- Properties stored in `AnnotationProperties` (fontSize, strokeColor, fillColor)

## Requirements

1. Detect when selected annotation is text type
2. Show text styling section in sidebar
3. Font size slider (12-72pt range)
4. Text color picker (using strokeColor)
5. Background color picker (using fillColor, including transparent)
6. Changes update annotation properties in real-time

## Architecture

```
AnnotateSidebarView
  ├── Existing sections (gradients, colors, sliders)
  └── TextStylingSection (conditional)
        ├── SidebarSectionHeader("Text Style")
        ├── FontSizeSlider
        ├── TextColorPicker
        └── BackgroundColorPicker
```

## Related Code Files

| File | Purpose |
|------|---------|
| `AnnotateSidebarView.swift` | Main sidebar view |
| `AnnotateSidebarComponents.swift` | Reusable components |
| `AnnotateState.swift:118-119` | selectedAnnotationId |
| `AnnotationItem.swift:45-65` | AnnotationProperties |

## Implementation Steps

### Step 1: Add helper to get selected text annotation

```swift
// AnnotateState.swift - add computed property
var selectedTextAnnotation: AnnotationItem? {
  guard let id = selectedAnnotationId,
        let annotation = annotations.first(where: { $0.id == id }),
        case .text = annotation.type else {
    return nil
  }
  return annotation
}
```

### Step 2: Add property update method

```swift
// AnnotateState.swift - add method
func updateAnnotationProperties(id: UUID, fontSize: CGFloat? = nil, strokeColor: Color? = nil, fillColor: Color? = nil) {
  guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }

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

### Step 3: Create TextStylingSection component

```swift
// AnnotateSidebarSections.swift - add new section
struct TextStylingSection: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    if let annotation = state.selectedTextAnnotation {
      VStack(alignment: .leading, spacing: 10) {
        SidebarSectionHeader(title: "Text Style")

        // Font size slider
        fontSizeSlider(for: annotation)

        // Text color
        textColorPicker(for: annotation)

        // Background color
        backgroundColorPicker(for: annotation)
      }
    }
  }

  private func fontSizeSlider(for annotation: AnnotationItem) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text("Size")
          .font(.system(size: 10))
          .foregroundColor(.white.opacity(0.6))
        Spacer()
        Text("\(Int(annotation.properties.fontSize))pt")
          .font(.system(size: 10))
          .foregroundColor(.white.opacity(0.4))
      }
      Slider(
        value: Binding(
          get: { annotation.properties.fontSize },
          set: { state.updateAnnotationProperties(id: annotation.id, fontSize: $0) }
        ),
        in: 12...72,
        step: 1
      )
      .controlSize(.small)
    }
  }

  private func textColorPicker(for annotation: AnnotationItem) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Text Color")
        .font(.system(size: 10))
        .foregroundColor(.white.opacity(0.6))

      CompactColorSwatchGrid(
        selectedColor: Binding(
          get: { annotation.properties.strokeColor },
          set: { if let color = $0 { state.updateAnnotationProperties(id: annotation.id, strokeColor: color) } }
        )
      )
    }
  }

  private func backgroundColorPicker(for annotation: AnnotationItem) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Background")
        .font(.system(size: 10))
        .foregroundColor(.white.opacity(0.6))

      HStack(spacing: 4) {
        // None/transparent button
        Button {
          state.updateAnnotationProperties(id: annotation.id, fillColor: .clear)
        } label: {
          Text("None")
            .font(.system(size: 9))
            .foregroundColor(.white)
            .frame(width: 36, height: 24)
            .background(
              RoundedRectangle(cornerRadius: 4)
                .fill(annotation.properties.fillColor == .clear ? Color.blue.opacity(0.3) : Color.white.opacity(0.1))
            )
        }
        .buttonStyle(.plain)

        // Color swatches
        ForEach([Color.white, Color.black, Color.yellow, Color.blue], id: \.self) { color in
          Button {
            state.updateAnnotationProperties(id: annotation.id, fillColor: color)
          } label: {
            Circle()
              .fill(color)
              .frame(width: 24, height: 24)
              .overlay(
                Circle()
                  .stroke(annotation.properties.fillColor == color ? Color.white : Color.white.opacity(0.2), lineWidth: 1)
              )
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}
```

### Step 4: Integrate into AnnotateSidebarView

```swift
// AnnotateSidebarView.swift - add section
var body: some View {
  ScrollView(.vertical, showsIndicators: true) {
    VStack(alignment: .leading, spacing: 12) {
      // Existing sections...
      noneButton
      gradientSection
      colorSection

      Divider().background(Color.white.opacity(0.1))

      slidersSection
      alignmentSection
      ratioSection

      // NEW: Text styling section (conditional)
      if state.selectedTextAnnotation != nil {
        Divider().background(Color.white.opacity(0.1))
        TextStylingSection(state: state)
      }

      Spacer(minLength: 20)
    }
    .padding(12)
  }
  // ...
}
```

## Todo List

- [ ] Add selectedTextAnnotation computed property
- [ ] Add updateAnnotationProperties method
- [ ] Create TextStylingSection component
- [ ] Add font size slider
- [ ] Add text color picker
- [ ] Add background color picker with "None" option
- [ ] Integrate section into AnnotateSidebarView
- [ ] Test real-time property updates
- [ ] Test bounds recalculation on font size change

## Success Criteria

- [ ] Text styling section appears when text annotation selected
- [ ] Font size slider updates text size in real-time
- [ ] Text color picker changes strokeColor
- [ ] Background picker changes fillColor
- [ ] "None" option sets transparent background
- [ ] Section hides when non-text annotation selected

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Binding updates cause performance issues | Low | State updates are lightweight |
| Font size change breaks layout | Medium | Recalculate bounds on size change |

## Security Considerations

None - UI controls only.

## Next Steps

After completing this phase, proceed to [Phase 05: Polish & Testing](./phase-05-polish-testing.md) for final refinements.
