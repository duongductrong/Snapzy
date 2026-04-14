#!/usr/bin/env swift

import Foundation

struct Manifest: Decodable {
  struct Fragment: Decodable {
    let file: String
    let prefixes: [String]
  }

  let sourceDirectory: String
  let sourceLanguage: String
  let version: String
  let fragments: [Fragment]
}

struct Catalog {
  let sourceLanguage: String
  let version: String
  let strings: [String: Any]

  var rootObject: [String: Any] {
    [
      "sourceLanguage": sourceLanguage,
      "strings": strings,
      "version": version,
    ]
  }
}

enum ToolError: LocalizedError {
  case usage(String)
  case invalidJSON(URL)
  case invalidCatalog(URL)
  case invalidManifest(String)
  case missingFragment(URL)
  case ambiguousOwner(key: String, owners: [String])
  case missingOwner(key: String)
  case misplacedKey(key: String, expected: String, actual: String)
  case duplicateKey(key: String, first: String, second: String)
  case l10nDrift(missing: [String], extra: [String])
  case tableMappingDrift(missing: [String], mismatched: [String], extra: [String])

  var errorDescription: String? {
    switch self {
    case .usage(let message):
      return message
    case .invalidJSON(let url):
      return "Invalid JSON at \(url.path)"
    case .invalidCatalog(let url):
      return "Invalid .xcstrings catalog at \(url.path)"
    case .invalidManifest(let message):
      return "Invalid manifest: \(message)"
    case .missingFragment(let url):
      return "Missing fragment catalog: \(url.path)"
    case .ambiguousOwner(let key, let owners):
      return "Key \(key) matches multiple fragments: \(owners.joined(separator: ", "))"
    case .missingOwner(let key):
      return "Key \(key) does not match any fragment prefix"
    case .misplacedKey(let key, let expected, let actual):
      return "Key \(key) belongs in \(expected) but was found in \(actual)"
    case .duplicateKey(let key, let first, let second):
      return "Duplicate key \(key) in \(first) and \(second)"
    case .l10nDrift(let missing, let extra):
      return "L10n drift detected. missing=\(missing.count) extra=\(extra.count)"
    case .tableMappingDrift(let missing, let mismatched, let extra):
      return "L10n table mapping drift detected. missing=\(missing.count) mismatched=\(mismatched.count) extra=\(extra.count)"
    }
  }
}

let fileManager = FileManager.default
let repoRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath)

func usage() -> Never {
  let message = """
  Usage:
    swift tools/localization/CatalogTool.swift audit
    swift tools/localization/CatalogTool.swift verify
  """
  fputs("\(message)\n", stderr)
  exit(1)
}

func loadManifest() throws -> Manifest {
  let manifestURL = repoRoot.appendingPathComponent("Snapzy/Resources/Localization/manifest.json")
  let data = try Data(contentsOf: manifestURL)
  let decoder = JSONDecoder()
  let manifest = try decoder.decode(Manifest.self, from: data)

  let files = Set(manifest.fragments.map(\.file))
  guard files.count == manifest.fragments.count else {
    throw ToolError.invalidManifest("fragment file names must be unique")
  }

  return manifest
}

func loadJSONObject(from url: URL) throws -> Any {
  let data = try Data(contentsOf: url)
  return try JSONSerialization.jsonObject(with: data)
}

func catalog(from url: URL) throws -> Catalog {
  guard let root = try loadJSONObject(from: url) as? [String: Any] else {
    throw ToolError.invalidJSON(url)
  }
  guard
    let sourceLanguage = root["sourceLanguage"] as? String,
    let version = root["version"] as? String,
    let strings = root["strings"] as? [String: Any]
  else {
    throw ToolError.invalidCatalog(url)
  }

  return Catalog(sourceLanguage: sourceLanguage, version: version, strings: strings)
}

func canonicalData(for object: Any) throws -> Data {
  guard JSONSerialization.isValidJSONObject(object) else {
    throw ToolError.invalidManifest("JSON object is not serializable")
  }

  var data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
  if data.last != 0x0A {
    data.append(0x0A)
  }
  return data
}

func sourceDirectoryURL(_ manifest: Manifest) -> URL {
  repoRoot.appendingPathComponent(manifest.sourceDirectory)
}

func fragmentURL(_ manifest: Manifest, _ fragment: Manifest.Fragment) -> URL {
  sourceDirectoryURL(manifest).appendingPathComponent(fragment.file)
}

func ownerFragment(for key: String, in manifest: Manifest) throws -> Manifest.Fragment {
  let matches = manifest.fragments.filter { fragment in
    fragment.prefixes.contains { prefix in key.hasPrefix(prefix) }
  }

  if matches.isEmpty {
    throw ToolError.missingOwner(key: key)
  }

  if matches.count > 1 {
    throw ToolError.ambiguousOwner(key: key, owners: matches.map(\.file))
  }

  return matches[0]
}

