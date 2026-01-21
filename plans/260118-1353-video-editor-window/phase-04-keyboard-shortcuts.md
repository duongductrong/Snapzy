# Phase 4: Keyboard Shortcuts

## Context

- [Phase 4 Main](./phase-04-controls-and-info-panel.md)

## Space Key for Play/Pause

In VideoEditorWindowController, add key monitoring:

```swift
override func keyDown(with event: NSEvent) {
    if event.keyCode == 49 { // Space key
        state.togglePlayback()
    } else {
        super.keyDown(with: event)
    }
}
```

## Alternative: Local Event Monitor

Use in setupContent() for more reliable key capture:

```swift
private var keyMonitor: Any?

private func setupKeyboardMonitor() {
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self = self,
              self.window?.isKeyWindow == true else { return event }

        // Space for play/pause (no modifiers)
        if event.keyCode == 49 && !event.modifierFlags.contains(.command) {
            self.state.togglePlayback()
            return nil
        }

        return event
    }
}

deinit {
    if let monitor = keyMonitor {
        NSEvent.removeMonitor(monitor)
    }
}
```

## Key Codes Reference

| Key | Code |
|-----|------|
| Space | 49 |
| S | 1 |
| Left Arrow | 123 |
| Right Arrow | 124 |
