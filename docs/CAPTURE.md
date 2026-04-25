# Capture, Recording, and Editing Flows

This doc follows the runtime path from trigger to saved asset, Quick Access, editors, and cloud actions.

User-facing copy in these flows is localized through `Snapzy/Shared/Localization/L10n.swift` and `Snapzy/Resources/Localization/{Shared,Features}/*.xcstrings`. Privacy permission copy lives in `InfoPlist.strings`. For localization ownership and rules, read [`LOCALIZATION.md`](LOCALIZATION.md).

## Flow Index

```mermaid
flowchart TD
    A["Trigger from menu bar or global shortcut"] --> B{"Mode"}

    B --> C["Fullscreen / Area screenshot"]
    B --> D["Scrolling capture"]
    B --> E["Capture Text (OCR)"]
    B --> F["Object cutout"]
    B --> G["Record screen"]

    C --> H["ScreenCaptureManager"]
    D --> I["ScrollingCaptureCoordinator"]
    E --> J["captureAreaAsImage -> OCRService"]
    F --> K["captureAreaAsImage -> ForegroundCutoutService"]
    G --> L["RecordingCoordinator -> ScreenRecordingManager"]

    H --> M["TempCaptureManager + PostCaptureActionHandler"]
    I --> M
    K --> M
    L --> M

    J --> N["Clipboard text result"]

    M --> O["Quick Access"]
    M --> P["Clipboard copy"]
    M --> Q["Annotate auto-open"]

    O --> R["Annotate"]
    O --> S["Video Editor"]
    O --> T["Manual screenshot cloud upload"]
```

## Screenshot, OCR, and Cutout

```mermaid
flowchart TD
    A["ScreenCaptureViewModel"] --> B["Ensure export folder permission"]
    B --> C["Prefetch SCShareableContent"]
    C --> D{"Capture mode"}

    D -->|Fullscreen| E["captureFullscreen()"]
    D -->|Area| F["FrozenAreaCaptureSession.prepare()"]
    D -->|OCR| G["AreaSelectionController.startSelection()"]
    D -->|Cutout| H["AreaSelectionController.startSelection()"]

    E --> I["ScreenCaptureManager.captureFullscreen()"]
    F --> J["AreaSelectionController.startSelection(backdrops:, applicationConfiguration:)"]
    J --> K{"Interaction mode"}
    K -->|Manual region| K1["FrozenAreaCaptureSession.cropImage()"]
    K -->|Application window| K2["ScreenCaptureManager.captureWindow()"]
    G --> L["ScreenCaptureManager.captureAreaAsImage()"]
    H --> M["ScreenCaptureManager.captureAreaAsImage()"]

    I --> N["TempCaptureManager.resolveSaveDirectory(.screenshot)"]
    K1 --> N
    K2 --> N
    N --> O["saveImage()/saveProcessedImage()"]
    O --> P["PostCaptureActionHandler"]

    G --> Q["OCRService.recognizeText()"]
    Q --> R["Copy recognized text to NSPasteboard"]

    H --> S["ForegroundCutoutService.extractForegroundResult()"]
    S --> T{"Auto-crop suggested and enabled?"}
    T -->|Yes| U["Crop transparent canvas to suggested rect"]
    T -->|No| V["Keep full transparent canvas"]
    U --> W["saveProcessedImage()"]
    V --> W
    W --> P
```

### Notes

