//
//  VideoEditorFontManager.swift
//  Snapzy
//
//  Resolves the macOS system font (SF Pro), installed device font families
//  (`NSFontManager.shared.availableFontFamilies`), and user-imported local
//  `.ttf` / `.otf` / `.ttc` files stored in Application Support. Provides
//  thread-safe CoreText descriptor resolution with explicit Weight (400-900),
//  Bold, and Italic synthesis.
//

import AppKit
import Combine
import CoreText
import Foundation

nonisolated struct VideoEditorInstalledFontFamily: Identifiable, Equatable, Sendable {
  let id: String
  let familyName: String
}

nonisolated struct VideoEditorImportedFontRecord: Codable, Identifiable, Equatable, Sendable {
  let id: String
  let displayName: String
  let filenames: [String]
}

/// Thread-safe CoreText font registry shared by main-thread UI and background export queues.
nonisolated enum VideoEditorFontResolver {
  private struct FaceEntry {
    let descriptor: CTFontDescriptor
    let weight: Int
    let isItalic: Bool
    let isVariableWeight: Bool
  }

  private struct PreviewFontCacheKey: Hashable {
    let familyId: String
    let sizeTenths: Int
    let weight: Int
    let italic: Bool
  }

  private static let wghtTag: Int = 0x7767_6874 // 'wght'
  private static let maxManifestBytes: Int = 1_048_576
  private static let maxImportedFontFileBytes: Int = 33_554_432
  private static let lock = NSLock()
  private static let bootLock = NSLock()
  private nonisolated(unsafe) static var didBoot = false
  private nonisolated(unsafe) static var facesByFamilyId: [String: [FaceEntry]] = [:]
  private nonisolated(unsafe) static var installedFamilyNameById: [String: String] = [:]
  private nonisolated(unsafe) static var installedIdByLowercasedName: [String: String] = [:]
  private nonisolated(unsafe) static var installedFamiliesOrdered: [VideoEditorInstalledFontFamily] = []
  private nonisolated(unsafe) static var previewFontCache: [PreviewFontCacheKey: CTFont] = [:]
  private nonisolated(unsafe) static var previewFontOrder: [PreviewFontCacheKey] = []

  /// Default font family ID: macOS system font (`SF Pro` / `NSFont.systemFont`).
  static let defaultFamilyId = "system"
  static let installedPrefix = "installed:"

  static func installedFamilyId(for familyName: String) -> String {
    "\(installedPrefix)\(familyName)"
  }

  static func readBoundedData(from url: URL, maxBytes: Int) throws -> Data {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard values.isRegularFile == true else {
      throw CocoaError(.fileReadCorruptFile)
    }
    if let size = values.fileSize, size < 0 || size > maxBytes {
      throw CocoaError(.fileReadTooLarge)
    }
    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    guard data.count <= maxBytes else {
      throw CocoaError(.fileReadTooLarge)
    }
    return data
  }

  static func storageRootURL() -> URL {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return appSupport
      .appendingPathComponent("Snapzy", isDirectory: true)
      .appendingPathComponent("VideoEditorFonts", isDirectory: true)
  }

  static func ensureBootstrapped() {
    bootLock.lock()
    defer { bootLock.unlock() }
    lock.lock()
    if didBoot {
      lock.unlock()
      return
    }
    lock.unlock()

    // 1. Discover installed macOS system & user font families (`NSFontManager` / CoreText).
    let rawNames = (CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []
    let cleanedNames = rawNames
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && !$0.hasPrefix(".") }
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

    var ordered: [VideoEditorInstalledFontFamily] = []
    var byId: [String: String] = [:]
    var byLower: [String: String] = [:]
    ordered.reserveCapacity(cleanedNames.count)
    for name in cleanedNames {
      let fid = installedFamilyId(for: name)
      guard byId[fid] == nil else { continue }
      byId[fid] = name
      byLower[name.lowercased()] = fid
      ordered.append(VideoEditorInstalledFontFamily(id: fid, familyName: name))
    }

    lock.lock()
    installedFamiliesOrdered = ordered
    installedFamilyNameById = byId
    installedIdByLowercasedName = byLower
    lock.unlock()

    // 2. Clean up incomplete `.staging-*` directories and recover any `.backup-<familyId>`
    // left behind if the app crashed mid-replace before `dest` was put in place.
    let root = storageRootURL()
    if let allItems = try? FileManager.default.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: nil,
      options: []
    ) {
      let backupPrefix = ".backup-"
      for item in allItems {
        let name = item.lastPathComponent
        if name.hasPrefix(".staging-") {
          try? FileManager.default.removeItem(at: item)
        } else if name.hasPrefix(backupPrefix) {
          let familyId = String(name.dropFirst(backupPrefix.count))
          guard !familyId.isEmpty else {
            try? FileManager.default.removeItem(at: item)
            continue
          }
          let destDir = root.appendingPathComponent(familyId, isDirectory: true)
          if FileManager.default.fileExists(atPath: destDir.path) {
            try? FileManager.default.removeItem(at: item)
          } else {
            try? FileManager.default.moveItem(at: item, to: destDir)
          }
        }
      }
    }
    let manifestURL = root.appendingPathComponent("imported_fonts.json")
    if let manifestData = try? readBoundedData(from: manifestURL, maxBytes: maxManifestBytes),
       let records = try? JSONDecoder().decode([VideoEditorImportedFontRecord].self, from: manifestData) {
      for record in records.prefix(500) {
        let dir = root.appendingPathComponent(record.id, isDirectory: true)
        let fontFiles = record.filenames
          .map { dir.appendingPathComponent(URL(fileURLWithPath: $0).lastPathComponent) }
          .filter { url in
            guard ["ttf", "otf", "ttc"].contains(url.pathExtension.lowercased()),
                  let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  vals.isRegularFile == true,
                  let size = vals.fileSize,
                  size > 0,
                  size <= maxImportedFontFileBytes
            else { return false }
            return true
          }
        if !fontFiles.isEmpty {
          registerFontFiles(urls: fontFiles, forFamilyId: record.id)
        }
      }
    }

    lock.lock()
    didBoot = true
    lock.unlock()
  }

  static func availableInstalledFamilies() -> [VideoEditorInstalledFontFamily] {
    ensureBootstrapped()
    lock.lock()
    defer { lock.unlock() }
    return installedFamiliesOrdered
  }

  static func isFamilyAvailable(_ familyId: String) -> Bool {
    if familyId.isEmpty || familyId == defaultFamilyId {
      return true
    }
    ensureBootstrapped()
    lock.lock()
    defer { lock.unlock() }
    if !(facesByFamilyId[familyId]?.isEmpty ?? true) {
      return true
    }
    if installedFamilyNameById[familyId] != nil {
      return true
    }
    let normalized = familyId.replacingOccurrences(of: "-", with: " ").lowercased()
    return installedIdByLowercasedName[familyId.lowercased()] != nil
      || installedIdByLowercasedName[normalized] != nil
  }

  static func isFamilyRegistered(_ familyId: String) -> Bool {
    ensureBootstrapped()
    lock.lock()
    defer { lock.unlock() }
    return !(facesByFamilyId[familyId]?.isEmpty ?? true)
  }

  static func installedFamilyName(for familyId: String) -> String? {
    ensureBootstrapped()
    lock.lock()
    defer { lock.unlock() }
    if let exact = installedFamilyNameById[familyId] {
      return exact
    }
    if familyId.hasPrefix(installedPrefix) {
      let raw = String(familyId.dropFirst(installedPrefix.count))
      if let matchedId = installedIdByLowercasedName[raw.lowercased()] {
        return installedFamilyNameById[matchedId]
      }
    }
    let normalized = familyId.replacingOccurrences(of: "-", with: " ").lowercased()
    if let matchedId = installedIdByLowercasedName[familyId.lowercased()] ?? installedIdByLowercasedName[normalized] {
      return installedFamilyNameById[matchedId]
    }
    return nil
  }

  @discardableResult
  static func registerFontFiles(urls: [URL], forFamilyId familyId: String) -> String? {
    var collected: [FaceEntry] = []
    var detectedFamilyName: String?

    for url in urls {
      if let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
         vals.isRegularFile != true || (vals.fileSize ?? 0) > maxImportedFontFileBytes {
        continue
      }
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
      guard let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else {
        continue
      }
      let looksVariable: Bool = descs.contains { desc in
        let probe = CTFontCreateWithFontDescriptor(desc, 12, nil)
        guard let axes = CTFontCopyVariationAxes(probe) as? [[CFString: Any]] else { return false }
        return axes.contains { ($0[kCTFontVariationAxisIdentifierKey] as? NSNumber)?.intValue == 0x7767_6874 }
      }

      for d in descs {
        if detectedFamilyName == nil,
           let fam = CTFontDescriptorCopyAttribute(d, kCTFontFamilyNameAttribute) as? String,
           !fam.isEmpty {
          detectedFamilyName = fam
        }
        let psName = ((CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute) as? String) ?? "").lowercased()
        let traits = CTFontDescriptorCopyAttribute(d, kCTFontTraitsAttribute) as? NSDictionary
        let symRaw = (traits?[kCTFontSymbolicTrait as String] as? UInt32) ?? 0
        let isItalic = (symRaw & CTFontSymbolicTraits.traitItalic.rawValue) != 0
          || psName.contains("italic")
          || psName.contains("oblique")
        let inferredWeight = inferWeight(psName: psName, traits: traits)
        collected.append(FaceEntry(
          descriptor: d,
          weight: inferredWeight,
          isItalic: isItalic,
          isVariableWeight: looksVariable
        ))
      }
    }

    guard !collected.isEmpty else { return nil }
    lock.lock()
    facesByFamilyId[familyId] = collected
    previewFontCache.removeAll()
    previewFontOrder.removeAll()
    lock.unlock()
    return detectedFamilyName
  }

  /// Cached `CTFont` helper for small UI specimen previews so SwiftUI inspector sliders
  /// never re-query CoreText descriptors on every frame.
  static func cachedPreviewFont(
    familyId: String,
    size: CGFloat,
    weight: Int,
    italic: Bool
  ) -> CTFont {
    let key = PreviewFontCacheKey(
      familyId: familyId,
      sizeTenths: Int((size * 10).rounded()),
      weight: weight,
      italic: italic
    )
    lock.lock()
    if let hit = previewFontCache[key] {
      lock.unlock()
      return hit
    }
    lock.unlock()

    let resolved = resolveFont(familyId: familyId, size: size, weight: weight, italic: italic).font
    lock.lock()
    if previewFontCache[key] == nil {
      if previewFontOrder.count >= 128, let evicted = previewFontOrder.first {
        previewFontOrder.removeFirst()
        previewFontCache[evicted] = nil
      }
      previewFontCache[key] = resolved
      previewFontOrder.append(key)
    }
    lock.unlock()
    return resolved
  }

  /// Resolve a `CTFont` for `familyId`, explicit `weight` (`400 ... 900`), and `italic`.
  /// Falls back cleanly to the macOS system font (`SF Pro`) whenever `familyId` is `"system"`
  /// or not installed on the current machine.
  static func resolveFont(
    familyId: String,
    size: CGFloat,
    weight: Int,
    italic: Bool
  ) -> (font: CTFont, needsSyntheticBoldStroke: Bool) {
    ensureBootstrapped()
    let clampedWeight = min(900, max(300, weight))
    let safeSize = max(1, size.isFinite ? size : 14)

    if familyId.isEmpty || familyId == defaultFamilyId {
      return (resolveSystemFont(size: safeSize, weight: clampedWeight, italic: italic), false)
    }

    lock.lock()
    var faces = facesByFamilyId[familyId]
    let installedName: String? = if faces == nil {
      installedFamilyNameById[familyId]
        ?? installedIdByLowercasedName[familyId.lowercased()].flatMap { installedFamilyNameById[$0] }
        ?? installedIdByLowercasedName[familyId.replacingOccurrences(of: "-", with: " ").lowercased()]
        .flatMap { installedFamilyNameById[$0] }
    } else {
      nil
    }
    lock.unlock()

    if faces == nil, let installedName {
      let loadedFaces = loadInstalledFamilyFaces(familyName: installedName)
      if !loadedFaces.isEmpty {
        lock.lock()
        facesByFamilyId[familyId] = loadedFaces
        lock.unlock()
        faces = loadedFaces
      }
    }

    guard let poolFaces = faces, !poolFaces.isEmpty else {
      return (resolveSystemFont(size: safeSize, weight: clampedWeight, italic: italic), false)
    }

    let matchingSlant = poolFaces.filter { $0.isItalic == italic }
    let useSyntheticOblique = italic && matchingSlant.isEmpty
    let candidates = matchingSlant.isEmpty ? poolFaces.filter { !$0.isItalic } : matchingSlant
    let pool = candidates.isEmpty ? poolFaces : candidates

    if let variableFace = pool.first(where: \.isVariableWeight) {
      let varied = CTFontDescriptorCreateCopyWithVariation(
        variableFace.descriptor,
        wghtTag as CFNumber,
        CGFloat(clampedWeight)
      )
      if useSyntheticOblique {
        var oblique = CGAffineTransform(a: 1, b: 0, c: 0.185, d: 1, tx: 0, ty: 0)
        return (CTFontCreateWithFontDescriptor(varied, safeSize, &oblique), false)
      }
      return (CTFontCreateWithFontDescriptor(varied, safeSize, nil), false)
    }

    let best = pool.min { abs($0.weight - clampedWeight) < abs($1.weight - clampedWeight) } ?? pool[0]
    let distinctWeights = Set(pool.map(\.weight))
    let needsSyntheticBold = clampedWeight >= 650 && distinctWeights.count == 1 && best.weight < 600

    if useSyntheticOblique {
      var oblique = CGAffineTransform(a: 1, b: 0, c: 0.185, d: 1, tx: 0, ty: 0)
      return (CTFontCreateWithFontDescriptor(best.descriptor, safeSize, &oblique), needsSyntheticBold)
    }
    return (CTFontCreateWithFontDescriptor(best.descriptor, safeSize, nil), needsSyntheticBold)
  }

  private static func resolveSystemFont(size: CGFloat, weight: Int, italic: Bool) -> CTFont {
    let nsWeight: NSFont.Weight = switch weight {
    case 850...: .black
    case 750 ..< 850: .heavy
    case 650 ..< 750: .bold
    case 550 ..< 650: .semibold
    case 450 ..< 550: .medium
    case 350 ..< 450: .regular
    default: .light
    }
    let base = NSFont.systemFont(ofSize: size, weight: nsWeight) as CTFont
    guard italic else { return base }
    if let italicCopy = CTFontCreateCopyWithSymbolicTraits(
      base,
      size,
      nil,
      .traitItalic,
      .traitItalic
    ) {
      return italicCopy
    }
    var oblique = CGAffineTransform(a: 1, b: 0, c: 0.185, d: 1, tx: 0, ty: 0)
    return CTFontCreateCopyWithAttributes(base, size, &oblique, nil)
  }

  private static func loadInstalledFamilyFaces(familyName: String) -> [FaceEntry] {
    let attrs: [CFString: Any] = [kCTFontFamilyNameAttribute: familyName]
    let query = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
    guard let matches = CTFontDescriptorCreateMatchingFontDescriptors(query, nil) as? [CTFontDescriptor],
          !matches.isEmpty
    else {
      return []
    }
    let looksVariable = matches.contains { desc in
      let probe = CTFontCreateWithFontDescriptor(desc, 12, nil)
      guard let axes = CTFontCopyVariationAxes(probe) as? [[CFString: Any]] else { return false }
      return axes.contains { ($0[kCTFontVariationAxisIdentifierKey] as? NSNumber)?.intValue == 0x7767_6874 }
    }
    return matches.map { d in
      let psName = ((CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute) as? String) ?? "").lowercased()
      let styleName = ((CTFontDescriptorCopyAttribute(d, kCTFontStyleNameAttribute) as? String) ?? "").lowercased()
      let traits = CTFontDescriptorCopyAttribute(d, kCTFontTraitsAttribute) as? NSDictionary
      let symRaw = (traits?[kCTFontSymbolicTrait as String] as? UInt32) ?? 0
      let isItalic = (symRaw & CTFontSymbolicTraits.traitItalic.rawValue) != 0
        || psName.contains("italic")
        || psName.contains("oblique")
        || styleName.contains("italic")
        || styleName.contains("oblique")
      let inferredWeight = inferWeight(psName: psName + " " + styleName, traits: traits)
      return FaceEntry(
        descriptor: d,
        weight: inferredWeight,
        isItalic: isItalic,
        isVariableWeight: looksVariable
      )
    }
  }

  private static func inferWeight(psName: String, traits: NSDictionary?) -> Int {
    if psName.contains("black") || psName.contains("heavy") {
      return 900
    }
    if psName.contains("extrabold") || psName.contains("ultrabold") {
      return 800
    }
    if psName.contains("semibold") || psName.contains("demibold") {
      return 600
    }
    if psName.contains("bold") {
      return 700
    }
    if psName.contains("medium") {
      return 500
    }
    if psName.contains("light") {
      return 300
    }
    if psName.contains("thin") {
      return 200
    }
    if let wNum = traits?[kCTFontWeightTrait as String] as? Double {
      if wNum >= 0.55 {
        return 800
      }
      if wNum >= 0.35 {
        return 700
      }
      if wNum >= 0.20 {
        return 600
      }
      if wNum >= 0.08 {
        return 500
      }
    }
    return 400
  }
}

