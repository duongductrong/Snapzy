# Capture Flow

Documentation of Snapzy's screen capture pipeline — from keyboard shortcut trigger to saved file and post-capture actions.

## Architecture Overview

```mermaid
flowchart TD
    subgraph Trigger["Trigger (Global Shortcut)"]
        A1["Cmd+Shift+3 (Fullscreen)"]
        A2["Cmd+Shift+4 (Area Select)"]
    end

    subgraph VM["CaptureViewModel"]
        B1["captureFullscreen()"]
        B2["captureArea()"]
        B3["Resolve save directory"]
        B4["Prefetch SCShareableContent"]
    end

    subgraph Selection["Area Selection"]
        C1["AreaSelectionController.startSelection()"]
        C2["User drags rect (NSScreen coords)"]
        C3["Returns CGRect"]
    end

    subgraph Engine["ScreenCaptureManager"]
        D1["loadShareableContent()"]
        D2["Find target SCDisplay"]
        D3["buildFilter() (exclude icons/widgets/self)"]
        D4["Configure SCStreamConfiguration"]
        D5["captureImageCompat()"]
        D6["macOS 14+: SCScreenshotManager | macOS 13: SCStream"]
        D7["Returns CGImage"]
    end

    subgraph Save["Image Saving"]
        F1["saveImage()"]
        F2{"Format?"}
        F3["PNG/JPEG: CGImageDestination"]
        F4["WebP: WebPEncoderService"]
        F5["verifyFileWritten()"]
        F6["captureCompletedSubject"]
    end

    subgraph Post["PostCaptureActionHandler"]
        G1["Show QuickAccess Card"]
        G2["Copy to Clipboard"]
        G3["Open Annotate Editor"]
    end

    subgraph Annotate["Annotate Pipeline"]
        H1["loadImageWithCorrectScale()"]
        H2["AnnotateCanvasView (preview)"]
        H3["renderFinalImage() (export)"]
        H4["imageData() → save to disk"]
    end

    A1 --> B1
    A2 --> B2 --> C1 --> C2 --> C3

    B1 & B2 --> B3 & B4 --> D1
    C3 --> D1

    D1 --> D2 --> D3 --> D4 --> D5 --> D6 --> D7
    D7 --> F1 --> F2
    F2 -->|PNG/JPEG| F3
    F2 -->|WebP| F4
    F3 & F4 --> F5 --> F6

    F6 --> G1 & G2 & G3
    G3 --> H1 --> H2 -->|Save/Export| H3 --> H4
```

## Key Files

| File | Responsibility |
|------|----------------|
| `Features/Capture/CaptureViewModel.swift` | Orchestrates capture from UI. Resolves save directory, prefetches content, calls ScreenCaptureManager. |
| `Services/Capture/ScreenCaptureManager.swift` | Core capture engine. Configures SCStreamConfiguration, builds content filters, captures via SCScreenshotManager (14+) or SCStream (13). |
| `Services/Capture/PostCaptureActionHandler.swift` | Executes post-capture actions: Quick Access card, clipboard copy, open Annotate. |
| `Features/Annotate/AnnotateState.swift` | Manages annotation state. `loadImageWithCorrectScale()` loads images at correct Retina scale. |
| `Features/Annotate/Components/AnnotateCanvasView.swift` | Displays image + annotations on canvas with scale-to-fit, zoom, pan. |
| `Features/Annotate/Services/AnnotateExporter.swift` | Exports annotated images. `renderFinalImage()` combines source image + annotations + background at pixel resolution. |
| `Services/Shortcuts/SystemScreenshotShortcutManager.swift` | Detects/manages conflicts with macOS built-in screenshot shortcuts. |

## Capture Modes

### Fullscreen (`captureFullscreen`)

1. Prefetch `SCShareableContent`
2. Find target `SCDisplay` by display ID
3. Build `SCContentFilter` (display-level, excludes icons/widgets/self as configured)
4. Configure `SCStreamConfiguration`:
   - `width/height` = display pixel dimensions × `backingScaleFactor`
   - `pixelFormat` = `kCVPixelFormatType_32BGRA`
   - `captureResolution = .best` (macOS 14.2+)
5. Capture via `SCScreenshotManager` (macOS 14+) or `SCStream` single-frame (macOS 13)
6. Save via `CGImageDestination` (PNG/JPEG) or `WebPEncoderService` (WebP)

### Area Select (`captureArea`)

1. `AreaSelectionController` shows overlay → user drags selection rect
2. Find matching `NSScreen` and `SCDisplay`
3. Capture **full display** at native pixel resolution
4. **Post-capture crop** using `CGImage.cropping(to:)` with pixel-coordinate rect — avoids `sourceRect` interpolation blur
5. Save cropped image

### OCR Area (`captureAreaAsImage`)

Same as Area Select but returns `CGImage` directly for text recognition instead of saving to disk.

## Image Quality Pipeline

| Stage | Units | Key Detail |
|-------|-------|------------|
| SCStreamConfiguration `width/height` | Pixels | Set to `display.width × backingScaleFactor` |
| `captureResolution = .best` | — | Hints SCK to use optimal pixel density (macOS 14.2+) |
| `CGImage.cropping(to:)` | Pixels | Post-capture crop, no resampling |
| `CGImageDestination` save | Pixels | Direct pixel data write, no quality loss |
| `loadImageWithCorrectScale()` | Points | Sets `NSImage.size = pixelSize / scaleFactor` (preserves bitmap rep) |
| `AnnotateCanvasView` display | Points | Scale-to-fit within window using `.clipShape()` (no rasterization) |
| `renderFinalImage()` export | Pixels | Uses `NSBitmapImageRep` at `pointSize × sourceImageScale` for Retina output |

## Post-Capture Actions

Configured in user preferences, handled by `PostCaptureActionHandler`:

- **Quick Access Card** — floating overlay showing thumbnail, drag-to-app, copy/open actions
- **Copy to Clipboard** — `NSPasteboard` with image data
- **Open Annotate** — loads image into annotation editor
