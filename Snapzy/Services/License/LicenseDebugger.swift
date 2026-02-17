//
//  LicenseDebugger.swift
//  Snapzy
//
//  Debug utilities for Polar.sh license integration
//

import Foundation

final class LicenseDebugger {
    static let shared = LicenseDebugger()

    private init() {}

    // MARK: - Debug Information

    func getDebugInfo() -> String {
        var info = """
        === License Debug Info ===
        Generated: \(Date())

        Configuration:
        """
        info += "\n  Polar API URL: \(PolarLicenseProvider.isSandbox ? "Sandbox" : "Production")"
        info += "\n  Organization ID: \(LicenseManager.shared.getOrganizationId()?.uuidString ?? "NOT SET")"
        info += "\n  Device Limit: \(LicenseManager.shared.getDeviceLimit())"

        info += "\n\nCached Data:"
        let cache = LicenseCache()
        if let activationId = cache.getActivationId() {
            info += "\n  Activation ID: \(activationId.uuidString)"
        } else {
            info += "\n  Activation ID: None"
        }

        if let licenseKey = cache.getLicenseKey() {
            info += "\n  License Key: \(licenseKey)"
        } else {
            info += "\n  License Key: None"
        }

        info += "\n\nLicense State:"
        info += "\n  State: \(LicenseManager.shared.state.description)"
        info += "\n  Is Valid: \(LicenseManager.shared.isLicensed)"

        return info
    }

    // MARK: - Test License Key Format

    func testLicenseKeyFormat(_ key: String) -> Bool {
        // Polar.sh license key format: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
        // or with prefix: PREFIX-XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
        let pattern = #"^[A-Z0-9]{4,8}-[A-Z0-9]{8}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{12}$"#
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(location: 0, length: key.count)
        return regex?.firstMatch(in: key, options: [], range: range) != nil
    }

    // MARK: - Manual Sandbox Check

    func testSandboxConnection(completion: @escaping (Bool, String) -> Void) {
        let urlString = "https://sandbox-api.polar.sh/v1/customer-portal"
        guard let url = URL(string: urlString) else {
            completion(false, "Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, "Connection error: \(error.localizedDescription)")
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    completion(true, "Status code: \(httpResponse.statusCode)")
                } else {
                    completion(false, "No response")
                }
            }
        }.resume()
    }

    // MARK: - Print Debug Info

    func printDebugInfo() {
        print(getDebugInfo())
    }
}
