# Phase 2: Dark Theme Onboarding Views

**Parent:** [plan.md](./plan.md)

## Context

All onboarding views currently use light-mode styling (blue icons, `.secondary` text, gray backgrounds). They will now render on top of the splash window's `NSVisualEffectView` blur layer, requiring a full dark/frosted restyle.

**Reference style** — `SplashContentView.swift`:
- White text: `.foregroundStyle(.white)`, `.white.opacity(0.7)`
- Frosted buttons: `Capsule().fill(.white.opacity(0.2))` + `Capsule().stroke(.white.opacity(0.3), lineWidth: 1)`
- Plain button style: `.buttonStyle(.plain)`

## Overview

Restyle 6 files to match the premium dark/blur aesthetic established by `SplashContentView`. All views must be readable against the translucent blur background without introducing any opaque backgrounds.

## Key Insights

1. **White-on-blur** is the core pattern. No opaque colored backgrounds (no `.blue`, no `.gray.opacity(0.05)`).
2. **Card backgrounds** use `.white.opacity(0.08)` — subtle frosted glass effect.
3. **Button styles unify** to frosted capsule (primary) and ghost capsule (secondary).
4. **VSDesignSystem** changes are the foundation — all views inherit updated styles automatically.
5. **PermissionRow** needs the most changes — icon backgrounds, badge colors, grant button, status indicator all switch to dark variants.

## Related Code Files

| File | Path | Lines | Changes |
|------|------|-------|---------|
| VSDesignSystem | `Snapzy/Features/Onboarding/DesignSystem/VSDesignSystem.swift` | 88 | Typography colors, all button styles |
| PermissionsView | `Snapzy/Features/Onboarding/Views/PermissionsView.swift` | 157 | Header icon, text colors |
| ShortcutsView | `Snapzy/Features/Onboarding/Views/ShortcutsView.swift` | 91 | Text colors, ShortcutBadge restyle |
| CompletionView | `Snapzy/Features/Onboarding/Views/CompletionView.swift` | 95 | Check icon, hint box, SettingsLink button |
| PermissionRow | `Snapzy/Features/Onboarding/Views/PermissionRow.swift` | 113 | Icon bg, badge colors, card bg, status |
| OnboardingFlowView | `Snapzy/Features/Onboarding/OnboardingFlowView.swift` | 90 | Remove WelcomeView case, simplify |

## Requirements

1. All text must be white (headings) or `.white.opacity(0.7)` (body/secondary)
2. All icons must be white or `.white.opacity(0.8)`
3. Card/row backgrounds: `.white.opacity(0.08)` with `RoundedRectangle(cornerRadius: 12)`
4. Primary buttons: frosted capsule — `.white.opacity(0.2)` fill, `.white.opacity(0.3)` stroke, white text
5. Secondary buttons: ghost capsule — `.white.opacity(0.1)` fill, `.white.opacity(0.2)` stroke, `.white.opacity(0.8)` text
6. No blue backgrounds (`.blue` fill for buttons is removed)
7. Permission granted status: green checkmark + "Granted" text, on `.green.opacity(0.15)` background
8. Required/Optional badges: use `.white.opacity(0.15)` background with `.orange` / `.white.opacity(0.5)` text

## Implementation Steps

### VSDesignSystem.swift

- [ ] Change `Typography.bodyColor` from `Color.secondary` to `Color.white.opacity(0.7)`
- [ ] Update `vsHeading()` to add `.foregroundStyle(.white)`
- [ ] Update `vsBody()` to use new `bodyColor`
- [ ] **PrimaryButtonStyle**: Replace `RoundedRectangle` fill `.blue` with `Capsule().fill(.white.opacity(0.2))`, add `.overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1))`, keep `.foregroundColor(.white)`, change corner shape from `RoundedRectangle(cornerRadius: 10)` to `Capsule()`
- [ ] **SecondaryButtonStyle**: Replace gray fill with `Capsule().fill(.white.opacity(0.1))`, add `.overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))`, change `.foregroundColor(.primary)` to `.foregroundColor(.white.opacity(0.8))`
- [ ] **SuccessButtonStyle**: Replace green fill with `Capsule().fill(.green.opacity(0.3))`, add green stroke `.overlay(Capsule().stroke(.green.opacity(0.4), lineWidth: 1))`
- [ ] Add `.buttonStyle(.plain)` note in comments (callers must use `.buttonStyle(.plain)` alongside these)

### PermissionRow.swift

