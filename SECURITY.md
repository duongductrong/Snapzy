# Security Policy

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues, discussions, or pull requests.**

Instead, report them privately using one of these methods:

1. **GitHub Security Advisory** — open a draft advisory at [github.com/duongductrong/Snapzy/security/advisories/new](https://github.com/duongductrong/Snapzy/security/advisories/new)
2. **Email** — contact the maintainer at the email address listed on the [GitHub profile](https://github.com/duongductrong)

Please include as much of the following information as possible:

- Description of the vulnerability
- Steps to reproduce or a proof-of-concept
- Affected version(s) and macOS version
- Potential impact

You should receive an initial acknowledgment within **72 hours**. A fix or mitigation will be communicated before public disclosure.

## Supported Versions

| Version | Supported |
| ------- | --------- |
| Latest release | ✅ |
| Older releases | ❌ — please upgrade |

Only the latest release receives security updates. If a critical vulnerability is confirmed, a patch release will be published as soon as possible.

## Runtime Hardening & Permissions

Snapzy is **not** sandboxed (`ENABLE_APP_SANDBOX = NO`) — it runs with the privileges of the
user account that launched it. Its protections come from the macOS Hardened Runtime, code
signing, and notarization rather than from an App Sandbox container:

| Protection | Status |
| --- | --- |
| Hardened Runtime | Enabled (`ENABLE_HARDENED_RUNTIME = YES`) |
| Code signature | Developer ID |
| Notarization | Notarized and stapled by Apple |
| Library validation | On — no `com.apple.security.cs.disable-library-validation`, so the process can only load code signed by the same team or by Apple |
| App Sandbox | **Disabled** |

The practical limits on what Snapzy can reach are therefore macOS TCC permissions (below) and
normal file-system ownership — not a sandbox container.

### Declared entitlements

`Snapzy/Snapzy.entitlements` declares the following. App Sandbox entitlements are **inert while
the sandbox is disabled**; they are listed here because they are declared in the file, not
because they currently grant or restrict anything.

| Entitlement | Purpose |
| --- | --- |
| `com.apple.security.network.client` | Outbound network for Sparkle update checks, user-initiated cloud uploads, and user-configured OCR endpoints |
| `com.apple.security.network.server` | Local loopback server for Google Drive OAuth authorization redirect |
| `com.apple.security.files.user-selected.read-write` | Read/write files the user explicitly picks (save dialogs, drag-to-app) |
| `com.apple.security.device.audio-input` | Microphone access for screen recordings with voice |
| `com.apple.security.temporary-exception.shared-preference.read-only` | Read `com.apple.symbolichotkeys` to detect system shortcut conflicts |
| `com.apple.security.temporary-exception.mach-lookup.global-name` | IPC with Sparkle updater (`-spks`, `-spki` services) |

### Permissions requested at runtime

| Permission | Required | Why |
| --- | --- | --- |
| Screen Recording | Yes | Core functionality — capturing the screen via ScreenCaptureKit |
| Microphone | Optional | Recording system audio + voice in screen recordings |
| Accessibility | Optional | Keystroke overlays and mouse click highlights during recording |

All permissions are requested through standard macOS prompts and can be revoked at any time in **System Settings → Privacy & Security**.

## Data Handling

- **Local-first** — All captures and recordings are stored locally. Cloud upload is opt-in and sends files only to **your own** cloud storage (AWS S3, Cloudflare R2, or Google Drive) — no third-party servers are involved.
- **No telemetry** — No analytics, tracking, or usage data is collected.
- **No accounts** — No sign-in, registration, or user accounts.
- **Network usage** — Outbound requests are limited to Sparkle update checks (appcast over HTTPS) and user-initiated cloud uploads. Both can be disabled in Preferences.
- **Passive QR decoding** — QR codes detected during OCR capture are decoded locally and copied only as plain text. Snapzy does not auto-open QR URLs, expand links over the network, execute commands, load WebViews, or place QR payloads on the pasteboard as file URLs.

## Command Line Tool (`snapzy`)

Snapzy embeds a `snapzy` command at `Snapzy.app/Contents/Helpers/snapzy` so agents and
scripts can capture the screen. Because Snapzy holds the Screen Recording permission, the
command must not turn that permission into a free-for-all for every local process. Details:
[docs/CLI.md](docs/CLI.md).

| Control | Behavior |
| --- | --- |
| Transport | Unix domain socket in `~/Library/Application Support/Snapzy/CLI/` (directory `0700`, socket `0600`); every connection must have the same user ID (`getpeereid`). No network listener |
| On/off | Settings → Command Line (`cliEnabled`, on by default). Off means no socket |
| Approval | Every command except `status` requires the calling app to be approved: **Always Allow / Allow Once / Don't Allow**. No button answers Return; an unanswered prompt times out after 25 s and denies that request (not remembered; only Don't Allow is stored) |
| Caller identity | Walk the CLI's parent processes to the first LaunchServices-registered app that is not Snapzy; verify the running process's code signature (Team ID, or Apple's anchor). Unverified apps are keyed by path, named by their bundle file name (not their own Info.plist), and the prompt shows a generic icon plus their real location |
| Prompt abuse | Unknown methods are rejected before any prompt and the prompt only names known commands; at most 3 apps can wait for a prompt; prompts for connections that went away are never shown |
| Visibility | The menu bar icon is tinted during every CLI capture; a toast names the app when the icon is hidden. Each capture is logged (`CLI` category) |
| Revocation | Settings → Command Line → Allowed apps. Decisions are stored per machine and never exported to `config.toml` |
| Side effects | CLI captures never touch the clipboard, Quick Access, or history, and never trigger a permission prompt |

Known limits — this is a consent check inside one user account, not a sandbox:

- Approval belongs to an **app**, so everything that app runs inherits it: approving a terminal
  approves every command typed or scripted in it.
- A malicious process running as the same user can make an approved app run `snapzy` for it
  (for example AppleScript, `open -a Terminal script.command`) or `exec` into an approved
  app's binary; parent processes are identified by PID. Such a process already has the
  user's full privileges, but treat approvals accordingly.
- Approving an app that runs untrusted code (an agent with broad shell access) lets that code
  capture the screen whenever Snapzy is running. Use Allow Once, or turn command line access
  off, when that is not acceptable.

## Cloud Credentials

- **Keychain storage** — Cloud access keys, secret keys, and Google Drive OAuth refresh/access tokens are stored exclusively in the macOS Keychain, never in plaintext files or UserDefaults.
- **Optional password protection** — Users can set a protection password for cloud credentials. The password is SHA-256 hashed before storage; no plaintext password is persisted.
- **Manual encrypted transfer** — Users may export cloud credentials only through an explicit in-app action. Exported archives are encrypted with a user-supplied passphrase and are never uploaded or synced by Snapzy.
- **No relay servers** — Uploads go directly from the app to your own storage endpoints (S3/R2 endpoints using AWS Signature V4, or Google Drive API using standard OAuth). Snapzy never proxies or stores files on its own infrastructure.

## Auto-Updates (Sparkle)

Snapzy uses [Sparkle](https://sparkle-project.org/) for in-app updates:

- Update checks are made over HTTPS against a signed appcast
- Downloaded updates are verified with EdDSA signatures before installation
- Users can disable automatic update checks in Preferences

## Third-Party Dependencies

| Dependency | Purpose | Source |
| --- | --- | --- |
| [Sparkle](https://sparkle-project.org/) | In-app updates | Swift Package Manager |

Snapzy has minimal third-party dependencies. The codebase relies primarily on Apple frameworks (SwiftUI, AppKit, ScreenCaptureKit, Vision, AVFoundation).

## Security Best Practices for Contributors

- Do not hard-code secrets, keys, or tokens in the source code.
- Do not introduce new entitlements without documenting the reason.
- Do not weaken the Hardened Runtime. In particular, never add `com.apple.security.cs.disable-library-validation` or `com.apple.security.cs.allow-unsigned-executable-memory` to the main app — they would allow unsigned or third-party code to load into a process that holds Screen Recording, Microphone, and Accessibility grants plus Keychain credentials.
- Follow Apple's [Secure Coding Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/SecureCodingGuide/) for any new platform integrations.

## License

This security policy is part of the [Snapzy](https://github.com/duongductrong/Snapzy) project, licensed under the [BSD 3-Clause License](LICENSE).