/// Main-actor observable font registry exposing macOS system & installed font families
/// first, plus user-imported local `.ttf` / `.otf` / `.ttc` font files.
@MainActor
final class VideoEditorFontManager: ObservableObject {
  static let shared = VideoEditorFontManager()

  @Published private(set) var installedFamilies: [VideoEditorInstalledFontFamily] = []
  @Published private(set) var importedFonts: [VideoEditorImportedFontRecord] = []
  @Published private(set) var lastErrorMessage: String?
  @Published private(set) var revision: Int = 0

  private static let maxManifestBytes: Int = 1_048_576
  private nonisolated static let maxImportedFontFileBytes: Int = 33_554_432
  private nonisolated static let importLock = NSLock()

  /// Explicit and nonisolated: avoids macOS 13-15 swift_task_deinitOnExecutor abort (#668).
  nonisolated deinit {}

  private var manifestURL: URL {
    VideoEditorFontResolver.storageRootURL().appendingPathComponent("imported_fonts.json")
  }

  private init() {
    VideoEditorFontResolver.ensureBootstrapped()
    reloadDiskState()
  }

  func reloadDiskState() {
    let availableNames = NSFontManager.shared.availableFontFamilies
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && !$0.hasPrefix(".") }
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

    if !availableNames.isEmpty {
      var seen: Set<String> = []
      installedFamilies = availableNames.compactMap { name in
        let id = VideoEditorFontResolver.installedFamilyId(for: name)
        guard seen.insert(id).inserted else { return nil }
        return VideoEditorInstalledFontFamily(id: id, familyName: name)
      }
    } else {
      installedFamilies = VideoEditorFontResolver.availableInstalledFamilies()
    }

