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

- General settings: language, appearance, sounds, URL scheme integration, `snapzy` command line access (`cli_enabled`, default `true`), show menu bar icon, login item, export folder path.
- Menu bar customization: icon style, item order, hidden items, and the macOS 27 "Show icons in menus" opt-in (`[menu_bar] show_item_icons`, default `false`; ignored on earlier macOS versions, which always show menu icons). The custom icon PNG file itself is not portable — `icon_style = "custom"` falls back to `default` on a Mac without a locally imported custom icon.
- Updates: automatic check/download and the Sparkle update channel (`stable` or `beta`).
- Capture settings: naming templates, screenshot format (`[capture.screenshot] format`: `"png"`, `"jpeg"`, `"webp"`, `"heic"`, or `"avif"`; importing `"avif"` on a macOS without an AVIF encoder keeps the value but warns, and captures save as PNG there), clipboard content for copied images (`[capture.screenshot] clipboard_content`: `"image_and_file"` (default) or `"image_only"`, which drops the file reference for Citrix/RDP/terminal paste targets), cursor/app inclusion, freeze area, Delayed Capture countdown (`[capture.screenshot] delayed_capture_seconds`: `3`, `5`, or `10`, default `3`; shared by delayed area and delayed fullscreen), show selection area overlay, magnifier preferences (`[capture.screenshot] reverse_magnifier_zoom_direction`, `show_magnifier_by_default`, `show_magnifier_color_panel`, `magnifier_size`: `"small"`, `"medium"`, or `"large"`, default `"medium"`), window shadow in Application Capture (`[capture.screenshot] include_window_shadow`, default `true`), scrolling hints, OCR notification (`[capture.ocr] success_notification`, default `true`), OCR provider selection (`[capture.ocr] selected_model`: `"builtin"` or `"custom:<uuid>"`), and custom OCR endpoint metadata (`[capture.ocr] custom_models`: JSON array, API keys excluded), object cutout auto-crop.
- After-capture actions for screenshot and recording: `save`, `quick_access`, `copy_file`, and `open_annotate` under `[capture.after.screenshot]` / `[capture.after.recording]`. Cloud upload is not part of this matrix — it is manual-only from Quick Access, Annotate, Video Editor, and History surfaces.
- Recording settings: format, quality, FPS, audio, microphone device id, cursor, click highlights, keystroke overlay, live annotation shortcuts, video editor zoom transition duration.
- Quick Access: visibility, position, countdown behavior, gesture toggles, trackpad swipe mode, pinned image zoom mode (`pin_zoom_mode`: `fixedViewport` by default or `windowFollowsImage`), swipe left/right actions, hide card when window open, animation style, open in Finder after saving (`[quick_access] open_in_finder_after_save`, default `true`), action order, enabled actions, card slots, hover-activated card action shortcuts.
- History: retention, maximum count, floating panel layout and filter.
- Cloud metadata: provider, bucket, region, endpoint, custom domain, expiration, share link style (`[cloud] share_link_style`: `"descriptive"` or `"short"`, default `"descriptive"`, S3 and R2 only), upload window position, and with `provider = "custom_http"` the active custom uploader (`[cloud] custom_uploader = "<uuid>"`). Custom uploader definitions are not in the file: they stay in Settings → Cloud on each Mac (a synced file cannot point uploads at a new server).
- Annotate preferences.
- Global, overlay, Annotate tool, Annotate action, and Video Editor action shortcuts.

The export intentionally excludes secrets and machine-private state:

- Cloud access key and secret key, and the imgbb API key, are not exported. They remain in Keychain. For imgbb the `[cloud]` table holds only `provider = "imgbb"` and `expire_time`.
- Custom OCR endpoint API keys are not exported. They remain in Keychain
  (`capture.ocr.custom_models` carries endpoint metadata only).
- Cloud credential archive transfer stays in the existing encrypted cloud
  import/export flow.
- Cloud configured/password-protection state is not exported because it depends
  on local Keychain items.
- Capture history, temp files, annotation sidecars, upload history, caches, and
  app diagnostics are not part of `config.toml`.
- Apps approved or denied for the `snapzy` command (`cliApprovedCallers`) are
  machine-specific and never exported or imported; only `cli_enabled` travels.
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
`{windowTitle}` (alias `{window.title}`) is the captured window's title, up to
80 characters with `/` replaced by `-`; empty for area and fullscreen captures.

## OCR provider configuration

Apple Vision is the built-in OCR provider and requires no model files. Custom
OpenAI-compatible endpoint metadata is stored in `capture.ocr.custom_models`;
API keys remain in the macOS Keychain and are never exported. The active
provider is stored in `capture.ocr.selected_model` as `builtin` or
`custom:<uuid>`.

Configurations created by older Snapzy versions may still contain a
`dl:<id>` selection or `catalog_models` field. The removed downloadable
provider is ignored and the selection is canonicalized to `builtin`.

## Annotate AI configuration

