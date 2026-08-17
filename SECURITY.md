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

## Plugin System

Plugins run **sandboxed native Swift binaries out-of-process**, so they get their own threat model rather
than an entry in a list. Full reference: [`docs/PLUGINS.md`](docs/PLUGINS.md).

### Containment

Plugin code never executes inside the main Snapzy process. Each plugin runs in an isolated child process
spawned via `posix_spawn` with an **enforced zero-entitlement App Sandbox** (`com.apple.security.app-sandbox`).
It has no ambient filesystem access, no network sockets, no ScreenCaptureKit, no Keychain, and no
clipboard. Communication with the host takes place over a dedicated UNIX domain socket pair (`socketpair`) using
length-prefixed binary framing and memory-mapped anonymous blob tables.

**Snapzy never `dlopen`s third-party code.** `InProcessPluginRuntime` is
constructed with `loadsBundles: false`, and only first-party plugins compiled
into the app run in-process. Loading a third-party binary into the host process would require
`com.apple.security.cs.disable-library-validation` on a non-sandboxed app
holding Screen Recording, Microphone, Accessibility, and Keychain authority —
which is why process isolation is a permanent design constraint.

### Two independent boundaries

1. **The sandbox** governs what the *process* can do — kernel-enforced by the App Sandbox.
2. **The broker** (`PluginServiceBroker`) governs what the *plugin* may ask the
   host to do. The manifest is authoritative: an undeclared capability is
   refused by name, a declared scope can only be narrowed by policy and never
   widened, and `snapzy.network` scoped to `["*"]` is narrowed to an empty grant
   rather than granted.

Neither boundary is load-bearing alone.

### Data reachable by a plugin

Only what the user pointed it at. `snapzy.asset.read` is scoped to a live
`invocationID` — there is no ambient handle to captures, and there is **no
capability for the capture history, the clipboard's contents, the screen, or
the filesystem**. `snapzy.secrets` is one Keychain item per plugin, returning
only what that plugin itself stored.

Every brokered call is recorded, redacted at write time, in the request
inspector (Settings → Plugins). Secrets do not reach that log or any other.

### Trust and revocation

Trust tiers change warnings and defaults, never containment: official,
verified, community, and sideloaded plugins all run in the same sandbox behind
the same broker. Official and verified native binaries require valid Developer ID
signatures matching team identifiers in the registry index; integrity is additionally
verified with sha256 checksums before anything leaves staging.

An update that widens capabilities — a new destination host, a new document
edit op — re-prompts for consent before the plugin can run. A `revoked: true`
entry in the index disables installed copies on the next fetch.

### For contributors

- **Do not bypass the sandbox or broker.** If a plugin needs a capability, broker it host-side.
- Adding a case to `SnapzyCapabilities.swift` widens the sentence "a plugin can…". Treat every addition as a security decision, not an API addition.
- Anything reachable from a plugin must route through `PluginServiceBroker`. A direct unbrokered path to host services is a vulnerability.

## Third-Party Dependencies

| Dependency | Purpose | Source |
| --- | --- | --- |
| [Sparkle](https://sparkle-project.org/) | In-app updates | Swift Package Manager |
| [PluginKit](https://github.com/gumbracelet/PluginKit) | Plugin manifests, capabilities, lifecycle | Vendored at `Packages/PluginKit` |

Snapzy has minimal third-party dependencies. The codebase relies primarily on Apple frameworks (SwiftUI, AppKit, ScreenCaptureKit, Vision, AVFoundation).

## Security Best Practices for Contributors

- Do not hard-code secrets, keys, or tokens in the source code.
- Do not introduce new entitlements without documenting the reason.
- Do not weaken the Hardened Runtime. In particular, never add `com.apple.security.cs.disable-library-validation` or `com.apple.security.cs.allow-unsigned-executable-memory` to the main app — they would allow unsigned or third-party code to load into a process that holds Screen Recording, Microphone, and Accessibility grants plus Keychain credentials. This is also why plugins run out-of-process; see [Plugin System](#plugin-system).
- Follow Apple's [Secure Coding Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/SecureCodingGuide/) for any new platform integrations.

## License

This security policy is part of the [Snapzy](https://github.com/duongductrong/Snapzy) project, licensed under the [BSD 3-Clause License](LICENSE).
