import Foundation
import AppKit
import Combine

// MARK: - License Invalidation Notification

extension Notification.Name {
    /// Posted when a license is invalidated (revoked, disabled, or tampered).
    /// Observers should force the user to re-activate their license.
    static let licenseInvalidated = Notification.Name("licenseInvalidated")
}

// MARK: - Configuration Constants

private struct LicenseConfig {
    // Organization ID is injected at build time via Secrets.xcconfig → Info.plist
    static var defaultOrganizationId: UUID? { SecretsConfig.polarOrganizationId }

    static let defaultDeviceLimit: Int = 2
}

@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    // MARK: - Published State

    @Published private(set) var state: LicenseState = .loading
    @Published private(set) var isActivating = false
    @Published var showInvalidLicenseAlert = false
    @Published var invalidLicenseMessage: String = ""

    // MARK: - Dependencies

    private let provider: PolarLicenseProvider
    private let cache: LicenseCache
    private let deviceFingerprint: DeviceFingerprint
    private let telemetry: LicenseTelemetry

    private var organizationId: UUID?
    private var deviceLimit: Int = LicenseConfig.defaultDeviceLimit

    private init() {
        self.provider = PolarLicenseProvider.shared
        self.cache = LicenseCache()
        self.deviceFingerprint = DeviceFingerprint.shared
        self.telemetry = LicenseTelemetry.shared

        loadOrganizationConfig()
        loadCachedState()
    }

    private func loadOrganizationConfig() {
        // First check UserDefaults (allows override)
        if let storedIdString = UserDefaults.standard.string(forKey: "polar_org_id"),
           let storedId = UUID(uuidString: storedIdString) {
            self.organizationId = storedId
        }
        // Then check hardcoded default (safely converted)
        else if let defaultId = LicenseConfig.defaultOrganizationId {
            self.organizationId = defaultId
        }

        let storedLimit = UserDefaults.standard.integer(forKey: "device_limit")
        self.deviceLimit = storedLimit > 0 ? storedLimit : LicenseConfig.defaultDeviceLimit
    }

    func configure(
        organizationId: UUID,
        deviceLimit: Int = 2
    ) {
        self.organizationId = organizationId
        self.deviceLimit = deviceLimit

        UserDefaults.standard.set(organizationId.uuidString, forKey: "polar_org_id")
        UserDefaults.standard.set(deviceLimit, forKey: "device_limit")
    }

    func getOrganizationId() -> UUID? {
        return organizationId
    }

    func getDeviceLimit() -> Int {
        return deviceLimit
    }



    /// Validates a license key against the server WITHOUT activating it.
    /// Use this to check key validity before calling `activateLicense(key:)`.
    /// - Returns: `ValidateResponse` if the key is valid and activatable.
    /// - Throws: Specific `LicenseError` if the key is invalid, revoked, disabled, or has no activations left.
    func validateLicenseKey(key: String) async throws -> ValidateResponse {
        guard let orgId = organizationId else {
            throw LicenseError.missingConfiguration
        }

        let response = try await provider.validate(key: key, organizationId: orgId)

        switch response.status {
        case "granted":
            // Activation limit is enforced server-side by the /activate endpoint.
            // No need to check here — usage ≠ activation count.
            return response
        case "revoked":
            throw LicenseError.licenseRevoked
        case "disabled":
            throw LicenseError.licenseDisabled
        default:
            throw LicenseError.validationFailed("License status: \(response.status)")
        }
    }

    func activateLicense(key: String) async throws {
        guard let orgId = organizationId else {
            throw LicenseError.missingConfiguration
        }

        isActivating = true
        defer { isActivating = false }

        let deviceId = deviceFingerprint.generate()

        #if DEBUG
        print("=== ACTIVATE: INPUT VALUES ===")
        print("key: \(key)")
        print("orgId: \(orgId.uuidString)")
        print("deviceId (label): \(deviceId)")
        print("==============================")
        #endif

        telemetry.track(event: .activationAttempted)

        do {
            let response = try await provider.activate(
                key: key,
                organizationId: orgId,
                label: deviceId
            )

            #if DEBUG
            print("=== ACTIVATE: RESPONSE ===")
            print("activation id (response.id): \(response.id)")
            print("licenseKeyId: \(response.licenseKeyId)")
            print("label: \(response.label)")
            print("licenseKey.key: \(response.licenseKey.key)")
            print("licenseKey.organizationId: \(response.licenseKey.organizationId)")
            print("licenseKey.status: \(response.licenseKey.status)")
            print("==========================")
            #endif

            try cache.saveLicense(response)

            #if DEBUG
            print("=== ACTIVATE: CACHED VALUES ===")
            print("cached activationId: \(String(describing: cache.getActivationId()))")
            print("cached licenseKey: \(String(describing: cache.getLicenseKey()))")
            print("================================")
            #endif

            let license = License(from: response)
            state = .licensed(license: license)

            telemetry.track(event: .licenseActivated)

        } catch let error as LicenseError {
            telemetry.track(event: .validationFailed, metadata: ["error": error.localizedDescription])
            throw error
        } catch {
            telemetry.track(event: .validationFailed, metadata: ["error": error.localizedDescription])
            throw LicenseError.networkError(error)
        }
    }

    func deactivateLicense() async throws {
        guard let orgId = organizationId,
              let activationId = cache.getActivationId(),
              let licenseKey = cache.getLicenseKey() else {
            #if DEBUG
            print("=== DEACTIVATE: MISSING DATA ===")
            print("orgId: \(String(describing: organizationId))")
            print("activationId: \(String(describing: cache.getActivationId()))")
            print("licenseKey: \(String(describing: cache.getLicenseKey()))")
            print("================================")
            #endif
            return
        }

        #if DEBUG
        print("=== DEACTIVATE: VALUES FROM CACHE ===")
        print("orgId: \(orgId.uuidString)")
        print("activationId: \(activationId.uuidString)")
        print("licenseKey: \(licenseKey)")
        print("=====================================")
        #endif

        telemetry.track(event: .deactivationAttempted)

        do {
            try await provider.deactivate(
                key: licenseKey,
                activationId: activationId,
                organizationId: orgId
            )

            try cache.clear()
            state = .noLicense

        } catch {
            telemetry.track(event: .validationFailed, metadata: ["error": error.localizedDescription])
            throw LicenseError.deactivationFailed(error.localizedDescription)
        }
    }

    func clearLicense() async throws {
        #if DEBUG
        print("=== CLEARING ALL LICENSE DATA ===")
        print("Before clear:")
        print("  activationId: \(String(describing: cache.getActivationId()))")
        print("  licenseKey: \(String(describing: cache.getLicenseKey()))")

        print("================================")
        #endif
        try cache.clear()
        state = .noLicense
        #if DEBUG
        print("=== LICENSE DATA CLEARED ===")
        print("State is now: \(state)")
        print("============================")
        #endif
    }

    func printDebugInfo() {
        print("╔══════════════════════════════════╗")
        print("║     LICENSE DEBUG INFO           ║")
        print("╠══════════════════════════════════╣")
        print("║ State: \(state)")
        print("║ OrgId: \(String(describing: organizationId))")
        print("║ ActivationId: \(String(describing: cache.getActivationId()))")
        print("║ LicenseKey: \(String(describing: cache.getLicenseKey()))")

        print("║ DeviceFingerprint: \(deviceFingerprint.generate())")
        if let entry = cache.load() {
            print("║ CachedLicense:")
            print("║   key: \(entry.license.key)")
            print("║   displayKey: \(entry.license.displayKey)")
            print("║   status: \(entry.license.status)")
            print("║   activation.id: \(String(describing: entry.license.activation?.id))")
            print("║   cachedAt: \(entry.cachedAt)")
            print("║   fingerprint: \(entry.deviceFingerprint)")
        } else {
            print("║ CachedLicense: nil")
        }
        print("╚══════════════════════════════════╝")
    }



    /// Whether the app is activated with a valid license key
    var isLicensed: Bool {
        if case .licensed = state { return true }
        return false
    }

    func generateDebugReport() -> String {
        return telemetry.generateDebugReport()
    }

    // MARK: - Cached State (Offline-First)

    /// Loads cached license on startup, then validates with the server in the background.
    private func loadCachedState() {
        // 1. Cached license exists → show it immediately (no UI delay)
        if let cached = cache.load() {
            state = .licensed(license: cached.license)
            #if DEBUG
            print("=== STARTUP: Loaded cached license (offline-first) ===")
            #endif

            // Validate with server in background (non-blocking)
            Task { await validateLicenseOnStartup() }
            return
        }

        // 2. No data at all
        state = .noLicense
    }

    /// Validates the cached license key against the server on startup.
    /// - If valid: refreshes the cache with the latest server data.
    /// - If revoked/disabled: invalidates the license and forces re-activation.
    /// - If offline/network error: silently keeps the cached license (offline-first).
    private func validateLicenseOnStartup() async {
        guard let orgId = organizationId,
              let licenseKey = cache.getLicenseKey() else {
            #if DEBUG
            print("=== STARTUP VALIDATE: Skipped (missing orgId or cached key) ===")
            #endif
            return
        }

        #if DEBUG
        print("=== STARTUP VALIDATE: Checking license with server... ===")
        #endif

        do {
            let response = try await provider.validate(key: licenseKey, organizationId: orgId)

            switch response.status {
            case "granted":
                // License is still valid — refresh cache with latest server data
                try cache.saveLicense(response)
                let license = License(from: response)
                state = .licensed(license: license)
                #if DEBUG
                print("=== STARTUP VALIDATE: License confirmed valid ===")
                #endif

            case "revoked":
                #if DEBUG
                print("=== STARTUP VALIDATE: License REVOKED ===")
                #endif
                handleLicenseInvalidated(reason: .revoked)

            case "disabled":
                #if DEBUG
                print("=== STARTUP VALIDATE: License DISABLED ===")
                #endif
                handleLicenseInvalidated(reason: .licenseDisabled)

            default:
                #if DEBUG
                print("=== STARTUP VALIDATE: Unexpected status '\(response.status)' ===")
                #endif
                handleLicenseInvalidated(reason: .validationFailed)
            }
        } catch let error as LicenseError {
            switch error {
            case .validationFailed, .invalidLicenseKey, .licenseRevoked, .licenseDisabled, .invalidResponse:
                // License is invalid on the server (e.g. 404, revoked, disabled)
                #if DEBUG
                print("=== STARTUP VALIDATE: License INVALID — \(error.localizedDescription) ===")
                #endif
                invalidLicenseMessage = error.localizedDescription
                showInvalidLicenseAlert = true

            case .networkError, .decodingError:
                // TODO: Define offline behavior (user will specify later)
                #if DEBUG
                print("=== STARTUP VALIDATE: Network/decode error, keeping cached license ===")
                print("  Error: \(error.localizedDescription)")
                #endif

            default:
                // TODO: Define offline behavior (user will specify later)
                #if DEBUG
                print("=== STARTUP VALIDATE: Unexpected error, keeping cached license ===")
                print("  Error: \(error.localizedDescription)")
                #endif
            }
        } catch {
            // TODO: Define offline behavior (user will specify later)
            #if DEBUG
            print("=== STARTUP VALIDATE: Unknown error, keeping cached license ===")
            print("  Error: \(error.localizedDescription)")
            #endif
        }
    }

    /// User chose to clear the invalid license and re-activate.
    func confirmClearInvalidLicense() {
        try? cache.clear()
        state = .noLicense
        showInvalidLicenseAlert = false
        NotificationCenter.default.post(name: .licenseInvalidated, object: nil)
    }

    /// User chose to quit the app instead of re-activating.
    func confirmQuitApp() {
        showInvalidLicenseAlert = false
        NSApplication.shared.terminate(nil)
    }

    // MARK: - License Invalidation

    /// Handles license invalidation: clears all cached data
    /// and posts a notification for the UI to force the license activation screen.
    /// Guards against re-entry — if already in `.noLicense` state, skips.
    private func handleLicenseInvalidated(reason: LicenseState.InvalidReason) {
        // Prevent multiple invalidation calls from opening multiple windows
        if case .noLicense = state { return }

        #if DEBUG
        print("=== LICENSE INVALIDATED: \(reason) ===")
        #endif

        try? cache.clear()
        state = .noLicense
        NotificationCenter.default.post(name: .licenseInvalidated, object: nil)
    }


}