`[annotate.ai]` holds Annotate's AI prompt options ([AI.md](AI.md)):
`provider` (`automatic`, `apple`, `endpoint:<uuid>`, `cli:claude`,
`cli:codex`, `cli:opencode`; anything else imports as `automatic`),
`send_image`, `cli_timeout` (seconds, 30...1800) and a model override per
agent CLI (`claude_model`, `codex_model`, `opencode_model`; empty = the CLI's
default). CLI paths, sending permissions and learned endpoint capabilities are
per-Mac and never exported.

## Automations configuration

Automations ([AUTOMATIONS.md](AUTOMATIONS.md)) export as one keyed table each,
`[automations.<uuid>]`, because the parser has no arrays of tables. `order`
keeps the list order. Steps are keyed sub-tables `[automations.<uuid>.steps.<nn>]`
in run order.

```toml
[automations.8f0c2a6e-5a1d-4b6c-9a3e-2f1b0c9d8e7a]
order = 0
name = "Cloud Share"
preset = "cloud-share"
enabled = true
capture = "area"
save_to_export = false
shortcut_key = "4"
shortcut_modifiers = ["control", "shift"]
menu_bar = false
quick_access = true
history = true
external_invocation = false

[automations.8f0c2a6e-5a1d-4b6c-9a3e-2f1b0c9d8e7a.steps.01]
kind = "copy_image"

[automations.8f0c2a6e-5a1d-4b6c-9a3e-2f1b0c9d8e7a.steps.02]
kind = "upload"

[automations.8f0c2a6e-5a1d-4b6c-9a3e-2f1b0c9d8e7a.steps.03]
kind = "copy_link"
style = "markdown"   # url | markdown | html | bbcode | custom (+ template = "…")

[automations.8f0c2a6e-5a1d-4b6c-9a3e-2f1b0c9d8e7a.steps.04]
kind = "notify"
```

- `capture`: `area`, `fullscreen`, `active_window`, `application_window`,
  `scrolling`, `recording_area`, `recording_window` (with
  `recording_output = "video" | "gif"`), `clipboard` (the clipboard image), or
  `input` (runs on a file handed in by Quick Access, History, CLI or
  Shortcuts; `save_to_export` and shortcuts do not apply and are not exported).
- `menu_bar`, `quick_access`, `history`: list the automation in the menu bar
  Automations submenu (capture and clipboard sources; ignored for `input`), the
  Quick Access "Run Automation" menu, and the History "Run Automation" menu.
  Omitted keys keep the value stored in `data`.
- `external_invocation`: allow the URL scheme, `snapzy automation run` and
  Shortcuts to start it (default `false`). `true` in an imported file is
  honored and logged.
