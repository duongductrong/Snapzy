# macOS Theming for Screenshot/Annotation Apps

## Executive Summary

macOS theming at window level requires AppKit's `NSWindow` for deep control. Special considerations for overlay windows, floating panels, and screen capture UI.

## Key Findings

### Window-Level Theming
- `NSWindow` provides extensive customization (title bars, transparency, visual effects)
- `NSVisualEffectView` for vibrancy/blur effects with semantic materials
- Window `appearance` property can override system appearance per-window

### Special Window Types
1. **Overlay Windows**: Need correct window level management
2. **Floating Panels**: Custom title bar handling
3. **Screen Capture UI**: Must work in both themes without affecting capture

### AppKit + SwiftUI Integration
- Use `NSHostingView` to embed SwiftUI in AppKit windows
- Access underlying `NSWindow` for advanced theming
- Ensure unified approach to avoid inconsistent theming

### Code Pattern for Custom Window

```swift
class CustomWindow: NSWindow {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect,
                   styleMask: [.closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: backingStoreType, defer: flag)

        self.titleVisibility = .hidden
        self.isMovableByWindowBackground = true
        self.backgroundColor = .clear
    }
}
```

### NSWindow Appearance Override

```swift
// Force specific appearance on window
window.appearance = NSAppearance(named: .darkAqua) // or .aqua for light
// nil = follow system
window.appearance = nil
```

### Common Pitfalls
- Mixing AppKit/SwiftUI without unified theme management
- Performance issues with heavy transparency/blur
- Window level conflicts for overlays

## References
- [Apple: NSWindow](https://developer.apple.com/documentation/appkit/nswindow)
- [Apple: NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview)
