import Foundation

enum LicenseState: Equatable {
    case licensed(license: License)
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
        case invalidLicenseKey
        case maximumDevicesReached
        case licenseDisabled
        case unknown(String)
    }

    var isValid: Bool {
        switch self {
        case .licensed(let license):
            return license.isValid
        case .invalid, .loading, .noLicense:
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
        case (.licensed(let l1), .licensed(let l2)):
            return l1 == l2
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
        case .licensed(let license):
            return "Licensed(\(license.displayKey))"
        case .invalid(let reason):
            return "Invalid(\(reason))"
        case .loading:
            return "Loading"
        case .noLicense:
            return "NoLicense"
        }
    }
}
