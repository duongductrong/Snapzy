# Phase 04: Integration and Wiring

**Status:** Completed
**Files:**
- `ZapShot/Features/Annotate/Window/AnnotateWindowController.swift`
- `ZapShot/Features/Annotate/Views/AnnotateToolbarView.swift`
- `ZapShot/Features/Annotate/Export/AnnotateExporter.swift`

## Objective

Wire keyboard shortcut notifications to save actions, mark saved after export, refactor shared utilities.

## Part A: Controller Notification Observers

Add notification observers in `AnnotateWindowController` to handle Cmd+S and Cmd+Shift+S.

### Step 1: Add Observer Setup

```swift
// Add after setupImageObserver() call in init(), or create new method

private func setupKeyboardShortcutObservers() {
  guard let window = self.window else { return }

  NotificationCenter.default.addObserver(
    forName: .annotateSave,
    object: window,
    queue: .main
  ) { [weak self] _ in
    Task { @MainActor in
      self?.performSave()
    }
  }

  NotificationCenter.default.addObserver(
    forName: .annotateSaveAs,
    object: window,
    queue: .main
  ) { [weak self] _ in
    Task { @MainActor in
      self?.performSaveAs()
    }
  }
}
```

### Step 2: Call Setup in Both Inits

```swift
// In init(item:) after setupContent():
setupKeyboardShortcutObservers()

// In init() after setupImageObserver():
setupKeyboardShortcutObservers()
```

### Step 3: Add Save Action Methods

```swift
private func performSave() {
  guard state.hasImage else { return }

  if let sourceURL = state.sourceURL {
    showSaveConfirmation(for: sourceURL)
  } else {
    performSaveAs()
  }
}

private func performSaveAs() {
  guard state.hasImage else { return }

  let panel = NSSavePanel()
  panel.allowedContentTypes = [.png, .jpeg]
  panel.nameFieldStringValue = generateFileName()
  panel.canCreateDirectories = true

  guard let window = self.window else { return }

  panel.beginSheetModal(for: window) { [weak self] response in
    guard let self = self, response == .OK, let url = panel.url else { return }
    AnnotateExporter.save(state: self.state, to: url)
    self.state.markAsSaved()
  }
}

private func generateFileName() -> String {
  guard let url = state.sourceURL else { return "annotated_image" }
  let baseName = url.deletingPathExtension().lastPathComponent
  return "\(baseName)_annotated"
}
```

## Part B: Update AnnotateToolbarView

Modify toolbar to mark saved after successful save operations.

### Current Issue

`AnnotateToolbarView.done()` and `saveAs()` don't call `state.markAsSaved()`.

### Solution

Pass state to exporter and mark saved on success. Simplest approach: post notification after save.

```swift
// In AnnotateToolbarView, modify saveAs():
private func saveAs() {
  AnnotateExporter.saveAs(state: state, closeWindow: true)
  // Note: closeWindow=true means window closes, no need to mark saved
}

// In showSaveConfirmation(), after successful save before close:
case .alertFirstButtonReturn:
  AnnotateExporter.saveToOriginal(state: state)
  state.markAsSaved()  // ADD THIS
  NSApp.keyWindow?.close()

case .alertSecondButtonReturn:
  let copyURL = generateCopyURL(from: sourceURL)
  AnnotateExporter.save(state: state, to: copyURL)
  state.markAsSaved()  // ADD THIS
  NSApp.keyWindow?.close()
```

## Part C: Extract Shared Utility

`generateCopyURL` exists in both `AnnotateToolbarView` and `AnnotateWindowController`.

### Option 1: Move to AnnotateExporter (Recommended)

```swift
// Add to AnnotateExporter.swift

static func generateCopyURL(from originalURL: URL) -> URL {
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
```

Then update callers:
```swift
// In AnnotateToolbarView:
let copyURL = AnnotateExporter.generateCopyURL(from: sourceURL)

// In AnnotateWindowController:
let copyURL = AnnotateExporter.generateCopyURL(from: sourceURL)
```

## Summary of All Changes

| File | Change |
|------|--------|
| `AnnotateState.swift` | Add `hasUnsavedChanges`, `markAsSaved()`, update `saveState()`, `applyCrop()`, `loadImage()` |
| `AnnotateWindow.swift` | Add notification names, override `performKeyEquivalent` |
| `AnnotateWindowController.swift` | Add `NSWindowDelegate`, `windowShouldClose`, notification observers, save methods |
| `AnnotateToolbarView.swift` | Add `state.markAsSaved()` after save operations |
| `AnnotateExporter.swift` | Add `generateCopyURL()` static method |

## Verification Checklist

- [ ] Cmd+S with source URL shows replace/copy dialog
- [ ] Cmd+S without source URL shows save panel
- [ ] Cmd+Shift+S always shows save panel
- [ ] After any save, `hasUnsavedChanges` is false
- [ ] Close button with unsaved changes shows confirmation
- [ ] Done button marks saved before close
- [ ] Save As marks saved before close