- Step tables: `kind` plus that kind's keys (snake_case), optional
  `enabled = false` and `on_failure = "continue"`. The full key list is in
  [AUTOMATIONS.md § Configuration](AUTOMATIONS.md#configuration-toml). Unknown
  keys warn. `save_to_folder.folder` is a path (`~` allowed) or `"export"`; the
  folder bookmark is created on import, and a missing folder is a warning (the
  step then shows "Needs setup").
- Integration steps (`webhook`, `run_script`, `run_shortcut`, `share_sheet`,
  `open_in_app`, `upload.destination`) are listed in
  [AUTOMATIONS.md § Configuration](AUTOMATIONS.md#configuration-toml). Secret
  values are never exported, only `{secret:NAME}` references. An imported
  automation whose webhook, custom-uploader, script or Shortcut steps differ
  from the one already on this Mac is marked "needs review" and won't run until
  it is opened and saved in Settings → Automations. Script and Shortcut steps
  stay off until "Allow script & Shortcut steps" is turned on in Settings; no
  file key can turn it on, and the per-automation "let other apps run its
  script steps" opt-in is never imported.
- Files from Snapzy before milestone 3 used `steps = ["copy_image",
  "upload_copy_link:markdown", …]`; that form is still imported
  (`upload_copy_link` becomes `upload` + `copy_link`).
- Each table also has `data` (the full automation JSON) so details the keys
  cannot express (steps or sources from a newer Snapzy) survive a round trip;
  edited keys and step tables win.
- The `[automations]` header is always exported. When the file has it, import
  replaces every automation (an empty section clears them); without it,
  automations are left untouched. Bad entries, unknown
  steps and modifier-less or duplicate shortcuts are warnings, never errors.

## Example

```toml
schema_version = 1
snapzy_min_version = "1.20.0"

[general]
language = "system"
appearance = "system"
play_sounds = true
url_scheme_enabled = true
cli_enabled = true
show_menu_bar_icon = true
start_at_login = false
export_location = "~/Desktop"

[updates]
check_automatically = true
download_automatically = false
channel = "stable" # "stable" | "beta" — invalid values are rejected on import

[menu_bar]
icon_style = "default" # "default" | "cameraViewfinder" | "cameraFill" | "scissors" | "photoOnRectangle" | "custom"
show_item_icons = false # macOS 27+: show icons next to Snapzy menu items
item_order = ["captureArea", "captureAreaAnnotate", "captureApplication", "captureFullscreen", "captureActiveWindow", "scrollingCapture", "captureOCR", "captureSmartElement", "captureObjectCutout", "recordScreen", "recordApplication", "openAnnotate", "combineImages", "editVideo", "cloudUploads", "openHistory", "shortcutList"]
hidden_items = []

[capture]
hide_desktop_icons = false
hide_desktop_widgets = false

[capture.naming]
screenshot_template = "Screenshots/{appName}/{yearShort}/{monthName}/{day}/Snapzy_{time}_{ms}"
recording_template = "Recordings/{appName}/{year}/{monthShort}/Snapzy_Recording_{day}_{time}"

[capture.screenshot]
format = "png" # "png" | "jpeg" | "webp" | "heic" | "avif"
clipboard_content = "image_and_file" # "image_and_file" | "image_only"
include_snapzy = false
show_cursor = false
freeze_area = false
delayed_capture_seconds = 3 # Delayed Capture countdown: 3, 5, or 10
show_selection_area_overlay = true
reverse_magnifier_zoom_direction = false
show_magnifier_by_default = false
show_magnifier_color_panel = true
magnifier_size = "medium"
include_window_shadow = true

[capture.ocr]
success_notification = true
selected_model = "builtin"
custom_models = "[]"

[capture.after.screenshot]
save = true
quick_access = true
copy_file = false
open_annotate = false

[recording]
format = "mov"
quality = "high"
max_resolution = "auto"
fps = 30
capture_system_audio = false
capture_microphone = false
show_cursor = true
studio_mode = false
dim_non_selected_area = true
highlight_clicks = false
show_keystrokes = false
video_editor_zoom_transition_duration = 0.4
video_editor_caption_language = ""

[quick_access]
enabled = true
play_sounds = true
open_in_finder_after_save = true
position = "topTrailing"
auto_dismiss = true
auto_dismiss_delay = 8.0
pause_countdown_on_hover = true
overlay_scale = 1.0
drag_drop = true
two_finger_swipe_to_dismiss = true
swipe_toward_edge_collapses = false
trackpad_swipe_mode = "inverted"
pin_zoom_mode = "fixedViewport"
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
auto_expand_canvas = true
crop_snap_to_edges = true
highlighter_text_snapping = true
measure_unit = "points"
measure_axis = "both"

[annotate.ai]
provider = "automatic"
send_image = true
cli_timeout = 180
claude_model = ""
codex_model = ""
opencode_model = ""

[shortcuts.global.fullscreen]
key = "3"
modifiers = ["command", "shift"]
enabled = true

[shortcuts.global.repeat_area]
key = "4"
modifiers = ["control", "command", "shift"]
enabled = true

[shortcuts.annotate_actions.auto_redact_sensitive_data]
enabled = true
key = ""
modifiers = []

[shortcuts.annotate_actions.auto_translate]
enabled = true
key = "t"
modifiers = ["command", "shift"]

[shortcuts.annotate_actions.translate_area]
enabled = true
key = "t"
modifiers = ["command", "option"]

[shortcuts.annotate_actions.ai_prompt]
enabled = true
key = "k"
modifiers = ["command"]

[shortcuts.video_editor.ai_prompt]
enabled = true
key = "k"
modifiers = ["command"]

[shortcuts.quick_access.edit_latest_capture]
enabled = false
key = "return"
modifiers = ["command"]

[shortcuts.quick_access.card_actions]
enabled = true

[shortcuts.quick_access.card_actions.copy]
enabled = true
key = "C"
modifiers = ["command"]

[shortcuts.quick_access.card_actions.delete]
enabled = true
key = "delete"
modifiers = ["command"]
```

`card_actions` covers every Quick Access card action (`copy`, `save_or_open`,
`dismiss`, `delete`, `edit`, `upload_to_cloud`, `pin_to_screen`, `optimize`,
`collapse_to_edge`). Each entry needs
`⌘`, `⌥`, or `⌃` in `modifiers` — bare and shift-only combos are rejected on import,
as is `fn`. `key = ""` clears a binding. Named keys accept either the exported symbol
or a readable word (`"delete"`/`"⌫"`, `"return"`/`"↩"`, `"esc"`/`"⎋"`, `"tab"`, arrows).

`shortcuts.video_editor.ai_prompt` is the Video Editor's Ask AI shortcut. It needs a
modifier, and the editor's built-in combos (`⌘Z`, `⇧⌘Z`, `⌘S`, `⌘U`, `⌘B`, `⌘=`, `⌘-`,
`⌘0`, `⌘C`/`⌘V`/`⌘X`/`⌘A`, `⌘W`/`⌘Q`/`⌘M`/`⌘H`/`⌘,`) are rejected on import. `key = ""`
clears it; `enabled = false` turns it off without losing the binding. Import does not
check global hotkeys (same as Annotate actions): an enabled global shortcut with the same
combo wins, and Settings → Shortcuts flags the clash the next time the row is edited.

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
- While an area capture session is presenting, the debounced sync re-arms
  instead of exporting, so the main-thread TOML export never lands mid-drag
  during rapid repeated captures; the postponed sync runs once the flow settles
  (and `flushPendingSync` still covers app termination).
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
