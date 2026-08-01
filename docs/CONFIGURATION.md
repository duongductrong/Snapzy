# TOML Configuration

Snapzy can export and import user-editable TOML configuration for backup,
dotfiles, and machine-to-machine setup. If the file changes while Snapzy is
closed, Snapzy automatically applies the valid TOML on the next launch.

Default path:

```text
~/.config/snapzy/config.toml
```

Settings -> Advanced -> Backup requires config folder access before Import,
Export, Restore defaults, or Open config.toml can be used. Granting access lets
Snapzy create `config.toml` with the current preferences if it is missing.
After launch, Snapzy observes app preference changes and debounces background
syncs into the managed file. The sync compares current settings with
`config.toml`; if the file is simply stale from older in-app changes, Snapzy
updates it. If the file appears to have external edits that Snapzy has not
applied yet, Snapzy stops and asks before replacing it. Settings -> Advanced
shows the current sync state and a manual Sync Now action. Open config.toml uses
the same safe sync path before opening the file.

When Settings asks for confirmation, Snapzy remembers the exact file signature
that caused the conflict. If `config.toml` changes again before the user
confirms replacing it, Snapzy cancels the write and asks the user to review the
file again.

Snapzy does not live-watch direct edits to `config.toml`; those edits are picked
up on the next app launch, or through explicit Import. Explicit import validates
a selected `.toml` backup, replaces the managed
`~/.config/snapzy/config.toml`, then applies it immediately.

If `~/.config` or `~/.config/snapzy` does not exist yet, the grant flow starts
from the nearest existing parent and creates the missing folder after the user
confirms access. Snapzy stores the bookmark for `~/.config/snapzy`.

For existing users upgrading from a version without TOML config support, Snapzy
opens the normal onboarding window directly on the config access step once
after launch. Granting access stores the folder bookmark, creates `config.toml`
if needed, and applies an existing valid file immediately. Users can skip the
step and grant access later from Settings -> Advanced.

## Scope

The TOML file covers portable app preferences:

- General settings: language, appearance, sounds, URL scheme integration, show menu bar icon, login item, export folder path.
- Menu bar customization: icon style, item order, hidden items (`[menu_bar]`). The custom icon PNG file itself is not portable — `icon_style = "custom"` falls back to `default` on a Mac without a locally imported custom icon.
- Updates: automatic check/download and the Sparkle update channel (`stable` or `beta`).
- Capture settings: naming templates, screenshot format, cursor/app inclusion, freeze area, show selection area overlay, reverse magnifier zoom direction, scrolling hints, OCR notification, object cutout auto-crop.
- After-capture actions for screenshot and recording: `save`, `quick_access`, `copy_file`, and `open_annotate` under `[capture.after.screenshot]` / `[capture.after.recording]`. Cloud upload is not part of this matrix — it is manual-only from Quick Access, Annotate, Video Editor, and History surfaces.
- Recording settings: format, quality, FPS, audio, microphone device id, cursor, click highlights, keystroke overlay, live annotation shortcuts, video editor zoom transition duration.
- Quick Access: visibility, position, countdown behavior, gesture toggles, trackpad swipe mode, swipe left/right actions, hide card when window open, animation style, action order, enabled actions, card slots.
- History: retention, maximum count, floating panel layout and filter.
- Cloud metadata: provider, bucket, region, endpoint, custom domain, expiration, and upload window position.
- Annotate preferences.
- Global, overlay, Annotate tool, and Annotate action shortcuts.

The export intentionally excludes secrets and machine-private state:

- Cloud access key and secret key are not exported. They remain in Keychain.
- Cloud credential archive transfer stays in the existing encrypted cloud
  import/export flow.
- Cloud configured/password-protection state is not exported because it depends
  on local Keychain items.
- Capture history, temp files, annotation sidecars, upload history, caches, and
  app diagnostics are not part of `config.toml`.
- File-access security-scoped bookmarks are not portable. Imported folder paths
  may still need to be confirmed in Settings on the destination Mac.

## Schema

Current schema version:

```toml
schema_version = 1
snapzy_min_version = "1.20.0"
```

Unknown keys are ignored. Known keys are validated by type and allowed value.
If import finds any error, Snapzy applies none of the changes. Warnings do not
block import.

