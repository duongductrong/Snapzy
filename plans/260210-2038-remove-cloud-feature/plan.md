# Plan: Remove Vestigial Cloud Feature

**Date:** 2026-02-10
**Status:** NOT STARTED
**Priority:** Low
**Scope:** 3 Swift files, ~15 lines removed

## Summary

Remove dead Cloud Upload code from Snapzy. No actual Cloud functionality exists -- only a UI toggle in Quick Access settings and its backing storage. The toggle controls nothing. Zero configuration/entitlement cleanup needed.

## Impact Analysis

- **3 files modified** (Swift only)
- **No breaking changes** -- property is not consumed by any view or logic outside the 3 files
- **No migration needed** -- orphaned UserDefaults key harmless, no data loss
- **Build risk:** Minimal -- removing unused code

## Phases

| # | Phase | Status | File |
|---|-------|--------|------|
| 1 | Remove Cloud Swift Code | NOT STARTED | [phase-01](./phase-01-remove-cloud-swift-code.md) |

## Files Affected

| File | Action |
|------|--------|
| `Snapzy/Features/QuickAccess/QuickAccessManager.swift` | Remove property, key, loader |
| `Snapzy/Features/Preferences/Tabs/QuickAccessSettingsView.swift` | Remove SettingRow |
| `Snapzy/Features/Preferences/PreferencesKeys.swift` | Remove constant |

## Verification

- [ ] Project builds without errors (`Cmd+B`)
- [ ] Quick Access settings view renders correctly without Cloud row
- [ ] No remaining references to `showCloudUpload` or `floatingShowCloudUpload` in `Snapzy/` source

## Notes

- Orphaned UserDefaults key `"floatingScreenshot.showCloudUpload"` left on existing installs is harmless; no cleanup migration warranted (YAGNI)
- SF Symbol `"cloud.fill"` only used by the removed SettingRow; no custom asset catalog cleanup needed
- Historical plan references in `plans/` directory left untouched (documentation, not code)
