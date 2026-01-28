# Research: Annotate/Background Implementation

## File Structure Overview
- `ClaudeShot/Features/Annotate/Background/BackgroundStyle.swift`: Core enums and type definitions for background styles.
- `ClaudeShot/Features/Annotate/State/AnnotateState.swift`: Central state management holding background configuration.
- `ClaudeShot/Features/Annotate/Views/AnnotateSidebarSections.swift`: UI components for selecting backgrounds and adjusting parameters.
- `ClaudeShot/Core/Services/SystemWallpaperManager.swift`: Service for fetching macOS system wallpapers.

## Key Components & Responsibilities
- **BackgroundStyle**: Enum defining `none`, `gradient`, `wallpaper(URL)`, `blurred(URL)`, and `solidColor`.
- **AnnotateState**: Manages `@Published` properties for `backgroundStyle`, `padding`, `inset`, `shadowIntensity`, and `cornerRadius`.
- **SystemWallpaperManager**: Singleton service providing `systemWallpapers` array and `loadSystemWallpapers()` async method.
- **WallpaperPreset / GradientPreset**: Enums providing predefined aesthetic options.

## State Management Pattern
- Uses **ObservableObject** (`AnnotateState`) as a single source of truth.
- **Slider Optimization**: Employs "preview" values (e.g., `previewPadding`) during dragging to ensure smooth UI response, committing to the actual value only after the drag ends.
- **Image Caching**: `AnnotateState` pre-caches background images in `cachedBackgroundImage` when the URL changes to avoid disk I/O during rendering.

## Wallpaper Types Supported
- **Solid Color**: Any SwiftUI `Color`.
- **Gradients**: 8 predefined linear gradients (e.g., Pink-Orange, Blue-Purple).
- **System Wallpapers**: Native macOS wallpapers fetched from system paths.
- **Custom Images**: User-selected image files via `NSOpenPanel`.
- **Presets**: Bundled abstract gradients (Ocean, Sunset, Forest).

## View Hierarchy & UI Components
- **Sidebar Sections**: Grouped into `SidebarGradientSection`, `SidebarWallpaperSection`, and `SidebarColorSection`.
- **Grid Layout**: Uses `LazyVGrid` for wallpaper and color swatches.
- **Slider Controls**: `SidebarSlidersSection` provides fine-grained control over layout parameters.

## Integration Points
- **AnnotateState**: The primary integration point; all rendering logic in the canvas reads from this state.
- **SystemWallpaperManager**: Integrated into the sidebar via `.task` to load wallpapers when the view appears.

## Reusable Patterns for VideoEditor
- **Enum-based Style**: Reusing `BackgroundStyle` ensures consistency between images and videos.
- **Smooth Sliders**: Replicate the `previewValue` pattern for real-time video property adjustments.
- **Wallpaper Service**: `SystemWallpaperManager` can be used as-is in the VideoEditor sidebar.
- **Image Alignment**: `imageOffset` calculation logic in `AnnotateState` handles 9-point alignment (center, topLeft, etc.).

## Unresolved Questions
- How does the `blurred` style handle real-time rendering performance for high-resolution images?
- Is there a standardized `BackgroundThumbnailView` component, or is each section implementing its own preview logic?