func mergedCatalog(from manifest: Manifest) throws -> Catalog {
  var mergedStrings: [String: Any] = [:]
  var duplicateOwners: [String: String] = [:]

  for fragment in manifest.fragments {
    let url = fragmentURL(manifest, fragment)
    guard fileManager.fileExists(atPath: url.path) else {
      throw ToolError.missingFragment(url)
    }

    let catalog = try catalog(from: url)
    guard catalog.sourceLanguage == manifest.sourceLanguage else {
      throw ToolError.invalidManifest("\(fragment.file) has sourceLanguage \(catalog.sourceLanguage), expected \(manifest.sourceLanguage)")
    }
    guard catalog.version == manifest.version else {
      throw ToolError.invalidManifest("\(fragment.file) has version \(catalog.version), expected \(manifest.version)")
    }

    for (key, value) in catalog.strings {
      let owner = try ownerFragment(for: key, in: manifest)
      if owner.file != fragment.file {
        throw ToolError.misplacedKey(key: key, expected: owner.file, actual: fragment.file)
      }
      if let firstOwner = duplicateOwners[key] {
        throw ToolError.duplicateKey(key: key, first: firstOwner, second: fragment.file)
      }
      duplicateOwners[key] = fragment.file
      mergedStrings[key] = value
    }
  }

  return Catalog(
    sourceLanguage: manifest.sourceLanguage,
    version: manifest.version,
    strings: mergedStrings
  )
}

