# Main View Background Rendering Optimization

## Overview

Optimize background rendering in VideoEditor and Annotate main views by implementing tiered image caching. Currently both features load 6K+ HEIC wallpapers at full resolution for display, causing unnecessary memory usage and rendering latency.

## Tiered Caching Architecture

| Tier | Size | Use Case | Status |
|------|------|----------|--------|
| Thumbnail | 128px | Sidebar grid display | Implemented |
| Preview | 2048px | Main view display | NEW |
| Full Resolution | Original | Export only | On-demand |

## Key Decisions

- **ImageIO downsampling** at 2048px (4K retina quality, ~4MB vs 50MB+ full-res)
- **Extend SystemWallpaperManager** with `loadPreviewImage()` method
- **Reuse NSCache infrastructure** already proven for thumbnails
- **Keep full-res for export** - ZoomCompositor loads from URL on-demand

## Phases

| Phase | Description | Status |
|-------|-------------|--------|
| [Phase 1](./phase-01-tiered-cache-infrastructure.md) | Add preview cache to SystemWallpaperManager | Pending |
| [Phase 2](./phase-02-videoeditor-integration.md) | Integrate preview cache into VideoEditor | Pending |
| [Phase 3](./phase-03-annotate-integration.md) | Update Annotate to use preview cache | Pending |
| [Phase 4](./phase-04-export-fullres.md) | Verify export uses full resolution | Pending |

## Success Metrics

- Memory reduction: ~90% for wallpaper display (4MB vs 50MB)
- Smooth slider interactions maintained
- Export quality unchanged (full resolution)
- No visible quality loss at 2048px preview

## Risk Assessment

- **Low**: ImageIO is battle-tested, same pattern as existing thumbnail cache
- **Medium**: Async loading may cause brief placeholder flash on wallpaper change

## Related Files

- `/ClaudeShot/Core/Services/SystemWallpaperManager.swift`
- `/ClaudeShot/Features/VideoEditor/State/VideoEditorState.swift`
- `/ClaudeShot/Features/Annotate/State/AnnotateState.swift`
- `/ClaudeShot/Features/VideoEditor/Export/ZoomCompositor.swift`