- Fullscreen still runs directly through `ScreenCaptureManager`, but area screenshot now freezes the active display first via `FrozenAreaCaptureSession`, then either crops from that cached snapshot or switches into exact window capture for application mode.
- Non-target displays still get blocking overlay windows during area screenshot, but only the frozen display accepts the drag selection in the current implementation.
- For screenshot sessions, the target display overlay now owns direct keyboard handling for `Escape` and the application-mode toggle key, so cancel still works when Snapzy starts from a background custom shortcut without depending on Accessibility-backed global key monitoring.
- `Cmd+Shift+4` area capture now has two interaction modes inside the same overlay session: manual region by default, and application window mode toggled with the configurable `Application Capture` key from Preferences → Shortcuts. The default key is `A`.
- In application window mode, `AreaSelectionController` builds a front-to-back candidate list from `CGWindowListCopyWindowInfo` plus `SCShareableContent`, highlights the hovered window above the dimming overlay, and captures the selected app window on click without requiring a drag rectangle.
- Exact window capture is handled by `ScreenCaptureManager.captureWindow()`. macOS 14+ uses ScreenCaptureKit window metrics directly; macOS 13+ stays supported with the same ScreenCaptureKit path plus a safe area-capture fallback if exact capture fails.
- The frozen/manual and application-window paths both preserve existing desktop icon/widget exclusion, cursor, own-app exclusion, temp-save, Quick Access, clipboard, and annotate routing behavior.
- OCR is the only capture path that does not create a file; it captures a `CGImage`, runs Vision OCR, and copies text to the pasteboard.
- Object cutout is macOS 14+ only. JPEG is overridden to PNG because transparency must be preserved.
- Capture toasts, alerts, open-panel prompts, and error surfaces are localized through `L10n`.

## Scrolling Capture

```mermaid
flowchart TD
    A["captureScrolling()"] --> B["AreaSelectionController.startSelection(mode: .scrollingCapture)"]
    B --> C["User selects only moving content"]
    C --> D["ScrollingCaptureCoordinator.beginSession()"]

    D --> E["Prepare region-scoped capture context"]
    D --> F["Show region overlay, HUD, preview window"]
    D --> G["Create live preview stream"]
    D --> H["Create commit scheduler"]

    G --> I["ScrollingCaptureFrameSource receives latest region frame"]
    I --> J["ScrollingCapturePreviewRenderer presents live image"]

    H --> K["Initial commit or scroll-triggered commit request"]
    K --> L["ScrollingCaptureCommitScheduler keeps latest pending request"]
    L --> M["refreshPreview() captures newest eligible frame"]
    M --> N["ScrollingCaptureStitcher append / ignore / pause / height-limit"]
    N --> O["Session model updates badge, caption, metrics"]

    F --> P["Global scroll monitor + settle timer"]
    P --> L

    O --> Q{"Done, cancel, or limit?"}
    Q -->|Continue| P
    Q -->|Done| R["finish() waits for idle commit lane"]
    R --> S["Flush final visible frame if needed"]
    S --> T["saveProcessedImage()"]
    T --> U["PostCaptureActionHandler"]
```

### Notes

- The subsystem in `Services/Capture/ScrollingCapture/` is intentionally self-contained: preview, stitcher, HUD, metrics, commit scheduling, and window placement all live there.
- The preview lane and commit lane are separate. Live preview can stay ahead while the stitcher locks the next safe frame.
- Vision is a recovery tool inside `ScrollingCaptureStitcher`, not the default hot path.
- Session guidance, runtime badges, preview captions, and recovery toasts are localized and should stay in sync with `docs/LOCALIZATION.md`.

## Recording, GIF Output, and Smart Camera

```mermaid
flowchart TD
    A["startRecordingFlow()"] --> B{"Remember last area?"}
    B -->|Yes| C["RecordingCoordinator.showToolbar(savedRect)"]
    B -->|No| D["AreaSelectionController.startSelection(mode: .recording)"]
    D --> C

    C --> E["RecordingToolbarWindow + region overlays"]
    E --> F["prepareRecording(rect, format, quality, fps, audio flags)"]
    F --> G["ScreenRecordingManager.startRecording()"]

    G --> H["SCStream + AVAssetWriter"]
    G --> I["RecordingMouseTracker"]
    G --> J["Optional click highlight + keystroke + annotation overlays"]

    H --> K["stopRecording()"]
    I --> K
    J --> K

    K --> L["Persist RecordingMetadata if mouse samples are available"]
    K --> M{"Output mode"}

    M -->|Video| N["PostCaptureActionHandler.handleVideoCapture()"]
    M -->|GIF| O["Quick Access placeholder card"]
    O --> P["GIFConverter.convert()"]
    P --> Q["Replace Quick Access item URL with GIF"]
    Q --> R["PostCaptureActionHandler.handleVideoCapture(skipQuickAccess: true)"]

    L --> S["VideoEditorAutoFocusEngine reads metadata later"]
```

