# Phase 02: Window Delegate for Close Confirmation

**Status:** Completed
**File:** `ZapShot/Features/Annotate/Window/AnnotateWindowController.swift`

## Objective

Implement `NSWindowDelegate` to intercept window close and show confirmation dialog when unsaved changes exist.

## Current State Analysis

- `AnnotateWindowController` manages window lifecycle (lines 14-163)
- Two init paths: `init(item:)` for QuickAccessItem, `init()` for empty/drag-drop
- Window close tracked via `NSWindow.willCloseNotification` in `AnnotateManager`
- No current delegate conformance

## Implementation

### Step 1: Add NSWindowDelegate Conformance

```swift
// Change line 14 class declaration
@MainActor
final class AnnotateWindowController: NSWindowController, NSWindowDelegate {
```

### Step 2: Set Delegate in Both Init Paths

```swift
// In init(item:) after super.init(window: window), around line 45
window.delegate = self

// In init() after super.init(window: window), around line 68
window.delegate = self
```

### Step 3: Implement windowShouldClose

```swift
// Add after showWindow() method, around line 130

// MARK: - NSWindowDelegate

func windowShouldClose(_ sender: NSWindow) -> Bool {
  guard state.hasUnsavedChanges else {
    return true  // No unsaved changes, allow close
  }

  showUnsavedChangesAlert(for: sender)
  return false  // Prevent immediate close, alert will handle it
}

private func showUnsavedChangesAlert(for window: NSWindow) {
  let alert = NSAlert()
  alert.messageText = "Unsaved Changes"
  alert.informativeText = "You have unsaved changes. Do you want to save before closing?"
  alert.alertStyle = .warning

  alert.addButton(withTitle: "Save")
  alert.addButton(withTitle: "Don't Save")
  alert.addButton(withTitle: "Cancel")

  alert.beginSheetModal(for: window) { [weak self] response in
    guard let self = self else { return }

    switch response {
    case .alertFirstButtonReturn:
      // Save - trigger done action then close
      self.performSaveAndClose()

    case .alertSecondButtonReturn:
      // Don't Save - close without saving
      self.forceClose()

    default:
      // Cancel - do nothing, stay open
      break
    }
  }
}

private func performSaveAndClose() {
  // If we have source URL, show replace/copy dialog (same as Done button)
  if let sourceURL = state.sourceURL {
    showSaveConfirmation(for: sourceURL)
  } else {
    // No source URL - show save panel
    AnnotateExporter.saveAs(state: state, closeWindow: true)
  }
}

private func showSaveConfirmation(for sourceURL: URL) {
  guard let window = self.window else { return }

  let alert = NSAlert()
  alert.messageText = "Save Changes"
  alert.informativeText = "How would you like to save your changes to \"\(sourceURL.lastPathComponent)\"?"
  alert.alertStyle = .informational

  alert.addButton(withTitle: "Replace Original")
  alert.addButton(withTitle: "Save as Copy")
  alert.addButton(withTitle: "Cancel")

  alert.beginSheetModal(for: window) { [weak self] response in
    guard let self = self else { return }

    switch response {
    case .alertFirstButtonReturn:
      // Replace original
      AnnotateExporter.saveToOriginal(state: self.state)
      self.state.markAsSaved()
      self.forceClose()

    case .alertSecondButtonReturn:
      // Save as copy
      let copyURL = self.generateCopyURL(from: sourceURL)
      AnnotateExporter.save(state: self.state, to: copyURL)
      self.state.markAsSaved()
      self.forceClose()

    default:
      // Cancel - do nothing
      break
    }
  }
}

private func generateCopyURL(from originalURL: URL) -> URL {
  let directory = originalURL.deletingLastPathComponent()
  let baseName = originalURL.deletingPathExtension().lastPathComponent
  let ext = originalURL.pathExtension

  var copyNumber = 1
  var newURL = directory.appendingPathComponent("\(baseName)_copy.\(ext)")

  while FileManager.default.fileExists(atPath: newURL.path) {
    copyNumber += 1
    newURL = directory.appendingPathComponent("\(baseName)_copy\(copyNumber).\(ext)")
  }

  return newURL
}

private func forceClose() {
  // Temporarily clear unsaved flag to allow close
  state.hasUnsavedChanges = false
  window?.close()
}
```

## Code Structure After Changes

```swift
@MainActor
final class AnnotateWindowController: NSWindowController, NSWindowDelegate {

  private let state: AnnotateState
  private var cancellables = Set<AnyCancellable>()

  init(item: QuickAccessItem) {
    // ... existing code ...
    super.init(window: window)
    window.delegate = self  // ADD
    setupContent()
  }

  init() {
    // ... existing code ...
    super.init(window: window)
    window.delegate = self  // ADD
    setupContent()
    setupImageObserver()
  }

  // ... existing methods ...

  // MARK: - NSWindowDelegate

  func windowShouldClose(_ sender: NSWindow) -> Bool { ... }
  private func showUnsavedChangesAlert(for window: NSWindow) { ... }
  private func performSaveAndClose() { ... }
  private func showSaveConfirmation(for sourceURL: URL) { ... }
  private func generateCopyURL(from originalURL: URL) -> URL { ... }
  private func forceClose() { ... }
}
```

## Notes

- `generateCopyURL` duplicated from `AnnotateToolbarView` - consider extracting to shared utility in Phase 04
- Sheet-based alerts (`beginSheetModal`) provide better UX than app-modal alerts
- `forceClose()` clears flag before close to prevent recursive delegate call

## Verification

1. Open annotation window, add annotation
2. Click window close button (red X)
3. Confirm "Unsaved Changes" alert appears
4. Test all three buttons: Save, Don't Save, Cancel
5. Test both QuickAccessItem and empty window flows
