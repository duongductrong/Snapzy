# Codebase Scout Report: ZapShot Video Editor

## Project Structure

```
ZapShot/
├── App/
│   └── ZapShotApp.swift
├── Core/
│   ├── ScreenCaptureManager.swift
│   ├── ScreenRecordingManager.swift      # Video recording with AVFoundation
│   ├── RecordingSession.swift
│   ├── KeyboardShortcutManager.swift
│   ├── AreaSelectionWindow.swift
│   └── ShortcutRecorderView.swift
├── Features/
│   ├── Annotate/                          # Reference pattern for window implementation
│   │   ├── Window/
│   │   │   ├── AnnotateWindow.swift
│   │   │   └── AnnotateWindowController.swift  # Key reference for unsaved changes handling
│   │   ├── Views/
│   │   ├── State/
│   │   ├── Canvas/
│   │   └── Export/
│   ├── VideoEditor/                       # Target implementation location
│   │   ├── VideoEditorWindow.swift        # Dark mode NSWindow config (exists)
│   │   ├── VideoEditorWindowController.swift  # Placeholder controller (exists)
│   │   ├── VideoEditorManager.swift       # Singleton manager (exists)
│   │   └── VideoEditorPlaceholderView.swift   # To be replaced
│   ├── Recording/
│   │   ├── RecordingCoordinator.swift
│   │   ├── RecordingToolbarWindow.swift
│   │   └── RecordingToolbarView.swift
│   ├── QuickAccess/
│   │   ├── QuickAccessItem.swift          # Data model with isVideo property
│   │   ├── QuickAccessManager.swift
│   │   └── QuickAccessCardView.swift
│   ├── Preferences/
│   └── Onboarding/
└── ContentView.swift
```

## Key Files for Video Editor Implementation

### Existing VideoEditor Files (to modify)
- `VideoEditorWindowController.swift:17` - Add VideoEditorState, setup unsaved changes
- `VideoEditorWindow.swift:11` - Window config already done
- `VideoEditorManager.swift:23` - Already handles window lifecycle
- `VideoEditorPlaceholderView.swift` - Replace with actual implementation

### Reference Patterns (AnnotateWindowController)
- Line 175-182: `windowShouldClose` with unsaved changes check
- Line 184-208: `showUnsavedChangesAlert` sheet modal
- Line 218-249: Save confirmation (Replace/Copy/Cancel)
- Line 264-286: Keyboard shortcut observers for save

### QuickAccessItem Model
- `QuickAccessItem.swift` - Contains `isVideo` property, `url` for video path

### ScreenRecordingManager
- Line 17-36: VideoFormat enum (mov, mp4)
- Line 40-61: VideoQuality enum
- Uses AVFoundation for recording

## UI Patterns Used

1. **Window Pattern**: NSWindow + NSWindowController + SwiftUI via NSHostingView
2. **State Management**: ObservableObject with @Published properties
3. **Dark Theme**: `NSAppearance(named: .darkAqua)`, transparent titlebar
4. **Modals**: NSAlert with `beginSheetModal` for confirmations

## Files to Create

1. `VideoEditorState.swift` - Observable state for video editing
2. `VideoEditorMainView.swift` - Main SwiftUI view container
3. `VideoPlayerSection.swift` - Video player with AVPlayerView
4. `VideoTimelineView.swift` - Timeline with scrubber and trim handles
5. `VideoTimelineFrameStrip.swift` - Frame thumbnail preview strip
6. `VideoControlsView.swift` - Play/pause, time display
7. `VideoEditorExporter.swift` - Trim and export logic