### Notes

- Recording metadata is stored separately from the media file and powers Smart Camera / Follow Mouse in the video editor.
- GIF output is a two-step flow: record video first, then convert and swap the Quick Access item.
- `RecordingCoordinator` owns toolbar and overlay UX. `ScreenRecordingManager` owns media capture, timing, and metadata persistence.
- `AppStatusBarController` stays menu-first during active recording. The menu bar item keeps Snapzy's normal identity, shows the live elapsed time, and exposes stop plus pause/resume from the menu instead of left-click-to-stop.
- Opening Preferences from the menu bar during recording keeps Settings reachable without forcing a stop. When own-app capture is enabled, the active recording stream dynamically excludes that Settings window.
- Recording toolbar labels, output mode copy, microphone/save-folder alerts, and export errors are localized.

## Post-Capture Routing

```mermaid
flowchart TD
    A["Capture file is ready"] --> B["TempCaptureManager.resolveSaveDirectory()"]
    B --> C{"Save enabled for this capture type?"}
    C -->|Yes| D["Write into user export directory"]
    C -->|No| E["Write into Application Support temp capture directory"]

    D --> F["PostCaptureActionHandler"]
    E --> F

    F --> G{"Show Quick Access?"}
    F --> H{"Copy file?"}
    F --> I{"Open Annotate? screenshot only"}

    G -->|Yes| J["QuickAccessManager.addScreenshot/addVideo"]
    G -->|No| K["No overlay card"]

    H -->|Yes| L["ClipboardHelper or file URL pasteboard write"]
    H -->|No| M["Skip clipboard"]

    I -->|Yes| N["AnnotateManager.openAnnotation(url:)"]
    I -->|No| O["Skip auto-open"]

    J --> P{"Temp file?"}
    P -->|Yes| Q["Save action moves file to export directory"]
    P -->|Dismiss| R["Temp file deleted"]
    P -->|Saved file| S["Open / drag / copy / delete"]

    J --> T{"Screenshot or video?"}
    T -->|Screenshot| U["Annotate, drag, cloud upload, save/open, delete"]
    T -->|Video or GIF| V["Video editor, drag, copy, save/open, delete"]
```

### Notes

- `AfterCaptureAction.save` is not a post-write callback. It changes the destination before the file is written.
- Current cloud behavior is manual from Quick Access or Annotate for screenshots. The preference toggle enables those affordances; it does not auto-upload in `PostCaptureActionHandler`.
- Temp captures are intentionally stored in Application Support, not `/tmp`, so drag-and-drop remains stable.
- Quick Access action labels and post-capture error states are localized.

## Annotate and Cloud Re-Upload

```mermaid
flowchart TD
    A["Quick Access screenshot or auto-open"] --> B["AnnotateManager"]
    B --> C["AnnotateWindowController + AnnotateState"]
    C --> D["Canvas, crop, blur, text, watermark, shapes, mockup, cutout"]

    D --> E{"Action"}
    E -->|Save / export| F["AnnotateExporter.renderFinalImage()"]
    E -->|Copy| G["Clipboard write"]
    E -->|Share| H["NSSharingServicePicker"]
    E -->|Upload| I["CloudManager.upload()"]

    F --> J["Update file on disk"]
    J --> K["QuickAccess thumbnail refresh"]
    J --> L{"Cloud URL already exists?"}
    L -->|Yes| M["Mark item as cloud-stale"]
    L -->|No| N["No stale marker"]

    I --> O["Persist cloud URL + key"]
    O --> P["Copy public URL to clipboard"]
    O --> Q["Clear stale marker"]
```

