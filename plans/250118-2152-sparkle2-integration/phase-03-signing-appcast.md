# Phase 3: Signing & Appcast

## Context
- [Main Plan](./plan.md)
- [Phase 2: Updater Integration](./phase-02-updater-integration.md)
- [Implementation Research](./research/researcher-02-sparkle-implementation.md)

## Overview
| Field | Value |
|-------|-------|
| Date | 2026-01-18 |
| Description | EdDSA key management, appcast creation, hosting setup |
| Priority | High |
| Status | Not Started |

## Key Insights
- EdDSA (ed25519) signatures required for Sparkle 2
- `generate_appcast` tool automates signing and delta generation
- GitHub Releases is recommended hosting solution
- Private key stored in Keychain, must be backed up securely

## Requirements
1. Document EdDSA key backup/restore workflow
2. Create appcast.xml template
3. Document `generate_appcast` usage
4. Set up GitHub Releases hosting workflow

## Architecture
```
Release Workflow:
1. Build & Archive app in Xcode
2. Export notarized .app
3. Create .zip or .dmg archive
4. Run generate_appcast on updates folder
5. Upload archive + appcast.xml to hosting

Hosting Structure (GitHub Releases):
├── v1.0.0/
│   ├── ZapShot-1.0.0.zip (signed)
│   └── release-notes.html
├── v1.1.0/
│   ├── ZapShot-1.1.0.zip (signed)
│   ├── ZapShot1.0.0-1.1.0.delta (auto-generated)
│   └── release-notes.html
└── appcast.xml
```

## Related Files
| File | Purpose |
|------|---------|
| `appcast.xml` | Update feed (hosted externally) |
| Updates folder | Local folder for generate_appcast |

## Implementation Steps

### Step 1: EdDSA Key Management

**Generate Keys (first time only):**
```bash
# Find Sparkle tools after SPM install
# Right-click Sparkle package in Xcode > Show in Finder
# Navigate to ../artifacts/sparkle/Sparkle/bin/

./generate_keys
```

**Backup Private Key:**
```bash
./generate_keys -x sparkle_private_key.pem
# Store securely (password manager, encrypted backup)
# NEVER commit to git
```

**Restore on New Machine:**
```bash
./generate_keys -f sparkle_private_key.pem
```

### Step 2: Create Appcast Template
Create `appcast.xml` for hosting:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>ZapShot Updates</title>
    <link>https://github.com/user/ZapShot/releases</link>
    <description>ZapShot application updates</description>
    <language>en</language>
    <item>
      <title>Version 1.1.0</title>
      <sparkle:version>2</sparkle:version>
      <sparkle:shortVersionString>1.1.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <pubDate>Sat, 18 Jan 2026 12:00:00 +0000</pubDate>
      <sparkle:releaseNotesLink>
        https://github.com/user/ZapShot/releases/download/v1.1.0/release-notes.html
      </sparkle:releaseNotesLink>
      <enclosure
        url="https://github.com/user/ZapShot/releases/download/v1.1.0/ZapShot-1.1.0.zip"
        sparkle:edSignature="BASE64_SIGNATURE_HERE"
        length="12345678"
        type="application/octet-stream"/>
    </item>
  </channel>
</rss>
```

### Step 3: Release Workflow with generate_appcast

```bash
# 1. Create updates folder
mkdir -p ~/ZapShot-Updates

# 2. Build & archive in Xcode
# Product > Archive > Distribute App > Developer ID

# 3. Create ZIP archive
cd /path/to/exported/app
zip -r ~/ZapShot-Updates/ZapShot-1.1.0.zip ZapShot.app

# 4. Add release notes (optional)
# Create ZapShot-1.1.0.html in same folder

# 5. Generate appcast
./generate_appcast ~/ZapShot-Updates

# Output:
# - appcast.xml (created/updated)
# - *.delta files (for incremental updates)
```

### Step 4: GitHub Releases Hosting

**Setup:**
1. Create GitHub repository for ZapShot
2. Use GitHub Releases for update hosting
3. Set SUFeedURL to raw appcast.xml URL

**Release Process:**
```bash
# Create release tag
git tag -a v1.1.0 -m "Version 1.1.0"
git push origin v1.1.0

# Upload via gh CLI
gh release create v1.1.0 \
  ~/ZapShot-Updates/ZapShot-1.1.0.zip \
  ~/ZapShot-Updates/ZapShot-1.1.0.html \
  --title "ZapShot 1.1.0" \
  --notes "See release notes"

# Upload appcast.xml to repo or GitHub Pages
```

**SUFeedURL Options:**
- GitHub Pages: `https://user.github.io/ZapShot/appcast.xml`
- Raw GitHub: `https://raw.githubusercontent.com/user/ZapShot/main/appcast.xml`
- Custom domain: `https://zapshot.app/appcast.xml`

## Todo List
- [ ] Generate EdDSA keys with `generate_keys`
- [ ] Backup private key securely
- [ ] Add public key to build settings (Phase 1)
- [ ] Create updates folder structure
- [ ] Create release notes template
- [ ] Test `generate_appcast` locally
- [ ] Set up GitHub Releases
- [ ] Configure SUFeedURL
- [ ] Test full update cycle

## Success Criteria
1. EdDSA private key backed up securely
2. `generate_appcast` produces valid appcast.xml
3. Appcast accessible via HTTPS
4. Update archives signed with EdDSA
5. Full update cycle works end-to-end

## Risk Assessment
| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Private key loss | Critical | Low | Backup immediately after generation |
| Invalid signatures | High | Low | Test with generate_appcast before release |
| Hosting downtime | Medium | Low | Use reliable host (GitHub) |

## Security Considerations
- **HTTPS Required**: All URLs must use HTTPS
- **Key Security**: Never store private key in git or cloud sync
- **Code Signing**: App must be Developer ID signed and notarized
- **Signature Verification**: Sparkle validates EdDSA before install

## Next Steps
After completing Phase 3:
1. Perform full integration test
2. Create first signed release
3. Verify update flow works correctly
4. Document release checklist for team
