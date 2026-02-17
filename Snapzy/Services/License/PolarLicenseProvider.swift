import Foundation

final class PolarLicenseProvider {
    private var _baseURL: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    // Sandbox mode toggle — automatically set based on build configuration.
    // IMPORTANT: Sandbox and Production use DIFFERENT organizations!
    #if DEBUG
    static var isSandbox: Bool = true {
        didSet {
            shared.updateBaseURL()
        }
    }
    #else
    static var isSandbox: Bool = false {
        didSet {
            shared.updateBaseURL()
        }
    }
    #endif

    private static var sandboxBaseURL: String = SecretsConfig.polarSandboxApiBaseURL
    private static var productionBaseURL: String = SecretsConfig.polarApiBaseURL

    // Use lazy initialization to ensure isSandbox is set first
    static let shared: PolarLicenseProvider = {
        let provider = PolarLicenseProvider()
        provider.updateBaseURL()
        return provider
    }()

    var currentBaseURL: String {
        return _baseURL
    }

    private init() {
        self._baseURL = PolarLicenseProvider.isSandbox
            ? PolarLicenseProvider.sandboxBaseURL
            : PolarLicenseProvider.productionBaseURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            // Try with fractional seconds first (API returns microseconds)
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) { return date }
            // Fall back to standard ISO8601
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(dateString)"
            )
        }

        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder.dateEncodingStrategy = .iso8601
    }

    fileprivate func updateBaseURL() {
        _baseURL = PolarLicenseProvider.isSandbox
            ? PolarLicenseProvider.sandboxBaseURL
            : PolarLicenseProvider.productionBaseURL
    }

    func activate(
        key: String,
        organizationId: UUID,
        label: String,
        metadata: [String: String]? = nil
    ) async throws -> ActivateResponse {
        let url = URL(string: "\(_baseURL)/license-keys/activate")!

        var body: [String: Any] = [
            "key": key,
            "organization_id": organizationId.uuidString.lowercased(),
            "label": label
        ]

        if let metadata = metadata {
            body["meta"] = metadata
        }

        #if DEBUG
        print("=== POLAR API REQUEST ===")
        print("URL: \(url.absoluteString)")
        print("Body: \(body)")
        print("=========================")
        #endif

        let request = try createRequest(url: url, body: body)

        let (data, response) = try await session.data(for: request)

        #if DEBUG
        if let httpResponse = response as? HTTPURLResponse {
            print("Response status: \(httpResponse.statusCode)")
        }
        if let responseString = String(data: data, encoding: .utf8) {
            print("Response body: \(responseString)")
        }
        #endif

        try validateResponse(response)

        do {
            return try decoder.decode(ActivateResponse.self, from: data)
        } catch {
            throw LicenseError.decodingError(error)
        }
    }

    func validate(
        key: String,
        organizationId: UUID,
        activationId: UUID? = nil,
        conditions: [String: Any]? = nil,
        incrementUsage: Int? = nil
    ) async throws -> ValidateResponse {
        let url = URL(string: "\(_baseURL)/license-keys/validate")!

        var body: [String: Any] = [
            "key": key,
            "organization_id": organizationId.uuidString.lowercased()
        ]

        if let activationId = activationId {
            body["activation_id"] = activationId.uuidString.lowercased()
        }

        if let conditions = conditions {
            body["conditions"] = conditions
        }

        if let incrementUsage = incrementUsage {
            body["increment_usage"] = incrementUsage
        }

        let request = try createRequest(url: url, body: body)

        let (data, response) = try await session.data(for: request)

        try validateResponse(response)

        do {
            return try decoder.decode(ValidateResponse.self, from: data)
        } catch {
            throw LicenseError.decodingError(error)
        }
    }

    func deactivate(
        key: String,
        activationId: UUID,
        organizationId: UUID
    ) async throws {
        let url = URL(string: "\(_baseURL)/license-keys/deactivate")!

        let body: [String: Any] = [
            "key": key,
            "activation_id": activationId.uuidString.lowercased(),
            "organization_id": organizationId.uuidString.lowercased()
        ]

        #if DEBUG
        print("=== POLAR DEACTIVATE REQUEST ===")
        print("URL: \(url.absoluteString)")
        print("Body dict: \(body)")
        // Log the actual JSON that will be sent
        if let jsonData = try? JSONSerialization.data(withJSONObject: body, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("Body JSON:\n\(jsonString)")
        }
        print("================================")
        #endif

        let request = try createRequest(url: url, body: body)

        let (data, response) = try await session.data(for: request)

        #if DEBUG
        if let httpResponse = response as? HTTPURLResponse {
            print("Deactivate response status: \(httpResponse.statusCode)")
            print("Deactivate response headers: \(httpResponse.allHeaderFields)")
        }
        if let responseString = String(data: data, encoding: .utf8) {
            print("Deactivate response body: \(responseString)")
        }
        #endif

        // Polar API returns 204 No Content on success — no body to decode
        try validateResponse(response)
    }

    func getLicense(
        licenseId: UUID,
        customerSession: String
    ) async throws -> ValidateResponse {
        let url = URL(string: "\(_baseURL)/license-keys/\(licenseId.uuidString)")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(customerSession)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)

        try validateResponse(response)

        do {
            return try decoder.decode(ValidateResponse.self, from: data)
        } catch {
            throw LicenseError.decodingError(error)
        }
    }

    private func createRequest(url: URL, body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            throw LicenseError.decodingError(error)
        }

        return request
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 400:
            throw LicenseError.invalidLicenseKey
        case 422:
            throw LicenseError.noActivationsRemaining
        case 401, 403:
            throw LicenseError.validationFailed("Unauthorized")
        case 404:
            throw LicenseError.validationFailed("License not found")
        case 429:
            throw LicenseError.validationFailed("Rate limit exceeded")
        case 500...599:
            throw LicenseError.networkError(NSError(domain: "PolarAPI", code: httpResponse.statusCode))
        default:
            throw LicenseError.unknown("Unexpected status code: \(httpResponse.statusCode)")
        }
    }
}
