//
//  OCRCatalogFixtures.swift
//  SnapzyTests
//
//  Catalog fixtures for tests: the bundled catalog ships empty, so tests that
//  need downloadable models inject their own definitions.
//

import Foundation
@testable import Snapzy

enum OCRCatalogFixtures {
  static let primaryModelID = "fixture-primary"
  static let secondaryModelID = "fixture-secondary"

  static func manifest(
    id: String,
    displayName: String = "Fixture Model"
  ) -> OCRModelManifest {
    let hash = String(repeating: "a", count: 64)
    return OCRModelManifest(
      id: id,
      displayName: displayName,
      parameterCountLabel: "1M",
      fp32SizeLabel: "10 MB",
      int8SizeLabel: "3 MB",
      adapter: .ppocrDBCTCV1,
      artifacts: [
        artifact(.detector, "https://example.com/det.onnx", 100, hash),
        artifact(.recognizer, "https://example.com/rec.onnx", 200, hash),
        artifact(.dictionary, "https://example.com/dict.txt", nil, nil),
      ]
    )
  }

  /// Stands in for a build that ships catalog entries in its bundled YAML.
  static func bundledLoadResult(
    ids: [String] = [primaryModelID, secondaryModelID]
  ) -> OCRModelCatalogLoadResult {
    let manifests = ids.map { manifest(id: $0) }
    return OCRModelCatalogLoadResult(
      manifests: manifests,
      definitions: manifests.compactMap { try? OCRCatalogManifestValidator.definition(from: $0) },
      errorDescription: nil
    )
  }

  @MainActor
  static func catalog(
    ids: [String] = [primaryModelID, secondaryModelID],
    userStore: OCRUserCatalogStore
  ) -> OCRModelCatalog {
    OCRModelCatalog(bundledLoadResult: bundledLoadResult(ids: ids), userStore: userStore)
  }

  @MainActor
  static func catalog(
    ids: [String] = [primaryModelID, secondaryModelID],
    defaults: UserDefaults
  ) -> OCRModelCatalog {
    catalog(ids: ids, userStore: OCRUserCatalogStore(defaults: defaults, reservedModelIDs: Set(ids)))
  }

  static func yaml(ids: [String] = [primaryModelID]) -> String {
    let hash = String(repeating: "a", count: 64)
    let models = ids.map { id in
      """
        - id: \(id)
          display_name: Fixture Model
          parameter_count_label: 1M
          fp32_size_label: 10 MB
          int8_size_label: 3 MB
          adapter: ppocr-db-ctc-v1
          artifacts:
            - role: detector
              source:
                type: url
                url: "https://example.com/det.onnx"
              expected_bytes: 100
              sha256: "\(hash)"
            - role: recognizer
              source:
                type: url
                url: "https://example.com/rec.onnx"
              expected_bytes: 200
              sha256: "\(hash)"
            - role: dictionary
              source:
                type: url
                url: "https://example.com/dict.txt"
      """
    }.joined(separator: "\n")
    return """
    format: snapzy-ocr-catalog
    schema_version: 1
    models:
    \(models)
    """
  }

  private static func artifact(
    _ role: OCRModelArtifactRole,
    _ url: String,
    _ bytes: Int64?,
    _ hash: String?
  ) -> OCRModelArtifactManifest {
    OCRModelArtifactManifest(
      role: role,
      source: OCRModelArtifactSourceManifest(
        type: .url,
        url: url,
        repository: nil,
        revision: nil,
        file: nil
      ),
      expectedBytes: bytes,
      sha256: hash
    )
  }
}
