# Phase 04: Video Editor Placeholder

**Date:** 2026-01-17
**Priority:** Medium
**Status:** Pending

## Context Links

- [Plan Overview](./plan.md)
- [Scout Report: AnnotateManager Pattern](./scout/scout-01-codebase-analysis.md)

## Overview

Create placeholder VideoEditor feature following the AnnotateManager pattern. Displays "Coming Soon" message when user double-clicks a video card.

## Requirements

### Functional
- Open placeholder window on video double-click
- Show video filename and "Coming Soon" message
- Single window per video (reuse if already open)
- Close button to dismiss

### Non-Functional
- Follow AnnotateManager singleton pattern
- Dark mode appearance matching AnnotateWindow
- Minimal implementation (placeholder only)

## Related Code Files

### Files to Create
| File | Action | Description |
|------|--------|-------------|
| `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/VideoEditor/VideoEditorManager.swift` | CREATE | Singleton manager |
| `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/VideoEditor/VideoEditorWindow.swift` | CREATE | Window configuration |
| `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/VideoEditor/VideoEditorWindowController.swift` | CREATE | Window controller |
| `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/VideoEditor/VideoEditorPlaceholderView.swift` | CREATE | Placeholder UI |

## Implementation Steps

### Step 1: Create VideoEditor directory

Create folder at: `ZapShot/Features/VideoEditor/`

### Step 2: Create VideoEditorManager.swift

```swift
//
//  VideoEditorManager.swift
//  ZapShot
//
//  Singleton manager for video editor windows (placeholder)
//

import AppKit
import Foundation

/// Manages video editor window instances
@MainActor
final class VideoEditorManager {

  static let shared = VideoEditorManager()

  private var windowControllers: [UUID: VideoEditorWindowController] = [:]

  private init() {}

  /// Open video editor for a quick access item
  func openEditor(for item: QuickAccessItem) {
    guard item.isVideo else { return }

    // Reuse existing window if open
    if let existing = windowControllers[item.id] {
      existing.showWindow()
      return
    }

    let controller = VideoEditorWindowController(item: item)
    windowControllers[item.id] = controller

    // Remove from tracking when window closes
    let itemId = item.id
    if let window = controller.window {
      NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.windowControllers.removeValue(forKey: itemId)
        }
      }
    }

    controller.showWindow()
  }

  /// Close all video editor windows
  func closeAll() {
    for controller in windowControllers.values {
      controller.window?.close()
    }
    windowControllers.removeAll()
  }
}
```

### Step 3: Create VideoEditorWindow.swift

```swift
//
//  VideoEditorWindow.swift
//  ZapShot
//
//  Dark mode video editor window configuration
//

import AppKit

/// Custom NSWindow for video editing with dark mode appearance
final class VideoEditorWindow: NSWindow {

  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    configure()
  }

  private func configure() {
    appearance = NSAppearance(named: .darkAqua)
    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    backgroundColor = NSColor(white: 0.12, alpha: 1)
    minSize = NSSize(width: 400, height: 300)
    isReleasedWhenClosed = false
    center()
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}
```

### Step 4: Create VideoEditorWindowController.swift

```swift
//
//  VideoEditorWindowController.swift
//  ZapShot
//
//  Controller managing video editor window lifecycle
//

import AppKit
import SwiftUI

/// Manages video editor window lifecycle
@MainActor
final class VideoEditorWindowController: NSWindowController {

  private let item: QuickAccessItem

  init(item: QuickAccessItem) {
    self.item = item

    let screen = NSScreen.main ?? NSScreen.screens.first!
    let windowWidth: CGFloat = 500
    let windowHeight: CGFloat = 350

    let origin = NSPoint(
      x: (screen.frame.width - windowWidth) / 2,
      y: (screen.frame.height - windowHeight) / 2
    )

    let window = VideoEditorWindow(
      contentRect: NSRect(origin: origin, size: NSSize(width: windowWidth, height: windowHeight))
    )

    super.init(window: window)

    setupContent()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupContent() {
    let placeholderView = VideoEditorPlaceholderView(videoName: item.url.lastPathComponent)
    window?.contentView = NSHostingView(rootView: placeholderView)
  }

  func showWindow() {
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}
```

### Step 5: Create VideoEditorPlaceholderView.swift

```swift
//
//  VideoEditorPlaceholderView.swift
//  ZapShot
//
//  Placeholder view for video editor (coming soon)
//

import SwiftUI

/// Placeholder view displayed when video editor is not yet implemented
struct VideoEditorPlaceholderView: View {
  let videoName: String

  var body: some View {
    VStack(spacing: 24) {
      Spacer()

      // Video icon
      Image(systemName: "film")
        .font(.system(size: 64))
        .foregroundColor(.secondary)

      // Title
      Text("Video Editor")
        .font(.title)
        .fontWeight(.semibold)
        .foregroundColor(.primary)

      // Coming soon message
      Text("Coming Soon")
        .font(.title2)
        .foregroundColor(.secondary)

      // Video filename
      Text(videoName)
        .font(.caption)
        .foregroundColor(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, 40)

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(NSColor.windowBackgroundColor))
  }
}
```

## Todo List

- [ ] Create `VideoEditor` directory in Features
- [ ] Create `VideoEditorManager.swift`
- [ ] Create `VideoEditorWindow.swift`
- [ ] Create `VideoEditorWindowController.swift`
- [ ] Create `VideoEditorPlaceholderView.swift`
- [ ] Verify project compiles
- [ ] Test double-click opens placeholder window

## Success Criteria

- [ ] Double-click video card opens placeholder window
- [ ] Window shows "Coming Soon" message
- [ ] Video filename displayed
- [ ] Window can be closed
- [ ] Same video reuses existing window
- [ ] Dark mode appearance matches app style

## Next Steps

Proceed to [Phase 05: Recording Integration](./phase-05-recording-integration.md).