    if let data = try? VideoEditorFontResolver.readBoundedData(from: manifestURL, maxBytes: Self.maxManifestBytes),
       let decoded = try? JSONDecoder().decode([VideoEditorImportedFontRecord].self, from: data) {
      importedFonts = Array(decoded.prefix(500)).filter { VideoEditorFontResolver.isFamilyRegistered($0.id) }
    } else {
      importedFonts = []
    }
  }

  func isFontAvailable(_ familyId: String) -> Bool {
    VideoEditorFontResolver.isFamilyAvailable(familyId)
  }

  func displayName(for familyId: String) -> String {
    if familyId.isEmpty || familyId == VideoEditorFontResolver.defaultFamilyId {
      return L10n.VideoEditor.systemFontDisplayName
    }
    if let imp = importedFonts.first(where: { $0.id == familyId }) {
      return imp.displayName
    }
    if let installedName = VideoEditorFontResolver.installedFamilyName(for: familyId) {
      return installedName
    }
    if familyId.hasPrefix(VideoEditorFontResolver.installedPrefix) {
      return String(familyId.dropFirst(VideoEditorFontResolver.installedPrefix.count))
    }
    return L10n.VideoEditor.systemFontDisplayName
  }

  /// Stage, validate, atomically install, and register font files without leaving partial files
  /// behind or losing an existing family directory if replacement fails.
  private nonisolated static func stageAndRegisterFontFiles(
    from urls: [URL]
  ) throws -> VideoEditorImportedFontRecord? {
    importLock.lock()
    defer { importLock.unlock() }

    let valid = urls.filter { ["ttf", "otf", "ttc"].contains($0.pathExtension.lowercased()) }
    guard !valid.isEmpty else { return nil }

    let slugBase = valid[0].deletingPathExtension().lastPathComponent
      .lowercased()
      .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    let familyId = "custom-\(slugBase.isEmpty ? UUID().uuidString.prefix(8).lowercased() : slugBase)"
    let root = VideoEditorFontResolver.storageRootURL()
    let stagingDir = root.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
    let destDir = root.appendingPathComponent(familyId, isDirectory: true)
    let backupDir = root.appendingPathComponent(".backup-\(familyId)", isDirectory: true)
    defer {
      try? FileManager.default.removeItem(at: stagingDir)
    }

    try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
    var stagedNames: [String] = []
    for src in valid {
      let accessed = src.startAccessingSecurityScopedResource()
      defer {
        if accessed {
          src.stopAccessingSecurityScopedResource()
        }
      }
      let vals = try src.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
      guard vals.isRegularFile == true,
            let size = vals.fileSize,
            size > 0,
            size <= maxImportedFontFileBytes
      else {
        throw CocoaError(.fileReadTooLarge)
      }
      let safeFileName = URL(fileURLWithPath: src.lastPathComponent).lastPathComponent
      let stagedFileURL = stagingDir.appendingPathComponent(safeFileName)
      if FileManager.default.fileExists(atPath: stagedFileURL.path) {
        try FileManager.default.removeItem(at: stagedFileURL)
      }
      try FileManager.default.copyItem(at: src, to: stagedFileURL)
      stagedNames.append(safeFileName)
    }

    var movedExistingToBackup = false
    if FileManager.default.fileExists(atPath: destDir.path) {
      if FileManager.default.fileExists(atPath: backupDir.path) {
        try FileManager.default.removeItem(at: backupDir)
      }
      try FileManager.default.moveItem(at: destDir, to: backupDir)
      movedExistingToBackup = true
    }

    var committedNewDest = false
    defer {
      if committedNewDest {
        if movedExistingToBackup {
          try? FileManager.default.removeItem(at: backupDir)
        }
      } else {
        if FileManager.default.fileExists(atPath: destDir.path) {
          try? FileManager.default.removeItem(at: destDir)
        }
        if movedExistingToBackup {
          try? FileManager.default.moveItem(at: backupDir, to: destDir)
        }
      }
    }

    try FileManager.default.moveItem(at: stagingDir, to: destDir)
    let installedURLs = stagedNames.map { destDir.appendingPathComponent($0) }
    guard let familyName = VideoEditorFontResolver.registerFontFiles(urls: installedURLs, forFamilyId: familyId) else {
      return nil
    }
    committedNewDest = true

    return VideoEditorImportedFontRecord(
      id: familyId,
      displayName: familyName,
      filenames: stagedNames
    )
  }

  /// Asynchronously import one or more local `.ttf`, `.otf`, or `.ttc` font files off `@MainActor`
  /// using serialized atomic staging so UI frames never stall and failed replacements restore the prior font.
  @discardableResult
  func importFontFilesAsync(from urls: [URL]) async -> String? {
    do {
      let record = try await Task.detached(priority: .userInitiated) {
        try Self.stageAndRegisterFontFiles(from: urls)
      }.value
      guard let record else { return nil }
      importedFonts.removeAll { $0.id == record.id }
      importedFonts.append(record)
      persistManifest()
      lastErrorMessage = nil
      revision += 1
      return record.id
    } catch {
      lastErrorMessage = error.localizedDescription
      return nil
    }
  }

  private func persistManifest() {
    guard let data = try? JSONEncoder().encode(importedFonts) else { return }
    try? FileManager.default.createDirectory(
      at: VideoEditorFontResolver.storageRootURL(),
      withIntermediateDirectories: true
    )
    try? data.write(to: manifestURL, options: .atomic)
  }
}
