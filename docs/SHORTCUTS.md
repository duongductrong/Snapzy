# Shortcuts & URL Scheme Automation

Global keyboard shortcuts, in-overlay capture shortcuts, Annotate editor shortcuts, conflict detection, the cheat-sheet overlay, and the `snapzy://` deep-link route table.

Verified against `Snapzy/Services/Shortcuts/`, `Snapzy/Features/Shortcuts/`, `Snapzy/Features/Annotate/Services/AnnotateShortcutManager.swift`, `Snapzy/App/SnapzyDeepLinkHandler.swift`, `Snapzy/Services/Capture/CaptureOverlayShortcutSettings.swift` at HEAD (`v1.30.0-beta.14`).

## Global shortcut mechanism

```mermaid
flowchart TD
    A["User presses hotkey"] --> B["Carbon RegisterEventHotKey<br/>event handler (app event target)"]
    A2["User presses Fn combo"] --> B2["NSEvent global+local keyDown monitors<br/>(fnBindings)"]
    B --> C["KeyboardShortcutManager.handleHotkey(id:)<br/>maps EventHotKeyID → ShortcutAction"]
    B2 --> C
    C --> D{"delegate set?"}
    D -- no --> E["log warning, ignore"]
    D -- yes --> F["ScreenCaptureViewModel.shortcutTriggered(action)"]
    F --> G["dispatch to capture / record / open actions"]
```

- Engine: `KeyboardShortcutManager.shared` (`Snapzy/Services/Shortcuts/KeyboardShortcutManager.swift`) — Carbon `RegisterEventHotKey` / `UnregisterEventHotKey`; hotkey IDs use signatures `ZSF1`…`ZSFK` (`0x5A53_46xx`).
- Config model: `ShortcutConfig { keyCode: UInt32, modifiers: UInt32 }` (Carbon modifiers), persisted as JSON in UserDefaults under per-shortcut keys (`fullscreenShortcut`, `areaShortcut`, `recordingShortcut`, …).
- Fn modifier: custom bit `ShortcutConfig.functionCarbonModifier = 0x2000`. Carbon `RegisterEventHotKey` cannot express Fn, so Fn-containing configs are **not** Carbon-registered — they are collected into `fnBindings` and dispatched via global+local `NSEvent` keyDown monitors (`updateFnMonitors()` / `handleFnKeyDown`), matched exactly (keyCode + full modifier set incl. Fn) by `ShortcutConfig.matches(event:)`. Fn-only combos (e.g. `fn+F3`) and Fn+modifier combos (e.g. `fn+⌘+F3`) both fire; the non-Fn sibling combo is never hijacked.
  - Requires Accessibility permission (global key monitors silently deliver nothing without it) — the Shortcuts settings tab shows a hint row when an Fn binding exists but `AXIsProcessTrusted()` is false (`KeyboardShortcutManager.hasFnBoundShortcuts`).
  - Monitors are passive: unlike Carbon hotkeys, the frontmost app still receives the keystroke.
  - Monitors are installed only while `shouldRegisterShortcuts` holds and at least one Fn binding exists; temporary suppression (shortcut recording) removes them.
- Delegate: `KeyboardShortcutDelegate.shortcutTriggered(ShortcutAction)` — implemented by `ScreenCaptureViewModel` (`Snapzy/Features/Capture/CaptureViewModel.swift`).
- Global enable: `shortcutsEnabled` UserDefaults flag; `enable()` / `disable()` re-register everything. Restored at init if previously enabled.
- Temporary suspension: `beginTemporaryShortcutSuppression()` / `endTemporaryShortcutSuppression()` — refcounted, unregisters hotkeys without touching the persisted enabled flag (used while recording shortcut input).
- Per-shortcut disable set: `shortcuts.disabledGlobalActions` (`PreferencesKeys.disabledGlobalShortcuts`).
- Cleared/unbound set: `shortcuts.clearedGlobalActions` (`PreferencesKeys.clearedGlobalShortcuts`) — `shortcut(for:)` returns `nil` for cleared kinds.

## Global shortcut table

All 18 `GlobalShortcutKind`s with shipping defaults (verified in `KeyboardShortcutManager.swift`):

