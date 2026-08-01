//
//  OCRCatalogManifest.swift
//  Snapzy
//
//  Versioned data format shared by bundled and user-defined OCR catalogs.
//

import Foundation

enum OCRModelManifestFormat: String, CaseIterable {
  case json
  case yaml

  init?(fileExtension: String) {
    switch fileExtension.lowercased() {
    case "json": self = .json
    case "yaml", "yml": self = .yaml
    default: return nil
    }
  }
}

struct OCRModelManifestDocument: Codable, Equatable {
  static let catalogFormat = "snapzy-ocr-catalog"
  static let modelFormat = "snapzy-ocr-model"
  static let currentSchemaVersion = 1

  let format: String
  let schemaVersion: Int
  let models: [OCRModelManifest]?
  let model: OCRModelManifest?

  static func catalog(_ models: [OCRModelManifest]) -> Self {
    Self(
      format: catalogFormat,
      schemaVersion: currentSchemaVersion,
      models: models,
      model: nil
    )
  }

  static func singleModel(_ model: OCRModelManifest) -> Self {
    Self(
      format: modelFormat,
      schemaVersion: currentSchemaVersion,
      models: nil,
      model: model
    )
  }

  enum CodingKeys: String, CodingKey {
    case format
    case schemaVersion = "schema_version"
    case models
    case model
  }
}

struct OCRModelManifest: Codable, Equatable, Identifiable {
  let id: String
  let displayName: String
  let parameterCountLabel: String
  let fp32SizeLabel: String
  let int8SizeLabel: String
  let adapter: OCRModelAdapterID
  let artifacts: [OCRModelArtifactManifest]

  enum CodingKeys: String, CodingKey {
    case id
    case displayName = "display_name"
    case parameterCountLabel = "parameter_count_label"
    case fp32SizeLabel = "fp32_size_label"
    case int8SizeLabel = "int8_size_label"
    case adapter
    case artifacts
  }
}

enum OCRModelAdapterID: String, Codable, Equatable {
  /// Current Snapzy PP-OCR contract: DB detector, NCHW/BGR tensors,
  /// height-48 recognizer, and greedy CTC decoding.
  case ppocrDBCTCV1 = "ppocr-db-ctc-v1"
}

struct OCRModelArtifactManifest: Codable, Equatable {
  let role: OCRModelArtifactRole
  let source: OCRModelArtifactSourceManifest
  let expectedBytes: Int64?
  let sha256: String?

  enum CodingKeys: String, CodingKey {
    case role
    case source
    case expectedBytes = "expected_bytes"
    case sha256
  }
}

enum OCRModelArtifactRole: String, Codable, CaseIterable, Hashable {
  case detector
  case recognizer
  case dictionary

  var fileName: String {
    switch self {
    case .detector: "det.onnx"
    case .recognizer: "rec.onnx"
    case .dictionary: "dict.txt"
    }
  }
}

struct OCRModelArtifactSourceManifest: Codable, Equatable {
  let type: OCRModelArtifactSourceType
  let url: String?
  let repository: String?
  let revision: String?
  let file: String?
}

enum OCRModelArtifactSourceType: String, Codable, CaseIterable {
  case url
  case huggingFace = "hugging_face"
}
