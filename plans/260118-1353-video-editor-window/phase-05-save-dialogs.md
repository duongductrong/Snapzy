# Phase 5: Save Dialogs

## Context

- [Phase 5 Main](./phase-05-export-and-save.md)

## Unsaved Changes Alert

Show when user closes window with unsaved changes:

```swift
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
            self.performSaveAndClose()
        case .alertSecondButtonReturn:
            self.forceClose()
        default:
            break
        }
    }
}
```

## Save Confirmation Dialog

Show when user chooses to save:

```swift
private func showSaveConfirmation() {
    guard let window = self.window else { return }

    let alert = NSAlert()
    alert.messageText = "Save Changes"
    alert.informativeText = "How would you like to save your changes to \"\(state.sourceURL.lastPathComponent)\"?"
    alert.alertStyle = .informational

    alert.addButton(withTitle: "Replace Original")
    alert.addButton(withTitle: "Save as Copy")
    alert.addButton(withTitle: "Cancel")

    alert.beginSheetModal(for: window) { [weak self] response in
        guard let self = self else { return }

        switch response {
        case .alertFirstButtonReturn:
            self.replaceOriginal()
        case .alertSecondButtonReturn:
            self.saveAsCopy()
        default:
            break
        }
    }
}
```

## Export Error Alert

```swift
private func showExportError(_ error: Error) {
    guard let window = self.window else { return }

    let alert = NSAlert()
    alert.messageText = "Export Failed"
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .critical
    alert.addButton(withTitle: "OK")
    alert.beginSheetModal(for: window)
}
```

## Export Progress Overlay

Add to VideoEditorMainView:
```swift
.overlay {
    if state.isExporting {
        ZStack {
            Color.black.opacity(0.7)
            ProgressView("Exporting...")
                .progressViewStyle(.circular)
                .foregroundColor(.white)
        }
    }
}
```