| Kind | Action | Default |
| --- | --- | --- |
| `fullscreen` | Capture Fullscreen | ⌘⇧3 |
| `area` | Capture Area | ⌘⇧4 |
| `areaAnnotate` | Capture Area & Annotate | ⌘⇧7 |
| `activeWindow` | Capture Active Window | ⌘⇧9 |
| `scrollingCapture` | Scrolling Capture | ⌘⇧6 |
| `recording` | Record Screen (start/stop toggle) | ⌘⇧5 |
| `ocr` | Capture Text (OCR) | ⌘⇧2 |
| `smartElement` | Capture Smart Element | ⌥⇧4 |
| `objectCutout` | Object Cutout | ⌘⇧1 |
| `annotate` | Open Annotate | ⌘⇧A |
| `videoEditor` | Open Video Editor | ⌘⇧E |
| `cloudUploads` | Cloud Uploads window | ⌘⇧L |
| `shortcutList` | Shortcut cheat sheet overlay | ⌘⇧K |
| `history` | History panel toggle | ⌘⇧H |
| `pauseResumeRecording` | Pause/Resume recording | **unbound** (recommended ⌘⇧Space) |
| `togglePenRecording` | Toggle pen overlay while recording | **unbound** |
| `restartRecording` | Restart current recording | **unbound** |
| `deleteRecording` | Delete in-progress recording | **unbound** |

- The four unbound-by-default kinds are seeded into the cleared set on first launch (`seedDefaultClearedShortcutsOnFirstLaunchIfNeeded`) so they never shadow existing user config. `pauseResumeRecordingShortcut` keeps the recommended ⌘⇧Space as its backing value, but resolves to `nil` via `shortcut(for:)` until the user binds it.
- Editing UI: Settings → Shortcuts (see [PREFERENCES.md](PREFERENCES.md)).

## Overlay shortcuts (in-overlay, not plain global hotkeys)

`CaptureOverlayShortcutSettings` (`Snapzy/Services/Capture/CaptureOverlayShortcutSettings.swift`):

- Two kinds: `applicationCapture` and `applicationRecording`; both default to single key **A** with no modifiers (child mode).
- Child mode (modifiers == 0): pressed *inside* the area-selection / recording overlay to switch to application-window mode. Menu bar items show it as a suffix of the parent shortcut.
- Independent mode (modifiers ≠ 0): registered as its own global hotkey (`applicationCaptureHotkeyRef` / `applicationRecordingHotkeyRef`) firing `.captureApplication` / `.recordApplication`.
- Keys: `shortcuts.area.applicationCapture`, `shortcuts.recording.applicationCapture`.

## Recording-behavior notes

- `recording` shortcut is a start/stop toggle: `toggleRecordingFromShortcut` stops the active recording (`RecordingCoordinator.stopFromStatusItem()`) or starts the recording flow otherwise.
- `pauseResumeRecording` no-ops unless a recording is active (`state.isPauseResumeEligible` guard, logged when ignored).
- `togglePenRecording` no-ops unless `RecordingCoordinator.shared.isActive`.

## Annotate editor shortcuts

`AnnotateShortcutManager` (`Snapzy/Features/Annotate/Services/AnnotateShortcutManager.swift`):

- 14 tool single-key shortcuts (`AnnotationToolType.defaultShortcut`, remappable): crop, selection, rectangle, filledRectangle, oval, arrow, line, text, highlighter, blur, spotlight, counter, watermark, pencil. (`mockup` excluded — internal only.)
- Tool keys stored per-tool under prefix `annotate.shortcut.`; per-tool disable set `shortcuts.disabledAnnotateToolShortcuts`.
- Action shortcuts (`AnnotateActionShortcutKind`, modifier combos as `ShortcutConfig`):

  | Kind | Default | Key |
  | --- | --- | --- |
  | `copyAndClose` | ⌘⇧C | `annotate.action.copyAndClose` |
  | `toggleSidebar` | ⌘B | `annotate.action.toggleSidebar` |
  | `togglePin` | ⌃⌘P | `annotate.action.togglePin` |
  | `cloudUpload` | ⌘U | `annotate.action.cloudUpload` |
  | `autoRedactSensitiveData` | unbound | `annotate.action.autoRedactSensitiveData` |

- Action disable set: `shortcuts.disabledAnnotateActionShortcuts`.

## Conflict detection

`ShortcutValidationService` (`Snapzy/Services/Shortcuts/ShortcutValidationService.swift`):

