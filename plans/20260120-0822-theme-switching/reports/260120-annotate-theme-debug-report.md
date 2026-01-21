# Annotate Theme Debug Report

**Date:** 2026-01-20
**Issue:** Annotate views not responding to theme changes (light/dark mode)

---

## Root Cause

**Primary Issue:** AnnotateMainView.swift forces dark mode via `.preferredColorScheme(.dark)` override (line 41), preventing theme switching.

**Secondary Issues:** Extensive use of hardcoded colors throughout annotation views using fixed white/black values instead of semantic colors.

---

## Critical Blocking Issue

### AnnotateMainView.swift
**Line 41:** `.preferredColorScheme(.dark)` — BLOCKS ALL THEME CHANGES

```swift
.background(Color(white: 0.12))
.preferredColorScheme(.dark)  // ← REMOVE THIS
```

This single line prevents entire annotation window from responding to ThemeManager changes.

---

## Hardcoded Colors by File

### 1. AnnotateMainView.swift
**Lines with hardcoded colors:**
- Line 19: `Color.white.opacity(0.1)` — divider
- Line 28: `Color.white.opacity(0.1)` — divider
- Line 36: `Color.white.opacity(0.1)` — divider
- Line 40: `Color(white: 0.12)` — background
- Line 41: `.preferredColorScheme(.dark)` — **CRITICAL: forces dark mode**

**Fix:**
```swift
// Replace line 40-41:
.background(Color(nsColor: .windowBackgroundColor))
// REMOVE: .preferredColorScheme(.dark)

// Replace dividers (lines 19, 28, 36):
.background(Color(nsColor: .separatorColor))
```

---

### 2. AnnotateToolbarView.swift
**Lines with hardcoded colors:**
- Line 47: `Color(white: 0.15)` — toolbar background
- Line 198: `highlightColor = .white` — default highlight
- Line 208: `.foregroundColor(isSelected ? highlightColor : .white)` — icon color
- Line 223: `Color.white.opacity(0.1)` — hover background
- Line 232: `Color.white.opacity(0.2)` — divider fill

**Fix:**
```swift
// Line 47 - toolbar background:
.background(Color(nsColor: .controlBackgroundColor))

// Line 198 - highlight color:
var highlightColor: Color = Color.primary

// Line 208 - icon foreground:
.foregroundColor(isSelected ? highlightColor : Color.primary)

// Line 223 - hover:
Color.primary.opacity(0.1)

// Line 232 - divider:
Color(nsColor: .separatorColor)
```

---

### 3. AnnotateSidebarView.swift
**Lines with hardcoded colors:**
- Line 25: `Color.white.opacity(0.1)` — divider
- Line 38: `Color.white.opacity(0.1)` — divider
- Line 43: `Color.white.opacity(0.1)` — divider
- Line 52: `Color(white: 0.1)` — sidebar background
- Line 65: `.foregroundColor(.white)` — "None" button text
- Line 70: `Color.white.opacity(0.1)` — none button background
- Line 133: `.solidColor(.white)` — auto-apply white background on padding
- Line 186: `Color.white` / `Color.white.opacity(0.2)` — color swatch stroke
- Line 205: `.foregroundColor(.white.opacity(0.6))` — slider label

**Fix:**
```swift
// Line 25, 38, 43 - dividers:
.background(Color(nsColor: .separatorColor))

// Line 52 - sidebar background:
.background(Color(nsColor: .controlBackgroundColor))

// Line 65 - button text:
.foregroundColor(.primary)

// Line 70 - button background:
Color.primary.opacity(0.1)

// Line 133 - auto-apply background (use semantic):
state.backgroundStyle = .solidColor(Color(nsColor: .textBackgroundColor))

// Line 186 - swatch stroke:
selectedColor == color ? Color.accentColor : Color.secondary.opacity(0.5)

// Line 205 - label:
.foregroundColor(.secondary)
```

---

### 4. AnnotateBottomBarView.swift
**Lines with hardcoded colors:**
- Line 31: `Color(white: 0.15)` — bottom bar background
- Line 47: `.foregroundColor(.white)` — zoom text
- Line 50: `.foregroundColor(.white.opacity(0.6))` — chevron icon
- Line 54: `Color.white.opacity(0.1)` — zoom background
- Line 65: `.foregroundColor(.white.opacity(0.6))` — drag handle text
- Line 68: `Color.white.opacity(0.05)` — drag handle background
- Line 131: `.foregroundColor(.white)` — button icon
- Line 135: `Color.white.opacity(0.15)` — button hover

**Fix:**
```swift
// Line 31 - bottom bar background:
.background(Color(nsColor: .controlBackgroundColor))

// Line 47, 131 - foreground:
.foregroundColor(.primary)

// Line 50, 65 - secondary text:
.foregroundColor(.secondary)

// Line 54, 68 - backgrounds:
Color.primary.opacity(0.1)
Color.primary.opacity(0.05)

// Line 135 - hover:
Color.primary.opacity(0.15)
```

---

