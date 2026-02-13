import Foundation

enum LicenseState: Equatable {
    case trial(daysRemaining: Int)
    case licensed(license: License)
    case trialExpired
    case invalid(reason: InvalidReason)
    case loading
    case noLicense

    enum InvalidReason: Equatable {
        case revoked
        case expired
        case deviceLimitExceeded
        case noActivationsRemaining
        case networkError
        case validationFailed
        case timeManipulationDetected
        case invalidLicenseKey
        case maximumDevicesReached
        case licenseDisabled
        case unknown(String)
    }

    var isValid: Bool {
        switch self {
        case .trial:
            return true
        case .licensed(let license):
            return license.isValid
        case .trialExpired, .invalid, .loading, .noLicense:
            return false
        }
    }

    var isTrial: Bool {
        switch self {
        case .trial:
            return true
        default:
            return false
        }
    }

    var license: License? {
        switch self {
        case .licensed(let license):
            return license
        default:
            return nil
        }
    }

    var daysRemaining: Int? {
        switch self {
        case .trial(let days):
            return days
        case .licensed(let license):
            if let expiresAt = license.expiresAt {
                let days = Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day
                return days
            }
            return nil
        default:
            return nil
        }
    }

    var statusDescription: String {
        switch self {
        case .trial(let days):
            return "Trial - \(days) days remaining"
        case .licensed(let license):
            switch license.status {
            case .granted:
                if let days = daysRemaining {
                    if days < 0 {
                        return "Expired"
                    } else if days == 0 {
                        return "Expires today"
                    } else {
                        return "Valid - \(days) days remaining"
                    }
                }
                return "Valid"
            case .revoked:
                return "Revoked"
            case .disabled:
                return "Disabled"
            }
        case .trialExpired:
            return "Trial expired"
        case .invalid(let reason):
            return "Invalid - \(reasonDescription(reason))"
        case .loading:
            return "Loading..."
        case .noLicense:
            return "No license"
        }
    }

    private func reasonDescription(_ reason: InvalidReason) -> String {
        switch reason {
        case .revoked:
            return "Your license has been revoked"
        case .expired:
            return "Your license has expired"
        case .deviceLimitExceeded:
            return "Maximum device limit exceeded"
        case .noActivationsRemaining:
            return "No activations remaining"
        case .networkError:
            return "Network error - please check your connection"
        case .validationFailed:
            return "License validation failed"
        case .timeManipulationDetected:
            return "Time manipulation detected"
        case .invalidLicenseKey:
            return "Invalid license key"
        case .maximumDevicesReached:
            return "Maximum devices reached"
        case .licenseDisabled:
            return "License has been disabled"
        case .unknown(let message):
            return message
        }
    }

    static func == (lhs: LicenseState, rhs: LicenseState) -> Bool {
        switch (lhs, rhs) {
        case (.trial(let days1), .trial(let days2)):
            return days1 == days2
        case (.licensed(let l1), .licensed(let l2)):
            return l1 == l2
        case (.trialExpired, .trialExpired):
            return true
        case (.invalid(let r1), .invalid(let r2)):
            return r1 == r2
        case (.loading, .loading):
            return true
        case (.noLicense, .noLicense):
            return true
        default:
            return false
        }
    }
}

extension LicenseState: CustomStringConvertible {
    var description: String {
        switch self {
        case .trial(let days):
            return "Trial(\(days) days)"
        case .licensed(let license):
            return "Licensed(\(license.displayKey))"
        case .trialExpired:
            return "TrialExpired"
        case .invalid(let reason):
            return "Invalid(\(reason))"
        case .loading:
            return "Loading"
        case .noLicense:
            return "NoLicense"
        }
    }
}

extension LicenseState {
    var entitlements: LicenseEntitlements {
        switch self {
        case .trial, .licensed:
            return .pro
        default:
            return .free
        }
    }
}
