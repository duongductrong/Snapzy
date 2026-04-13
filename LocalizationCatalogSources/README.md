# Localization Catalog Sources

Split source-of-truth for app localization lives here.

## Rules

- Edit the domain fragment here when possible
- Treat `Snapzy/Resources/Localizable.xcstrings` as generated runtime output
- Keep keys inside the fragment that owns their prefix in `manifest.json`

## Commands

```bash
# Redistribute runtime-catalog changes back into source fragments
swift -module-cache-path build/swift-module-cache tools/localization/catalog-tool.swift split

# Regenerate the runtime catalog from source fragments
swift -module-cache-path build/swift-module-cache tools/localization/catalog-tool.swift merge

# Check fragment ownership, runtime sync, and L10n drift
swift -module-cache-path build/swift-module-cache tools/localization/catalog-tool.swift verify
```
