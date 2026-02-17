import Foundation

struct License: Codable, Equatable {
    let id: UUID
    let customerId: UUID
    let organizationId: UUID
    let benefitId: UUID
    let key: String
    let displayKey: String
    let status: LicenseStatus
    let limitActivations: Int?
    let usage: Int
    let limitUsage: Int?
    let validations: Int
    let lastValidatedAt: Date?
    let expiresAt: Date?
    let createdAt: Date
    let activation: Activation?

    var isValid: Bool {
        status == .granted && !isExpired
    }

    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }

    var remainingActivations: Int? {
        guard let limit = limitActivations else { return nil }
        // Approximate — actual enforcement is at the API level via /activate.
        return max(0, limit - usage)
    }

    struct Activation: Codable, Equatable {
        let id: UUID
        let licenseKeyId: UUID
        let label: String
        let meta: [String: String]
        let createdAt: Date

        init(id: UUID, licenseKeyId: UUID, label: String, meta: [String: String], createdAt: Date) {
            self.id = id
            self.licenseKeyId = licenseKeyId
            self.label = label
            self.meta = meta
            self.createdAt = createdAt
        }

        init(from response: ValidateResponse.ActivationResponse) {
            self.id = UUID(uuidString: response.id) ?? UUID()
            self.licenseKeyId = UUID(uuidString: response.licenseKeyId) ?? UUID()
            self.label = response.label
            self.meta = response.meta ?? [:]
            self.createdAt = response.createdAt
        }

        init(from response: ActivateResponse) {
            self.id = UUID(uuidString: response.id) ?? UUID()
            self.licenseKeyId = UUID(uuidString: response.licenseKeyId) ?? UUID()
            self.label = response.label
            self.meta = response.meta ?? [:]
            self.createdAt = response.createdAt
        }
    }
}

enum LicenseStatus: String, Codable {
    case granted
    case revoked
    case disabled

    init(from string: String) {
        self = LicenseStatus(rawValue: string) ?? .disabled
    }
}

extension License {
    init(from response: ValidateResponse) {
        self.id = UUID()
        self.customerId = UUID()
        self.organizationId = UUID()
        self.benefitId = UUID()
        self.key = response.key
        self.displayKey = response.displayKey
        self.status = LicenseStatus(from: response.status)
        self.limitActivations = response.limitActivations
        self.usage = response.usage
        self.limitUsage = response.limitUsage
        self.validations = response.validations
        self.lastValidatedAt = response.lastValidatedAt
        self.expiresAt = response.expiresAt
        self.createdAt = Date()

        if let activationResponse = response.activation {
            self.activation = Activation(
                id: UUID(uuidString: activationResponse.id) ?? UUID(),
                licenseKeyId: UUID(uuidString: activationResponse.licenseKeyId) ?? UUID(),
                label: activationResponse.label,
                meta: activationResponse.meta ?? [:],
                createdAt: activationResponse.createdAt
            )
        } else {
            self.activation = nil
        }
    }

    init(from response: ActivateResponse) {
        self.id = UUID(uuidString: response.id) ?? UUID()
        self.customerId = UUID(uuidString: response.licenseKey.customerId) ?? UUID()
        self.organizationId = UUID(uuidString: response.licenseKey.organizationId) ?? UUID()
        self.benefitId = UUID(uuidString: response.licenseKey.benefitId) ?? UUID()
        self.key = response.licenseKey.key
        self.displayKey = response.licenseKey.displayKey
        self.status = LicenseStatus(from: response.licenseKey.status)
        self.limitActivations = response.licenseKey.limitActivations
        self.usage = response.licenseKey.usage
        self.limitUsage = response.licenseKey.limitUsage
        self.validations = response.licenseKey.validations
        self.lastValidatedAt = response.licenseKey.lastValidatedAt
        self.expiresAt = response.licenseKey.expiresAt
        self.createdAt = response.licenseKey.createdAt

        self.activation = Activation(from: response)
    }
}

struct ValidateResponse: Codable {
    let id: String
    let customerId: String
    let customer: Customer?
    let organizationId: String
    let benefitId: String
    let key: String
    let displayKey: String
    let status: String
    let limitActivations: Int?
    let usage: Int
    let limitUsage: Int?
    let validations: Int
    let lastValidatedAt: Date?
    let expiresAt: Date?
    let activation: ActivationResponse?

    struct Customer: Codable {
        let id: String
        let email: String?
        let name: String?
    }

    struct ActivationResponse: Codable {
        let id: String
        let licenseKeyId: String
        let label: String
        let meta: [String: String]?
        let createdAt: Date
    }
}

struct ActivateResponse: Codable {
    let id: String
    let licenseKeyId: String
    let label: String
    let meta: [String: String]?
    let createdAt: Date
    let modifiedAt: Date?
    let licenseKey: LicenseKeyInfo

    struct LicenseKeyInfo: Codable {
        let id: String
        let customerId: String
        let customer: Customer?
        let organizationId: String
        let benefitId: String
        let key: String
        let displayKey: String
        let status: String
        let limitActivations: Int?
        let usage: Int
        let limitUsage: Int?
        let validations: Int
        let lastValidatedAt: Date?
        let expiresAt: Date?
        let createdAt: Date
        let modifiedAt: Date?

        struct Customer: Codable {
            let id: String
            let email: String?
            let name: String?
            let avatarUrl: String?
        }
    }
}
