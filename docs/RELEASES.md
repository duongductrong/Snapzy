# Snapzy Release Workflow

## Prerequisites

1. EdDSA private key for Sparkle (`SPARKLE_PRIVATE_KEY` secret)
2. One of the following signing strategies (in priority order):

| Strategy | Required Secrets | Notarization |
|----------|-----------------|--------------|
| Developer ID | `DEVELOPER_ID_P12`, `DEVELOPER_ID_PASSWORD` | Yes (with `APPLE_ID`, `APPLE_ID_PASSWORD`, `APPLE_TEAM_ID`) |
| Self-signed cert | `SELF_SIGNED_CERT_P12`, `SELF_SIGNED_CERT_PASSWORD` | No |
| Ad-hoc | `ALLOW_ADHOC_RELEASE=true` (repo variable) | No |

## CI Signing Architecture

The release workflow uses manual `codesign` for all signing strategies. The binary is extracted from the Xcode archive via `ditto` and signed component-by-component (inside-out for Sparkle framework).

- **Developer ID builds** use `--timestamp` (secure timestamp from Apple) and hardened runtime (`-o runtime`) — both required for notarization.
- **Self-signed and ad-hoc builds** use `--timestamp=none` (no Apple server access needed) but still enable hardened runtime.

## Release Steps

### 1. Build & Archive

```bash
# In Xcode:
# Product > Archive > Distribute App > Developer ID
# Wait for notarization to complete
```

### 2. Create Update Archive

```bash
# Navigate to exported app location
cd /path/to/exported

# Create ZIP archive (preserves code signature)
zip -r ~/Snapzy-Updates/Snapzy-X.Y.Z.zip Snapzy.app

# Optional: Create release notes HTML
cat > ~/Snapzy-Updates/Snapzy-X.Y.Z.html << 'EOF'
<html>
<body>
<h2>What's New in X.Y.Z</h2>
<ul>
  <li>Feature 1</li>
  <li>Bug fix 2</li>
</ul>
</body>
</html>
EOF
```

### 3. Generate Appcast

```bash
# Locate Sparkle tools
SPARKLE_BIN=~/Library/Developer/Xcode/DerivedData/Snapzy-*/SourcePackages/artifacts/sparkle/Sparkle/bin

# Generate appcast (auto-signs and creates deltas)
$SPARKLE_BIN/generate_appcast ~/Snapzy-Updates

# Output:
# - appcast.xml (updated)
# - *.delta files (for incremental updates)
```

### 4. Upload to GitHub Releases

```bash
# Create and push tag
git tag -a vX.Y.Z -m "Version X.Y.Z"
git push origin vX.Y.Z

# Create release with assets
gh release create vX.Y.Z \
  ~/Snapzy-Updates/Snapzy-X.Y.Z.zip \
  ~/Snapzy-Updates/Snapzy-X.Y.Z.html \
  --title "Snapzy X.Y.Z" \
  --notes "See release notes for details"

# Upload appcast.xml to repo root or GitHub Pages
cp ~/Snapzy-Updates/appcast.xml ./appcast.xml
git add appcast.xml
git commit -m "chore: update appcast for vX.Y.Z"
git push
```

## Beta Channel

Snapzy ships two Sparkle update channels from a single `appcast.xml`:

- **Stable** (default): items with no channel tag. All users receive these.
- **Beta**: items tagged `<sparkle:channel>beta</sparkle:channel>`. Only users who opt in via **Settings → About → Update Channel → Beta** receive them (beta users also receive stable items).

The channel preference is stored in `updates.channel` (UserDefaults) and exported to `config.toml` under `[updates] channel`. `UpdaterManager.allowedChannels(for:)` returns `["beta"]` only when opted in.

### Branch Model

- `master` is the stable production line and the canonical source for `appcast.xml`; the Sparkle feed URL is intentionally served from `master` for both stable users and users who opt into beta updates.
- `beta` is the pre-release integration line. CI, SwiftFormat validation, release preparation, and release publishing all recognize it as the beta target.
- The release workflows enforce the pairing: stable releases target `master`, and beta releases target `beta`.

### Versioning Scheme

