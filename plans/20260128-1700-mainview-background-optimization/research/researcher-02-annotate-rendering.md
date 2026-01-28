# Researcher 02: Annotate Rendering Research

## Current Rendering Architecture
The rendering pipeline in `AnnotateCanvasView` is built on a layered `ZStack` approach, separating the background, the source image, and the annotation drawing layers.

- **Main Component**: `AnnotateCanvasView.swift`
- **Structure**:
    1. **`backgroundLayer`**: Renders the background based on `BackgroundStyle` (solid, gradient, wallpaper, or blurred).
    2. **`imageLayer`**: Renders the source image with corner radius and shadows.
    3. **`CanvasDrawingView`**: Overlays the annotation items using `AnnotationRenderer`.
- **Scaling**: A unified scaling factor (`scale`) is calculated in `canvasContent` to fit the logical canvas (image + padding + alignment space) into the available container size.
- **Metal Integration**: Both `backgroundLayer` and `imageLayer` utilize `.drawingGroup()` to rasterize content into Metal textures, which is critical for maintaining performance when applying effects like blurs and shadows.

## Existing Caching Patterns
- **Wallpaper Cache**: `AnnotateState` maintains `cachedBackgroundImage` (an `NSImage?`). This is loaded once when the background style is set or changed, preventing expensive disk I/O during every view update (e.g., during slider drags).
- **Blur Cache**: `AnnotationRenderer` utilizes a `BlurCacheManager` (referenced in `AnnotationRenderer.swift:17`) to store and retrieve rendered blur regions for the source image.
- **Preview Values**: To ensure smooth interactions, the state uses "effective" values (e.g., `effectivePadding`, `effectiveCornerRadius`). These switch to a `previewValue` during slider interactions to minimize high-frequency state updates to the primary model.

## Image Loading Locations (Full-res)
Full-resolution images are loaded from disk in the following locations:
- **Wallpaper/Background Image**: `ClaudeShot/Features/Annotate/State/AnnotateState.swift:71`
  - Method: `loadBackgroundImage(from url: URL)`
  - Call: `cachedBackgroundImage = NSImage(contentsOf: url)`
- **Source Image**: `ClaudeShot/Features/Annotate/State/AnnotateState.swift:294`
  - Method: `loadImageWithCorrectScale(from url: URL)`
  - Call: `guard let image = NSImage(contentsOf: url) else { return nil }`

## Performance Patterns for Reuse
- **`.drawingGroup()`**: Essential for the background optimization. Any complex video background or animated wallpaper should likely be wrapped in a drawing group to offload rendering to the GPU.
- **Effective Value Pattern**: The `previewPadding ?? padding` pattern in `AnnotateState` should be used for any new video-specific parameters (like video opacity or playback speed) to maintain UI responsiveness.
- **ZStack Layering**: Maintaining the separation between the background layer and the content layer allows for independent optimization (e.g., freezing the image layer while the background is changing).
- **State-driven Caching**: The logic in `AnnotateState.swift:50` (`didSet` on `backgroundStyle`) is a clean pattern for triggering background asset loads.
