# Self-Signed Certificate Setup

Snapzy uses a self-signed code signing certificate to preserve macOS TCC permissions (Screen Recording, Microphone, etc.) across Sparkle updates.

## Why This Matters

macOS tracks app permissions by **code signing identity**. Ad-hoc signing (`codesign --sign -`) produces a unique identity per build, so every update causes macOS to revoke permissions. A persistent self-signed certificate fixes this.

## One-Time Setup

### 1. Generate the Certificate

```bash
chmod +x scripts/create-signing-cert.sh
./scripts/create-signing-cert.sh
```

You'll be prompted for a password — remember it for step 2.

### 2. Add GitHub Secrets

Go to **Settings → Secrets and variables → Actions** in your GitHub repo and add:

| Secret Name | Value |
|---|---|
| `SELF_SIGNED_CERT_P12` | Base64 output from the script |
| `SELF_SIGNED_CERT_PASSWORD` | The password you entered |

### 3. Verify

Push a release and check the "Import self-signed certificate" step in the workflow logs. You should see the certificate imported successfully.

## Local Testing

Use `scripts/test-tcc-local.sh` to verify TCC permissions persist across updates locally:

```bash
# Step 1: Generate cert and import into login keychain
./scripts/create-signing-cert.sh

# Step 2: Build, sign with self-signed cert, install as v1
./scripts/test-tcc-local.sh build-v1
# → Open app → Grant Screen Recording + Microphone

# Step 3: Re-sign and replace (simulates Sparkle update)
./scripts/test-tcc-local.sh build-v2
# → Open app → Verify permissions are STILL granted ✅

# (Optional) Compare with ad-hoc to prove the difference
./scripts/test-tcc-local.sh compare
# → Open app → Permissions are LOST ❌
```

Clean up test artifacts when done:

```bash
./scripts/test-tcc-local.sh clean
```

## Signing Hierarchy

The release workflow uses this fallback chain:

1. **Developer ID** — best (Gatekeeper pass + TCC persist). Requires Apple Developer Program.
2. **Self-signed cert** — good (TCC persist, Gatekeeper warning on first install).
3. **Ad-hoc** — worst (TCC revoked every update).

## Upgrading to Developer ID

When you enroll in Apple Developer Program:

1. Add `DEVELOPER_ID_P12`, `DEVELOPER_ID_PASSWORD` secrets
2. Optionally add `APPLE_ID`, `APPLE_ID_PASSWORD`, `APPLE_TEAM_ID` for notarization
3. Remove `SELF_SIGNED_CERT_P12` and `SELF_SIGNED_CERT_PASSWORD` (optional)
4. Users re-grant permissions **once** on the first update with the new identity

## Certificate Renewal

The default certificate is valid for 10 years. To regenerate:

```bash
./scripts/create-signing-cert.sh "Snapzy Self-Signed" 3650
```

Then update the GitHub Secrets with the new values.
