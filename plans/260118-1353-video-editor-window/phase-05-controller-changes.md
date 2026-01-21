# Phase 5: Controller Changes

## Context

- [Phase 5 Main](./phase-05-export-and-save.md)

## NSWindowDelegate Conformance

```swift
final class VideoEditorWindowController: NSWindowController, NSWindowDelegate {

    private let state: VideoEditorState
    private let quickAccessItemId: UUID?

    init(item: QuickAccessItem) {
        self.quickAccessItemId = item.id
        self.state = VideoEditorState(url: item.url)
        // ... existing init code ...
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard state.hasUnsavedChanges else { return true }
        showUnsavedChangesAlert(for: sender)
        return false
    }
}
```

## Save Actions

```swift
private func performSaveAndClose() {
    showSaveConfirmation()
}

private func replaceOriginal() {
    state.isExporting = true

    Task {
        do {
            try await VideoEditorExporter.replaceOriginal(
                asset: state.asset,
                timeRange: state.trimTimeRange,
                originalURL: state.sourceURL
            )
            state.markAsSaved()
            forceClose()
        } catch {
            showExportError(error)
        }
        state.isExporting = false
    }
}

private func saveAsCopy() {
    state.isExporting = true

    Task {
        do {
            _ = try await VideoEditorExporter.saveAsCopy(
                asset: state.asset,
                timeRange: state.trimTimeRange,
                originalURL: state.sourceURL
            )
            state.markAsSaved()
            forceClose()
        } catch {
            showExportError(error)
        }
        state.isExporting = false
    }
}

private func forceClose() {
    state.hasUnsavedChanges = false

    if let itemId = quickAccessItemId {
        QuickAccessManager.shared.removeItem(id: itemId)
    }

    window?.close()
}
```

## Keyboard Shortcut: Cmd+S

```swift
private func setupKeyboardShortcutObservers() {
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self = self,
              self.window?.isKeyWindow == true else { return event }

        // Cmd+S for save
        if event.modifierFlags.contains(.command) && event.keyCode == 1 {
            self.performSave()
            return nil
        }

        // Space for play/pause
        if event.keyCode == 49 && !event.modifierFlags.contains(.command) {
            self.state.togglePlayback()
            return nil
        }

        return event
    }
}

private func performSave() {
    guard state.hasUnsavedChanges else { return }
    showSaveConfirmation()
}
```
