# Keyboard Shortcuts

## Tool Selection

| Shortcut | Tool | Icon |
|----------|------|------|
| `V` | Selection | arrow.up.left |
| `C` | Crop | crop |
| `R` | Rectangle | rectangle |
| `O` | Oval/Circle | circle |
| `A` | Arrow | arrow.right |
| `L` | Line | line.diagonal |
| `T` | Text | textformat |
| `H` | Highlighter | highlighter |
| `B` | Blur | aqi.medium |
| `N` | Counter/Number | number |
| `P` | Pencil | pencil |

## Actions

| Shortcut | Action |
|----------|--------|
| `⌘Z` | Undo |
| `⌘⇧Z` | Redo |
| `⌘S` | Save |
| `⌘⇧S` | Save As... |
| `⌘C` | Copy to clipboard |
| `⌘W` | Close window |
| `Escape` | Deselect / Cancel |
| `Delete` | Delete selected annotation |
| `⌘A` | Select all annotations |

## Canvas Navigation

| Shortcut | Action |
|----------|--------|
| `⌘+` | Zoom in |
| `⌘-` | Zoom out |
| `⌘0` | Fit to window |
| `⌘1` | Actual size (100%) |
| `Space + Drag` | Pan canvas |

## Modifier Keys (while drawing)

| Modifier | Effect |
|----------|--------|
| `⇧` (Shift) | Constrain to straight line / perfect square / circle |
| `⌥` (Option) | Draw from center |
| `⌘` (Command) | Temporarily switch to selection tool |

## Implementation Notes

1. Register shortcuts in `AnnotateMainView` using `.keyboardShortcut()` modifier
2. For single-key shortcuts (V, R, O, etc.), use `onKeyPress` or `NSEvent` monitoring
3. Tool shortcuts should only work when canvas is focused (not text input)
4. Cmd+Z/Cmd+Shift+Z should work globally in the annotation window