| Release | Marketing version | Git tag | Build number (`sparkle:version`) |
|---------|------------------|---------|-------------------------------|
| Stable | `1.29.0` | `v1.29.0` | global counter +1 |
| Beta | `1.29.0-beta.1`, `-beta.2`, … | `v1.29.0-beta.N` | global counter +1 (same counter) |

Sparkle compares the numeric build number only — the `-beta.N` suffix is cosmetic. The single monotonic counter guarantees a promoted stable always outranks its betas.

### Releasing a Beta

Either:

- **Actions → Release Prepare** on the `beta` branch → run with `channel = beta` and a bump type (`patch`/`minor`/`major`). The bump type applies to the base version when starting a new beta line; subsequent betas keep the base and increment `N` (derived from existing `vX.Y.Z-beta.*` tags).
- Or push a commit to `beta` titled `release(minor-beta): ...` (also `patch-beta`, `major-beta`).

Then merge the generated `release/vX.Y.Z-beta.N` PR into `beta`. The publish pipeline will:

- Build, sign, and notarize the DMG exactly like stable
- Create the GitHub Release with **prerelease = true** (the "latest" pointer stays on stable)
- Add a `<sparkle:channel>beta</sparkle:channel>` item to `appcast.xml`
- **Skip** the Homebrew cask and README install-URL updates
- Send the Discord notification prefixed with `[Beta]`
- Commit release metadata to `beta` and mirror the updated canonical `appcast.xml` to `master`, where the Sparkle feed is served

> **Note:** merge or close a beta release PR before dispatching the next one — two open prepare runs bump from the same pbxproj state and would collide.

### Promoting a Beta to Stable

Promotion is an ordinary stable release — a full rebuild from master HEAD (the version string is baked into the signed binary, so beta artifacts cannot be re-tagged):

1. Merge the validated `beta` branch into `master`, then ensure `master` contains exactly what should ship (no unwanted commits).
2. **Actions → Release Prepare** on `master` → run with `channel = stable`. When the current version is a beta, the `-beta.N` suffix is stripped (bump type is ignored) → version `X.Y.Z`.
3. Review the `release/vX.Y.Z` PR into `master` — the changelog spans everything since the **last stable tag**, so all beta-tested commits are included. Merge.
4. The publish pipeline runs the full stable path: `prerelease = false`, untagged appcast item, cask + README updated, Discord notify without `[Beta]`.
5. Verify a beta-channel install is offered `X.Y.Z` (its build number is higher than every beta).

> **Changelog folding:** the stable entry is the single source of truth for the whole beta cycle. `generate-changelog.sh` filters release-automation commits (`chore: bump version …`, `chore: update appcast …`, `chore: release v…`) out of every generated changelog, and `update-changelog.sh` removes the `## [X.Y.Z-beta.N]` sections of the same base version from `CHANGELOG.md` when the stable `X.Y.Z` entry is prepended — beta entries never appear alongside their stable promotion. Beta entries of abandoned lines (different base version) are left untouched.

### Switching Back from Beta (Downgrade Policy)

Sparkle never offers a lower build than the one installed, so switching the channel back to Stable does **not** downgrade:

