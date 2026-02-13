import Foundation
import Combine

// MARK: - Configuration Constants

private struct LicenseConfig {
    // TODO: Replace with your actual Polar.sh Organization ID
    // Get it from https://polar.sh/dashboard/settings
    // Format: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    static let defaultOrganizationIdString: String? = "5791385b-ccb4-4a3d-9909-ded8bd28ec31"

    static let defaultDeviceLimit: Int = 2
    static let trialDays: Int = 30
    static let gracePeriodDays: Int = 1
    static let maxGracePeriods: Int = 2

    static var defaultOrganizationId: UUID? {
        guard let idString = defaultOrganizationIdString else { return nil }
        return UUID(uuidString: idString)
    }
}

@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    @Published private(set) var state: LicenseState = .loading
    @Published private(set) var isValidating = false
    @Published private(set) var isActivating = false

    private let provider: PolarLicenseProvider
    private let cache: LicenseCache
    private let timeValidator: TimeValidator
    private let deviceFingerprint: DeviceFingerprint
    private let telemetry: LicenseTelemetry

    private var organizationId: UUID?
    private var deviceLimit: Int = LicenseConfig.defaultDeviceLimit

    private init() {
        self.provider = PolarLicenseProvider.shared
        self.cache = LicenseCache()
        self.timeValidator = TimeValidator()
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

    func configure(organizationId: UUID, deviceLimit: Int = 2) {
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

    func startTrial() async {
        let trialStart = Date()
        cache.setTrialStart(trialStart)

        UserDefaults.standard.set(0, forKey: "grace_count")
        UserDefaults.standard.set(trialStart, forKey: "last_validation_time")

        let daysRemaining = calculateTrialDaysRemaining()
        state = .trial(daysRemaining: daysRemaining)

        telemetry.track(event: .trialStarted)
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

    func validateLicense() async {
        guard let orgId = organizationId else {
            if cache.isTrialStarted() {
                state = checkTrialStatus()
            } else {
                state = .noLicense
            }
            return
        }

        isValidating = true
        defer { isValidating = false }

        let localTime = Date()
        let timeValidation = performTimeValidation(localTime: localTime)

        if case .timeManipulationDetected = timeValidation {
            state = .invalid(reason: .timeManipulationDetected)
            telemetry.track(event: .timeManipulationDetected)
            return
        }

        let licenseKey = cache.getLicenseKey()
        let activationId = cache.getActivationId()

        do {
            let response = try await provider.validate(
                key: licenseKey ?? "",
                organizationId: orgId,
                activationId: activationId
            )

            try cache.saveLicense(response)

            switch response.status {
            case "granted":
                let license = License(from: response)
                state = .licensed(license: license)
                telemetry.track(event: .licenseValidated)

                cache.setLastValidationTime(localTime)
                UserDefaults.standard.set(0, forKey: "grace_count")

            case "revoked":
                state = .invalid(reason: .revoked)
                telemetry.track(event: .licenseRevoked)

            case "disabled":
                state = .invalid(reason: .validationFailed)
                telemetry.track(event: .validationFailed, metadata: ["reason": "license_disabled"])

            default:
                state = .invalid(reason: .unknown(response.status))
            }

        } catch {
            handleOfflineValidation(timeValidation: timeValidation, localTime: localTime)
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
        print("  trialStarted: \(cache.isTrialStarted())")
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
        print("║ TrialStarted: \(cache.isTrialStarted())")
        print("║ TrialStart: \(String(describing: cache.getTrialStart()))")
        print("║ GraceCount: \(cache.getGraceCount())")
        print("║ LastValidation: \(String(describing: cache.getLastValidationTime()))")
        print("║ DeviceFingerprint: \(deviceFingerprint.generate())")
        print("║ CacheValid: \(cache.isCacheValid())")
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

    func checkTrialStatus() -> LicenseState {
        guard let trialStart = cache.getTrialStart() else {
            return .noLicense
        }

        let trialEnd = trialStart.addingTimeInterval(Double(30 * 24 * 60 * 60))
        let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: trialEnd).day ?? 0

        if daysRemaining > 0 {
            return .trial(daysRemaining: daysRemaining)
        } else {
            telemetry.track(event: .trialExpired)
            return .trialExpired
        }
    }

    func shouldShowProFeatures() -> Bool {
        switch state {
        case .trial, .licensed:
            return true
        default:
            return false
        }
    }

    func canAccessFeature(_ feature: LicenseEntitlements.LicenseFeature) -> Bool {
        return state.entitlements.canAccessFeature(feature)
    }

    func generateDebugReport() -> String {
        return telemetry.generateDebugReport()
    }

    private func loadCachedState() {
        if cache.isTrialStarted() {
            state = checkTrialStatus()
        } else if let cached = cache.load() {
            state = .licensed(license: cached.license)
        } else {
            state = .noLicense
        }
    }

    private func performTimeValidation(localTime: Date) -> TimeValidator.TimeValidationResult {
        let context = TimeValidator.TimeContext(
            serverTime: cache.load()?.license.lastValidatedAt,
            lastLocalTime: cache.getLastValidationTime(),
            graceCount: cache.getGraceCount()
        )

        return timeValidator.validateTime(
            serverTime: context.serverTime,
            localTime: localTime,
            context: context
        )
    }

    private func handleOfflineValidation(
        timeValidation: TimeValidator.TimeValidationResult,
        localTime: Date
    ) {
        switch timeValidation {
        case .valid:
            if let cached = cache.load() {
                state = .licensed(license: cached.license)
            } else {
                state = .invalid(reason: .networkError)
            }

        case .gracePeriodAllowed(let remaining):
            var count = cache.getGraceCount()
            count += 1
            UserDefaults.standard.set(count, forKey: "grace_count")
            UserDefaults.standard.set(localTime, forKey: "last_validation_time")

            telemetry.track(event: .gracePeriodUsed)

            if let cached = cache.load() {
                state = .licensed(license: cached.license)
            } else if cache.isTrialStarted() {
                state = checkTrialStatus()
            } else {
                state = .invalid(reason: .networkError)
            }

        case .gracePeriodExceeded:
            telemetry.track(event: .gracePeriodExceeded)
            state = .invalid(reason: .networkError)

        case .timeManipulationDetected:
            telemetry.track(event: .timeManipulationDetected)
            state = .invalid(reason: .timeManipulationDetected)
        }
    }

    private func calculateTrialDaysRemaining() -> Int {
        guard let trialStart = cache.getTrialStart() else { return 0 }

        let trialEnd = trialStart.addingTimeInterval(Double(30 * 24 * 60 * 60))
        return Calendar.current.dateComponents([.day], from: Date(), to: trialEnd).day ?? 0
    }
}