### Notes

- Annotate windows cache session state per Quick Access item so the user can reopen the same card and keep editing.
- Watermark annotations are editable items with text, style, opacity, size, rotation, and color controls; export/copy/share/upload render them through the same final image pipeline as other annotations.
- Manually opened Annotate windows from the menu bar, global shortcut, or toolbar plus button are independent, so users can work with multiple clipboard/drop sessions side by side.
- If a screenshot was already uploaded, later edits mark the cloud state stale until the user re-uploads.
- Annotate dialogs, preset actions, mockup labels, cutout/export alerts, and cloud re-upload messaging are localized.

## Video Editor

```mermaid
flowchart TD
    A["Quick Access video/GIF or empty editor"] --> B["VideoEditorManager"]
    B --> C["VideoEditorWindowController + VideoEditorState"]
    C --> D["Load asset and timeline"]
    D --> E{"Recording metadata available?"}
    E -->|Yes| F["VideoEditorAutoFocusEngine builds Follow Mouse path"]
    E -->|No| G["Manual zoom workflow only"]

    F --> H["Trim, zoom segments, wallpaper/background, export settings"]
    G --> H
    H --> I{"Export mode"}
    I -->|Video| J["VideoEditorExporter"]
    I -->|GIF| K["GIFResizer / GIF export path"]
    J --> L["Saved output file"]
    K --> L
```

## Key Files

| File | Responsibility |
| --- | --- |
| `Snapzy/Shared/Localization/L10n.swift` | Shared localization bridge for these flows |
| `Snapzy/Resources/Localization/{Shared,Features}/*.xcstrings` | Split runtime String Catalogs backing translated flow copy |
| `Snapzy/Features/Capture/CaptureViewModel.swift` | Entry point for screenshot, scrolling capture, OCR, cutout, and recording launch |
| `Snapzy/Services/Capture/ScreenCaptureManager.swift` | Core screenshot engine, frozen snapshot capture, and file writing |
| `Snapzy/Services/Capture/FrozenAreaCaptureSession.swift` | Frozen display snapshots used by area screenshot selection |
| `Snapzy/Services/Capture/PostCaptureActionHandler.swift` | Quick Access, clipboard, and screenshot auto-open routing |
| `Snapzy/Services/Capture/TempCaptureManager.swift` | Save-vs-temp destination logic and temp capture lifecycle |
| `Snapzy/Services/Capture/ScrollingCapture/ScrollingCaptureCoordinator.swift` | Long screenshot session orchestration |
| `Snapzy/Services/Capture/ScrollingCapture/ScrollingCaptureStitcher.swift` | Stitching and Vision-assisted recovery |
| `Snapzy/Features/Recording/RecordingCoordinator.swift` | Recording toolbar, overlays, stop/GIF handoff |
| `Snapzy/Services/Capture/ScreenRecordingManager.swift` | Screen recording media pipeline and metadata persistence |
| `Snapzy/Features/QuickAccess/QuickAccessManager.swift` | Floating stack state and countdown behavior |
| `Snapzy/Features/QuickAccess/Components/QuickAccessCardView.swift` | Card-level actions including screenshot cloud upload |
| `Snapzy/Features/Annotate/AnnotateManager.swift` | Annotate window lifecycle and session caching |
| `Snapzy/Features/Annotate/Services/AnnotateExporter.swift` | Final image render/export |
| `Snapzy/Features/VideoEditor/VideoEditorManager.swift` | Video editor window lifecycle |
| `Snapzy/Features/VideoEditor/Services/VideoEditorAutoFocusEngine.swift` | Follow Mouse / Smart Camera path reconstruction |
| `Snapzy/Services/Cloud/CloudManager.swift` | Upload facade, provider creation, history persistence |
