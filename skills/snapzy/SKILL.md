---
name: snapzy
description: "Take screenshots and screen recordings on macOS with the `snapzy` command line tool — a whole display, one window (even when covered), or a rectangle — and get back a file path plus JSON metadata, with no clicks or overlay. Use this whenever you need to see what is on the user's Mac screen: checking how an app or UI change looks, grabbing a window of a running app (simulator, browser, editor), capturing an error dialog, or giving yourself a screenshot to look at — or recording a demo video of it — even if the user just says \"take a screenshot\", \"record my screen\", \"look at my screen\" or \"what does the window look like\". Also use it when the user mentions Snapzy's CLI, `snapzy` / `snapzy-debug` exit codes or approval prompts, or is working on the CLI's code (SnapzyCLIKit, CLIServer, headless capture) in the Snapzy repo."
---

# snapzy

`snapzy` is a thin client for Snapzy.app. The app does the capture over a Unix socket, so the calling terminal never needs Screen Recording permission. Commands return JSON on stdout when stdout is not a terminal (always the case when you run it), errors as JSON on stderr, and a meaningful exit code.

This file covers **using** the tool. If you are changing the CLI's own code in the Snapzy repo, read `references/contributing.md` instead.

## Finding the binary

Try in order and use the first that works:

1. `snapzy` on PATH (Homebrew cask, `install.sh`, or Settings → Command Line → Install).
2. `snapzy-debug` on PATH — the link a Debug build installs. Use it when the user is developing Snapzy.
3. `/Applications/Snapzy.app/Contents/Helpers/snapzy` — always present in an installed app.

If none exist, Snapzy is not installed (or is older than the CLI); tell the user rather than trying to install it.

## Workflow

1. **Check readiness once**: `snapzy status`. It never needs approval and returns e.g.
   `{"appVersion":"2.1.0","authorization":"undetermined","cliEnabled":true,"onboardingCompleted":true,"screenRecordingPermission":"granted"}`.
   If `authorization` is `undetermined`, warn the user that a Snapzy prompt is about to appear and they must click **Always Allow** or **Allow Once** within 25 s. Otherwise the next command fails with exit 7.
