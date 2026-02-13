import Foundation

enum LicenseTier: String, CaseIterable {
    case free = "Free"
    case pro = "Pro"

    var displayName: String {
        switch self {
        case .free:
            return "Free"
        case .pro:
            return "Pro"
        }
    }

    var features: [String] {
        switch self {
        case .free:
            return [
                "Basic screenshot capture",
                "Area selection",
                "5 recordings per month",
                "Standard export quality"
            ]
        case .pro:
            return [
                "Unlimited screen recording",
                "Full annotation tools",
                "Video editing",
                "4K export quality",
                "Priority support",
                "Cloud sync",
                "OCR text recognition"
            ]
        }
    }
}

struct LicenseEntitlements {
    let canRecord: Bool
    let canAnnotate: Bool
    let canEditVideo: Bool
    let canUseOCR: Bool
    let recordingLimit: Int?
    let exportQuality: ExportQuality

    enum ExportQuality: String {
        case standard = "Standard"
        case high = "High"
        case maximum = "Maximum"
    }

    static let free = LicenseEntitlements(
        canRecord: true,
        canAnnotate: true,
        canEditVideo: false,
        canUseOCR: false,
        recordingLimit: 5,
        exportQuality: .standard
    )

    static let pro = LicenseEntitlements(
        canRecord: true,
        canAnnotate: true,
        canEditVideo: true,
        canUseOCR: true,
        recordingLimit: nil,
        exportQuality: .maximum
    )
}

extension LicenseEntitlements {
    func canAccessFeature(_ feature: LicenseFeature) -> Bool {
        switch feature {
        case .screenCapture:
            return true
        case .screenRecording:
            return canRecord
        case .annotation:
            return canAnnotate
        case .videoEditing:
            return canEditVideo
        case .ocr:
            return canUseOCR
        case .highQualityExport:
            return exportQuality != .standard
        case .unlimitedRecording:
            return recordingLimit == nil
        }
    }

    enum LicenseFeature {
        case screenCapture
        case screenRecording
        case annotation
        case videoEditing
        case ocr
        case highQualityExport
        case unlimitedRecording
    }
}