### 5. AnnotateCanvasView.swift
**Lines with hardcoded colors:**
- Line 27: `Color(white: 0.08)` — canvas background

**Fix:**
```swift
// Line 27 - canvas background:
Color(nsColor: .textBackgroundColor)
```

---

### 6. AnnotateSidebarComponents.swift
**Lines with hardcoded colors:**
- Line 18: `.foregroundColor(.white.opacity(0.6))` — section header
- Line 37: `isSelected ? Color.white : Color.clear` — gradient preset stroke
- Line 70: `Color(white: 0.3/0.5/0.7/0.9)` — gray color swatches
- Line 103: `Color.white` / `Color.white.opacity(0.2)` — swatch stroke
- Line 121: `.foregroundColor(.white.opacity(0.6))` — slider label
- Line 156: `Color.white.opacity(0.05)` — alignment grid background
- Line 169: `Color.white.opacity(0.2)` — alignment cell fill

**Fix:**
```swift
// Line 18 - section header:
.foregroundColor(.secondary)

// Line 37 - gradient stroke:
isSelected ? Color.accentColor : Color.clear

// Line 70 - gray swatches (keep semantic grays):
[.gray, Color(nsColor: .labelColor), Color(nsColor: .secondaryLabelColor), ...]

// Line 103 - swatch stroke:
isSelected ? Color.accentColor : Color.secondary.opacity(0.5)

// Line 121 - slider label:
.foregroundColor(.secondary)

// Line 156 - grid background:
Color.secondary.opacity(0.1)

// Line 169 - cell fill:
Color.secondary.opacity(0.3)
```

---

### 7. TextStylingSection.swift
**Lines with hardcoded colors:**
- Line 38: `.foregroundColor(.white.opacity(0.6))` — size label
- Line 42: `.foregroundColor(.white.opacity(0.4))` — size value
- Line 61: `.foregroundColor(.white.opacity(0.6))` — text color label
- Line 75: `Color.white` / `Color.white.opacity(0.2)` — circle stroke
- Line 92: `.foregroundColor(.white.opacity(0.6))` — background label
- Line 100: `.foregroundColor(.white)` — "None" button text
- Line 105: `Color.white.opacity(0.1)` — "None" button background
- Line 121: `Color.white` / `Color.white.opacity(0.2)` — circle stroke

**Fix:**
```swift
// Line 38, 61, 92 - labels:
.foregroundColor(.secondary)

// Line 42 - value:
.foregroundColor(.tertiary)

// Line 75, 121 - circle stroke:
Color.accentColor : Color.secondary.opacity(0.5)

// Line 100 - "None" text:
.foregroundColor(.primary)

// Line 105 - "None" background:
Color.primary.opacity(0.1)
```

---

### 8. AnnotationPropertiesSection.swift
**Lines with hardcoded colors:**
- Line 58: `.foregroundColor(.white.opacity(0.6))` — color label
- Line 79: `.foregroundColor(.white.opacity(0.6))` — fill label
- Line 146: `Color.white.opacity(0.3)` — clear swatch stroke
- Line 150: `.foregroundColor(.white.opacity(0.5))` — xmark icon
- Line 158: `Color.white` / `Color.white.opacity(0.2)` — swatch stroke

**Fix:**
```swift
// Line 58, 79 - labels:
.foregroundColor(.secondary)

// Line 146 - clear swatch:
Color.secondary.opacity(0.5)

// Line 150 - xmark:
.foregroundColor(.secondary)

// Line 158 - swatch stroke:
selectedColor == color ? Color.accentColor : Color.secondary.opacity(0.5)
```

---

### 9. TextEditOverlay.swift
**Lines with hardcoded colors:**
- Line 51: `Color.white.opacity(0.1)` — editing background fill

**Fix:**
```swift
// Line 51 - editing background:
Color.primary.opacity(0.05)
```

---

### 10. CropOverlayView.swift
**Lines with hardcoded colors:**
- Line 34: `Color.white` — crop border stroke
- Line 41: `Color.black.opacity(0.5)` — dashed inner border
- Line 112: `Color.black.opacity(0.5)` — dim color constant
- Line 149: `Color.white` — handle fill

**Fix:**
```swift
// Line 34 - crop border:
Color.primary

// Line 41 - dashed border:
Color.secondary.opacity(0.8)

// Line 112 - dim overlay:
Color.black.opacity(0.5)  // Keep as-is (overlay effect)

// Line 149 - handle fill:
Color(nsColor: .controlBackgroundColor)
```

---

### 11. AnnotateDropZoneView.swift
**Lines with hardcoded colors:**
- Line 48: `Color(white: 0.08)` — drop zone background
- Line 56: `.preferredColorScheme(.dark)` — **BLOCKS theme in preview**

**Fix:**
```swift
// Line 48 - background:
Color(nsColor: .textBackgroundColor)

// Line 56 - REMOVE from preview:
// .preferredColorScheme(.dark)  // DELETE
```

---

### 12. AnnotateWindow.swift
**Status:** ✅ Already updated with theme support

