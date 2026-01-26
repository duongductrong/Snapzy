# Scout Report: Annotate Module Architecture

## 1. Folder Structure

```
Features/Annotate/
├── AnnotateManager.swift          # Singleton coordinator - window lifecycle
├── Background/
│   └── BackgroundStyle.swift      # Background enums/presets (gradient, solid, wallpaper)
├── Canvas/
│   ├── AnnotationFactory.swift    # Factory pattern - creates AnnotationItems from input
│   ├── AnnotationRenderer.swift   # CGContext renderer - draws annotations
│   ├── BlurCacheManager.swift     # Performance cache for blur effects
│   ├── BlurEffectRenderer.swift   # GPU-accelerated blur (pixelated + Gaussian)
│   └── CanvasDrawingView.swift    # NSView wrapper - mouse events, hit testing
├── Export/
│   └── AnnotateExporter.swift     # Export engine - renders final composited image
├── State/
│   ├── AnnotateState.swift        # Central ObservableObject - all state management
│   ├── AnnotationItem.swift       # Data model - annotation types, properties, hit testing
│   └── AnnotationToolType.swift   # Tool enum
├── Tools/                          # Empty - tool logic embedded in CanvasDrawingView
├── Views/
│   ├── AnnotateMainView.swift     # Root container - toolbar + sidebar + canvas + bottombar
│   ├── AnnotateCanvasView.swift   # SwiftUI canvas - drag-drop, zoom, alignment logic
│   ├── AnnotateToolbarView.swift  # Top toolbar
│   ├── AnnotateSidebarView.swift  # Settings sidebar
│   ├── AnnotateBottomBarView.swift
│   ├── CropOverlayView.swift      # Crop UI overlay
│   ├── TextEditOverlay.swift      # Text editing overlay
│   └── (other UI components)
└── Window/
    ├── AnnotateWindow.swift       # NSWindow configuration
    └── AnnotateWindowController.swift
```

## 2. AnnotateManager Pattern (Singleton Coordinator)

**Role:** Window lifecycle + instance tracking
**Pattern:** Singleton with dictionary-based tracking

```swift
@MainActor final class AnnotateManager {
    static let shared
    private var windowControllers: [UUID: AnnotateWindowController] = [:]
    private var emptyWindowController: AnnotateWindowController?
    
    func openAnnotation(for item: QuickAccessItem)
    func openEmptyAnnotation()  // Drag-drop workflow
    func closeAll()
}
```

**Integration Point:** New MockupRenderer should follow same pattern if needs standalone windows

## 3. State Management (Central ObservableObject)

**File:** `AnnotateState.swift`
**Pattern:** Single source of truth, @Published properties

**Key State Groups:**
- Source image: `sourceImage`, `sourceURL`
- Tool state: `selectedTool`, `strokeWidth`, `strokeColor`, `fillColor`, `blurType`
- UI state: `showSidebar`, `zoomLevel`
- Background: `backgroundStyle`, `padding`, `inset`, `shadowIntensity`, `cornerRadius`, `imageAlignment`
- Annotations: `annotations: [AnnotationItem]`, `selectedAnnotationId`
- Crop: `cropRect`, `isCropActive`
- Undo/Redo: `undoStack`, `redoStack`, `canUndo`, `canRedo`

**Key Methods:**
- `displayScale(for:margin:)` - calculates fit-to-container scale
- `imageOffset(for:imageDisplaySize:displayPadding:)` - alignment calculations
- `loadImage(from:)` - loads with Retina scaling correction
- `saveState()` / `undo()` / `redo()` - undo management
- Annotation manipulation: `selectAnnotation`, `updateAnnotationBounds`, `nudgeSelectedAnnotation`

**Integration Point:** MockupRenderer needs similar state object with device frame properties

## 4. View Architecture (SwiftUI + NSView Hybrid)

**Hierarchy:**
```
AnnotateMainView (SwiftUI)
├── AnnotateToolbarView
├── AnnotateSidebarView
├── AnnotateCanvasView (SwiftUI)
│   └── GeometryReader
│       └── ZStack
│           ├── backgroundLayer (gradient/solid/wallpaper)
│           ├── imageLayer (source image)
│           ├── CanvasDrawingView (NSViewRepresentable wrapper)
│           │   └── DrawingCanvasNSView (NSView - mouse handling)
│           ├── TextEditOverlay
│           └── CropOverlayView
└── AnnotateBottomBarView
```

**Pattern:** SwiftUI for layout/UI, NSView for low-level drawing/events

**AnnotateCanvasView Responsibilities:**
- Scale calculations (fit-to-window with margin)
- Alignment space calculations
- Background rendering (gradient/solid/wallpaper/blur)
- Image positioning with offset
- Drag-drop handling
- Zoom (CMD+scroll)

**Integration Point:** MockupRenderer canvas needs similar hybrid approach - SwiftUI layout + NSView for device frame rendering

