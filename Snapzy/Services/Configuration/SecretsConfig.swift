import Foundation

/// Centralized accessor for build-time injected secrets via Info.plist.
///
/// Values are populated from `Secrets.xcconfig` → Build Settings → Info.plist at compile time.
/// This avoids hardcoding sensitive values directly in source code.
enum SecretsConfig {

    // MARK: - Polar License

    /// The Polar.sh Organization ID, injected via `POLAR_ORG_ID` build setting.
    static var polarOrganizationId: UUID? {
        guard let idString = Bundle.main.infoDictionary?["PolarOrganizationId"] as? String,
              !idString.isEmpty,
              idString != "your-org-id-here" else {
            return nil
        }
        return UUID(uuidString: idString)
    }

    /// The Polar.sh production API base URL, injected via `POLAR_API_BASE_URL` build setting.
    static var polarApiBaseURL: String {
        guard let url = Bundle.main.infoDictionary?["PolarApiBaseUrl"] as? String,
              !url.isEmpty else {
            return "https://api.polar.sh/v1/customer-portal"
        }
        return url
    }

    /// The Polar.sh sandbox API base URL, injected via `POLAR_SANDBOX_API_BASE_URL` build setting.
    static var polarSandboxApiBaseURL: String {
        guard let url = Bundle.main.infoDictionary?["PolarSandboxApiBaseUrl"] as? String,
              !url.isEmpty else {
            return "https://sandbox-api.polar.sh/v1/customer-portal"
        }
        return url
    }
}
