# Recording Annotation Overlay - Implementation Plan

## Summary
Add real-time annotation drawing during screen recording. Users toggle an annotation toolbar from the recording status bar, draw on a transparent overlay captured in video, with auto-snapping draggable toolbar that adapts horizontal/vertical layout based on screen position.

## Architecture Decision
**Approach: Transparent overlay window rendered INTO the recording area** — annotations drawn on a transparent NSWindow within the capture rect are automatically captured by ScreenCaptureKit (no frame compositing needed). This is the simplest, most performant approach.

## Phases

| # | Phase | Status | File |
|---|-------|--------|------|
| 1 | Recording Annotation State & Data Layer | pending | [phase-01-state-layer.md](phase-01-state-layer.md) |
| 2 | Annotation Toggle in Recording Toolbar/StatusBar | pending | [phase-02-toolbar-toggle.md](phase-02-toolbar-toggle.md) |
| 3 | Floating Annotation Toolbar (Draggable + Snap + Direction) | pending | [phase-03-annotation-toolbar.md](phase-03-annotation-toolbar.md) |
| 4 | Transparent Drawing Overlay Window | pending | [phase-04-drawing-overlay.md](phase-04-drawing-overlay.md) |
| 5 | Integration with RecordingCoordinator | pending | [phase-05-coordinator-integration.md](phase-05-coordinator-integration.md) |

## Key Insight
ScreenCaptureKit captures ALL visible windows in the recording rect (except excluded apps). A transparent NSWindow with annotations drawn on it will appear in the recording automatically — **zero frame compositing code needed**. The toolbar itself is excluded (our app is excluded from capture), but the overlay window must NOT be excluded.

## Risk Assessment
- **Low risk**: Reusing existing AnnotationRenderer + AnnotationItem models
- **Medium risk**: Overlay window must be included in capture while toolbar is excluded
- **Mitigation**: Create overlay as a separate NSWindow not owned by our app bundle, OR use a child process, OR mark it specifically for inclusion via `exceptingWindows`

## Tools Subset for Recording
Selection, Rectangle, Oval, Arrow, Line, Pencil, Highlighter (7 tools — no crop/blur/text/counter/mockup)

## Auto-Clear Feature
Annotations can auto-disappear based on per-tool configurable rules:
- **Time-based**: Annotation fades out after X seconds (e.g., 3s, 5s, 10s, never)
- **Count-based**: Annotation removed when N newer annotations are drawn (e.g., after 3, 5, 10 more draws)
- **Configurable per tool**: Each tool can independently choose time-based, count-based, or persist (never clear)
- Default: persist (never auto-clear) — user opts in via toolbar popover per tool
