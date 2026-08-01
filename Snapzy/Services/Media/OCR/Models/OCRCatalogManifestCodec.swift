//
//  OCRCatalogManifestCodec.swift
//  Snapzy
//
//  Strict JSON/YAML codec for OCR model manifests.
//

import Foundation
import Yams

enum OCRCatalogManifestCodec {
  /// Reads at most one byte beyond the manifest limit so a selected oversized
  /// file cannot be loaded into memory before the normal size check runs.
  static func decode(contentsOf url: URL) throws -> OCRModelManifestDocument {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(
      upToCount: OCRCatalogManifestValidator.maximumManifestBytes + 1
    ) ?? Data()
    return try decode(data, fileExtension: url.pathExtension)
  }

  static func decode(_ data: Data, fileExtension: String) throws -> OCRModelManifestDocument {
    guard data.count <= OCRCatalogManifestValidator.maximumManifestBytes else {
      throw OCRModelManifestError.fileTooLarge
    }
    guard let format = OCRModelManifestFormat(fileExtension: fileExtension) else {
      throw OCRModelManifestError.unsupportedFileType(fileExtension)
    }
    guard let source = String(data: data, encoding: .utf8) else {
      throw OCRModelManifestError.invalid("file must be UTF-8")
    }

    do {
      try OCRManifestYAMLSafetyValidator.validateSourceTokens(source)
      guard let root = try Yams.compose(yaml: source) else {
        throw OCRModelManifestError.invalid("file is empty")
      }
      try OCRManifestYAMLSafetyValidator.validate(root)
      let document: OCRModelManifestDocument = switch format {
      case .json:
        try JSONDecoder().decode(OCRModelManifestDocument.self, from: data)
      case .yaml:
        try YAMLDecoder().decode(OCRModelManifestDocument.self, from: source)
      }
      _ = try OCRCatalogManifestValidator.validate(document)
      return document
    } catch let error as OCRModelManifestError {
      throw error
    } catch YamlError.duplicatedKeysInMapping(let duplicates, _) {
      throw OCRModelManifestError.invalid(
        "duplicate key \(duplicates.sorted().joined(separator: ", "))"
      )
    } catch {
      throw OCRModelManifestError.invalid(String(describing: error))
    }
  }

  static func encode(
    _ document: OCRModelManifestDocument,
    format: OCRModelManifestFormat
  ) throws -> Data {
    _ = try OCRCatalogManifestValidator.validate(document)
    switch format {
    case .json:
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      return try encoder.encode(document)
    case .yaml:
      return try Data(YAMLEncoder().encode(document).utf8)
    }
  }
}

private enum OCRManifestYAMLSafetyValidator {
  private static let maximumDepth = 20
  private static let maximumNodes = 20_000

  /// Yams resolves aliases while composing a node tree, so reject anchor and
  /// alias indicators before composition. Quoted values are deliberately
  /// ignored, allowing ordinary strings to contain `&` and `*`.
  static func validateSourceTokens(_ source: String) throws {
    let characters = Array(source)
    var inSingleQuote = false
    var inDoubleQuote = false
    var inComment = false
    var escapingDoubleQuote = false
    var skippingEscapedSingleQuote = false

    for index in characters.indices {
      let character = characters[index]
      if character == "\n" {
        inComment = false
        escapingDoubleQuote = false
        continue
      }
      if inComment { continue }

      if inDoubleQuote {
        if escapingDoubleQuote {
          escapingDoubleQuote = false
        } else if character == "\\" {
          escapingDoubleQuote = true
        } else if character == "\"" {
          inDoubleQuote = false
        }
        continue
      }
      if inSingleQuote {
        if skippingEscapedSingleQuote {
          skippingEscapedSingleQuote = false
          continue
        }
        if character == "'" {
          let nextIndex = characters.index(after: index)
          if nextIndex != characters.endIndex, characters[nextIndex] == "'" {
            skippingEscapedSingleQuote = true
          } else {
            inSingleQuote = false
          }
        }
        continue
      }

      switch character {
      case "#": inComment = true
      case "\"": inDoubleQuote = true
      case "'": inSingleQuote = true
      case "&", "*":
        let isTokenStart: Bool
        if index == characters.startIndex {
          isTokenStart = true
        } else {
          let previous = characters[characters.index(before: index)]
          isTokenStart = previous.isWhitespace || "[{,:?-".contains(previous)
        }
        if isTokenStart {
          throw OCRModelManifestError.invalid("YAML anchors and aliases are not supported")
        }
      default: break
      }
    }
  }

