# Sparkle 2 Integration Plan

## Overview
| Field | Value |
|-------|-------|
| Date | 2026-01-18 |
| Status | Planning |
| Priority | High |
| Target | ZapShot macOS 14.0+ |

## Objective
Integrate Sparkle 2 framework to enable automatic updates and "Check for Updates..." functionality in ZapShot menu bar app using SPUStandardUpdaterController (Sparkle 2 API).

## Phases

### Phase 1: Sparkle Setup
**File:** [phase-01-sparkle-setup.md](./phase-01-sparkle-setup.md)
- Add Sparkle 2 via Swift Package Manager
- Configure Info.plist keys via INFOPLIST_KEY_ build settings
- Run `generate_keys` to create EdDSA keypair

**Status:** ✅ Completed

### Phase 2: Updater Integration
**File:** [phase-02-updater-integration.md](./phase-02-updater-integration.md)
- Create SPUStandardUpdaterController in ZapShotApp (programmatic setup for SwiftUI)
- Add "Check for Updates..." menu item in MenuBarContentView
- Add update settings section in GeneralSettingsView

**Status:** ✅ Completed

### Phase 3: Signing & Appcast
**File:** [phase-03-signing-appcast.md](./phase-03-signing-appcast.md)
- Document EdDSA key management and backup
- Create appcast.xml feed structure
- Document `generate_appcast` workflow and hosting

**Status:** ✅ Completed

## Key Files
| File | Purpose |
|------|---------|
| `ZapShot/App/ZapShotApp.swift` | App entry, AppDelegate, MenuBarContentView |
| `ZapShot/Features/Preferences/Tabs/GeneralSettingsView.swift` | General settings (add Updates section) |
| `ZapShot.xcodeproj/project.pbxproj` | Xcode project config, build settings |

## Sparkle 2 Key Points
- Use `SPUStandardUpdaterController` (not deprecated `SUUpdater`)
- EdDSA (ed25519) signatures required
- Programmatic setup required for SwiftUI apps
- Tools location: `../artifacts/sparkle/Sparkle/bin/`
- Sparkle auto-checks every 24h after user grants permission on second launch
- Test by clearing last check: `defaults delete <bundle-id> SULastCheckTime`

## Research References
- [researcher-01-sparkle-basics.md](./research/researcher-01-sparkle-basics.md)
- [researcher-02-sparkle-implementation.md](./research/researcher-02-sparkle-implementation.md)
- [scout-01-integration-points.md](./scout/scout-01-integration-points.md)

## Success Criteria
1. Sparkle 2 added via SPM, builds without errors
2. "Check for Updates..." menu item triggers update check
3. Automatic background checks enabled (every 24h default)
4. Update preferences in Settings
5. EdDSA keys generated and public key in Info.plist
6. Appcast structure documented

## Risks
| Risk | Mitigation |
|------|------------|
| Info.plist generation | Use INFOPLIST_KEY_ build settings |
| Private key loss | Document export/backup with `-x` flag |
| Sandboxing | ZapShot not sandboxed, simpler setup |

## Timeline
- Phase 1: 1 hour
- Phase 2: 2 hours
- Phase 3: 1 hour
- **Total:** ~4 hours
