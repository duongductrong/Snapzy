# Phase 03: PermissionsView with PermissionRow Component

## Context

- **Parent Plan:** [plan.md](../plan.md)
- **Dependencies:** Phase 01 (VSDesignSystem), ScreenCaptureManager
- **Related Docs:** macOS permission handling patterns

## Overview

| Field | Value |
|-------|-------|
| Date | 260116 |
| Description | Create PermissionsView with reusable PermissionRow component |
| Priority | High |
| Status | Pending |

## Requirements

1. Header with shield icon and "Grant Permissions" title
2. Reusable `PermissionRow` showing: icon, title, description, status
3. Status: "Grant Access" button or green checkmark when granted
4. Bottom nav: "Quit" (secondary) left, "Next" (primary) right
5. "Next" disabled until all permissions granted
6. Integrate with `ScreenCaptureManager` for permission state

## Architecture

```swift
struct PermissionRow: View {
  let icon: String
  let title: String
  let description: String
  let isGranted: Bool
  let onGrant: () -> Void
}

struct PermissionsView: View {
  @ObservedObject var screenCaptureManager: ScreenCaptureManager
  let onQuit: () -> Void
  let onNext: () -> Void
}
```

## Related Files

- `ZapShot/Core/ScreenCaptureManager.swift` - hasPermission, requestPermission()
- `ZapShot/Features/Onboarding/DesignSystem/VSDesignSystem.swift`

## Implementation

### Step 1: Create PermissionRow.swift

**File:** `ZapShot/Features/Onboarding/Views/PermissionRow.swift`

```swift
//
//  PermissionRow.swift
//  ZapShot
//
//  Reusable permission row component for onboarding
//

import SwiftUI

struct PermissionRow: View {
  let icon: String
  let title: String
  let description: String
  let isGranted: Bool
  let onGrant: () -> Void

  var body: some View {
    HStack(spacing: 16) {
      // Icon
      Image(systemName: icon)
        .font(.system(size: 24))
        .foregroundColor(.blue)
        .frame(width: 44, height: 44)
        .background(
          RoundedRectangle(cornerRadius: 10)
            .fill(Color.blue.opacity(0.1))
        )

      // Title and Description
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 14, weight: .semibold))

        Text(description)
          .font(.system(size: 12))
          .foregroundColor(.secondary)
      }

      Spacer()

      // Status
      if isGranted {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 24))
          .foregroundColor(.green)
      } else {
        Button("Grant Access") {
          onGrant()
        }
        .buttonStyle(VSDesignSystem.PrimaryButtonStyle())
      }
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color.gray.opacity(0.05))
    )
  }
}

#Preview {
  VStack(spacing: 12) {
    PermissionRow(
      icon: "rectangle.dashed.badge.record",
      title: "Screen Recording",
      description: "Required to capture screenshots",
      isGranted: false,
      onGrant: {}
    )
    PermissionRow(
      icon: "rectangle.dashed.badge.record",
      title: "Screen Recording",
      description: "Required to capture screenshots",
      isGranted: true,
      onGrant: {}
    )
  }
  .padding()
  .frame(width: 450)
}
```

### Step 2: Create PermissionsView.swift

**File:** `ZapShot/Features/Onboarding/Views/PermissionsView.swift`

```swift
//
//  PermissionsView.swift
//  ZapShot
//
//  Permissions grant screen for onboarding flow
//

import SwiftUI

struct PermissionsView: View {
  @ObservedObject var screenCaptureManager: ScreenCaptureManager
  let onQuit: () -> Void
  let onNext: () -> Void

  private var allPermissionsGranted: Bool {
    screenCaptureManager.hasPermission
  }

  var body: some View {
    VStack(spacing: 24) {
      // Header
      VStack(spacing: 12) {
        Image(systemName: "shield.checkered")
          .font(.system(size: 48))
          .foregroundColor(.blue)

        Text("Grant Permissions")
          .vsHeading()

        Text("ZapShot needs a few permissions to work properly.")
          .vsBody()
      }

      Spacer()
        .frame(height: 20)

      // Permission Rows
      VStack(spacing: 12) {
        PermissionRow(
          icon: "rectangle.dashed.badge.record",
          title: "Screen Recording",
          description: "Required to capture screenshots of your screen",
          isGranted: screenCaptureManager.hasPermission,
          onGrant: {
            Task {
              await screenCaptureManager.requestPermission()
            }
          }
        )
      }
      .frame(maxWidth: 400)

      Spacer()

      // Bottom Navigation
      HStack {
        Button("Quit") {
          onQuit()
        }
        .buttonStyle(VSDesignSystem.SecondaryButtonStyle())

        Spacer()

        Button("Next") {
          onNext()
        }
        .buttonStyle(VSDesignSystem.PrimaryButtonStyle(isDisabled: !allPermissionsGranted))
        .disabled(!allPermissionsGranted)
      }
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task {
      await screenCaptureManager.checkPermission()
    }
  }
}

#Preview {
  PermissionsView(
    screenCaptureManager: ScreenCaptureManager.shared,
    onQuit: {},
    onNext: {}
  )
  .frame(width: 500, height: 450)
}
```

## Todo

- [ ] Create PermissionRow.swift with reusable component
- [ ] Create PermissionsView.swift with header and navigation
- [ ] Integrate with ScreenCaptureManager.hasPermission
- [ ] Wire up Grant Access to requestPermission()
- [ ] Disable Next button until permissions granted
- [ ] Add previews for visual verification
- [ ] Verify compilation

## Success Criteria

- [ ] PermissionRow displays icon, title, description, and status
- [ ] Status toggles between button and checkmark based on isGranted
- [ ] PermissionsView shows header with shield icon
- [ ] Permission state updates reactively from ScreenCaptureManager
- [ ] Next button disabled when permissions not granted
- [ ] Quit button triggers onQuit callback
- [ ] Code compiles without errors
