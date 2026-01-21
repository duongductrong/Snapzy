# Scout Report: Recording-Related Files

## Recording Feature Files
| File | Purpose |
|------|---------|
| `ZapShot/Features/Recording/RecordingToolbarView.swift` | Main toolbar UI (target for revamp) |
| `ZapShot/Features/Recording/RecordingToolbarWindow.swift` | NSWindow container for toolbar |
| `ZapShot/Features/Recording/RecordingStatusBarView.swift` | Status bar during recording |
| `ZapShot/Features/Recording/RecordingCoordinator.swift` | Coordinates recording workflow |
| `ZapShot/Features/Recording/RecordingRegionOverlayWindow.swift` | Overlay for region selection |

## Core Files
| File | Purpose |
|------|---------|
| `ZapShot/Core/ScreenRecordingManager.swift` | Recording manager, contains VideoFormat enum |
| `ZapShot/Core/RecordingSession.swift` | Recording session management |

## UI Components & Styles
| File | Purpose |
|------|---------|
| `ZapShot/Features/Onboarding/DesignSystem/VSDesignSystem.swift` | Design system with ButtonStyles |
| `ZapShot/Core/ShortcutRecorderView.swift` | Custom button style example |

## Material Usage (existing patterns)
- `RecordingStatusBarView.swift` - uses `.ultraThinMaterial`
- `RecordingToolbarView.swift` - uses `.ultraThinMaterial`

## SF Symbol Usage
- `ZapShotApp.swift`, `PreferencesView.swift`, `RecordingToolbarView.swift`

## Unresolved Questions
- None