- **Supported path (default):** the beta build stays installed until the next stable release ships with a higher build number — the promotion flow guarantees this. The About-tab warning communicates it.
- **Manual immediate downgrade:** quit Snapzy, download the latest stable DMG from [GitHub Releases](https://github.com/duongductrong/Snapzy/releases), and replace the app in `/Applications`. Caveat: beta builds may have migrated preferences/data formats; going backwards is unsupported. Recommend exporting the TOML config before joining the beta.
- **Rejected:** republishing a stable with an artificially inflated build number — it breaks the monotonic counter and confuses appcast history.

### Prerequisites & Process Notes

- The first beta must not ship before the app release containing the channel picker (users need the UI to opt in).
- Don't leave a beta line dangling: promote or supersede betas promptly so beta users converge back onto stable.
- Abandoned beta lines (e.g. `1.29.0` never promoted, jump to `1.30.0`) are fine — items stay as prereleases; optionally clean them from `appcast.xml` later.

## Key Management

### Backup Private Key
```bash
$SPARKLE_BIN/generate_keys -x sparkle_private_key.pem
# Store securely (password manager, encrypted backup)
# NEVER commit to git!
```

### Restore on New Machine
```bash
$SPARKLE_BIN/generate_keys -f sparkle_private_key.pem
```

### View Public Key
```bash
$SPARKLE_BIN/generate_keys -p
```

## SUFeedURL Configuration

Current URL in Info.plist:
```
https://raw.githubusercontent.com/duongductrong/Snapzy/master/appcast.xml
```

Update this value in `Snapzy/Resources/Info.plist` if your release repository changes.

## Testing Updates

```bash
# Clear last check time to force update check
defaults delete com.trongduong.snapzy SULastCheckTime

# Run app and click "Check for Updates..."
```

## Distribution Tiers

### Developer ID (recommended)
- Signed with Apple Developer ID certificate
- Hardened runtime enabled
- Notarized by Apple (if credentials configured)
- Users can install without Gatekeeper warnings

### Self-signed Certificate
- Preserves TCC permissions across Sparkle updates
- Not notarized — users must right-click > Open on first launch
- Move the app to `/Applications` before first launch

### Ad-hoc (emergency fallback)
- Requires `ALLOW_ADHOC_RELEASE=true` repository variable
- TCC permissions and Keychain trust lost after every update
- Not suitable for regular distribution

## Release Notifications

Release notifications are handled by a **separate workflow** (`release-notify.yml`) that triggers automatically after `release-publish.yml` completes successfully. This keeps the publish workflow focused on build/sign/release, and makes it easy to add new notification channels.

**Architecture:**

```
release-publish.yml (build → sign → release)
        ↓ workflow_run trigger
release-notify.yml
  ├── prepare  (fetch release metadata from GitHub API)
  ├── discord  (parallel)
  ├── slack    (parallel, add when needed)
  └── telegram (parallel, add when needed)
```

### Discord

#### 1. Create a Discord Webhook

1. Open your Discord server
2. Go to **Server Settings → Integrations → Webhooks**
3. Click **New Webhook**
4. Choose the target channel for release announcements
5. (Optional) Set the webhook name (e.g., "Snapzy Releases") and avatar
6. Click **Copy Webhook URL** — it looks like:
   ```
   https://discord.com/api/webhooks/123456789012345678/abcdefg...
   ```

#### 2. Add the Secret to GitHub

1. Go to your GitHub repository → **Settings → Secrets and variables → Actions**
2. Click **New repository secret**
3. Name: `DISCORD_WEBHOOK_URL`
4. Value: paste the webhook URL from step 1
5. Click **Add secret**

#### What Gets Posted

Each release notification includes:
- **Title**: version number with link to the GitHub release page
- **Body**: full changelog from `CHANGELOG.md` (features, bug fixes, etc.)
- **Quick links**: DMG download and release page
- **Timestamp**: when the release was published

If `DISCORD_WEBHOOK_URL` is not configured, the job is silently skipped — no failures.

### Adding a New Channel

To add a notification channel (e.g., Slack, Telegram):

1. Open `.github/workflows/release-notify.yml`
2. Add a new job that depends on `prepare`
3. Use `${{ needs.prepare.outputs.version }}`, `.release_url`, `.download_url`, and `.body` for release data
4. Add the required secrets (e.g., `SLACK_WEBHOOK_URL`) to GitHub repository settings

See the commented examples at the bottom of `release-notify.yml`.

## Troubleshooting

1. **Button always disabled**: Check Info.plist has SUFeedURL and SUPublicEDKey
2. **Signature errors**: Ensure private key matches public key in app
3. **No updates found**: Verify appcast.xml sparkle:version > current CFBundleVersion
4. **Notification not sent**: Verify the channel secret (e.g., `DISCORD_WEBHOOK_URL`) is set correctly in GitHub repository settings. Check the `release-notify` workflow run logs for HTTP status warnings.
5. **Notarization rejected**: Check the notarization log in the GitHub Actions output (printed automatically on failure). Common causes:
   - Missing hardened runtime (`flags=` line doesn't show `runtime`)
   - Missing secure timestamp (`--timestamp=none` was used)
   - `com.apple.security.get-task-allow` entitlement present in release build
6. **Notarization timeout**: Apple service can be slow. The workflow uses a 15-minute timeout. If consistently timing out, check DMG size and Apple system status.
7. **Stapling failed**: Ensure the DMG was notarized successfully first. `stapler staple` only works after Apple issues a ticket.