- [ ] Icon container: change `.fill(Color.blue.opacity(0.1))` to `.fill(Color.white.opacity(0.1))`, icon color from `.blue` to `.white.opacity(0.8)`
- [ ] Title text: add `.foregroundColor(.white)`
- [ ] Description text: change `.foregroundColor(.secondary)` to `.foregroundColor(.white.opacity(0.5))`
- [ ] Required badge: change bg `.orange.opacity(0.2)` to `.orange.opacity(0.25)`, keep `.foregroundColor(.orange)`
- [ ] Optional badge: change bg `.gray.opacity(0.2)` to `.white.opacity(0.15)`, change text to `.foregroundColor(.white.opacity(0.5))`
- [ ] Granted status: keep green colors, change bg to `.green.opacity(0.15)`
- [ ] Card background: change `.fill(Color.gray.opacity(0.05))` to `.fill(Color.white.opacity(0.08))`
- [ ] Add subtle border: `.overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.1), lineWidth: 1))`

### PermissionsView.swift

- [ ] Header icon: change `.foregroundColor(.blue)` to `.foregroundColor(.white.opacity(0.8))`
- [ ] Heading text: already uses `.vsHeading()` (will inherit white from VSDesignSystem update)
- [ ] Body text: already uses `.vsBody()` (will inherit white from update)
- [ ] Button styles: already use `VSDesignSystem.PrimaryButtonStyle()` / `SecondaryButtonStyle()` (will inherit frosted style)
- [ ] No other changes needed (permission logic unchanged)

### ShortcutsView.swift

- [ ] App icon: no change needed (app icon renders fine on dark)
- [ ] Heading/body: inherit from `.vsHeading()` / `.vsBody()` updates
- [ ] **ShortcutBadge** restyle: change key bg `.fill(Color.gray.opacity(0.15))` to `.fill(Color.white.opacity(0.1))`, add `.overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.15), lineWidth: 1))`
- [ ] ShortcutBadge key text: add `.foregroundColor(.white)`
- [ ] ShortcutBadge action text: change `.foregroundColor(.secondary)` to `.foregroundColor(.white.opacity(0.6))`
- [ ] Buttons: inherit from VSDesignSystem updates

### CompletionView.swift

- [ ] Success circle bg: change `.fill(Color.green.opacity(0.15))` to `.fill(Color.green.opacity(0.12))`
- [ ] Checkmark icon: keep `.foregroundColor(.green)` (green on dark looks good)
- [ ] Menu bar hint box: change `.fill(Color.blue.opacity(0.08))` to `.fill(Color.white.opacity(0.08))`, add `.overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1), lineWidth: 1))`
- [ ] Hint icon: change `.foregroundColor(.blue)` to `.foregroundColor(.white.opacity(0.7))`
- [ ] Hint text: change `.foregroundColor(.secondary)` to `.foregroundColor(.white.opacity(0.6))`
- [ ] **SettingsLink button**: replace blue `RoundedRectangle` with frosted capsule matching PrimaryButtonStyle
- [ ] "Get Started" button: inherits SecondaryButtonStyle update

### OnboardingFlowView.swift

- [ ] Remove `.welcome` case from `OnboardingStep` enum (splash replaces welcome)
- [ ] Remove `WelcomeView` import/usage from `switch` block
- [ ] Update `@State private var currentStep` default to `.permissions`
- [ ] Keep `completeOnboarding()`, `hasCompletedOnboarding`, `resetOnboarding()` static methods
- [ ] Note: This view may become unused if `SplashOnboardingRootView` inlines the step logic. Decide in Phase 1 whether to keep `OnboardingFlowView` as a wrapper or inline steps directly.

## Todo List

```
- [ ] Restyle VSDesignSystem (typography + 3 button styles)
- [ ] Restyle PermissionRow (icon, badges, card, status)
- [ ] Restyle PermissionsView (header icon color)
- [ ] Restyle ShortcutsView (ShortcutBadge component)
- [ ] Restyle CompletionView (hint box, SettingsLink, success icon)
- [ ] Update OnboardingFlowView (remove welcome step)
- [ ] Verify compile after all changes
- [ ] Visual check: all text readable on blur background
```

## Success Criteria

- All text is white-family colors (no dark text invisible on blur)
- All buttons use frosted capsule style consistent with `SplashContentView`
- Card backgrounds use subtle `.white.opacity(0.08)` — visible but not opaque
- Permission grant/check logic unchanged (no functional regressions)
- Each file remains under 200 lines
- No hardcoded light-mode colors remain (no `.blue` fills, no `.gray.opacity(0.05)`)

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Green status colors too dim on blur | Low | Medium | Test with `.green` at full saturation; add `.shadow(color: .green.opacity(0.3), radius: 4)` if needed |
| SettingsLink may not respect custom button styling | Medium | Medium | Wrap label in custom styling directly on the `SettingsLink { Label }` content |
| `.buttonStyle(.plain)` missing on some buttons | Medium | Low | Audit all `Button` calls to ensure `.buttonStyle(.plain)` is present when using custom styles |
| App icon rendering on dark bg | Low | Low | `NSApp.applicationIconImage` already has alpha; renders fine on any background |

## Next Steps

After this phase, proceed to [Phase 3](./phase-03-integration.md) to wire `SplashWindowController` and remove `WindowGroup(id: "onboarding")`.
