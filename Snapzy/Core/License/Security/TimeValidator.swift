import Foundation

final class TimeValidator {
    private let maxAllowedDrift: TimeInterval
    private let gracePeriod: TimeInterval
    private let maxGracePeriods: Int

    struct TimeContext {
        var serverTime: Date?
        var lastLocalTime: Date?
        var graceCount: Int
    }

    init(
        maxAllowedDrift: TimeInterval = 300,
        gracePeriod: TimeInterval = 86400,
        maxGracePeriods: Int = 2
    ) {
        self.maxAllowedDrift = maxAllowedDrift
        self.gracePeriod = gracePeriod
        self.maxGracePeriods = maxGracePeriods
    }

    func validateTime(
        serverTime: Date?,
        localTime: Date,
        context: TimeContext
    ) -> TimeValidationResult {

        if let serverTime = serverTime {
            let drift = abs(serverTime.timeIntervalSince(localTime))
            if drift > maxAllowedDrift {
                return .timeManipulationDetected
            }
        }

        if let lastLocalTime = context.lastLocalTime {
            let elapsed = localTime.timeIntervalSince(lastLocalTime)

            if elapsed > gracePeriod {
                if context.graceCount < maxGracePeriods {
                    return .gracePeriodAllowed(remaining: maxGracePeriods - context.graceCount)
                } else {
                    return .gracePeriodExceeded
                }
            }
        }

        return .valid
    }

    func validateTimeWithServer(
        serverTime: Date?,
        localTime: Date
    ) -> TimeValidationResult {
        guard let serverTime = serverTime else {
            return .valid
        }

        let drift = abs(serverTime.timeIntervalSince(localTime))
        if drift > maxAllowedDrift {
            return .timeManipulationDetected
        }

        return .valid
    }

    func getServerTimeFromResponse(_ response: [String: Any]) -> Date? {
        if let lastValidatedAtString = response["last_validated_at"] as? String {
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: lastValidatedAtString)
        }
        if let expiresAtString = response["expires_at"] as? String {
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: expiresAtString)
        }
        return nil
    }

    func shouldRecheckTime(graceCount: Int) -> Bool {
        return graceCount < maxGracePeriods
    }

    enum TimeValidationResult {
        case valid
        case gracePeriodAllowed(remaining: Int)
        case gracePeriodExceeded
        case timeManipulationDetected

        var isValid: Bool {
            switch self {
            case .valid:
                return true
            case .gracePeriodAllowed:
                return true
            default:
                return false
            }
        }

        var requiresRevalidation: Bool {
            switch self {
            case .gracePeriodAllowed:
                return true
            case .gracePeriodExceeded:
                return true
            default:
                return false
            }
        }
    }
}

final class NTPTimeProvider {
    static let shared = NTPTimeProvider()

    private init() {}

    func fetchTime(completion: @escaping (Result<Date, Error>) -> Void) {
        fetchTimeFromApple { result in
            switch result {
            case .success(let date):
                completion(.success(date))
            case .failure:
                completion(.failure(NTPError.allServersFailed))
            }
        }
    }

    private func fetchTimeFromApple(completion: @escaping (Result<Date, Error>) -> Void) {
        let task = Process()
        task.launchPath = "/usr/bin/sntp"
        task.arguments = ["-sS", "time.apple.com"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                if output.contains("NTP ok") {
                    completion(.success(Date()))
                    return
                }
            }
            completion(.failure(NTPError.invalidResponse))
        } catch {
            completion(.failure(NTPError.hostResolutionFailed))
        }
    }
}

enum NTPError: Error {
    case hostResolutionFailed
    case noAddresses
    case socketCreationFailed
    case sendFailed
    case receiveFailed
    case invalidResponse
    case allServersFailed

    var errorDescription: String? {
        switch self {
        case .hostResolutionFailed:
            return "Failed to resolve NTP server hostname"
        case .noAddresses:
            return "No addresses found for NTP server"
        case .socketCreationFailed:
            return "Failed to create socket"
        case .sendFailed:
            return "Failed to send NTP request"
        case .receiveFailed:
            return "Failed to receive NTP response"
        case .invalidResponse:
            return "Invalid NTP response"
        case .allServersFailed:
            return "All NTP servers failed"
        }
    }
}
