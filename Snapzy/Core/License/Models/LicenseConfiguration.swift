import Foundation

struct LicenseConfiguration {
    var organizationId: UUID?
    let deviceLimit: Int
    let trialDays: Int
    let gracePeriodDays: Int
    let maxGracePeriods: Int
    let apiBaseURL: String
    let validateInterval: TimeInterval
    let cacheValidityDuration: TimeInterval

    static let `default` = LicenseConfiguration(
        organizationId: nil,
        deviceLimit: 2,
        trialDays: 30,
        gracePeriodDays: 1,
        maxGracePeriods: 2,
        apiBaseURL: "https://api.polar.sh/v1/customer-portal",
        validateInterval: 86400,
        cacheValidityDuration: 82800
    )

    static let sandbox = LicenseConfiguration(
        organizationId: nil,
        deviceLimit: 2,
        trialDays: 30,
        gracePeriodDays: 1,
        maxGracePeriods: 2,
        apiBaseURL: "https://sandbox-api.polar.sh/v1/customer-portal",
        validateInterval: 86400,
        cacheValidityDuration: 82800
    )
}

extension LicenseConfiguration {
    var isConfigured: Bool {
        organizationId != nil
    }

    var organizationIdString: String? {
        organizationId?.uuidString
    }
}
