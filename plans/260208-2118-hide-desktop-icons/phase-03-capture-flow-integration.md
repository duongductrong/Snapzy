# Phase 03: Capture Flow Integration

**Parent Plan:** [plan.md](./plan.md)
**Dependencies:** [Phase 01](./phase-01-desktop-icon-manager-service.md), [Phase 02](./phase-02-preferences-integration.md)
**Docs:** [system-architecture](../../docs/system-architecture.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-02-08 |
| Description | Wire DesktopIconManager into screenshot and recording capture flows |
| Priority | High |
| Implementation Status | Pending |
| Review Status | Pending |

## Key Insights

- Read `hideDesktopIcons` preference via `UserDefaults.standard.bool(forKey:)` at capture time
- **Fullscreen capture:** hide icons -> 150ms wait -> capture -> restore
- **Area capture:** user selects area first (icons visible) -> hide icons -> 150ms wait -> capture -> restore
- **OCR capture:** same as area capture
- **Recording:** hide icons before recording starts -> restore after recording stops
- Use helper method to avoid repeating hide/restore logic
- `defer`-like pattern ensures restoration even on errors

## Requirements

1. Check `hideDesktopIcons` preference before each capture
2. Hide icons before capture, restore after (guaranteed)
3. 150ms delay after hiding to ensure overlay renders before capture
4. Area/OCR: hide after selection completes, before actual capture
5. Recording: hide before `startRecording()`, restore in `cleanup()`
6. No visual disruption if preference is disabled

## Architecture

```
ScreenCaptureViewModel
├── captureFullscreen()  -> hideIfNeeded -> delay -> capture -> restore
├── captureArea()        -> select area -> hideIfNeeded -> delay -> capture -> restore
├── captureOCR()         -> select area -> hideIfNeeded -> delay -> capture -> restore
└── private helpers:
    └── shouldHideDesktopIcons: Bool  (reads UserDefaults)

RecordingCoordinator
├── startRecording()     -> hideIfNeeded before recorder.startRecording()
└── cleanup()            -> restoreIcons() always called
```

## Related Code Files

- `Snapzy/Core/ScreenCaptureViewModel.swift` (lines 165-368) -- capture methods
- `Snapzy/Features/Recording/RecordingCoordinator.swift` (lines 312-383, 489-503) -- recording start + cleanup
- `Snapzy/Core/Services/DesktopIconManager.swift` -- the service from Phase 01

## Implementation Steps

### Step 1: Add helper property to ScreenCaptureViewModel

File: `Snapzy/Core/ScreenCaptureViewModel.swift`

Add private computed property (after line 53, near other private properties):

```swift
  private var shouldHideDesktopIcons: Bool {
    UserDefaults.standard.bool(forKey: PreferencesKeys.hideDesktopIcons)
  }
```

Add private helper methods:

```swift
  private func hideDesktopIconsIfNeeded() async {
    guard shouldHideDesktopIcons else { return }
    DesktopIconManager.shared.hideIcons()
    // Wait for overlay to render before capture
    try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
  }

  private func restoreDesktopIconsIfNeeded() {
    DesktopIconManager.shared.restoreIcons()
  }
```

### Step 2: Integrate into `captureFullscreen()`

File: `Snapzy/Core/ScreenCaptureViewModel.swift`

Replace the existing `captureFullscreen()` method body (lines 165-184):

```swift
  func captureFullscreen() {
    Task {
      isCapturing = true

      // Hide desktop icons if enabled
      await hideDesktopIconsIfNeeded()

      // Minimal delay to ensure UI state updates before capture
      try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

      let result = await captureManager.captureFullscreen(
        saveDirectory: saveDirectory,
        format: selectedFormat.format
      )

      // Always restore icons
      restoreDesktopIconsIfNeeded()

      isCapturing = false
      lastCaptureResult = result

      if case .success = result, playSound {
        playScreenshotSound()
      }
    }
  }
```

### Step 3: Integrate into `captureArea()`

File: `Snapzy/Core/ScreenCaptureViewModel.swift`

In the `captureArea()` method, add hide/restore around the actual capture (inside the `Task { @MainActor in` block, lines 216-235). The area selection happens first with icons visible, then hide before capture:

```swift
        Task { @MainActor in
          self.isCapturing = true

          // Hide desktop icons after area selection, before capture
          await self.hideDesktopIconsIfNeeded()

          // Delay to ensure overlay windows are fully hidden from screen buffer
          try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

          let result = await self.captureManager.captureArea(
            rect: selectedRect,
            saveDirectory: self.saveDirectory,
            format: self.selectedFormat.format
          )

          // Always restore icons
          self.restoreDesktopIconsIfNeeded()

          self.isCapturing = false
          self.lastCaptureResult = result

          if case .success = result, self.playSound {
            self.playScreenshotSound()
          }
        }
```

### Step 4: Integrate into `captureOCR()`

File: `Snapzy/Core/ScreenCaptureViewModel.swift`

Same pattern -- add hide/restore in the `Task { @MainActor in` block (lines 336-365):

```swift
        Task { @MainActor in
          // Hide desktop icons after area selection, before capture
          await self.hideDesktopIconsIfNeeded()

          // Delay to ensure overlay windows are fully hidden
          try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

          do {
            guard let image = try await self.captureManager.captureAreaAsImage(rect: selectedRect) else {
              QuickAccessSound.failed.play()
              self.restoreDesktopIconsIfNeeded()
              self.isAreaSelectionActive = false
              return
            }

            let text = try await OCRService.shared.recognizeText(from: image)

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

            QuickAccessSound.complete.play()
          } catch {
            QuickAccessSound.failed.play()
          }

          // Always restore icons
          self.restoreDesktopIconsIfNeeded()
          self.isAreaSelectionActive = false
        }
```

### Step 5: Integrate into RecordingCoordinator

File: `Snapzy/Features/Recording/RecordingCoordinator.swift`

**5a.** Add helper property (after line 26, with other private properties):

```swift
  private var shouldHideDesktopIcons: Bool {
    UserDefaults.standard.bool(forKey: PreferencesKeys.hideDesktopIcons)
  }
```

**5b.** In `startRecording()` method (line 312), add hide before `recorder.startRecording()`:

```swift
  private func startRecording() {
    guard let rect = selectedRect, let window = toolbarWindow else { return }

    // ... existing format/fps/quality/audio setup code unchanged ...

    Task {
      do {
        try await recorder.prepareRecording(
          rect: rect,
          format: format,
          quality: quality,
          fps: fps,
          captureSystemAudio: captureSystemAudio,
          captureMicrophone: captureMicrophone,
          saveDirectory: saveDirectory
        )

        // Hide desktop icons before recording starts
        if shouldHideDesktopIcons {
          DesktopIconManager.shared.hideIcons()
          try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
        }

        try await recorder.startRecording()

        // ... existing overlay/toolbar code unchanged ...

      } catch let error as RecordingError {
        DesktopIconManager.shared.restoreIcons()
        showErrorAlert(error)
        cancel()
      } catch {
        DesktopIconManager.shared.restoreIcons()
        showErrorAlert(.setupFailed(error.localizedDescription))
        cancel()
      }
    }
  }
```

**5c.** In `cleanup()` method (line 489), add restore as first action:

```swift
  private func cleanup() {
    // Restore desktop icons (safe to call even if not hidden)
    DesktopIconManager.shared.restoreIcons()

    // Remove escape monitors
    removeEscapeMonitors()

    // ... rest of existing cleanup unchanged ...
  }
```

**5d.** Also restore in `restartRecording()` error catch blocks and add hide before restart recording starts (line 244). Add `DesktopIconManager.shared.hideIcons()` before the second `recorder.startRecording()` call and `restoreIcons()` in the catch blocks.

## Todo List

- [ ] Add `shouldHideDesktopIcons` + helper methods to `ScreenCaptureViewModel`
- [ ] Integrate into `captureFullscreen()`
- [ ] Integrate into `captureArea()`
- [ ] Integrate into `captureOCR()`
- [ ] Add helper property to `RecordingCoordinator`
- [ ] Integrate into `startRecording()`
- [ ] Integrate into `cleanup()`
- [ ] Integrate into `restartRecording()` error paths
- [ ] Test: fullscreen capture with toggle on -- no icons in capture
- [ ] Test: area capture with toggle on -- icons visible during selection, hidden during capture
- [ ] Test: recording with toggle on -- icons hidden throughout recording
- [ ] Test: all flows with toggle off -- no behavior change
- [ ] Test: error during capture -- icons restored

## Success Criteria

1. Fullscreen capture hides icons before capture, restores after
2. Area/OCR capture hides icons after selection, before capture, restores after
3. Recording hides icons before start, restores after stop/cancel/delete
4. Toggle off = zero behavioral change (no regressions)
5. Icons always restored even on capture/recording errors
6. No visible flicker or delay to user when preference is disabled
7. Overlay windows do NOT appear in captured screenshots/recordings

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Icons not restored on crash | Medium | OS cleans up windows on process termination |
| Race condition: rapid captures | Low | `isHidden` guard prevents double-hide |
| Overlay visible in capture | High | `sharingType = .none` + test verification |
| Performance impact when disabled | None | Early return when preference is false |
| Recording restart loses hide state | Medium | Re-hide in `restartRecording()` flow |

## Security Considerations

- Only reads a boolean from UserDefaults
- No elevated privileges required
- No file system mutations
- Screen capture permission already required by app

## Next Steps

After all 3 phases implemented:
1. Manual testing on single and multi-monitor setups
2. Test with dynamic wallpapers and dark mode
3. Consider adding keyboard shortcut to toggle (future enhancement)