func extractL10nKeys() throws -> Set<String> {
  let localizationRoot = repoRoot.appendingPathComponent("Snapzy/Shared/Localization")
  let regex = try NSRegularExpression(pattern: #"(?:string|format)\(\s*"([a-z0-9][a-z0-9.-]*\.[a-z0-9][a-z0-9.-]*)""#)
  var keys = Set<String>()

  let enumerator = fileManager.enumerator(at: localizationRoot, includingPropertiesForKeys: [.isRegularFileKey])
  while case let fileURL as URL = enumerator?.nextObject() {
    guard fileURL.pathExtension == "swift" else { continue }
    guard fileURL.lastPathComponent.hasPrefix("L10n") else { continue }

    let content = try String(contentsOf: fileURL, encoding: .utf8)
    let range = NSRange(content.startIndex..<content.endIndex, in: content)
    for match in regex.matches(in: content, range: range) {
      guard let range = Range(match.range(at: 1), in: content) else { continue }
      keys.insert(String(content[range]))
    }
  }

  return keys
}

func extractL10nTableMappings() throws -> [String: String] {
  let l10nURL = repoRoot.appendingPathComponent("Snapzy/Shared/Localization/L10n.swift")
  let content = try String(contentsOf: l10nURL, encoding: .utf8)
  let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
  guard let startIndex = lines.firstIndex(where: { $0.contains("private nonisolated static let tableMappings") }) else {
    throw ToolError.invalidManifest("missing tableMappings in L10n.swift")
  }
  let pattern = try NSRegularExpression(pattern: #"^\s*\("([a-z0-9.-]+)",\s*"([A-Za-z0-9-]+)"\),?\s*$"#)
  var mappings: [String: String] = [:]
  var didReachEnd = false

  for line in lines[lines.index(after: startIndex)...] {
    let lineString = String(line)
    if lineString.trimmingCharacters(in: .whitespacesAndNewlines) == "]" {
      didReachEnd = true
      break
    }

    let range = NSRange(lineString.startIndex..<lineString.endIndex, in: lineString)
    guard let match = pattern.firstMatch(in: lineString, range: range) else { continue }
    guard
      let prefixRange = Range(match.range(at: 1), in: lineString),
      let tableRange = Range(match.range(at: 2), in: lineString)
    else {
      continue
    }

    let prefix = String(lineString[prefixRange])
    let tableName = String(lineString[tableRange])
    if mappings.updateValue(tableName, forKey: prefix) != nil {
      throw ToolError.invalidManifest("duplicate table mapping prefix in L10n.swift: \(prefix)")
    }
  }

  guard didReachEnd else {
    throw ToolError.invalidManifest("missing closing ] for tableMappings in L10n.swift")
  }

  return mappings
}

func expectedTableMappings(from manifest: Manifest) -> [String: String] {
  var mappings: [String: String] = [:]

  for fragment in manifest.fragments {
    let tableName = URL(fileURLWithPath: fragment.file).deletingPathExtension().lastPathComponent
    for prefix in fragment.prefixes {
      mappings[prefix] = tableName
    }
  }

  return mappings
}

func allLocales(in catalog: Catalog) -> [String] {
  var locales = Set<String>()
  for value in catalog.strings.values {
    guard
      let entry = value as? [String: Any],
      let localizations = entry["localizations"] as? [String: Any]
    else {
      continue
    }
    locales.formUnion(localizations.keys)
  }
  return locales.sorted()
}

func countsByFragment(using manifest: Manifest, catalog: Catalog) throws -> [(String, Int)] {
  var counts: [String: Int] = [:]
  for fragment in manifest.fragments {
    counts[fragment.file] = 0
  }

  for key in catalog.strings.keys {
    let owner = try ownerFragment(for: key, in: manifest)
    counts[owner.file, default: 0] += 1
  }

  return manifest.fragments.map { ($0.file, counts[$0.file, default: 0]) }
}

func verify(manifest: Manifest) throws {
  let merged = try mergedCatalog(from: manifest)

  let catalogKeys = Set(merged.strings.keys)
  let l10nKeys = try extractL10nKeys()
  let missing = l10nKeys.subtracting(catalogKeys).sorted()
  let extra = catalogKeys.subtracting(l10nKeys).sorted()
  guard missing.isEmpty && extra.isEmpty else {
    throw ToolError.l10nDrift(missing: missing, extra: extra)
  }

  let expectedMappings = expectedTableMappings(from: manifest)
  let actualMappings = try extractL10nTableMappings()
  let missingMappings = Set(expectedMappings.keys).subtracting(Set(actualMappings.keys)).sorted()
  let extraMappings = Set(actualMappings.keys).subtracting(Set(expectedMappings.keys)).sorted()
  let mismatchedMappings = expectedMappings.keys.sorted().compactMap { prefix -> String? in
    guard let actualTableName = actualMappings[prefix] else { return nil }
    let expectedTableName = expectedMappings[prefix]
    guard actualTableName != expectedTableName else { return nil }
    return "\(prefix): expected \(expectedTableName ?? "<missing>"), got \(actualTableName)"
  }
  guard missingMappings.isEmpty && mismatchedMappings.isEmpty && extraMappings.isEmpty else {
    throw ToolError.tableMappingDrift(
      missing: missingMappings,
      mismatched: mismatchedMappings,
      extra: extraMappings
    )
  }

  let locales = allLocales(in: merged)
  print("Localization verify passed.")
  print("  keys=\(catalogKeys.count)")
  print("  locales=\(locales.count) [\(locales.joined(separator: ", "))]")
  print("  missing=0")
  print("  extra=0")
}

func audit(manifest: Manifest) throws {
  let merged = try mergedCatalog(from: manifest)
  let counts = try countsByFragment(using: manifest, catalog: merged)
  let l10nKeys = try extractL10nKeys()
  let catalogKeys = Set(merged.strings.keys)
  let missing = l10nKeys.subtracting(catalogKeys).sorted()
  let extra = catalogKeys.subtracting(l10nKeys).sorted()
  let expectedMappings = expectedTableMappings(from: manifest)
  let actualMappings = try extractL10nTableMappings()
  let missingMappings = Set(expectedMappings.keys).subtracting(Set(actualMappings.keys)).sorted()
  let extraMappings = Set(actualMappings.keys).subtracting(Set(expectedMappings.keys)).sorted()
  let mismatchedMappings = expectedMappings.keys.sorted().compactMap { prefix -> String? in
    guard let actualTableName = actualMappings[prefix] else { return nil }
    let expectedTableName = expectedMappings[prefix]
    guard actualTableName != expectedTableName else { return nil }
    return "\(prefix): expected \(expectedTableName ?? "<missing>"), got \(actualTableName)"
  }

  print("Catalog directory: \(manifest.sourceDirectory)")
  print("  keys=\(catalogKeys.count)")
  print("  locales=\(allLocales(in: merged).count)")
  print("  sourceLanguage=\(merged.sourceLanguage)")
  print("  version=\(merged.version)")
  print("Fragment ownership:")
  for (file, count) in counts {
    print("  \(file): \(count)")
  }
  print("L10n drift:")
  print("  missing=\(missing.count)")
  print("  extra=\(extra.count)")
  if !missing.isEmpty {
    print("  missingKeys=\(missing.joined(separator: ", "))")
  }
  if !extra.isEmpty {
    print("  extraKeys=\(extra.joined(separator: ", "))")
  }
  print("Table mapping drift:")
  print("  missing=\(missingMappings.count)")
  print("  mismatched=\(mismatchedMappings.count)")
  print("  extra=\(extraMappings.count)")
  if !missingMappings.isEmpty {
    print("  missingPrefixes=\(missingMappings.joined(separator: ", "))")
  }
  if !mismatchedMappings.isEmpty {
    print("  mismatchedMappings=\(mismatchedMappings.joined(separator: " | "))")
  }
  if !extraMappings.isEmpty {
    print("  extraPrefixes=\(extraMappings.joined(separator: ", "))")
  }
}

do {
  guard CommandLine.arguments.count == 2 else {
    usage()
  }

  let command = CommandLine.arguments[1]
  let manifest = try loadManifest()

  switch command {
  case "audit":
    try audit(manifest: manifest)
  case "verify":
    try verify(manifest: manifest)
  default:
    usage()
  }
} catch {
  fputs("catalog-tool error: \(error.localizedDescription)\n", stderr)
  exit(1)
}
