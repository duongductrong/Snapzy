import Foundation
import Security
import CommonCrypto

final class DeviceFingerprint {
    private let lock = NSLock()
    private var cachedFingerprint: String?

    static let shared = DeviceFingerprint()

    private init() {}

    func generate() -> String {
        lock.lock()
        defer { lock.unlock() }

        if let existing = cachedFingerprint {
            return existing
        }

        let components = [
            getHardwareUUID() ?? "unknown",
            getDeviceModel() ?? "unknown",
            getSerialNumber() ?? "unknown"
        ]

        let fingerprint = components
            .joined(separator: "|")
            .data(using: .utf8)!
            .sha256Hash()

        cachedFingerprint = fingerprint
        return fingerprint
    }

    func generateDeviceName() -> String {
        let model = getDeviceModel() ?? "Mac"
        let userName = NSUserName() ?? "User"
        return "\(model) - \(userName)"
    }

    private func getHardwareUUID() -> String? {
        let task = Process()
        task.launchPath = "/usr/sbin/ioreg"
        task.arguments = ["-rd1", "-c", "IOPlatformExpertDevice"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                if let range = output.range(of: "\"IOPlatformUUID\" = \"") {
                    let start = range.upperBound
                    if let endRange = output[start...].firstIndex(of: "\"") {
                        let uuid = String(output[start..<endRange])
                        return uuid
                    }
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    private func getDeviceModel() -> String? {
        let task = Process()
        task.launchPath = "/usr/sbin/sysctl"
        task.arguments = ["-n", "hw.model"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func getSerialNumber() -> String? {
        let task = Process()
        task.launchPath = "/usr/sbin/ioreg"
        task.arguments = ["-rd1", "-c", "IOPlatformExpertDevice"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                if let range = output.range(of: "\"IOPlatformSerialNumber\" = \"") {
                    let start = range.upperBound
                    if let endRange = output[start...].firstIndex(of: "\"") {
                        let serial = String(output[start..<endRange])
                        return serial
                    }
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cachedFingerprint = nil
    }
}

extension Data {
    func sha256Hash() -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))

        self.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(self.count), &hash)
        }

        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
