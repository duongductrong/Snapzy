# Working on the snapzy CLI code

Read this when changing the CLI itself in the Snapzy repo. `docs/CLI.md` is the source of truth for behaviour; keep it in step with any change you make (commands, flags, exit codes, install paths).

## Contents

- Layout
- Adding a command
- Contracts not to break
- Testing and running
- Gotchas

## Layout

| Path | Owns |
| --- | --- |
| `Packages/SnapzyCLIKit/Sources/SnapzyCLIProtocol/` | Wire contract, Foundation-only: `Methods/CLIMethod.swift` (method list + params), `Models/` (results, `CLIError`), `Wire/` (frames, envelopes, handshake, `ProtocolVersion`, `SocketLocation`, `CommandName`) |
| `…/SnapzyCLIClient/` | Socket connection, `AppLocator`, `AppLauncher`, `CLISession` |
| `…/SnapzyCLICore/` | ArgumentParser tree (`SnapzyCommand`, `Commands/`), `GlobalOptions`, `Output/` (renderer, human-readable text) |
| `…/SnapzyCLIDev/` | `snapzy-dev`, development executable only |
| `SnapzyCLI/main.swift` | Xcode target `SnapzyCLI` → product `snapzy`, embedded at `Snapzy.app/Contents/Helpers/snapzy` |
| `Snapzy/Services/CommandLine/` | App side: `CLIServer` (registers routes), `CLISocketListener`, `CLIConnection`, `CLIRequestRouter`, `CLIAuthorizationCoordinator`/`Store`, `CLIClientIdentityResolver`, `CLIToolInstaller`, `CLIActivityIndicator`, `Handlers/` |
| `Snapzy/Services/Capture/HeadlessCapture/` | `HeadlessCaptureService`, `CaptureTargetResolver`, staging, `AppNameMatcher` |
| `Snapzy/Features/CommandLine/` | Approval prompt UI |
| `Snapzy/Features/Preferences/Components/PreferencesCommandLineSection.swift` | Settings → Command Line |

Why the split: the app links `SnapzyCLIProtocol` to serve the socket, so that target must never import the client or ArgumentParser. `SnapzyCLICore` is a library so commands are testable without an executable.

The Xcode project uses file-system-synchronized groups, so new Swift files under `Snapzy/` or `SnapzyTests/` are picked up without editing `project.pbxproj`.

## Adding a command

Example: a new `list.foo` method.

1. **Protocol** — add the case to `CLIMethod` (and its row in the header table), params struct next to it if any, result model in `Models/`. Use `CLIEmpty` for no params. Keep models `Codable, Sendable, Equatable`.
2. **App handler** — a `nonisolated struct … : CLIRequestHandling` in `Snapzy/Services/CommandLine/Handlers/`, then `router.register(.listFoo, …)` in `CLIServer`. Throw `CLIError` for expected failures; any other error becomes `internal`. Capture logic belongs in `HeadlessCaptureService`, not in handlers. Add the method to `CLIAuthorizationCoordinator.exemptMethods` only if it reveals nothing about the screen (today: `hello`, `system.status`).
3. **CLI command** — an `AsyncParsableCommand` in `SnapzyCLICore/Commands/`, include `@OptionGroup var global: GlobalOptions`, run through `CommandRunner.run(global) { client, renderer in … }`, register it in the parent's `subcommands`. Add human-readable rendering in `Output/HumanReadable+Models.swift`.
4. **Docs** — `docs/CLI.md` command table, options, wire protocol methods list.
5. **Tests** — see below.

A new method is a minor protocol change; an older app answers `unknownMethod` (exit 5), which is fine. Removing or renaming a method or field is a major change.

## Contracts not to break

Agents depend on these, so treat them as API:

- Exit codes per `CLIErrorCode.exitCode` (6 is reserved for user-cancelled). Never repurpose a code.
- JSON on stdout when not a TTY or `--json`; errors (including ArgumentParser usage errors, mapped to exit 2) as JSON on stderr in the same mode. Sorted keys, unescaped slashes (`CLIJSON`).
- Unknown error codes decode as `internal`, unknown `Authorization`/`Permission` values as their safe defaults — new values must stay forward-compatible.
- Coordinates: global points, top-left origin of the main display (`CLICoordinateSpace`).
- Headless captures never open Quick Access, touch the clipboard, add history, apply presets, play sounds, or prompt for permission.
- Socket path per bundle ID; Debug (`com.trongduong.snapzy.debug`) and release never share a socket or a PATH name (`snapzy-debug` vs `snapzy`).
- Approval decisions live in `UserDefaults` key `cliApprovedCallers` and are never exported to `config.toml`.

## Testing and running

```bash
# Package (fast, also run in CI)
swift test --package-path Packages/SnapzyCLIKit

# App-side tests
./scripts/run-tests.sh -only-testing:SnapzyTests/CLIRequestRouterTests
```

Package tests: `CommandParsingTests`, `OutputTests`, `DoctorTests`, `CLIClientSocketTests`, `AppDiscoveryTests`, plus protocol `EnvelopeContractTests`, `FrameTests`, `ProtocolModelTests`. App tests live in `SnapzyTests/Services/CommandLine/` and `SnapzyTests/Services/Capture/HeadlessCapture/`.

End to end against a Debug build:

```bash
SNAPZY_APP_PATH="$PWD/.build/xcode-derived-data/Build/Products/Debug/Snapzy Debug.app" \
  swift run --package-path Packages/SnapzyCLIKit snapzy-dev doctor
```

or call `snapzy-debug` (installed from the Debug app's Settings → Command Line). After app-side changes, rebuild and relaunch the app with `scripts/build_and_run.sh` before testing.

## Gotchas

- Window/screen tests fail while the Mac is locked (ScreenCaptureKit sees no displays).
- Release builds with Xcode 26.4 / Swift 6.3 can crash the optimizer in `S3MultipartUploader.swift`; CI uses 26.2.
- `scripts/dry-run-release.sh` runs `rm -rf build/` — use a scratch copy.
- Homebrew silently replaces a dangling link but errors on a live one; matters when testing `CLIToolInstaller`.
- Commit messages have no scope (`feat:`, not `feat(cli):`).