  static func validate(_ root: Node) throws {
    var nodeCount = 0
    try validateSafety(root, depth: 0, nodeCount: &nodeCount)
    let rootEntries = try mapping(root, at: "root", allowed: [
      "format", "schema_version", "models", "model",
    ])
    if let models = rootEntries["models"] {
      guard case .sequence(let sequence) = models else {
        throw OCRModelManifestError.invalid("root.models must be an array")
      }
      for (index, model) in sequence.enumerated() {
        try validateModel(model, at: "models[\(index)]")
      }
    }
    if let model = rootEntries["model"] {
      try validateModel(model, at: "model")
    }
  }

  private static func validateModel(_ node: Node, at path: String) throws {
    let entries = try mapping(node, at: path, allowed: [
      "id", "display_name", "parameter_count_label", "fp32_size_label",
      "int8_size_label", "adapter", "artifacts",
    ])
    guard let artifacts = entries["artifacts"], case .sequence(let sequence) = artifacts else {
      return
    }
    for (index, artifact) in sequence.enumerated() {
      let artifactPath = "\(path).artifacts[\(index)]"
      let artifactEntries = try mapping(artifact, at: artifactPath, allowed: [
        "role", "source", "expected_bytes", "sha256",
      ])
      if let source = artifactEntries["source"] {
        _ = try mapping(source, at: "\(artifactPath).source", allowed: [
          "type", "url", "repository", "revision", "file",
        ])
      }
    }
  }

  private static func validateSafety(
    _ node: Node,
    depth: Int,
    nodeCount: inout Int
  ) throws {
    nodeCount += 1
    guard depth <= maximumDepth, nodeCount <= maximumNodes else {
      throw OCRModelManifestError.invalid("YAML nesting or node limit exceeded")
    }
    guard node.anchor == nil else {
      throw OCRModelManifestError.invalid("YAML anchors are not supported")
    }

    switch node {
    case .alias:
      throw OCRModelManifestError.invalid("YAML aliases are not supported")
    case .scalar(let scalar):
      let allowedScalarTags: Set<String> = [
        Tag.Name.implicit.rawValue,
        Tag.Name.str.rawValue,
        Tag.Name.bool.rawValue,
        Tag.Name.float.rawValue,
        Tag.Name.null.rawValue,
        Tag.Name.int.rawValue,
      ]
      guard allowedScalarTags.contains(scalar.tag.rawValue) else {
        throw OCRModelManifestError.invalid("custom YAML tags are not supported")
      }
    case .mapping(let mapping):
      guard mapping.tag == .implicit else {
        throw OCRModelManifestError.invalid("explicit YAML tags are not supported")
      }
      for pair in mapping {
        try validateSafety(pair.key, depth: depth + 1, nodeCount: &nodeCount)
        try validateSafety(pair.value, depth: depth + 1, nodeCount: &nodeCount)
      }
    case .sequence(let sequence):
      guard sequence.tag == .implicit else {
        throw OCRModelManifestError.invalid("explicit YAML tags are not supported")
      }
      for child in sequence {
        try validateSafety(child, depth: depth + 1, nodeCount: &nodeCount)
      }
    }
  }

  private static func mapping(
    _ node: Node,
    at path: String,
    allowed: Set<String>
  ) throws -> [String: Node] {
    guard case .mapping(let mapping) = node else {
      throw OCRModelManifestError.invalid("\(path) must be an object")
    }
    var entries: [String: Node] = [:]
    for pair in mapping {
      guard case .scalar(let scalar) = pair.key else {
        throw OCRModelManifestError.invalid("\(path) contains a non-string key")
      }
      let key = scalar.string
      guard key != "<<" else {
        throw OCRModelManifestError.invalid("YAML merge keys are not supported")
      }
      guard allowed.contains(key) else {
        throw OCRModelManifestError.invalid("unknown key \(path).\(key)")
      }
      guard entries.updateValue(pair.value, forKey: key) == nil else {
        throw OCRModelManifestError.invalid("duplicate key \(path).\(key)")
      }
    }
    return entries
  }
}
