import Foundation

enum LicenseError: Error, LocalizedError {
    case missingConfiguration
    case invalidLicenseKey
    case networkError(Error)
    case validationFailed(String)
    case deviceLimitExceeded
    case maximumDevicesReached
    case licenseRevoked
    case licenseExpired
    case licenseDisabled
    case activationFailed(String)
    case deactivationFailed(String)
    case noActivationsRemaining
    case invalidResponse
    case decodingError(Error)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "License is not configured. Please configure your organization ID."
        case .invalidLicenseKey:
            return "The license key is invalid."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .validationFailed(let message):
            return "Validation failed: \(message)"
        case .deviceLimitExceeded:
            return "Maximum device limit exceeded. Please deactivate a device or purchase a new license."
        case .maximumDevicesReached:
            return "Maximum devices reached for this license."
        case .licenseRevoked:
            return "Your license has been revoked."
        case .licenseExpired:
            return "Your license has expired."
        case .licenseDisabled:
            return "Your license has been disabled."
        case .activationFailed(let message):
            return "Activation failed: \(message)"
        case .deactivationFailed(let message):
            return "Deactivation failed: \(message)"
        case .noActivationsRemaining:
            return "No activations remaining on this license."
        case .invalidResponse:
            return "Invalid response from server."
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
}
