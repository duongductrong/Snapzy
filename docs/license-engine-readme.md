# Snapzy LicenseKit

## Overview

LicenseKit is a comprehensive licensing system for Snapzy that integrates with Polar.sh's license key API. It provides:

- **Device-based licensing** with configurable limits (default: 2 devices)
- **30-day free trial** starting on user action
- **Time-shifting prevention** with server time validation
- **Grace period support** (24 hours, max 2 uses)
- **Offline caching** with encrypted local storage
- **Anti-cheat measures** including device fingerprinting

## Architecture

```
Snapzy/Core/License/
├── Models/
│   ├── License.swift              # License data model
│   ├── LicenseState.swift         # State enum (trial, active, expired, invalid)
│   └── LicenseConfiguration.swift # Configuration model
├── Providers/
│   └── PolarLicenseProvider.swift # Polar.sh API client
├── Security/
│   ├── DeviceFingerprint.swift   # Hardware fingerprint generation
│   ├── TimeValidator.swift        # Time manipulation detection
│   └── KeychainService.swift      # Secure storage
├── Cache/
│   └── LicenseCache.swift         # License caching layer
├── Telemetry/
│   └── LicenseTelemetry.swift     # Usage analytics
├── LicenseManager.swift           # Main singleton @MainActor
├── LicenseError.swift             # Error types
└── LicenseConstants.swift         # Constants and entitlements
```

## Configuration

### Polar.sh Dashboard Setup

1. Create a Polar.sh account at https://polar.sh
2. Create a new organization
3. Go to **Products** → **Benefits** → **Create Benefit**
4. Select **License Keys**
5. Configure:
   - **Prefix**: `SNAPZY-XXXXXX`
   - **Activation Limit**: 2 (default, can be adjusted per key)
   - **Expiration**: Set based on your pricing model
6. Copy the **Organization ID** from your dashboard settings

### App Configuration

```swift
// Configure in your app startup (e.g., AppDelegate)
LicenseManager.shared.configure(
    organizationId: UUID("your-org-id-here"),
    deviceLimit: 2
)
```

## Usage

### Starting a Trial

```swift
Task {
    await LicenseManager.shared.startTrial()
}
```

### Activating a License

```swift
do {
    try await LicenseManager.shared.activateLicense(key: "SNAPZY-XXXXX-XXXXX")
} catch {
    print("Activation failed: \(error)")
}
```

### Validating on Launch

```swift
Task {
    await LicenseManager.shared.validateLicense()
}
```

### Checking Feature Access

```swift
if LicenseManager.shared.canAccessFeature(.videoEditing) {
    // Enable video editing features
}
```

## Security Features

### Device Fingerprinting

- Generates unique device identifier from:
  - Hardware UUID
  - Device model
  - Serial number
- Stored securely in Keychain
- Verified on cache load

### Time-Shifting Prevention

- Compares local time with server timestamp
- Max allowed drift: 5 minutes
- Grace period: 24 hours (max 2 uses)
- Time manipulation detection

### License Caching

- Encrypted storage in UserDefaults + Keychain
- Valid for 24 hours (with grace period)
- Fingerprint verification prevents restore attacks

## Anti-Cheat Summary

| Threat            | Mitigation                               |
| ----------------- | ---------------------------------------- |
| Time manipulation | Server time validation + drift detection |
| License sharing   | Device fingerprint + activation binding  |
| Offline abuse     | Grace period limits + telemetry          |
| Cache tampering   | Encryption + fingerprint verification    |
| API abuse         | Rate limiting (Polar enforced)           |

## Error Handling

```swift
switch LicenseManager.shared.state {
case .invalid(let reason):
    switch reason {
    case .deviceLimitExceeded:
        showDeviceManagementAlert()
    case .timeManipulationDetected:
        showClockAlert()
    default:
        showGenericError()
    }
case .trialExpired:
    showUpgradePrompt()
default:
    break
}
```

## Testing

### Sandbox Mode

Polar provides a sandbox environment for testing:

```swift
// In development builds
PolarLicenseProvider.sandboxBaseURL = "https://sandbox-api.polar.sh/v1/customer-portal"
```

### Debug Report

```swift
print(LicenseManager.shared.generateDebugReport())
```

## Requirements

- macOS 14.0+
- Xcode 15.0+
- Polar.sh account

## License

MIT License - See LICENSE file for details.
