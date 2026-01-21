# Phase 02: Screenshot Stack Manager

## Context

- [Main Plan](./plan.md)
- [Phase 01: Floating Window Infrastructure](./phase-01-floating-window-infrastructure.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 260115 |
| Description | State management for screenshot stack with thumbnail generation and lifecycle |
| Priority | High |
| Status | `pending` |
| Estimated Effort | 2-3 hours |

## Requirements

1. **ScreenshotItem model** - holds URL, thumbnail, timestamp, unique ID
2. **Thumbnail generation** - efficient downscaling from full image
3. **Stack management** - add/remove items, max limit enforcement
4. **Auto-dismiss timer** - optional auto-removal after configurable timeout
5. **Observable state** - SwiftUI-compatible reactive updates
6. **Singleton access** - shared instance for global access

## Architecture

```
FloatingScreenshotManager (ObservableObject, @MainActor)
├── @Published items: [ScreenshotItem]
├── @Published position: FloatingPosition
├── @Published isVisible: Bool
├── maxVisibleItems: Int = 5
├── autoDismissDelay: TimeInterval = 10
├── panelController: FloatingPanelController
└── methods:
    ├── addScreenshot(url: URL)
    ├── removeScreenshot(id: UUID)
    ├── dismissAll()
    ├── copyToClipboard(id: UUID)
    ├── openInFinder(id: UUID)
    └── setPosition(_ position: FloatingPosition)

ScreenshotItem (Identifiable, Equatable)
├── id: UUID
├── url: URL
├── thumbnail: NSImage
├── capturedAt: Date
└── dismissTimer: Task<Void, Never>?

ThumbnailGenerator (utility)
└── static func generate(from url: URL, maxSize: CGFloat) async -> NSImage?
```

## Related Files

| File | Action | Purpose |
|------|--------|---------|
| `ZapShot/Features/FloatingScreenshot/ScreenshotItem.swift` | Create | Data model |
| `ZapShot/Features/FloatingScreenshot/ThumbnailGenerator.swift` | Create | Image downscaling |
| `ZapShot/Features/FloatingScreenshot/FloatingScreenshotManager.swift` | Create | State management |

## Implementation Steps

### Step 1: Create ScreenshotItem model

```swift
// ScreenshotItem.swift
import AppKit
import Foundation

struct ScreenshotItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let thumbnail: NSImage
    let capturedAt: Date

    init(url: URL, thumbnail: NSImage) {
        self.id = UUID()
        self.url = url
        self.thumbnail = thumbnail
        self.capturedAt = Date()
    }

    static func == (lhs: ScreenshotItem, rhs: ScreenshotItem) -> Bool {
        lhs.id == rhs.id
    }
}
```

### Step 2: Create ThumbnailGenerator

```swift
// ThumbnailGenerator.swift
import AppKit
import Foundation

enum ThumbnailGenerator {
    static func generate(from url: URL, maxSize: CGFloat = 200) async -> NSImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }

        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return nil }

        // Calculate scaled size maintaining aspect ratio
        let scale: CGFloat
        if originalSize.width > originalSize.height {
            scale = maxSize / originalSize.width
        } else {
            scale = maxSize / originalSize.height
        }

        let newSize = CGSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )

        // Create thumbnail
        let thumbnail = NSImage(size: newSize)
        thumbnail.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        thumbnail.unlockFocus()

        return thumbnail
    }
}
```

### Step 3: Create FloatingScreenshotManager

```swift
// FloatingScreenshotManager.swift
import AppKit
import Combine
import SwiftUI

@MainActor
final class FloatingScreenshotManager: ObservableObject {
    static let shared = FloatingScreenshotManager()

    @Published private(set) var items: [ScreenshotItem] = []
    @Published var position: FloatingPosition = .bottomRight
    @Published var autoDismissEnabled: Bool = true
    @Published var autoDismissDelay: TimeInterval = 10

    let maxVisibleItems = 5

    private let panelController = FloatingPanelController()
    private var dismissTimers: [UUID: Task<Void, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupBindings()
    }

    private func setupBindings() {
        // Update panel when items change
        $items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.updatePanel()
            }
            .store(in: &cancellables)

        // Reposition when position changes
        $position
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPosition in
                self?.panelController.updatePosition(newPosition)
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    func addScreenshot(url: URL) async {
        guard let thumbnail = await ThumbnailGenerator.generate(from: url) else { return }

        let item = ScreenshotItem(url: url, thumbnail: thumbnail)

        // Remove oldest if at max
        if items.count >= maxVisibleItems {
            if let oldestId = items.first?.id {
                removeScreenshot(id: oldestId)
            }
        }

        items.append(item)

        // Start auto-dismiss timer
        if autoDismissEnabled {
            startDismissTimer(for: item.id)
        }
    }

    func removeScreenshot(id: UUID) {
        cancelDismissTimer(for: id)
        items.removeAll { $0.id == id }

        if items.isEmpty {
            panelController.hide()
        }
    }

    func dismissAll() {
        for item in items {
            cancelDismissTimer(for: item.id)
        }
        items.removeAll()
        panelController.hide()
    }

    func copyToClipboard(id: UUID) {
        guard let item = items.first(where: { $0.id == id }),
              let image = NSImage(contentsOf: item.url) else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    func openInFinder(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: "")
    }

    func setPosition(_ newPosition: FloatingPosition) {
        position = newPosition
    }

    // MARK: - Private Methods

    private func updatePanel() {
        if items.isEmpty {
            panelController.hide()
        } else {
            // Panel content update handled by SwiftUI binding
            // Size calculation based on card count
            let cardHeight: CGFloat = 120
            let spacing: CGFloat = 8
            let padding: CGFloat = 12
            let width: CGFloat = 220
            let height = CGFloat(items.count) * cardHeight + CGFloat(items.count - 1) * spacing + padding * 2

            panelController.updateSize(CGSize(width: width, height: height))
        }
    }

    private func startDismissTimer(for id: UUID) {
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(self?.autoDismissDelay ?? 10) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.removeScreenshot(id: id)
            }
        }
        dismissTimers[id] = task
    }

    private func cancelDismissTimer(for id: UUID) {
        dismissTimers[id]?.cancel()
        dismissTimers.removeValue(forKey: id)
    }
}
```

## Todo List

- [ ] Implement `ScreenshotItem.swift`
- [ ] Implement `ThumbnailGenerator.swift`
- [ ] Implement `FloatingScreenshotManager.swift`
- [ ] Test thumbnail generation from PNG/JPEG
- [ ] Test stack add/remove logic
- [ ] Test max items enforcement (oldest removed)
- [ ] Test auto-dismiss timer
- [ ] Test copy to clipboard
- [ ] Test open in Finder

## Success Criteria

1. Thumbnail generated efficiently (< 50ms for typical screenshot)
2. Stack correctly limits to 5 items, removing oldest first
3. Auto-dismiss removes card after configured delay
4. Copy to clipboard works with full-resolution image
5. Open in Finder reveals file correctly
6. Memory stable - no leaks from thumbnail generation

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Memory bloat from thumbnails | Medium | High | Limit thumbnail size to 200px, max 5 items |
| Race condition on add/remove | Low | Medium | `@MainActor` ensures serial access |
| Timer leaks | Medium | Low | Cancel timers on remove, use weak self |
| File deleted before copy | Low | Low | Guard for file existence in copy method |
