# ZapShot Onboarding Design System Implementation Plan

**Created:** 260116 | **Status:** Pending | **Priority:** High

## Overview

Implement a cohesive onboarding flow for ZapShot with reusable design system components. Flow: Welcome -> Permissions -> Shortcuts.

## Architecture

```
ZapShot/Features/Onboarding/
├── DesignSystem/
│   └── VSDesignSystem.swift      # Typography + Button styles
├── Views/
│   ├── WelcomeView.swift         # Welcome screen
│   ├── PermissionsView.swift     # Permission grants
│   ├── PermissionRow.swift       # Reusable permission component
│   └── ShortcutsView.swift       # Shortcut setup
└── OnboardingFlowView.swift      # Flow coordinator
```

## Phases

| Phase | Description | Status | Progress |
|-------|-------------|--------|----------|
| [Phase 01](./phases/phase-01-design-system-foundation.md) | VSDesignSystem + Button Styles | Pending | 0% |
| [Phase 02](./phases/phase-02-welcome-view.md) | WelcomeView Implementation | Pending | 0% |
| [Phase 03](./phases/phase-03-permissions-view.md) | PermissionsView + PermissionRow | Pending | 0% |
| [Phase 04](./phases/phase-04-shortcuts-and-integration.md) | ShortcutsView + Flow Integration | Pending | 0% |

## Dependencies

- `ScreenCaptureManager.swift` - Permission checking/requesting
- `KeyboardShortcutManager.swift` - Shortcut enable/disable
- `ZapShotApp.swift` - App entry point integration

## Success Criteria

- [ ] VSDesignSystem provides consistent typography and button styles
- [ ] All three views render correctly with proper styling
- [ ] Permission status updates reactively
- [ ] Shortcuts can be enabled/declined
- [ ] Onboarding flow navigates correctly between views
- [ ] Code compiles without errors