## 5. Export Functionality

**File:** `AnnotateExporter.swift`
**Pattern:** Static methods operating on AnnotateState

**Export Flow:**
1. `renderFinalImage(state:)` creates NSImage
2. Calculate effective bounds (crop or full)
3. Create context with total size (image + padding + alignment space)
4. Draw background (`drawBackground`)
5. Calculate image position based on alignment
6. Draw cropped source image with corner radius clipping
7. Draw annotations via `AnnotationRenderer` with offset
8. Save/copy/share

**Key Methods:**
- `saveAs(state:closeWindow:)` - NSSavePanel dialog
- `saveToOriginal(state:)` - overwrite source
- `copyToClipboard(state:)` - pasteboard
- `share(state:from:)` - NSSharingServicePicker

**Offset Logic:** Annotations adjusted by `-cropOrigin + imageX/imageY` for alignment

**Integration Point:** MockupRenderer export needs similar compositing - device frame + screenshot + background

## 6. Tools Implementation (Embedded in CanvasDrawingView)

**Pattern:** No separate tool classes - logic in `DrawingCanvasNSView`

**Tool Handling:**
- Mouse events: `mouseDown/Dragged/Up` switch on `state.selectedTool`
- Drawing: stores `currentPath`, `dragStart`, `isDrawing`
- Selection: hit testing via `hitTestAnnotation`, drag/resize via handles
- Factory: `AnnotationFactory.createAnnotation()` converts input to `AnnotationItem`

**Coordinate System:**
- Image coords: stored annotations (resolution-independent)
- Display coords: UI/rendering (scaled to fit window)
- Transforms: `displayToImage()`, `imageToDisplay()` with `displayScale`

**Integration Point:** MockupRenderer should separate device frame selection from annotation tools

## 7. Canvas Rendering (CGContext)

**File:** `AnnotationRenderer.swift`
**Pattern:** Stateless struct operating on CGContext

**Rendering:**
```swift
struct AnnotationRenderer {
    let context: CGContext
    var sourceImage: NSImage?
    var blurCacheManager: BlurCacheManager?
    
    func draw(_ annotation: AnnotationItem)
    func drawCurrentStroke(tool:start:currentPath:...)
    func drawBlurPreview(...)
}
```

**Annotation Types:** rectangle, oval, arrow, line, path, highlight, blur, text, counter

**Blur Optimization:**
- `BlurCacheManager` caches rendered blur regions by annotation ID
- GPU-accelerated via shared `CIContext` (Metal-backed)
- Pixelated: manual pixel sampling + block fill
- Gaussian: CIFilter + CIGaussianBlur

**Integration Point:** MockupRenderer needs similar CGContext rendering for device frames

## 8. Background Handling

**File:** `BackgroundStyle.swift`
**Pattern:** Enum with associated values

```swift
enum BackgroundStyle {
    case none
    case gradient(GradientPreset)
    case wallpaper(URL)
    case blurred(URL)
    case solidColor(Color)
}
```

**Rendering Locations:**
- Preview: `AnnotateCanvasView.backgroundLayer` (SwiftUI)
- Export: `AnnotateExporter.drawBackground` (CGContext)

**Alignment:** `ImageAlignment` enum (9 positions) + offset calculations

**Integration Point:** MockupRenderer backgrounds should reuse BackgroundStyle or extend it

## Integration Recommendations for Mockup Renderer

1. **Reuse Patterns:**
   - Singleton manager (MockupRendererManager)
   - Central state object (MockupState: ObservableObject)
   - Hybrid SwiftUI + NSView architecture
   - Export static methods pattern

2. **Extend Existing:**
   - BackgroundStyle (already supports gradients/solid/wallpaper)
   - AnnotateExporter offset logic for device frame positioning
   - Blur cache pattern for performance

3. **New Components:**
   - DeviceFrame model (iPhone, iPad, MacBook presets)
   - Device frame SVG/PNG renderer
   - Screenshot positioning within device screen bounds

4. **Coordinate Systems:**
   - Device frame coords (device dimensions)
   - Screenshot coords (actual image size)
   - Display coords (scaled to fit window)
   - Use transforms like Annotate: `frameToDisplay()`, `displayToFrame()`

5. **State Structure:**
   ```swift
   class MockupState: ObservableObject {
       @Published var screenshot: NSImage?
       @Published var selectedDevice: DeviceFrame
       @Published var backgroundStyle: BackgroundStyle
       @Published var deviceRotation: CGFloat
       @Published var screenshotScale: CGFloat  // fit/fill within device screen
       // Reuse: padding, shadowIntensity, cornerRadius from Annotate
   }
   ```

6. **Export Flow:**
   - Render device frame background
   - Position device frame with alignment/padding
   - Mask screenshot to device screen bounds
   - Apply shadows/reflections
   - Composite with background
