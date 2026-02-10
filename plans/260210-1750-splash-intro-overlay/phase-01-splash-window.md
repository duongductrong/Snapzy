# Phase 1: Splash Window + Blur Setup

**Status:** Pending
**Plan:** [plan.md](./plan.md)

## Context Links

- [AreaSelectionWindow.swift](/Users/duongductrong/Developer/ZapShot/Snapzy/Core/AreaSelectionWindow.swift) - NSPanel pattern reference
- [RecordingRegionOverlayWindow.swift](/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Recording/RecordingRegionOverlayWindow.swift) - Overlay window pattern reference

## Overview

Create `SplashWindow.swift` containing two types: `SplashWindowController` (singleton manager) and `SplashWindow` (NSPanel subclass). The window covers the main screen with a transparent background, layers an NSVisualEffectView for blur, and hosts SwiftUI content via NSHostingView.

## Key Insights

- Existing NSPanel overlays use `[.borderless, .nonactivatingPanel]` style, `isOpaque = false`, `backgroundColor = .clear`
- Unlike area selection (`.screenSaver` level), splash uses `.floating` -- high enough to be visible, low enough to not block system UI
- NSVisualEffectView with `.behindWindow` blending provides native macOS blur. Animating its `alphaValue` from 0 to 1 creates the blur fade-in effect
- The splash window SHOULD become key (unlike area selection panels) because user needs to click the Continue button

## Requirements

1. Fullscreen NSPanel covering `NSScreen.main` frame
2. Transparent background initially (`backgroundColor = .clear`, `isOpaque = false`)
3. NSVisualEffectView as background layer, starting at `alphaValue = 0`
4. NSHostingView on top hosting `SplashContentView`
5. `SplashWindowController` singleton with `show()` and `dismiss(completion:)` methods
6. Fade-out animation on dismiss using `NSAnimationContext.runAnimationGroup`

## Architecture

```
SplashWindowController (@MainActor, static let shared)
  |-- splashWindow: SplashWindow?
  |-- show()              // creates window, orders front, triggers content animation
  |-- dismiss(completion:) // fades out window, then calls completion, then cleans up

SplashWindow (NSPanel)
  |-- blurView: NSVisualEffectView  (alphaValue animated 0 -> 1)
  |-- hostingView: NSHostingView<SplashContentView>  (on top of blur)
  |-- canBecomeKey: true   (user must click button)
  |-- canBecomeMain: false
```

## Related Code Files

| File | Relevance |
|------|-----------|
| `Snapzy/Core/AreaSelectionWindow.swift` | NSPanel config pattern (lines 281-316) |
| `Snapzy/Features/Recording/RecordingRegionOverlayWindow.swift` | Simpler NSPanel config (lines 43-71) |

## Implementation Steps

### Step 1: Create file and SplashWindow class (~40 lines)

File: `Snapzy/Features/Splash/SplashWindow.swift`

```swift
import AppKit
import SwiftUI

/// Fullscreen splash overlay panel with blur background
final class SplashWindow: NSPanel {
  let blurView: NSVisualEffectView

  init(screen: NSScreen) {
    self.blurView = NSVisualEffectView()

    super.init(
      contentRect: screen.frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    configureWindow()
    setupViews(screen: screen)
  }

  private func configureWindow() {
    isFloatingPanel = true
    isOpaque = false
    backgroundColor = .clear
    level = .floating
    hasShadow = false
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    animationBehavior = .none
  }

  private func setupViews(screen: NSScreen) {
    let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))

    // Blur background (starts invisible)
    blurView.frame = container.bounds
    blurView.autoresizingMask = [.width, .height]
    blurView.blendingMode = .behindWindow
    blurView.material = .fullScreenUI
    blurView.state = .active
    blurView.alphaValue = 0
    container.addSubview(blurView)

    self.contentView = container
  }

  /// Attach SwiftUI content on top of blur
  func attachContent(_ view: some View) {
    guard let container = contentView else { return }
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = container.bounds
    hostingView.autoresizingMask = [.width, .height]
    // Transparent background so blur shows through
    hostingView.layer?.backgroundColor = .clear
    container.addSubview(hostingView)
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
```

### Step 2: Create SplashWindowController (~60 lines)

```swift
/// Manages splash window lifecycle -- show on launch, dismiss on continue
@MainActor
final class SplashWindowController {
  static let shared = SplashWindowController()

  private var splashWindow: SplashWindow?

  private init() {}

  /// Show splash on main screen. Calls onContinue when user taps Continue.
  func show(onContinue: @escaping () -> Void) {
    guard let screen = NSScreen.main else { return }

    let window = SplashWindow(screen: screen)
    self.splashWindow = window

    let contentView = SplashContentView(
      onContinue: { [weak self] in
        self?.dismiss(completion: onContinue)
      }
    )
    window.attachContent(contentView)

    // Show window
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    // Animate blur in after brief delay (content view controls its own animation)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      self.animateBlurIn()
    }
  }

  private func animateBlurIn() {
    guard let window = splashWindow else { return }
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.6
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      window.blurView.animator().alphaValue = 1.0
    })
  }

  /// Fade out and clean up
  func dismiss(completion: @escaping () -> Void) {
    guard let window = splashWindow else {
      completion()
      return
    }

    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.4
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      window.animator().alphaValue = 0
    }, completionHandler: { [weak self] in
      window.orderOut(nil)
      window.close()
      self?.splashWindow = nil
      completion()
    })
  }
}
```

## Todo List

- [ ] Create `Snapzy/Features/Splash/` directory
- [ ] Create `SplashWindow.swift` with `SplashWindow` class
- [ ] Add `SplashWindowController` to same file
- [ ] Verify blur material looks good on both light/dark mode
- [ ] Test fade-in/fade-out animations

## Success Criteria

- [x] Window covers full main screen
- [x] Background starts fully transparent (see-through)
- [x] Blur fades in smoothly after 0.3s delay
- [x] Window dismisses with fade-out animation
- [x] Completion callback fires after fade-out completes
- [x] File stays under 120 lines

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| NSHostingView background not transparent | Medium | Set `layer?.backgroundColor = .clear` on hosting view |
| Blur material too dark/light | Low | Use `.fullScreenUI` material; test both appearances |
| Window doesn't receive clicks | Medium | `canBecomeKey = true` ensures button interaction works |

## Next Steps

Proceed to [Phase 2](./phase-02-splash-content-view.md) to build the animated SwiftUI content.
