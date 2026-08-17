# Vendored: PluginKit

Upstream: https://github.com/gumbracelet/PluginKit

Vendored from commit `84e28412664d0f347c98ce2cf6cae3b786d71f3b` (tag `v1.0.0`).

## Why vendored

Two reasons, both temporary by intent:

1. **Xcode package-resolution bug.** When a local package (SnapzyPluginAPI)
   depends on the *same* remote package the project references directly
   (PluginKit), `xcodebuild` intermittently fails with "found multiple
   top-level packages named 'PluginKit'". Path-based identities dedupe
   correctly. Referencing PluginKit as a local package from both the project
   and SnapzyPluginAPI resolves deterministically.

2. **Exact pinning.** The plan pins PluginKit to an exact version. A committed
   copy is the strongest possible pin and removes the network from the build
   graph.

## How to update

1. Check out the upstream tag, copy `Sources/` and `Package.swift` here.
2. Update the commit recorded above.
3. Run the full Snapzy test suite (`xcodebuild … test`) — PluginKit is the
   plugin system's foundation, so nothing short of green is acceptable.

Only `Sources/` and `Package.swift` are vendored. Upstream's own test suite
lives upstream; Snapzy's tests exercise the seam it cares about.
