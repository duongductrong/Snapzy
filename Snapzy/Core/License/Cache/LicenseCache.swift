import Foundation

final class LicenseCache {
    private let keychain = KeychainService()
    private let defaults = UserDefaults.standard

    private let licenseCacheKey = "com.snapzy.license.cache"
    private let trialStartKey = "com.snapzy.trial.start"
    private let trialStartedKey = "com.snapzy.trial.started"
    private let graceCountKey = "com.snapzy.grace.count"
    private let lastValidationTimeKey = "com.snapzy.validation.time"
    private let licenseKeyKey = "com.snapzy.license.key"

    struct CacheEntry: Codable {
        let license: License
        let deviceFingerprint: String
        let cachedAt: Date
        let graceCount: Int
    }

    func saveLicense(_ response: ActivateResponse) throws {
        let license = License(from: response)
        let fingerprint = DeviceFingerprint.shared.generate()

        let entry = CacheEntry(
            license: license,
            deviceFingerprint: fingerprint,
            cachedAt: Date(),
            graceCount: 0
        )

        try saveCacheEntry(entry)

        try keychain.save(data: response.id.data(using: .utf8)!, forKey: "activation_id")

        try keychain.save(data: response.licenseKey.key.data(using: .utf8)!, forKey: licenseKeyKey)
    }

    func saveLicense(_ response: ValidateResponse) throws {
        let license = License(from: response)
        let fingerprint = DeviceFingerprint.shared.generate()
        let currentGraceCount = getGraceCount()

        let entry = CacheEntry(
            license: license,
            deviceFingerprint: fingerprint,
            cachedAt: Date(),
            graceCount: currentGraceCount
        )

        try saveCacheEntry(entry)

        if let activationId = response.activation?.id {
            try keychain.save(data: activationId.data(using: .utf8)!, forKey: "activation_id")
        }
    }

    private func saveCacheEntry(_ entry: CacheEntry) throws {
        let data = try JSONEncoder().encode(entry)
        defaults.set(data, forKey: licenseCacheKey)
    }

    func load() -> CacheEntry? {
        guard let data = defaults.data(forKey: licenseCacheKey) else {
            return nil
        }

        guard let entry = try? JSONDecoder().decode(CacheEntry.self, from: data) else {
            return nil
        }

        let currentFingerprint = DeviceFingerprint.shared.generate()
        if entry.deviceFingerprint != currentFingerprint {
            return nil
        }

        return entry
    }

    func getActivationId() -> UUID? {
        guard let data = try? keychain.load(forKey: "activation_id"),
              let idString = String(data: data, encoding: .utf8) else {
            return nil
        }

        return UUID(uuidString: idString)
    }

    func getLicenseKey() -> String? {
        guard let data = try? keychain.load(forKey: licenseKeyKey) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func setLicenseKey(_ key: String) throws {
        try keychain.save(data: key.data(using: .utf8)!, forKey: licenseKeyKey)
    }

    func setTrialStart(_ date: Date) {
        defaults.set(date, forKey: trialStartKey)
        defaults.set(true, forKey: trialStartedKey)
    }

    func getTrialStart() -> Date? {
        return defaults.object(forKey: trialStartKey) as? Date
    }

    func isTrialStarted() -> Bool {
        return defaults.bool(forKey: trialStartedKey)
    }

    func incrementGraceCount() {
        let count = getGraceCount() + 1
        defaults.set(count, forKey: graceCountKey)
    }

    func getGraceCount() -> Int {
        return defaults.integer(forKey: graceCountKey)
    }

    func setLastValidationTime(_ date: Date) {
        defaults.set(date, forKey: lastValidationTimeKey)
    }

    func getLastValidationTime() -> Date? {
        return defaults.object(forKey: lastValidationTimeKey) as? Date
    }

    func clear() throws {
        defaults.removeObject(forKey: licenseCacheKey)
        defaults.removeObject(forKey: trialStartKey)
        defaults.removeObject(forKey: trialStartedKey)
        defaults.removeObject(forKey: graceCountKey)
        defaults.removeObject(forKey: lastValidationTimeKey)

        try? keychain.delete(forKey: "activation_id")
        try? keychain.delete(forKey: licenseKeyKey)
    }

    func isCacheValid() -> Bool {
        guard let entry = load() else { return false }

        let maxCacheAge: TimeInterval = 82800
        return Date().timeIntervalSince(entry.cachedAt) < maxCacheAge
    }
}
