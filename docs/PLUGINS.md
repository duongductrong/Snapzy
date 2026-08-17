# Plugins

Snapzy plugins **run real code** and **participate in editing workflows**: a
plugin can read the capture you invoked it on, ask the host for OCR lines with
bounding boxes, call a network endpoint, and write structured results back into
a live editor as **one undoable step**.

This document is part of the security model. If it overstates what is enforced,
you make trust decisions on a false basis — so it starts with what plugins
**cannot** do, and every claim below names the test behind it.

- Writing one? Start at [Quick start](#quick-start).
- Deciding whether to trust one? Read [What plugins cannot do](#what-plugins-cannot-do)
  and [Trust tiers](#trust-tiers).

---

## What plugins cannot do

Native Swift plugin code runs in an **App-Sandboxed helper process (`com.apple.security.app-sandbox`) with zero entitlements**, one process per plugin, communicating over a framed binary protocol via UNIX domain sockets.

| A plugin cannot… | Why not |
| --- | --- |
| Read or write arbitrary files | The sandbox enforces strict file isolation. Only the plugin's own container is accessible |
| Reach the network directly | Direct network sockets are refused by sandbox policy. Requests must be brokered via `snapzy.network` against declared hosts |
| Capture the screen | No ScreenCaptureKit access and no Screen Recording TCC grant |
| Read the clipboard | There is no clipboard-read capability at all. Writing is a separate, sensitive capability |
| Reach the Keychain directly | Direct Keychain access is denied. `snapzy.secrets` is brokered and returns only what the plugin itself stored |
| Read your capture history | The history database is not exposed as a capability |
| Spawn arbitrary unverified processes | Child process creation is blocked by sandbox policy |
| Draw unmanaged windows or steal focus | UI is declarative: the plugin describes a form or alert, and the **host** renders it |
| Run forever or exhaust memory | The host process supervisor enforces timeouts and terminates misbehaving plugins via SIGKILL |

---

## What plugins can do

Every capability is declared in the manifest, shown before install, and gated
at every call.

| Capability | Sensitivity | What it grants | The consent copy it generates |
| --- | --- | --- | --- |
| `snapzy.asset.read` | sensitive | The bytes of the capture you invoked on, for that invocation only | *"…can read the image you run it on."* |
| `snapzy.ocr` | benign | Local Vision recognition, lines with boxes | *"…can read text in images on your Mac."* |
| `snapzy.image` | benign | Host-side decode / resize / crop / encode | *"…can process images."* |
| `snapzy.media` | benign | Duration, a frame at a time, extracted audio | *"…can inspect the video."* |
| `snapzy.network` | **dangerous** | HTTP to the hosts named in its scope | *"…and send it to `api.openai.com`."* |
| `snapzy.document.write` | sensitive | Structured edits, limited to the ops in its scope | *"…can add items to the document you have open."* |
| `snapzy.ui` | benign | Host-rendered form, confirm, result panel, progress | *"…can ask you questions."* |
| `snapzy.clipboard.write` | sensitive | Write text or an image to the clipboard | *"…can put things on your clipboard."* |
| `snapzy.storage` | benign | Its own container, nothing else's | *"…can save its own settings."* |
| `snapzy.secrets` | sensitive | One Keychain item, holding only what it wrote | *"…can store a credential."* |
| `snapzy.notify` | benign | A system notification | *"…can send you notifications."* |

Consent copy names **the data, not the API**, and is generated from the
capability scopes — never written by the plugin author.

---

## Quick start

Authoring a Swift native plugin is simple with the `snapzy-plugin` toolchain:

```bash
# 1. Initialize a new plugin project
snapzy-plugin init com.example.myplugin

# 2. Open directory
cd com.example.myplugin

# 3. Build the plugin bundle (.snapzyplugin)
snapzy-plugin build

# 4. Test locally with live development mode
snapzy-plugin dev

# 5. Run tests with Swift Testing harness
swift test
```

### Swift Plugin Authoring Example

```swift
import Foundation
import SnapzyPluginSDK

@main
struct MyPlugin: SnapzyPlugin {
  init() {}

  func activate(_ context: SnapzyPluginContext) async throws {
    context.command("run") { request, ctx in
      let text = try await ctx.asset.read()
      try await ctx.ui.toast(message: "Processed capture!")
      return .completed("Success")
    }
  }
}
```

### Testing with `SnapzyPluginTesting`

```swift
import Foundation
import SnapzyPluginTesting
import Testing
@testable import MyPlugin

@Test func runCommandExecutes() async throws {
  let host = FakeHost()
  host.registerAsset(Data("fake-image-bytes".utf8))

  let harness = PluginHarness(MyPlugin.self, host: host)
  let result = try await harness.execute("run")

  #expect(result.isSuccess)
}
```

---

## Packaging and Distribution

Package and sign your plugin for distribution using `snapzy-plugin`:

```bash
# Package for distribution with Developer ID signing
snapzy-plugin package --identity "Developer ID Application: Your Name (TEAMID)"
```

This outputs a signed `.snapzyplugin` bundle, a `.zip` archive, and the computed SHA-256 digest ready for the registry index.
