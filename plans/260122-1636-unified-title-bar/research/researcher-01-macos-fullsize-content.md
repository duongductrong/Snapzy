# Research Report: macOS Full-Size Content View

## Overview
Research on macOS NSWindow full-size content view configuration for achieving seamless title bar integration where dark background extends behind traffic light buttons.

## Key Findings

### 1. NSWindow.styleMask Configuration
- Use `.fullSizeContentView` in styleMask to allow content to draw into title bar area
- Current implementation uses `[.titled, .closable, .miniaturizable, .resizable]`
- Need to add `.fullSizeContentView` to extend content behind title bar

### 2. Title Bar Transparency
- `titlebarAppearsTransparent = true` - Already implemented ✓
- `titleVisibility = .hidden` - Already implemented ✓
- These properties hide standard title bar, allowing custom content as primary visual

### 3. SwiftUI Content Extension
- Use `.ignoresSafeArea(.all, edges: .top)` modifier in SwiftUI views
- Ensures content extends to very top of window behind title bar
- Alternative: `HiddenTitleBarWindowStyle()` in WindowGroup lifecycle

### 4. Traffic Light Button Handling
**Spacing/Padding:**
- Account for safe area insets around traffic light buttons
- Use GeometryReader to determine safe area insets
- Traffic lights typically 78px wide (20px buttons + spacing)
- Height approximately 22px from top

**Common Patterns:**
- Add leading padding to toolbar content (typically 80px)
- Use `.safeAreaInset(edge: .top)` for custom title bar views
- Maintain minimum 20px top padding for traffic lights

### 5. Edge Cases & Best Practices

**Flickering Prevention:**
- Brief flicker may occur when window first appears
- Workaround: `DispatchQueue.main.async { window.orderOut(nil); window.makeKeyAndOrderFront(nil) }`

**Visual Artifacts:**
- Ensure background color extends to edges
- Test with both light/dark mode
- Verify traffic lights remain visible against background

**SwiftUI + AppKit Integration:**
- Configure NSWindow correctly for full-size content
- Manage sidebarTrackingSeparator in AppKit alongside SwiftUI layouts

## Sources
- Stack Overflow: NSWindow titlebar transparency
- Apple Developer Forums
- SwiftUI custom window tutorials
- Real-world macOS app implementations

## Recommendations
1. Add `.fullSizeContentView` to styleMask
2. Add safe area padding to toolbar views
3. Test thoroughly with light/dark themes
4. Verify traffic light visibility and spacing
