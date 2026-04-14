# Localization Catalogs

Centralized runtime source-of-truth for app localization lives here under `Resources/Localization/`.

## Layout

- `Shared/`: cross-feature vocabulary, errors, permissions, and other shared copy
- `Features/`: feature-owned catalogs aligned to runtime domains
- `Generated/`: reserved for generated localization artifacts if we add them later
- `manifest.json`: prefix ownership for the split catalogs

## Rules

- Edit the owning `.xcstrings` fragment here when possible
- Keep keys inside the fragment that owns their prefix in `manifest.json`
- These catalogs are the runtime resources used by the app. No monolith merge step.

## Commands

```bash
# Check fragment ownership and L10n drift
swift -module-cache-path build/swift-module-cache tools/localization/CatalogTool.swift verify
```
