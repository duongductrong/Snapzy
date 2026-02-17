import Foundation

enum LicenseEvent: String {
    case appLaunched = "app_launched"

    case licenseActivated = "license_activated"
    case licenseValidated = "license_validated"
    case licenseRevoked = "license_revoked"
    case licenseExpired = "license_expired"
    case validationFailed = "validation_failed"
    case deviceLimitExceeded = "device_limit_exceeded"
    case activationAttempted = "activation_attempted"
    case deactivationAttempted = "deactivation_attempted"
}

final class LicenseTelemetry {
    static let shared = LicenseTelemetry()

    private let defaults = UserDefaults.standard
    private let eventsKey = "com.snapzy.telemetry.events"

    private init() {}

    func track(event: LicenseEvent, metadata: [String: String] = [:]) {
        var events = loadEvents()

        let eventEntry = TelemetryEntry(
            id: UUID(),
            timestamp: Date(),
            event: event.rawValue,
            metadata: metadata,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        )

        events.append(eventEntry)

        if events.count > 100 {
            events = Array(events.suffix(50))
        }

        saveEvents(events)
    }

    func getRecentEvents(limit: Int = 10) -> [TelemetryEntry] {
        let events = loadEvents()
        return Array(events.suffix(limit))
    }

    func getEventCount(for event: String) -> Int {
        return loadEvents().filter { $0.event == event }.count
    }

    func clearEvents() {
        defaults.removeObject(forKey: eventsKey)
    }

    private func loadEvents() -> [TelemetryEntry] {
        guard let data = defaults.data(forKey: eventsKey),
              let events = try? JSONDecoder().decode([TelemetryEntry].self, from: data) else {
            return []
        }
        return events
    }

    private func saveEvents(_ events: [TelemetryEntry]) {
        if let data = try? JSONEncoder().encode(events) {
            defaults.set(data, forKey: eventsKey)
        }
    }
}

struct TelemetryEntry: Codable {
    let id: UUID
    let timestamp: Date
    let event: String
    let metadata: [String: String]
    let appVersion: String
    let buildNumber: String
}

extension LicenseTelemetry {
    func generateDebugReport() -> String {
        var report = """
        === License Telemetry Report ===
        Generated: \(Date())
        App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")
        Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown")

        Events Summary:
        """

        let eventCounts: [(String, String)] = [
            (LicenseEvent.appLaunched.rawValue, "App Launches"),

            (LicenseEvent.licenseActivated.rawValue, "License Activations"),
            (LicenseEvent.licenseValidated.rawValue, "Validations"),
            (LicenseEvent.licenseRevoked.rawValue, "Revocations"),
            (LicenseEvent.validationFailed.rawValue, "Validation Failures")
        ]

        for (eventId, name) in eventCounts {
            let count = getEventCount(for: eventId)
            report += "\n  \(name): \(count)"
        }

        report += "\n\nRecent Events:"

        for entry in getRecentEvents(limit: 20) {
            report += "\n  [\(entry.timestamp)] \(entry.event)"
        }

        return report
    }
}