Capture naming templates support `{datetime}`, `{date}`, `{year}`,
`{yearShort}`, `{month}`, `{monthName}`, `{monthShort}`, `{day}`, `{time}`,
`{ms}`, `{timestamp}`, `{type}`, and `{appName}`. Use `/` to
create subfolders under the selected export folder; each path segment is
sanitized and traversal segments are ignored.
`{year_short}`, `{yy}`, `{month_name}`, `{month_short}`, and `{app_name}`
are also accepted as aliases.

`{appName}` resolves to the captured application's name (or frontmost app name
for fullscreen/area captures). It resolves to an empty string when the context
is not available.

## Example

```toml
schema_version = 1
snapzy_min_version = "1.20.0"

[general]
language = "system"
appearance = "system"
play_sounds = true
url_scheme_enabled = true
show_menu_bar_icon = true
start_at_login = false
export_location = "~/Desktop"

[updates]
check_automatically = true
download_automatically = false
channel = "stable" # "stable" | "beta" — invalid values are rejected on import

[menu_bar]
icon_style = "default" # "default" | "cameraViewfinder" | "cameraFill" | "scissors" | "photoOnRectangle" | "custom"
item_order = ["captureArea", "captureAreaAnnotate", "captureApplication", "captureFullscreen", "captureActiveWindow", "scrollingCapture", "captureOCR", "captureSmartElement", "captureObjectCutout", "recordScreen", "recordApplication", "openAnnotate", "combineImages", "editVideo", "cloudUploads", "openHistory", "shortcutList"]
hidden_items = []

[capture]
hide_desktop_icons = false
hide_desktop_widgets = false

[capture.naming]
screenshot_template = "Screenshots/{appName}/{yearShort}/{monthName}/{day}/Snapzy_{time}_{ms}"
recording_template = "Recordings/{appName}/{year}/{monthShort}/Snapzy_Recording_{day}_{time}"

[capture.screenshot]
format = "png"
include_snapzy = false
show_cursor = false
freeze_area = false
show_selection_area_overlay = true
reverse_magnifier_zoom_direction = false

[capture.after.screenshot]
save = true
quick_access = true
copy_file = false
open_annotate = false

[recording]
format = "mov"
quality = "high"
fps = 30
capture_system_audio = false
capture_microphone = false
show_cursor = true
dim_non_selected_area = true
highlight_clicks = false
show_keystrokes = false
video_editor_zoom_transition_duration = 0.4

[quick_access]
enabled = true
position = "topTrailing"
auto_dismiss = true
auto_dismiss_delay = 8.0
pause_countdown_on_hover = true
overlay_scale = 1.0
drag_drop = true
two_finger_swipe_to_dismiss = true
trackpad_swipe_mode = "inverted"
swipe_left_action = "dismiss"
swipe_right_action = "dismiss"
hide_card_when_window_open = true
animation_style = "slide"
actions_order = ["copy", "saveOrOpen", "edit", "uploadToCloud", "pinToScreen", "dismiss", "delete"]
enabled_actions = ["copy", "delete", "dismiss", "edit", "pinToScreen", "saveOrOpen", "uploadToCloud"]

[history]
enabled = true
retention_days = 30
max_count = 500

[annotate]
clipboard_image_open_behavior = "ask"
default_tool = "selection"
remember_last_tool = false
close_after_drag = true
bring_forward_after_drag = false
quick_properties_sync = true
combine_save_as_edit = true
crop_snap_to_edges = true

[shortcuts.global.fullscreen]
key = "3"
modifiers = ["command", "shift"]
enabled = true

[shortcuts.annotate_actions.auto_redact_sensitive_data]
enabled = true
key = ""
modifiers = []

[shortcuts.quick_access.edit_latest_capture]
enabled = false
key = "return"
modifiers = ["command"]
```

## Manual Testing

Use these commands to reset only the TOML config access state while keeping the
app in an existing-user state. This simulates an upgrade from a version that did
not have `config.toml` support yet.

```bash
osascript -e 'quit app "Snapzy"' 2>/dev/null || true

PLIST="$HOME/Library/Containers/com.trongduong.snapzy/Data/Library/Preferences/com.trongduong.snapzy"

defaults write "$PLIST" onboardingCompleted -bool true
defaults write "$PLIST" sponsorPromptSeen -bool true
defaults delete "$PLIST" configuration.accessOnboardingPrompted 2>/dev/null || true
defaults delete "$PLIST" configuration.directoryBookmark 2>/dev/null || true
defaults delete "$PLIST" configuration.fileBookmark 2>/dev/null || true
defaults delete "$PLIST" configuration.lastAppliedSignature 2>/dev/null || true

killall cfprefsd 2>/dev/null || true
```