Lines 45-48 correctly handle theme:
```swift
if themeManager.preferredAppearance == .light {
  backgroundColor = NSColor(white: 0.95, alpha: 1)
} else if themeManager.preferredAppearance == .dark {
  backgroundColor = NSColor(white: 0.12, alpha: 1)
```

**Issue:** Window applyTheme() called on init, but NOT called when theme changes at runtime.

**Fix needed:** Add theme change observer in AnnotateWindow or AnnotateWindowController.

---

### 13. AnnotationRenderer.swift (Canvas Rendering)
**Lines with hardcoded colors:**
- Line 175: `NSColor.white` — counter text (hardcoded white on colored background)
- Line 227: `NSColor.gray.cgColor` — blur fallback preview stroke

**Fix:**
```swift
// Line 175 - counter text (keep white - contrast on colored circle):
.foregroundColor: NSColor.white  // OK - fixed contrast need

// Line 227 - blur preview:
strokeColor: NSColor.secondaryLabelColor.cgColor
```

---

### 14. CanvasDrawingView.swift
**Lines with hardcoded colors:**
- Line 590: `NSColor.white.cgColor` — selection handle fill

**Fix:**
```swift
// Line 590 - handle fill:
context.setFillColor(NSColor.controlBackgroundColor.cgColor)
```

---

## Summary Statistics

**Total files with hardcoded colors:** 14
**Total hardcoded color instances:** 60+
**Critical blocking issues:** 2 (AnnotateMainView.preferredColorScheme, AnnotateDropZoneView preview)
**Window theme update:** Missing runtime observer

---

## Recommended Fix Priority

### P0 - Critical (Blocks Theme Switching)
1. **AnnotateMainView.swift line 41** — Remove `.preferredColorScheme(.dark)`
2. **AnnotateDropZoneView.swift line 56** — Remove `.preferredColorScheme(.dark)` from preview
3. **AnnotateWindow.swift** — Add theme change observer to call applyTheme()

### P1 - High (Major Visual Issues)
4. AnnotateMainView.swift — Replace all Color(white:) with semantic colors
5. AnnotateToolbarView.swift — Replace hardcoded backgrounds/foregrounds
6. AnnotateSidebarView.swift — Replace hardcoded backgrounds/foregrounds
7. AnnotateBottomBarView.swift — Replace hardcoded backgrounds/foregrounds
8. AnnotateCanvasView.swift — Replace canvas background

### P2 - Medium (UI Consistency)
9. AnnotateSidebarComponents.swift — Replace component colors
10. TextStylingSection.swift — Replace text styling UI colors
11. AnnotationPropertiesSection.swift — Replace properties UI colors
12. TextEditOverlay.swift — Replace editing overlay background
13. CropOverlayView.swift — Replace crop UI colors (keep overlay dim as-is)

### P3 - Low (Rendering Layer)
14. CanvasDrawingView.swift — Replace selection handle fill
15. AnnotationRenderer.swift — Replace blur fallback color (keep counter text white)

---

## Implementation Notes

### Semantic Color Mapping

**Dark Mode Colors → Semantic Equivalents:**
- `Color(white: 0.08-0.15)` → `Color(nsColor: .controlBackgroundColor)` or `.textBackgroundColor`
- `Color.white` (text) → `Color.primary` or `.foregroundColor(.primary)`
- `Color.white.opacity(0.6)` → `Color.secondary` or `.foregroundColor(.secondary)`
- `Color.white.opacity(0.1-0.2)` (bg) → `Color.primary.opacity(0.1)` or `.secondary.opacity(0.2)`
- Dividers → `Color(nsColor: .separatorColor)`
- Selection/Highlight → `Color.accentColor` (respects system accent)

### Theme Update Observer

Add to AnnotateWindow or AnnotateWindowController:

```swift
private var themeObserver: NSObjectProtocol?

func setupThemeObserver() {
  themeObserver = NotificationCenter.default.addObserver(
    forName: .themeDidChange,
    object: nil,
    queue: .main
  ) { [weak self] _ in
    self?.applyTheme()
  }
}

deinit {
  if let observer = themeObserver {
    NotificationCenter.default.removeObserver(observer)
  }
}
```

---

## Testing Checklist

After fixes:
- [ ] Switch to Light mode → all backgrounds/text readable
- [ ] Switch to Dark mode → all backgrounds/text readable
- [ ] Switch to Auto mode → follows system appearance
- [ ] Toolbar buttons visible in both modes
- [ ] Sidebar controls readable in both modes
- [ ] Canvas background appropriate in both modes
- [ ] Color pickers/swatches visible in both modes
- [ ] Text annotations readable in both modes
- [ ] Crop overlay visible in both modes
- [ ] Bottom bar controls visible in both modes

---

## Unresolved Questions

1. Should AnnotateWindow background follow semantic `windowBackgroundColor` or keep custom grays?
2. Should color picker swatches adapt to theme or stay fixed (current: white stroke)?
3. Counter annotation text: keep white for contrast or adapt (current: hardcoded white on colored circle)?

---

**End of Report**
