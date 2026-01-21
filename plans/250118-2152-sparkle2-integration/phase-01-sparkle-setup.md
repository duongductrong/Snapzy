# Phase 1: Sparkle 2 Setup

## Context
- [Main Plan](./plan.md)
- [Sparkle Basics Research](./research/researcher-01-sparkle-basics.md)
- [Integration Points](./scout/scout-01-integration-points.md)

## Overview
| Field | Value |
|-------|-------|
| Date | 2026-01-18 |
| Description | Add Sparkle 2 via SPM and configure Info.plist keys |
| Priority | High |
| Status | Not Started |

## Key Insights
- ZapShot uses `GENERATE_INFOPLIST_FILE = YES` (no manual Info.plist)
- Must use `INFOPLIST_KEY_` build settings to inject Sparkle keys
- SPM is recommended installation method for Sparkle 2
- EdDSA keys must be generated before first release

## Requirements
1. Add Sparkle 2 package dependency
2. Configure SUFeedURL via build settings
3. Configure SUPublicEDKey via build settings
4. Generate EdDSA keypair using Sparkle's tools

## Architecture
```
ZapShot.xcodeproj
├── Package Dependencies
│   └── Sparkle (https://github.com/sparkle-project/Sparkle)
└── Build Settings
    ├── INFOPLIST_KEY_SUFeedURL = "https://..."
    └── INFOPLIST_KEY_SUPublicEDKey = "base64-key"
```

## Related Files
| File | Changes |
|------|---------|
| `ZapShot.xcodeproj/project.pbxproj` | SPM dependency, build settings |

## Implementation Steps

### Step 1: Add Sparkle via SPM
1. Open `ZapShot.xcodeproj` in Xcode
2. File > Add Package Dependencies...
3. Enter URL: `https://github.com/sparkle-project/Sparkle`
4. Select version rule: "Up to Next Major Version" from 2.0.0
5. Add to target: ZapShot

### Step 2: Generate EdDSA Keys
```bash
# Locate generate_keys after SPM adds Sparkle
# Path: DerivedData or right-click Sparkle package > Show in Finder
# Navigate to: ../artifacts/sparkle/Sparkle/bin/

./generate_keys
```

Output example:
```
A key has been generated and saved in your keychain. Add the `SUPublicEDKey` key to
the Info.plist of each app for which you intend to use Sparkle for distributing
updates. It should appear like this:

    <key>SUPublicEDKey</key>
    <string>pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ=</string>
```

### Step 3: Configure Build Settings
In Xcode, select ZapShot target > Build Settings > Add User-Defined Settings:

| Key | Value |
|-----|-------|
| `INFOPLIST_KEY_SUFeedURL` | `https://yourdomain.com/appcast.xml` |
| `INFOPLIST_KEY_SUPublicEDKey` | `<your-generated-public-key>` |

Alternative: Edit `project.pbxproj` directly in buildSettings section:
```
INFOPLIST_KEY_SUFeedURL = "https://zapshot.app/appcast.xml";
INFOPLIST_KEY_SUPublicEDKey = "pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ=";
```

### Step 4: Verify Build
1. Build project (Cmd+B)
2. Check Product > Show Build Folder in Finder
3. Right-click ZapShot.app > Show Package Contents
4. Open Contents/Info.plist
5. Verify SUFeedURL and SUPublicEDKey present

## Todo List
- [ ] Add Sparkle 2 SPM dependency
- [ ] Run `generate_keys` tool
- [ ] Copy public key from output
- [ ] Add INFOPLIST_KEY_SUFeedURL build setting
- [ ] Add INFOPLIST_KEY_SUPublicEDKey build setting
- [ ] Build and verify Info.plist contains keys

## Success Criteria
1. Sparkle framework linked to ZapShot target
2. `import Sparkle` compiles without errors
3. Built app's Info.plist contains SUFeedURL
4. Built app's Info.plist contains SUPublicEDKey
5. EdDSA private key stored in login Keychain

## Risk Assessment
| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| SPM resolution fails | High | Low | Use specific version tag |
| Build settings not applied | Medium | Medium | Verify in built Info.plist |
| Key generation fails | High | Low | Check Keychain Access permissions |

## Security Considerations
- **Private Key**: Stored in macOS Keychain, never commit to git
- **Key Backup**: Use `./generate_keys -x private-key-file` to export for backup
- **Key Import**: Use `./generate_keys -f private-key-file` on new machine
- **Feed URL**: Must use HTTPS for security

## Next Steps
After completing Phase 1:
1. Proceed to [Phase 2: Updater Integration](./phase-02-updater-integration.md)
2. Implement SPUStandardUpdaterController in SwiftUI app