2. **Discover the target** when you don't already know it: `snapzy list displays`, `snapzy list apps`, `snapzy list windows [--app NAME] [--all]`.
3. **Capture** into a path you choose (always pass `-o`, otherwise the file sits in Snapzy's staging folder and is deleted after 24 h).
4. **Look at it**: read the returned `files[].path` with your image-viewing tool. Pass `--max-dimension 1568` when the image is for you, so it stays small enough for vision input.

Run commands one at a time: the app serves one capture at a time and answers `busy` (exit 5) otherwise.

## Commands

| Goal | Command |
| --- | --- |
| Main display | `snapzy capture screen -o /tmp/shot.png` |
| Every display | `snapzy capture screen --display all -o /tmp/shots/` (one file each) |
| A specific display | `snapzy capture screen --display ID -o …` (ID from `list displays`) |
| Frontmost window of an app | `snapzy capture window --app Safari -o /tmp/safari.png` |
| Window by title | `snapzy capture window --app "Google Chrome" --title 'Pull request' -o …` (`--title` is a regex) |
| Exact window | `snapzy capture window --id 195 -o …` (ID from `list windows`) |
| Focused window | `snapzy capture window --active -o …` |
| Rectangle | `snapzy capture area --rect 0,0,800,600 -o …` |

### Recording video

| Goal | Command |
| --- | --- |
| Record the main display for 10 s | `snapzy record screen --duration 10 -o /tmp/demo.mov` |
| Record a window until you stop it | `snapzy record window --app Simulator --detach -o /tmp/sim.mp4`, then later `snapzy record stop` |
| Record a rectangle | `snapzy record area --rect 0,0,1280,720 --duration 5 -o /tmp/area.mov` |
| What is recording? | `snapzy record status` |

- Without `--detach` the command blocks until `--duration` elapses or it gets Ctrl-C/SIGTERM, then prints `{"file":{"path":…,"durationSeconds":…,"width":…,"height":…,"bytes":…,"format":"mov"},"id":…}`. As an agent, prefer `--duration`, or `--detach` + `snapzy record stop`; don't leave an attached recording running in the background without a way to stop it.
- `snapzy record stop` delivers the file to the `-o` given at start (or its own `-o`) and prints the same JSON.
- `-o` must end in `.mov` or `.mp4` (or be a directory). Options: `--fps 30|60`, `--quality high|medium|low`, `--no-cursor`, `--system-audio`, `--mic` (only if Snapzy already has Microphone access).
- One recording at a time; `busy` (exit 5) means one is already running. `targetNotFound` (exit 4) from `record stop` means nothing is recording.
- A recording captures everything on that display or window for its whole length — record only what the task needs, keep it short, and tell the user you are recording.

Useful options on every `capture`:

- `-o PATH` — a file, a directory (trailing `/` or existing dir), or `-` for raw image bytes on stdout. An existing file fails with exit 2 unless `--force`.
- `--format png|jpg|webp|heic|avif` — defaults to the `-o` extension, else png. `--quality 0…1` for JPEG, HEIC and AVIF. AVIF needs a macOS with an AVIF encoder.
- `--max-dimension PX` — downscale so the longest edge is ≤ PX.
- `--no-shadow` (window only), `--cursor` to include the pointer.

Global: `--json`, `--timeout S` (default 30), `--launch-timeout S` (default 15), `--no-launch` (fail instead of starting Snapzy; by default the CLI opens it in the background).

### Matching apps and windows

`--app` takes a bundle ID or name, case-insensitive: exact bundle ID wins, then exact name, then name prefix. With several windows the frontmost wins; the result's `matchedCandidates` says how many matched, and `--index N` (0-based, front to back) picks another. If `matchedCandidates` > 1 and you're not sure you got the right one, `list windows --app NAME` and capture by `--id`.

`--app` and `--id` only find **on-screen** windows. A minimized or other-Space window from `list windows --all` gives `targetNotFound`; ask the user to bring it on screen.

### Coordinates

Every frame and `--rect` uses global **points**, origin at the top-left of the main display. Displays left of / above the main one have negative coordinates (`--rect -1440,0,800,600` works as written). A `frame` from `list windows` or `list displays` can be passed straight to `capture area --rect x,y,w,h`. The area must lie fully on screen (it may span displays); partly off screen is exit 2, fully off screen exit 4.

To capture part of a window (e.g. its toolbar), take the window's `frame` from `list windows` and offset from its origin. Output pixel size is points × `scale` (2 on Retina) unless `--max-dimension` shrinks it.

## Output

```json
{"durationMs":244,"files":[{"bytes":1204134,"displayID":1,"format":"png","height":2338,
 "path":"/tmp/shot.png","scale":2,"width":3600}]}
```

Window captures add `window` (`id`, `title`, `app {name, bundleID, pid}`, `frame`, `displayID`, `isOnScreen`, `isActive`) and `matchedCandidates`. Errors on stderr look like `{"error":{"code":"targetNotFound","message":"…","hint":"…"}}` — the `hint` is written for you; follow it.

## Exit codes and what to do

| Exit | Codes | What to do |
| --- | --- | --- |
| 0 | — | Read `files[].path` |
| 1 | `internal` | Report message to the user; retry once at most |
| 2 | `invalidArguments` | Fix flags (`snapzy help capture window`), area partly off screen, or `-o` exists → add `--force` or pick a new name |
| 3 | `permissionDenied`, `onboardingIncomplete` | Snapzy lacks Screen Recording, or it was just granted and Snapzy needs a relaunch, or setup is unfinished. The user must fix this in Snapzy/System Settings — you can't |
| 4 | `targetNotFound` | Re-list; the window may have closed, be off screen, or the app name differs |
| 5 | `appUnavailable`, `launchTimeout`, `disabled`, `busy`, `versionMismatch`, `unknownMethod` | `disabled` → user turns on Settings → Command Line. `busy` → wait and retry. Screen locked → ask user to unlock. Otherwise run `snapzy doctor` |
| 7 | `notAuthorized` | The calling app (your terminal / Claude / editor) was denied or nobody answered the prompt. Ask the user to retry and click Allow, or re-allow it in Settings → Command Line → Allowed apps. Don't loop — each retry shows another prompt |

`snapzy doctor` checks the binary, PATH, app, socket and status and explains each failure in plain words; run it whenever something unexpected happens and relay its output.

## Things to respect

- A capture shows the user's real screen, which may include private content (messages, other tabs). Capture the narrowest target that answers the question — a window rather than the whole screen — and don't take screenshots the task doesn't need.
- Headless captures never touch the clipboard, Quick Access, history or sounds; there is nothing to clean up besides files you wrote.
- Approval is per calling app and is the user's decision. Never try to change `cliApprovedCallers` or other Snapzy defaults yourself.
