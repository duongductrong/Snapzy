#!/usr/bin/env swift

import Foundation

struct Manifest: Decodable {
  struct Fragment: Decodable {
    let file: String
    let prefixes: [String]
  }

  let runtimeCatalog: String
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
  case runtimeMismatch
  case l10nDrift(missing: [String], extra: [String])

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
    case .runtimeMismatch:
      return "Runtime Localizable.xcstrings is out of date. Run split then merge."
    case .l10nDrift(let missing, let extra):
      return "L10n drift detected. missing=\(missing.count) extra=\(extra.count)"
    }
  }
}

let fileManager = FileManager.default
let repoRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath)

func usage() -> Never {
  let message = """
  Usage:
    swift tools/localization/catalog-tool.swift audit
    swift tools/localization/catalog-tool.swift split
    swift tools/localization/catalog-tool.swift merge
    swift tools/localization/catalog-tool.swift verify
  """
  fputs("\(message)\n", stderr)
  exit(1)
}

func loadManifest() throws -> Manifest {
  let manifestURL = repoRoot.appendingPathComponent("LocalizationCatalogSources/manifest.json")
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

func writeJSONObject(_ object: Any, to url: URL) throws {
  try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  let data = try canonicalData(for: object)
  try data.write(to: url, options: .atomic)
}

func runtimeCatalogURL(_ manifest: Manifest) -> URL {
  repoRoot.appendingPathComponent(manifest.runtimeCatalog)
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

func splitRuntimeCatalog(using manifest: Manifest) throws {
  let runtimeCatalog = try catalog(from: runtimeCatalogURL(manifest))
  var buckets: [String: [String: Any]] = [:]

  for fragment in manifest.fragments {
    buckets[fragment.file] = [:]
  }

  for key in runtimeCatalog.strings.keys.sorted() {
    let owner = try ownerFragment(for: key, in: manifest)
    buckets[owner.file, default: [:]][key] = runtimeCatalog.strings[key]
  }

  for fragment in manifest.fragments {
    let fragmentCatalog = Catalog(
      sourceLanguage: manifest.sourceLanguage,
      version: manifest.version,
      strings: buckets[fragment.file] ?? [:]
    )
    try writeJSONObject(fragmentCatalog.rootObject, to: fragmentURL(manifest, fragment))
  }

  print("Split \(runtimeCatalog.strings.count) keys into \(manifest.fragments.count) fragment catalogs.")
}

func mergeFragments(using manifest: Manifest) throws {
  let merged = try mergedCatalog(from: manifest)
  try writeJSONObject(merged.rootObject, to: runtimeCatalogURL(manifest))
  print("Merged \(merged.strings.count) keys into \(manifest.runtimeCatalog).")
}

func extractL10nKeys() throws -> Set<String> {
  let localizationRoot = repoRoot.appendingPathComponent("Snapzy/Shared/Localization")
  let regex = try NSRegularExpression(pattern: #""([a-z0-9][a-z0-9.-]*\.[a-z0-9][a-z0-9.-]*)""#)
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
  let runtimeCatalog = try catalog(from: runtimeCatalogURL(manifest))
  let merged = try mergedCatalog(from: manifest)

  let runtimeData = try canonicalData(for: runtimeCatalog.rootObject)
  let mergedData = try canonicalData(for: merged.rootObject)
  guard runtimeData == mergedData else {
    throw ToolError.runtimeMismatch
  }

  let catalogKeys = Set(merged.strings.keys)
  let l10nKeys = try extractL10nKeys()
  let missing = l10nKeys.subtracting(catalogKeys).sorted()
  let extra = catalogKeys.subtracting(l10nKeys).sorted()
  guard missing.isEmpty && extra.isEmpty else {
    throw ToolError.l10nDrift(missing: missing, extra: extra)
  }

  let locales = allLocales(in: merged)
  print("Localization verify passed.")
  print("  keys=\(catalogKeys.count)")
  print("  locales=\(locales.count) [\(locales.joined(separator: ", "))]")
  print("  missing=0")
  print("  extra=0")
}

func audit(manifest: Manifest) throws {
  let runtimeCatalog = try catalog(from: runtimeCatalogURL(manifest))
  let counts = try countsByFragment(using: manifest, catalog: runtimeCatalog)
  let l10nKeys = try extractL10nKeys()
  let catalogKeys = Set(runtimeCatalog.strings.keys)
  let missing = l10nKeys.subtracting(catalogKeys).sorted()
  let extra = catalogKeys.subtracting(l10nKeys).sorted()

  print("Runtime catalog: \(manifest.runtimeCatalog)")
  print("  keys=\(catalogKeys.count)")
  print("  locales=\(allLocales(in: runtimeCatalog).count)")
  print("  sourceLanguage=\(runtimeCatalog.sourceLanguage)")
  print("  version=\(runtimeCatalog.version)")
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
  case "split":
    try splitRuntimeCatalog(using: manifest)
  case "merge":
    try mergeFragments(using: manifest)
  case "verify":
    try verify(manifest: manifest)
  default:
    usage()
  }
} catch {
  fputs("catalog-tool error: \(error.localizedDescription)\n", stderr)
  exit(1)
}
