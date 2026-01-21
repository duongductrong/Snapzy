# Phase 01: Implementation

**File:** `ZapShot/Features/Annotate/Window/AnnotateWindowController.swift`

## Step 1: Add Property

Location: After line 18 (`private var cancellables = Set<AnyCancellable>()`)

```swift
private let quickAccessItemId: UUID?
```

## Step 2: Update init(item:)

Location: Line 20-51

Before:
```swift
init(item: QuickAccessItem) {
  // Load full image from URL and adjust for Retina scaling
  let image = Self.loadImageWithCorrectScale(from: item.url) ?? item.thumbnail

  self.state = AnnotateState(image: image, url: item.url)
  // ... rest
```

After:
```swift
init(item: QuickAccessItem) {
  self.quickAccessItemId = item.id

  // Load full image from URL and adjust for Retina scaling
  let image = Self.loadImageWithCorrectScale(from: item.url) ?? item.thumbnail

  self.state = AnnotateState(image: image, url: item.url)
  // ... rest
```

## Step 3: Update init()

Location: Line 54-77

Before:
```swift
/// Empty initializer for drag-drop workflow
init() {
  self.state = AnnotateState()
  // ... rest
```

After:
```swift
/// Empty initializer for drag-drop workflow
init() {
  self.quickAccessItemId = nil
  self.state = AnnotateState()
  // ... rest
```

## Step 4: Update forceClose()

Location: Line 247-250

Before:
```swift
private func forceClose() {
  state.hasUnsavedChanges = false
  window?.close()
}
```

After:
```swift
private func forceClose() {
  state.hasUnsavedChanges = false

  // Remove associated QuickAccess card if opened from QuickAccess
  if let itemId = quickAccessItemId {
    QuickAccessManager.shared.removeItem(id: itemId)
  }

  window?.close()
}
```

## Verification

After implementation, run through test checklist in `plan.md`.