To test the missing-folder path, remove the user-managed config folder before
launching Snapzy:

```bash
rm -rf "$HOME/.config/snapzy"
open -a Snapzy
```

Expected result: Snapzy opens the onboarding window directly on the config
access step. After granting access, the user remains on the step until clicking
Continue. Snapzy creates
`~/.config/snapzy/config.toml` automatically and no manual export/import step is
required.

To test applying an existing direct edit after grant, prepare a config file
first:

```bash
mkdir -p "$HOME/.config/snapzy"
cp "$HOME/Desktop/config.toml" "$HOME/.config/snapzy/config.toml"
open -a Snapzy
```

Expected result: after the user grants access, Snapzy stores the folder
bookmark and applies the existing valid `config.toml` immediately.

To test the Settings -> Advanced warning without showing the launch step, mark
the config access onboarding step as already shown, then remove the stored
folder/file bookmarks:

```bash
osascript -e 'quit app "Snapzy"' 2>/dev/null || true

PLIST="$HOME/Library/Containers/com.trongduong.snapzy/Data/Library/Preferences/com.trongduong.snapzy"

defaults write "$PLIST" onboardingCompleted -bool true
defaults write "$PLIST" sponsorPromptSeen -bool true
defaults write "$PLIST" configuration.accessOnboardingPrompted -bool true
defaults delete "$PLIST" configuration.directoryBookmark 2>/dev/null || true
defaults delete "$PLIST" configuration.fileBookmark 2>/dev/null || true

killall cfprefsd 2>/dev/null || true
open -a Snapzy
```

Expected result: Settings -> Advanced -> Backup shows a config access warning.
Import, Export, Restore defaults, and Open config.toml are disabled until access
is granted.
Clicking the warning row or the Grant Access button opens the same folder grant
flow. Completed backup actions show a toast instead of a persistent Last Result
log section.

## Implementation Notes

- `SnapzyConfigurationService` is the facade used by Settings.
- `SnapzyConfigurationSyncCoordinator` observes preference changes, debounces
  background app-to-file syncs, flushes pending sync before Open config.toml and
  app termination, and exposes status for Settings -> Advanced.
- `SnapzyConfigurationAccessGranting` owns the shared macOS folder picker flow
  used by onboarding and Settings -> Advanced. A successful grant prepares the
  default folder and file so the user does not need to export/import manually.
- Settings import replaces the managed `config.toml` after validation succeeds,
  then applies the same contents so the backup file and app state stay aligned.
- Background sync and Open config.toml sync current settings into the managed
  file only when the file still matches Snapzy's last applied/exported
  signature. If the file has unapplied external edits, Settings asks before
  replacing it.
- Debounced background sync exports settings on the main actor, then performs
  managed file I/O on a utility-priority task so ordinary settings UI remains
  responsive. All managed `config.toml` reads/writes use a shared serial queue
  so manual actions, Open config.toml, Import/Restore, and background sync do
  not write the file concurrently.
- Only the latest managed config operation may update Snapzy's
  `configuration.lastAppliedSignature`, which prevents an older background sync
  from marking stale contents after a newer Import/Restore/manual sync.
- Restore defaults replaces the managed `config.toml` with a generated default
  TOML document and applies it after confirmation.
- `SnapzyConfigurationAutoImporter` runs during app launch, hashes the current
  file contents, and imports only when `config.toml` changed since the last
  successful launch-time apply.
- `SnapzyConfigurationExporter` and its shortcut extension build deterministic
  TOML so exported files are diff-friendly.
- `SnapzyConfigurationImporter` parses, validates, then applies mutations only
  after validation succeeds.
- `SimpleTOMLParser` is intentionally focused on Snapzy's schema surface:
  strings, booleans, integers, doubles, arrays, dotted keys, and nested tables.

## Related docs

- [`PREFERENCES.md`](PREFERENCES.md) — in-app preferences backing the exported keys
- [`CLOUD.md`](CLOUD.md) — cloud credentials, manual upload entry points
- [`APP_LIFECYCLE.md`](APP_LIFECYCLE.md) — launch-time auto-import and onboarding grant flow
- [`SHORTCUTS.md`](SHORTCUTS.md) — shortcut sections exported to TOML
