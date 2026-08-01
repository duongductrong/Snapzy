//
//  OCRCatalogManifestValidator.swift
//  Snapzy
//
//  Semantic validation and normalization for untrusted OCR manifests.
//

import Foundation

enum OCRModelManifestError: LocalizedError, Equatable {
  case unsupportedFileType(String)
  case fileTooLarge
  case invalid(String)

  var errorDescription: String? {
    switch self {
    case .unsupportedFileType(let fileExtension):
      "Unsupported OCR manifest type .\(fileExtension). Use JSON, YAML, or YML."
    case .fileTooLarge:
      "The OCR manifest exceeds the 256 KB size limit."
    case .invalid(let reason):
      "Invalid OCR model manifest: \(reason)"
    }
  }
}

enum OCRCatalogManifestValidator {
  static let maximumManifestBytes = 256 * 1024
  private static let maximumArtifactBytes: Int64 = 8 * 1024 * 1024 * 1024

  static func validate(_ document: OCRModelManifestDocument) throws -> [OCRModelManifest] {
    guard document.schemaVersion == OCRModelManifestDocument.currentSchemaVersion else {
      throw OCRModelManifestError.invalid("unsupported schema_version \(document.schemaVersion)")
    }

    let models: [OCRModelManifest]
    switch document.format {
    case OCRModelManifestDocument.catalogFormat:
      guard let catalogModels = document.models, document.model == nil else {
        throw OCRModelManifestError.invalid("catalog documents require models and cannot contain model")
      }
      guard catalogModels.count <= 100 else {
        throw OCRModelManifestError.invalid("a catalog cannot contain more than 100 models")
      }
      models = catalogModels
    case OCRModelManifestDocument.modelFormat:
      guard let model = document.model, document.models == nil else {
        throw OCRModelManifestError.invalid("model documents require model and cannot contain models")
      }
      models = [model]
    default:
      throw OCRModelManifestError.invalid("unsupported format \(document.format)")
    }

    let duplicateIDs = Dictionary(grouping: models, by: \.id).filter { $0.value.count > 1 }.keys
    guard duplicateIDs.isEmpty else {
      throw OCRModelManifestError.invalid("duplicate model id \(duplicateIDs.sorted().joined(separator: ", "))")
    }
    for model in models {
      try validateModel(model)
    }
    return models
  }

  static func definition(from model: OCRModelManifest) throws -> OCRModelDefinition {
    try validateModel(model)
    let files = try OCRModelArtifactRole.allCases.map { role -> OCRModelFile in
      guard let artifact = model.artifacts.first(where: { $0.role == role }) else {
        throw OCRModelManifestError.invalid("\(model.id) is missing \(role.rawValue)")
      }
      return try OCRModelFile(
        name: role.fileName,
        url: resolvedURL(for: artifact.source),
        expectedBytes: artifact.expectedBytes,
        sha256: artifact.sha256
      )
    }
    return OCRModelDefinition(
      id: model.id,
      displayName: model.displayName,
      parameterCountLabel: model.parameterCountLabel,
      fp32SizeLabel: model.fp32SizeLabel,
      int8SizeLabel: model.int8SizeLabel,
      adapterID: model.adapter,
      files: files
    )
  }

  private static func validateModel(_ model: OCRModelManifest) throws {
    guard model.id.range(of: "^[a-z0-9][a-z0-9._-]{0,63}$", options: .regularExpression) != nil else {
      throw OCRModelManifestError
        .invalid("model id must use 1–64 lowercase letters, numbers, dots, dashes, or underscores")
    }
    for (name, value) in [
      ("display_name", model.displayName),
      ("parameter_count_label", model.parameterCountLabel),
      ("fp32_size_label", model.fp32SizeLabel),
      ("int8_size_label", model.int8SizeLabel),
    ] {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty,
            trimmed.count <= 100,
            trimmed.rangeOfCharacter(from: .controlCharacters) == nil else {
        throw OCRModelManifestError.invalid("\(model.id).\(name) must contain 1–100 characters")
      }
    }
    guard model.adapter == .ppocrDBCTCV1 else {
      throw OCRModelManifestError.invalid("unsupported adapter \(model.adapter.rawValue)")
    }
    guard model.artifacts.count == OCRModelArtifactRole.allCases.count,
          Set(model.artifacts.map(\.role)) == Set(OCRModelArtifactRole.allCases) else {
      throw OCRModelManifestError.invalid("\(model.id) requires one detector, recognizer, and dictionary artifact")
    }

    for artifact in model.artifacts {
      _ = try resolvedURL(for: artifact.source)
      if let bytes = artifact.expectedBytes {
        guard bytes > 0, bytes <= maximumArtifactBytes else {
          throw OCRModelManifestError.invalid("\(model.id).\(artifact.role.rawValue) has invalid expected_bytes")
        }
      }
      if artifact.role != .dictionary {
        guard artifact.expectedBytes != nil else {
          throw OCRModelManifestError.invalid("\(model.id).\(artifact.role.rawValue) requires expected_bytes")
        }
        guard isSHA256(artifact.sha256) else {
          throw OCRModelManifestError.invalid("\(model.id).\(artifact.role.rawValue) requires lowercase SHA-256")
        }
      } else if artifact.sha256 != nil, !isSHA256(artifact.sha256) {
        throw OCRModelManifestError.invalid("\(model.id).dictionary has invalid SHA-256")
      }
    }
  }

  private static func resolvedURL(for source: OCRModelArtifactSourceManifest) throws -> URL {
    switch source.type {
    case .url:
      guard source.repository == nil, source.revision == nil, source.file == nil,
            let rawURL = source.url,
            let components = URLComponents(string: rawURL),
            components.scheme?.lowercased() == "https",
            components.host?.isEmpty == false,
            components.user == nil,
            components.password == nil,
            let url = components.url else {
        throw OCRModelManifestError.invalid("URL sources require one HTTPS url and no credentials")
      }
      return url
    case .huggingFace:
      guard source.url == nil,
            let repository = source.repository,
            repository.range(of: "^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$", options: .regularExpression) != nil,
            repository.split(separator: "/").allSatisfy({ $0 != "." && $0 != ".." }),
            let revision = source.revision,
            revision.range(of: "^[A-Za-z0-9._-]{1,128}$", options: .regularExpression) != nil,
            revision != ".",
            revision != "..",
            let file = source.file,
            isSafeHuggingFacePath(file),
            let url = URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(file)") else {
        throw OCRModelManifestError
          .invalid("Hugging Face sources require repository, revision, and a safe relative file path")
      }
      return url
    }
  }

  private static func isSafeHuggingFacePath(_ path: String) -> Bool {
    guard !path.isEmpty, path.count <= 512, !path.hasPrefix("/") else { return false }
    return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
      !$0.isEmpty && $0 != "." && $0 != ".."
        && $0.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
    }
  }

  private static func isSHA256(_ value: String?) -> Bool {
    value?.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
  }
}
