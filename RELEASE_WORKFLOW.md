# ClaudeShot Release Workflow

## Prerequisites

1. EdDSA private key in Keychain (generated via `generate_keys`)
2. Developer ID signed and notarized app
3. GitHub repository with Releases enabled

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
zip -r ~/ClaudeShot-Updates/ClaudeShot-X.Y.Z.zip ClaudeShot.app

# Optional: Create release notes HTML
cat > ~/ClaudeShot-Updates/ClaudeShot-X.Y.Z.html << 'EOF'
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
SPARKLE_BIN=~/Library/Developer/Xcode/DerivedData/ClaudeShot-*/SourcePackages/artifacts/sparkle/Sparkle/bin

# Generate appcast (auto-signs and creates deltas)
$SPARKLE_BIN/generate_appcast ~/ClaudeShot-Updates

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
  ~/ClaudeShot-Updates/ClaudeShot-X.Y.Z.zip \
  ~/ClaudeShot-Updates/ClaudeShot-X.Y.Z.html \
  --title "ClaudeShot X.Y.Z" \
  --notes "See release notes for details"

# Upload appcast.xml to repo root or GitHub Pages
cp ~/ClaudeShot-Updates/appcast.xml ./appcast.xml
git add appcast.xml
git commit -m "chore: update appcast for vX.Y.Z"
git push
```

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
https://raw.githubusercontent.com/user/ClaudeShot/main/appcast.xml
```

Update to your actual repository URL in `ClaudeShot/ClaudeShot.plist`.

## Testing Updates

```bash
# Clear last check time to force update check
defaults delete com.duongductrong.claudeshot SULastCheckTime

# Run app and click "Check for Updates..."
```

## Troubleshooting

1. **Button always disabled**: Check Info.plist has SUFeedURL and SUPublicEDKey
2. **Signature errors**: Ensure private key matches public key in app
3. **No updates found**: Verify appcast.xml sparkle:version > current CFBundleVersion