- Cross-namespace duplicate checks (global ↔ annotate action ↔ independent overlay ↔ annotate tool): duplicate → `.reject` with `.error` severity, blocks assignment.
- System screenshot conflicts: `SystemScreenshotShortcutManager` reads `com.apple.symbolichotkeys` via `UserDefaults(suiteName:)` (requires the shared-preference entitlement — see [APP_LIFECYCLE.md](APP_LIFECYCLE.md)). Symbolic hotkey IDs: 28 (save area), 29 (copy area), 30 (save screen), 31 (copy screen), 184 (screenshot options).
- Only `fullscreen`, `area`, `recording` are `isSystemConflictRelevant`; conflicts surface as `.warning` (accepted, non-blocking).
- Prompt-once flow: `systemShortcutsDisablePromptSeen` UserDefaults flag gates the "disable macOS shortcuts" prompt; unreadable plist → assume no conflict (no nag).

## Shortcut cheat sheet overlay

- `ShortcutOverlayManager` (`Snapzy/Features/Shortcuts/ShortcutOverlayManager.swift`) — full-screen borderless `NSPanel` (`.screenSaver` level, joins all spaces), content from `ShortcutOverlayContentBuilder.buildSections()` (`Snapzy/Features/Shortcuts/ShortcutOverlayModels.swift`).
- Open/toggle: ⇧⌘K, menu bar → Keyboard Shortcuts, or `snapzy://show/shortcuts`. Blocked while recording (`RecordingCoordinator.shared.isActive` guard).
- Esc closes (local + global monitors); "Open Settings" deep-links to Settings → Shortcuts.

## URL scheme automation

Scheme: `snapzy://` (registered in `Snapzy/Resources/Info.plist` `CFBundleURLTypes`).

Gate: `urlSchemeEnabled` (default `true`; Settings → Advanced → URL Scheme integration). Disabled or unknown routes are logged and ignored.

Dispatch: AppleEvent `kAEGetURL` → `AppDelegate` (queued pre-launch) → `AppCoordinator.handleDeepLink` → `SnapzyDeepLinkHandler` (`Snapzy/App/SnapzyDeepLinkHandler.swift`); routes parsed by `SnapzyDeepLinkAction.init?(url:)`.

### Canonical route table

| Route | Action |
| --- | --- |
| `snapzy://capture/fullscreen` | Capture fullscreen |
| `snapzy://capture/area` | Capture area |
| `snapzy://capture/application` | Application-window capture |
| `snapzy://capture/active-window` | Capture active window |
| `snapzy://capture/area-annotate` | Capture area → Annotate |
| `snapzy://capture/scrolling` | Scrolling capture |
| `snapzy://capture/ocr` | OCR capture |
| `snapzy://capture/smart-element` | Smart Element capture |
| `snapzy://capture/object-cutout` | Object cutout |
| `snapzy://record/screen` | Start screen recording |
| `snapzy://record/application` | Application-window recording |
| `snapzy://open/annotate` | Open empty Annotate editor |
| `snapzy://open/combine` | Combine images (see params below) |
| `snapzy://open/video-editor` | Open empty Video Editor |
| `snapzy://open/cloud-uploads` | Toggle Cloud Uploads window |
| `snapzy://open/history` | Toggle History panel |
| `snapzy://show/shortcuts` | Toggle shortcut cheat sheet |
| `snapzy://settings` / `snapzy://settings?tab=<tab>` | Open Settings, optionally to a tab |

- `open/combine` query params: repeat `?file=` with absolute paths; ≥2 valid files → combines directly, otherwise opens the combine picker (`CombineImagesCoordinator.presentPicker()`). Example:

  ```sh
  open 'snapzy://open/combine?file=/tmp/first.png&file=/tmp/second.png'
  ```

- Settings tabs: `general`, `capture`, `annotate`, `quick-access`, `history`, `shortcuts`, `permissions`, `cloud`, `advanced`, `about`. Also accepted as path form (`snapzy://settings/capture`).
- Aliases exist for most routes — e.g. `capture/focused-window`, `capture/window`, `record/window`, `screenshot/area`, `ocr`, `annotate`, `combine`, `uploads`, `history`, `shortcuts`, `preferences`, plus tab aliases (`screenshots`, `privacy`, `config`, `toml`, …). Full alias list: `SnapzyDeepLinkAction.init?(url:)` in `Snapzy/App/SnapzyDeepLinkHandler.swift`.

## Related docs

- [APP_LIFECYCLE.md](APP_LIFECYCLE.md) — deep-link dispatch, entitlements, menu bar
- [PREFERENCES.md](PREFERENCES.md) — Shortcuts tab reference
- [CAPTURE.md](CAPTURE.md) — capture flows triggered by shortcuts
- [RECORDING.md](RECORDING.md) — recording start/stop/pause behavior
- [ANNOTATE.md](ANNOTATE.md) — editor tools and actions
- [CONFIGURATION.md](CONFIGURATION.md) — TOML control of shortcut prefs
