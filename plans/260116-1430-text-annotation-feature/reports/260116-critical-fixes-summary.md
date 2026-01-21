# Critical Fixes Required - Text Annotation Feature

**Date:** 2026-01-16
**Priority:** HIGH
**Estimated Time:** 1-2 hours

---

## Critical Issue: Potential Memory Leak

**File:** `TextEditOverlay.swift`
**Lines:** 54-59
**Risk:** Medium (SwiftUI views are value types, but @ObservedObject holds reference)

### Current Code:
```swift
.onChange(of: isFocused) { _, newValue in
  // Commit when focus is lost
  if !newValue && state.editingTextAnnotationId == editingId {
    commitEdit(id: editingId)
  }
}
```

### Recommended Fix:
```swift
.onChange(of: isFocused) { [weak state] _, newValue in
  guard let state = state else { return }
  if !newValue && state.editingTextAnnotationId == editingId {
    commitEdit(id: editingId)
  }
}
```

**Alternative:** Test memory deallocation to confirm if fix needed. SwiftUI views being value types may mitigate this.

---

## High Priority Fix #1: Y-Axis Coordinate Validation

**File:** `TextEditOverlay.swift`
**Lines:** 64-78
**Risk:** High (misalignment at edges, extreme zoom)

### Issue:
- No bounds validation after coordinate transformation
- Complex Y-flip calculation prone to edge case bugs
- No assertions for debugging invalid states

### Recommended Implementation:
```swift
private func calculateDisplayBounds(_ imageBounds: CGRect) -> CGRect {
  // Document coordinate system clearly
  // Image coordinates: bottom-left origin (AppKit)
  // Display coordinates: top-left origin (SwiftUI)

  let displayX = imageBounds.origin.x * scale + imageOffset.x + imageSize.width / 2

  // Flip Y: convert from bottom-left to top-left origin
  let flippedY = imageSize.height - imageBounds.origin.y - imageBounds.height
  let displayY = flippedY * scale + imageOffset.y + imageSize.height / 2

  let rect = CGRect(
    x: displayX,
    y: displayY,
    width: imageBounds.width * scale,
    height: imageBounds.height * scale
  )

  // Validate bounds (helps catch coordinate bugs early)
  assert(rect.width > 0 && rect.height > 0, "Invalid display bounds: \(rect)")

  return rect
}
```

**Test Cases Needed:**
- Text at (0, 0)
- Text at (imageWidth, imageHeight)
- Zoom 0.25x with text editing
- Zoom 3.0x with text editing
- Padding 200pt with text at edges

---

## High Priority Fix #2: Text Bounds Calculation Safety

**File:** `AnnotateState.swift`
**Lines:** 233-247
**Risk:** Medium (potential crash, unbounded text size)

### Issues:
1. No font creation validation
2. No maximum size constraints
3. Could create massive annotations (performance/memory)

### Recommended Implementation:
```swift
private func calculateTextBounds(text: String, fontSize: CGFloat, origin: CGPoint) -> CGRect {
  // Clamp font size to reasonable range (prevent extreme values)
  let clampedFontSize = min(max(fontSize, 8), 144)

  // Safe font creation with fallback
  let font = NSFont.systemFont(ofSize: clampedFontSize)
  let attributes: [NSAttributedString.Key: Any] = [.font: font]

  let displayText = text.isEmpty ? "Text" : text
  let size = (displayText as NSString).size(withAttributes: attributes)
  let padding: CGFloat = 4

  // Enforce maximum bounds (prevent performance issues)
  let maxWidth: CGFloat = 2000
  let maxHeight: CGFloat = 500

  return CGRect(
    x: origin.x,
    y: origin.y,
    width: min(size.width + padding * 2, maxWidth),
    height: min(size.height + padding * 2, maxHeight)
  )
}
```

**Reasoning:**
- Font size range 8-144pt covers all practical use cases
- Max width 2000pt ≈ reasonable for 4K displays
- Max height 500pt ≈ ~15 lines of large text
- Prevents accidentally creating multi-megapixel text annotations

---

## Medium Priority Improvements

### 1. Extract Magic Number
**File:** `TextEditOverlay.swift:33`
```swift
private let minTextFieldWidth: CGFloat = 80 // Minimum comfortable typing width
.frame(minWidth: max(displayBounds.width, minTextFieldWidth))
```

### 2. Document Color Comparison
**File:** `TextStylingSection.swift:142-146`
```swift
/// Compare colors for UI selection state
/// Note: Uses SwiftUI Color equality. May have precision limits across color spaces.
private func colorsMatch(_ a: Color, _ b: Color) -> Bool {
  return a == b
}
```

---

## Action Plan

1. **Immediate (Critical):**
   - [ ] Test TextEditOverlay deallocation with Instruments
   - [ ] If leaks detected, apply weak capture fix

2. **Before Next Release (High):**
   - [ ] Implement calculateDisplayBounds validation
   - [ ] Add edge case tests (boundaries, extreme zoom)
   - [ ] Implement calculateTextBounds safety constraints
   - [ ] Test with 200+ character strings

3. **Code Quality (Medium):**
   - [ ] Extract minTextFieldWidth constant
   - [ ] Add color comparison documentation

4. **Verification:**
   - [ ] Run full test suite
   - [ ] Manual QA on edge cases
   - [ ] Confirm build still succeeds

---

## Estimated Impact

**Without Fixes:**
- Potential memory leak (low probability but high impact if occurs)
- Text overlay misalignment at image boundaries (medium probability)
- App crash with extreme font sizes (low probability)
- Performance degradation with massive text annotations (low probability)

**With Fixes:**
- ✅ Production-ready code
- ✅ Defensive against edge cases
- ✅ Better debugging capabilities (assertions)
- ✅ Predictable performance characteristics

---

## Next Steps

Use `/fix` skill to address these issues systematically, starting with high-priority coordinate validation and bounds safety.
