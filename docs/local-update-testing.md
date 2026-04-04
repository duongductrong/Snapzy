# Local Sparkle Update Testing

Test the full Sparkle in-app update flow locally before pushing releases. This validates that code signing configurations work correctly with Sparkle's XPC installer in sandboxed mode.

> [!IMPORTANT]
> The release workflow signs with `codesign` which does **not** substitute Xcode build variables like `$(PRODUCT_BUNDLE_IDENTIFIER)`. All signing scripts pre-process the entitlements file with `sed` to substitute the actual bundle ID. Without this, Sparkle's XPC mach-lookup connections fail with error 4005.

## Prerequisites

1. **Self-signed certificate** in your login keychain:
   ```bash
   # Generate if missing
   ./scripts/create-signing-cert.sh
   ```

2. **Sparkle EdDSA private key** file (same key used in `SPARKLE_PRIVATE_KEY` GitHub secret):
   ```bash
   export SPARKLE_PRIVATE_KEY_FILE=~/path/to/sparkle_private_key.pem
   ```

3. **Built Sparkle artifacts** (the `sign_update` binary):
   - Build the project once in Xcode (`Cmd+B`) to populate SPM artifacts
   - The script auto-discovers `sign_update` from `build/*/SourcePackages/artifacts/`

## How It Works

The script creates a simulated update scenario:

```
 ┌────────────────────┐     appcast.xml      ┌───────────────────────┐
 │  Installed v99.0.0 │ ──── checks ───────► │  Local HTTP :8089     │
 │  /Applications/    │                      │  ├── appcast.xml      │
 │  Snapzy.app        │ ◄── downloads ────── │  └── Snapzy-test.dmg  │
 └────────────────────┘     v99.0.1 DMG      └───────────────────────┘
```

1. Builds an Xcode archive (reused across runs)
2. Creates **v1** (99.0.0) — patches `Info.plist`, signs, installs to `/Applications`
3. Creates **v2** (99.0.1) — patches `Info.plist`, signs, creates DMG
4. Signs DMG with Sparkle EdDSA key
5. Generates `appcast.xml` pointing to `http://localhost:8089/Snapzy-test.dmg`
6. Starts a local HTTP server on port 8089

## Signing Modes

| Mode | Sparkle helpers | Main app | Purpose |
|---|---|---|---|
| `test-current` | Self-signed cert | Self-signed cert | Reproduce error 4005 |
| `test-hybrid` | Ad-hoc (`-`) | Self-signed cert | Validate hybrid fix |

"Sparkle helpers" = `Installer.xpc`, `Downloader.xpc`, `Autoupdate`, `Updater.app`, `Sparkle.framework`

## Usage

### Test current signing (reproduce error 4005)

```bash
export SPARKLE_PRIVATE_KEY_FILE=~/path/to/sparkle_private_key.pem
./scripts/test-update-local.sh test-current
```

1. Wait for build + server start
2. Open Snapzy from `/Applications`
3. Menu bar → Preferences → About → **Check for Updates**
4. **Expected**: Error 4005 — "remote port connection was invalidated"
5. `Ctrl+C` to stop server

### Test hybrid signing (validate fix)

```bash
./scripts/test-update-local.sh test-hybrid
```

1. Wait for build + server start
2. Open Snapzy from `/Applications`
3. Menu bar → Preferences → About → **Check for Updates**
4. **Expected**: Update downloads and installs — app relaunches as v99.0.1
5. `Ctrl+C` to stop server

### Clean up

```bash
./scripts/test-update-local.sh clean
```

Removes `/tmp/test-sparkle-update/`. Does **not** remove `/Applications/Snapzy.app` — re-install from a release DMG or use `test-tcc-local.sh` to restore.

## Keychain Trust Persistence Test

Use the dedicated script to verify that Keychain `Always Allow` survives updates when signing identity stays stable:

```bash
# Stable identity scenario (expected: no re-prompt after update)
./scripts/test-keychain-update-local.sh verify-stable

# Negative control (expected: prompt can reappear with ad-hoc update)
./scripts/test-keychain-update-local.sh verify-adhoc-control
```

Outputs:

- JSON report: `plans/260404-0843-cloud-keychain-persistence/reports/phase-03-keychain-update-verification.json`
- Markdown report: `plans/260404-0843-cloud-keychain-persistence/reports/phase-03-keychain-update-verification.md`

The app probe path uses launch argument `--keychain-probe-cloud` and returns one of:

- `KC_OK`
- `KC_AUTH_REQUIRED`
- `KC_INTERACTION_NOT_ALLOWED`
- `KC_ITEM_NOT_FOUND`
- `KC_ERROR_<status>`

## Notes

- Test versions (`99.0.0`, `99.0.1`) avoid conflicts with real releases
- First run builds the archive (~2-5 min); subsequent runs reuse it
- The feed URL in v1's `Info.plist` is patched to `http://localhost:8089/appcast.xml`
- Server runs on port 8089 to avoid collisions with common dev servers
- Archive is stored at `/tmp/test-sparkle-update/archive/` — delete to force rebuild

## Related

- [Self-signed certificate setup](self-signed-certificate-setup.md)
- [Release workflow](project-workflow.md)
- `scripts/test-tcc-local.sh` — TCC permission persistence testing (separate concern)
- `scripts/test-keychain-update-local.sh` — Keychain trust persistence testing
