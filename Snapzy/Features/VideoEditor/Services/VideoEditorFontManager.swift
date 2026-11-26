//
//  VideoEditorFontManager.swift
//  Snapzy
//
//  Resolves the macOS system font (SF Pro), installed device font families
//  (`NSFontManager.shared.availableFontFamilies`), opt-in SHA-256 verified
//  SIL Open Font License 1.1 families from a pinned `google/fonts` commit,
//  and user-imported local `.ttf` / `.otf` / `.ttc` files stored in Application Support.
//  Provides thread-safe CoreText descriptor resolution with explicit Weight (400-900),
//  Bold, and Italic synthesis.
//

import AppKit
import Combine
import CoreText
import CryptoKit
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

nonisolated struct VideoEditorCatalogFontAsset: Equatable, Sendable {
  /// Relative path under `VideoEditorFontManager.pinnedGoogleFontsBaseURL` (URL-escaped).
  let relativePath: String
  /// Local filename stored inside `<storageRoot>/<family.id>/`.
  let fileName: String
  /// Expected lowercase 64-character hex SHA-256 digest verified before writing to disk.
  let sha256: String

  var downloadURL: URL? {
    URL(string: VideoEditorFontManager.pinnedGoogleFontsBaseURL + relativePath)
  }
}

nonisolated struct VideoEditorCatalogFontFamily: Identifiable, Equatable, Sendable {
  let id: String
  let displayName: String
  let categoryLabel: String
  let files: [VideoEditorCatalogFontAsset]
  let licenseAsset: VideoEditorCatalogFontAsset
}

nonisolated enum VideoEditorFontDownloadError: LocalizedError, Equatable, Sendable {
  case invalidURL(String)
  case httpStatus(Int)
  case fileTooLarge(maxBytes: Int)
  case checksumMismatch(fileName: String)
  case registrationFailed(String)

  var errorDescription: String? {
    switch self {
    case .invalidURL(let path):
      "Invalid font URL for \(path)."
    case .httpStatus(let code):
      "Font download failed with HTTP \(code)."
    case .fileTooLarge(let maxBytes):
      "Font file exceeded the \(maxBytes / (1024 * 1024)) MB safety limit."
    case .checksumMismatch(let fileName):
      "SHA-256 verification failed for \(fileName)."
    case .registrationFailed(let familyName):
      "CoreText could not register font family \(familyName)."
    }
  }
}

/// Thread-safe bounded HTTP data fetcher that enforces a strict byte ceiling both on
/// `expectedContentLength` and mid-stream before buffering unbounded data in memory.
private final nonisolated class BoundedFontDataDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  nonisolated deinit {}

  private let lock = NSLock()
  private let maxBytes: Int
  private var buffer = Data()
  private var terminalError: Error?
  private var continuation: CheckedContinuation<Data, Error>?

  nonisolated init(maxBytes: Int, continuation: CheckedContinuation<Data, Error>) {
    self.maxBytes = maxBytes
    self.continuation = continuation
    super.init()
  }

  func urlSession(
    _: URLSession,
    dataTask _: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
      lock.lock()
      terminalError = VideoEditorFontDownloadError.httpStatus(http.statusCode)
      lock.unlock()
      completionHandler(.cancel)
      return
    }
    if response.expectedContentLength > Int64(maxBytes) {
      lock.lock()
      terminalError = VideoEditorFontDownloadError.fileTooLarge(maxBytes: maxBytes)
      lock.unlock()
      completionHandler(.cancel)
      return
    }
    if response.expectedContentLength > 0 {
      lock.lock()
      buffer.reserveCapacity(Int(min(response.expectedContentLength, Int64(maxBytes))))
      lock.unlock()
    }
    completionHandler(.allow)
  }

  func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    lock.lock()
    if terminalError != nil {
      lock.unlock()
      return
    }
    if buffer.count + data.count > maxBytes {
      terminalError = VideoEditorFontDownloadError.fileTooLarge(maxBytes: maxBytes)
      lock.unlock()
      dataTask.cancel()
      return
    }
    buffer.append(data)
    lock.unlock()
  }

  func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
    lock.lock()
    let cont = continuation
    continuation = nil
    let savedError = terminalError
    let resultData = buffer
    lock.unlock()

    guard let cont else { return }
    if let savedError {
      cont.resume(throwing: savedError)
    } else if let error {
      cont.resume(throwing: error)
    } else {
      cont.resume(returning: resultData)
    }
  }
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

    registerStoredFonts(under: storageRootURL())

    lock.lock()
    didBoot = true
    lock.unlock()
  }

  static func registerStoredFonts(under root: URL) {
    guard let subdirs = try? FileManager.default.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else { return }

    for dir in subdirs {
      let familyId = dir.lastPathComponent
      let fontFiles = (try? FileManager.default.contentsOfDirectory(
        at: dir,
        includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
      ))?
        .filter { url in
          guard ["ttf", "otf", "ttc"].contains(url.pathExtension.lowercased()),
                let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                vals.isRegularFile == true,
                (vals.fileSize ?? 0) <= maxImportedFontFileBytes
          else { return false }
          return true
        } ?? []
      if !fontFiles.isEmpty {
        registerFontFiles(urls: fontFiles, forFamilyId: familyId)
      }
    }
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

  static func unregisterFamily(_ familyId: String) {
    lock.lock()
    facesByFamilyId.removeValue(forKey: familyId)
    previewFontCache.removeAll()
    previewFontOrder.removeAll()
    lock.unlock()
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
/// first, opt-in SHA-256 verified SIL OFL 1.1 font downloads from a pinned `google/fonts`
/// commit, and user-imported local `.ttf` / `.otf` / `.ttc` font files.
@MainActor
final class VideoEditorFontManager: ObservableObject {
  nonisolated deinit {}

  static let shared = VideoEditorFontManager()

  /// Immutable commit SHA in `google/fonts` from which opt-in OFL fonts and `OFL.txt` licenses are fetched.
  nonisolated static let pinnedGoogleFontsCommit = "5026800714d07231937d92eb4cceabf06e05d74e"
  nonisolated static let pinnedGoogleFontsBaseURL =
    "https://raw.githubusercontent.com/google/fonts/5026800714d07231937d92eb4cceabf06e05d74e/ofl/"

  /// Hard 5 MB per-asset download cap enforced both on `Content-Length` and mid-stream.
  nonisolated static let maxDownloadAssetBytes = 5_242_880

  /// Curated SIL Open Font License 1.1 catalog with pinned SHA-256 digests for every font binary and `OFL.txt`.
  nonisolated static let curatedCatalog: [VideoEditorCatalogFontFamily] = [
    VideoEditorCatalogFontFamily(
      id: "montserrat",
      displayName: "Montserrat",
      categoryLabel: "Geometric Sans",
      files: [
        VideoEditorCatalogFontAsset(
          relativePath: "montserrat/Montserrat%5Bwght%5D.ttf",
          fileName: "Montserrat[wght].ttf",
          sha256: "0f7b311b2f3279e4eef9b2f968bcdbab6e28f4daeb1f049f4f278a902bcd82f7"
        ),
        VideoEditorCatalogFontAsset(
          relativePath: "montserrat/Montserrat-Italic%5Bwght%5D.ttf",
          fileName: "Montserrat-Italic[wght].ttf",
          sha256: "51607f316bc020e59f03cbf51543eecffbea501c0b31d73e5b82927c5cca442c"
        ),
      ],
      licenseAsset: VideoEditorCatalogFontAsset(
        relativePath: "montserrat/OFL.txt",
        fileName: "OFL.txt",
        sha256: "8b7141c03fa4f8d44e6345d5d4931709290f0f67875e452e95ac1fd3a027802e"
      )
    ),
    VideoEditorCatalogFontFamily(
      id: "be-vietnam-pro",
      displayName: "Be Vietnam Pro",
      categoryLabel: "Editorial Sans",
      files: [
        VideoEditorCatalogFontAsset(
          relativePath: "bevietnampro/BeVietnamPro-Regular.ttf",
          fileName: "BeVietnamPro-Regular.ttf",
          sha256: "cd1ef6e9d7db28ad5cdb88a65ccbe693870e60d340b791f349d248342b4fe4c3"
        ),
        VideoEditorCatalogFontAsset(
          relativePath: "bevietnampro/BeVietnamPro-SemiBold.ttf",
          fileName: "BeVietnamPro-SemiBold.ttf",
          sha256: "bd8e27eb02720b9d91e59e4f10a90878643219f25ce6a8d9a4f06a8a88d3bb71"
        ),
        VideoEditorCatalogFontAsset(
          relativePath: "bevietnampro/BeVietnamPro-Bold.ttf",
          fileName: "BeVietnamPro-Bold.ttf",
          sha256: "7f738fe5c43c8872807b20e2d30d42163618de8a4daf7f48a939adac32c16847"
        ),
        VideoEditorCatalogFontAsset(
          relativePath: "bevietnampro/BeVietnamPro-ExtraBold.ttf",
          fileName: "BeVietnamPro-ExtraBold.ttf",
          sha256: "44dbfa01553d227bec76ba6446c5618870a76a4a3297f41630dde859d0650d02"
        ),
        VideoEditorCatalogFontAsset(
          relativePath: "bevietnampro/BeVietnamPro-Black.ttf",
          fileName: "BeVietnamPro-Black.ttf",
          sha256: "dd0ec461782da7f4a58698b431a67c455ced7c09deb9c40d7b47e61975d3ffdb"
        ),
        VideoEditorCatalogFontAsset(
          relativePath: "bevietnampro/BeVietnamPro-Italic.ttf",
          fileName: "BeVietnamPro-Italic.ttf",
          sha256: "a33ebb3f68e0e260a7d3874d64259ad309971a2daf969e7ce5f444d70bce535f"
        ),
        VideoEditorCatalogFontAsset(
          relativePath: "bevietnampro/BeVietnamPro-BoldItalic.ttf",
          fileName: "BeVietnamPro-BoldItalic.ttf",
          sha256: "a2a65bdf9b251beb3d658ae691889d71ce63c0290940c87ca60b449ceb0bdaee"
        ),
      ],
      licenseAsset: VideoEditorCatalogFontAsset(
        relativePath: "bevietnampro/OFL.txt",
        fileName: "OFL.txt",
        sha256: "6b7f8f73609a25ea78c891e34cf37b06f8a676b7ea986e941e43b009110f2a85"
      )
    ),
    VideoEditorCatalogFontFamily(
      id: "inter",
      displayName: "Inter",
      categoryLabel: "UI Neo-Grotesque",
      files: [
        VideoEditorCatalogFontAsset(
          relativePath: "inter/Inter%5Bopsz,wght%5D.ttf",
          fileName: "Inter[opsz,wght].ttf",
          sha256: "29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"
        ),
        VideoEditorCatalogFontAsset(
          relativePath: "inter/Inter-Italic%5Bopsz,wght%5D.ttf",
          fileName: "Inter-Italic[opsz,wght].ttf",
          sha256: "acd98e64795781b2058f07b18475e0ecee2a0fe2b42a49e2f9e37d0d6bf66ce6"
        ),
      ],
      licenseAsset: VideoEditorCatalogFontAsset(
        relativePath: "inter/OFL.txt",
        fileName: "OFL.txt",
        sha256: "5b9321a4298cfeb6b34354164a1c3afc3db114569984c502b9b35d988fd58c57"
      )
    ),
    VideoEditorCatalogFontFamily(
      id: "plus-jakarta-sans",
      displayName: "Plus Jakarta Sans",
      categoryLabel: "Modern Display",
      files: [
        VideoEditorCatalogFontAsset(
          relativePath: "plusjakartasans/PlusJakartaSans%5Bwght%5D.ttf",
          fileName: "PlusJakartaSans[wght].ttf",
          sha256: "89b3fb38aa0d275d7a731d0d817a4f1622b316b4d7fbdedcf02ee9099ff68bc8"
        ),
        VideoEditorCatalogFontAsset(
          relativePath: "plusjakartasans/PlusJakartaSans-Italic%5Bwght%5D.ttf",
          fileName: "PlusJakartaSans-Italic[wght].ttf",
          sha256: "9529eb888668b6a3c6dd75b6341a2fc5263fb6c9e788822e6117c29dd9e8b115"
        ),
      ],
      licenseAsset: VideoEditorCatalogFontAsset(
        relativePath: "plusjakartasans/OFL.txt",
        fileName: "OFL.txt",
        sha256: "995c7199cab65954f545996326755daee7b63cc6b42b06c13da1f9502ab08a99"
      )
    ),
    VideoEditorCatalogFontFamily(
      id: "playfair-display",
      displayName: "Playfair Display",
      categoryLabel: "High-Contrast Serif",
      files: [
        VideoEditorCatalogFontAsset(
          relativePath: "playfairdisplay/PlayfairDisplay%5Bwght%5D.ttf",
          fileName: "PlayfairDisplay[wght].ttf",
          sha256: "c40f2293766a503bc70cce9e512ef844a4ccb7cbcde792fe2ea31d191917d8d6"
        ),
        VideoEditorCatalogFontAsset(
          relativePath: "playfairdisplay/PlayfairDisplay-Italic%5Bwght%5D.ttf",
          fileName: "PlayfairDisplay-Italic[wght].ttf",
          sha256: "a5e26dc5e2e77fb2803a0bf02fd4f81ee136ec8dea863ccdb0c59a263b21378b"
        ),
      ],
      licenseAsset: VideoEditorCatalogFontAsset(
        relativePath: "playfairdisplay/OFL.txt",
        fileName: "OFL.txt",
        sha256: "566be814f8e96e93dfa16101331557eb6b5467e9e03f627c0910fe93ca12300e"
      )
    ),
    VideoEditorCatalogFontFamily(
      id: "space-grotesk",
      displayName: "Space Grotesk",
      categoryLabel: "Tech Headline",
      files: [
        VideoEditorCatalogFontAsset(
          relativePath: "spacegrotesk/SpaceGrotesk%5Bwght%5D.ttf",
          fileName: "SpaceGrotesk[wght].ttf",
          sha256: "acad6de1fc93436f5c0f1f4137751ef04f1aea3063e7036535970ffcfbd79f72"
        ),
      ],
      licenseAsset: VideoEditorCatalogFontAsset(
        relativePath: "spacegrotesk/OFL.txt",
        fileName: "OFL.txt",
        sha256: "564ce565c371c5e5bbf286006565a7c9aa55a9f56e7ca58d56e05d649dd61a72"
      )
    ),
    VideoEditorCatalogFontFamily(
      id: "jetbrains-mono",
      displayName: "JetBrains Mono",
      categoryLabel: "Developer Mono",
      files: [
        VideoEditorCatalogFontAsset(
          relativePath: "jetbrainsmono/JetBrainsMono%5Bwght%5D.ttf",
          fileName: "JetBrainsMono[wght].ttf",
          sha256: "48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"
        ),
        VideoEditorCatalogFontAsset(
          relativePath: "jetbrainsmono/JetBrainsMono-Italic%5Bwght%5D.ttf",
          fileName: "JetBrainsMono-Italic[wght].ttf",
          sha256: "85ae2a5cd3f56baf1ce1c21a851322c58e3d8fbe8e8ad4a4d090a820dd7fe558"
        ),
      ],
      licenseAsset: VideoEditorCatalogFontAsset(
        relativePath: "jetbrainsmono/OFL.txt",
        fileName: "OFL.txt",
        sha256: "b2fe5e8987594e9ffd1d2ca52a2f5d73eb8335243893c5d6254b5ad69269591d"
      )
    ),
    VideoEditorCatalogFontFamily(
      id: "oswald",
      displayName: "Oswald",
      categoryLabel: "Condensed Impact",
      files: [
        VideoEditorCatalogFontAsset(
          relativePath: "oswald/Oswald%5Bwght%5D.ttf",
          fileName: "Oswald[wght].ttf",
          sha256: "5b38c246e255a12f5712d640d56bcced0672466fc68983d2d0410ec0457c2817"
        ),
      ],
      licenseAsset: VideoEditorCatalogFontAsset(
        relativePath: "oswald/OFL.txt",
        fileName: "OFL.txt",
        sha256: "0fd731a904b729a4e02eaf5e8ebd06783edd9abe400e8882760160230675b652"
      )
    ),
  ]

  @Published private(set) var installedFamilies: [VideoEditorInstalledFontFamily] = []
  @Published private(set) var downloadedCatalogIds: Set<String> = []
  @Published private(set) var downloadingIds: Set<String> = []
  @Published private(set) var importedFonts: [VideoEditorImportedFontRecord] = []
  @Published private(set) var lastErrorMessage: String?
  @Published private(set) var revision: Int = 0

  private static let maxManifestBytes: Int = 1_048_576
  private static let maxLicenseBytes: Int = 262_144
  private static let maxImportedFontFileBytes: Int = 33_554_432

  let storageRootURL: URL
  private let urlSessionConfiguration: URLSessionConfiguration

  private var manifestURL: URL {
    storageRootURL.appendingPathComponent("imported_fonts.json")
  }

  init(
    storageRootURL: URL = VideoEditorFontResolver.storageRootURL(),
    urlSessionConfiguration: URLSessionConfiguration? = nil
  ) {
    self.storageRootURL = storageRootURL
    if let urlSessionConfiguration {
      self.urlSessionConfiguration = urlSessionConfiguration
    } else {
      let config = URLSessionConfiguration.default
      config.timeoutIntervalForRequest = 30
      config.timeoutIntervalForResource = 60
      config.waitsForConnectivity = false
      self.urlSessionConfiguration = config
    }
    VideoEditorFontResolver.ensureBootstrapped()
    if storageRootURL != VideoEditorFontResolver.storageRootURL() {
      VideoEditorFontResolver.registerStoredFonts(under: storageRootURL)
    }
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

    var detectedCatalog: Set<String> = []
    for family in Self.curatedCatalog {
      let dir = storageRootURL.appendingPathComponent(family.id, isDirectory: true)
      let licenseURL = dir.appendingPathComponent(family.licenseAsset.fileName)
      let hasAllFiles = family.files.allSatisfy { asset in
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(asset.fileName).path)
      } && FileManager.default.fileExists(atPath: licenseURL.path)
      if hasAllFiles, VideoEditorFontResolver.isFamilyRegistered(family.id) {
        detectedCatalog.insert(family.id)
      }
    }
    downloadedCatalogIds = detectedCatalog

    if let data = try? VideoEditorFontResolver.readBoundedData(from: manifestURL, maxBytes: Self.maxManifestBytes),
       let decoded = try? JSONDecoder().decode([VideoEditorImportedFontRecord].self, from: data) {
      importedFonts = Array(decoded.prefix(500)).filter { VideoEditorFontResolver.isFamilyRegistered($0.id) }
    } else {
      importedFonts = []
    }
  }

  func isFontAvailable(_ familyId: String) -> Bool {
    if downloadedCatalogIds.contains(familyId) {
      return true
    }
    return VideoEditorFontResolver.isFamilyAvailable(familyId)
  }

  func displayName(for familyId: String) -> String {
    if familyId.isEmpty || familyId == VideoEditorFontResolver.defaultFamilyId {
      return L10n.VideoEditor.systemFontDisplayName
    }
    if let catalog = Self.curatedCatalog.first(where: { $0.id == familyId }) {
      return catalog.displayName
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

  /// Returns the locally stored `OFL.txt` license text for a downloaded catalog family.
  func licenseText(for familyId: String) -> String? {
    let safeComponent = URL(fileURLWithPath: familyId).lastPathComponent
    guard !safeComponent.isEmpty else { return nil }
    let licenseURL = storageRootURL
      .appendingPathComponent(safeComponent, isDirectory: true)
      .appendingPathComponent("OFL.txt")
    guard let data = try? VideoEditorFontResolver.readBoundedData(from: licenseURL, maxBytes: Self.maxLicenseBytes)
    else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  /// Opt-in user-initiated download of a SIL Open Font License 1.1 family from the pinned
  /// `google/fonts` commit. Performs HTTP transfer, 5 MB cap enforcement, SHA-256 verification,
  /// atomic file staging, and CoreText registration entirely off `@MainActor`.
  func downloadCatalogFont(_ family: VideoEditorCatalogFontFamily) async throws {
    guard !downloadingIds.contains(family.id) else { return }
    downloadingIds.insert(family.id)
    lastErrorMessage = nil
    defer { downloadingIds.remove(family.id) }

    let rootURL = storageRootURL
    let sessionConfig = urlSessionConfiguration
    let maxBytes = Self.maxDownloadAssetBytes

    do {
      try await Task.detached(priority: .userInitiated) {
        try await Self.fetchVerifyStageAndRegister(
          family: family,
          storageRootURL: rootURL,
          sessionConfiguration: sessionConfig,
          maxBytes: maxBytes
        )
      }.value
      downloadedCatalogIds.insert(family.id)
      lastErrorMessage = nil
      revision += 1
    } catch {
      lastErrorMessage = error.localizedDescription
      throw error
    }
  }

  nonisolated static func sha256Hex(of data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  private nonisolated static func fetchBoundedData(
    from url: URL,
    sessionConfiguration: URLSessionConfiguration,
    maxBytes: Int
  ) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      let delegate = BoundedFontDataDelegate(maxBytes: maxBytes, continuation: continuation)
      let session = URLSession(configuration: sessionConfiguration, delegate: delegate, delegateQueue: nil)
      var request = URLRequest(url: url)
      request.cachePolicy = .reloadIgnoringLocalCacheData
      let task = session.dataTask(with: request)
      task.resume()
      session.finishTasksAndInvalidate()
    }
  }

  private nonisolated static func fetchVerifyStageAndRegister(
    family: VideoEditorCatalogFontFamily,
    storageRootURL: URL,
    sessionConfiguration: URLSessionConfiguration,
    maxBytes: Int
  ) async throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: storageRootURL, withIntermediateDirectories: true)

    let safeId = URL(fileURLWithPath: family.id).lastPathComponent
    let stagingDir = storageRootURL.appendingPathComponent(".staging-\(safeId)-\(UUID().uuidString)", isDirectory: true)
    let destDir = storageRootURL.appendingPathComponent(safeId, isDirectory: true)
    try fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: stagingDir) }

    let allAssets = family.files + [family.licenseAsset]
    for asset in allAssets {
      guard let url = asset.downloadURL else {
        throw VideoEditorFontDownloadError.invalidURL(asset.relativePath)
      }
      let data = try await fetchBoundedData(
        from: url,
        sessionConfiguration: sessionConfiguration,
        maxBytes: maxBytes
      )
      let actualHash = sha256Hex(of: data)
      guard actualHash == asset.sha256.lowercased() else {
        throw VideoEditorFontDownloadError.checksumMismatch(fileName: asset.fileName)
      }
      let safeFileName = URL(fileURLWithPath: asset.fileName).lastPathComponent
      let stagedFileURL = stagingDir.appendingPathComponent(safeFileName)
      try data.write(to: stagedFileURL, options: .atomic)
    }

    if fileManager.fileExists(atPath: destDir.path) {
      _ = try fileManager.replaceItemAt(destDir, withItemAt: stagingDir)
    } else {
      try fileManager.moveItem(at: stagingDir, to: destDir)
    }

    let fontURLs = family.files.map { asset in
      destDir.appendingPathComponent(URL(fileURLWithPath: asset.fileName).lastPathComponent)
    }
    guard VideoEditorFontResolver.registerFontFiles(urls: fontURLs, forFamilyId: family.id) != nil else {
      try? fileManager.removeItem(at: destDir)
      throw VideoEditorFontDownloadError.registrationFailed(family.displayName)
    }
  }

  @discardableResult
  func importFontFiles(from urls: [URL]) -> String? {
    let valid = urls.filter { ["ttf", "otf", "ttc"].contains($0.pathExtension.lowercased()) }
    guard !valid.isEmpty else { return nil }

    let slugBase = valid[0].deletingPathExtension().lastPathComponent
      .lowercased()
      .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    let familyId = "custom-\(slugBase.isEmpty ? UUID().uuidString.prefix(8).lowercased() : slugBase)"
    let destDir = storageRootURL.appendingPathComponent(familyId, isDirectory: true)

    do {
      try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
      var copiedURLs: [URL] = []
      var copiedNames: [String] = []
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
              size <= Self.maxImportedFontFileBytes
        else {
          throw CocoaError(.fileReadTooLarge)
        }
        let safeFileName = URL(fileURLWithPath: src.lastPathComponent).lastPathComponent
        let dst = destDir.appendingPathComponent(safeFileName)
        if FileManager.default.fileExists(atPath: dst.path) {
          try FileManager.default.removeItem(at: dst)
        }
        try FileManager.default.copyItem(at: src, to: dst)
        copiedURLs.append(dst)
        copiedNames.append(safeFileName)
      }

      guard let familyName = VideoEditorFontResolver.registerFontFiles(urls: copiedURLs, forFamilyId: familyId) else {
        try? FileManager.default.removeItem(at: destDir)
        return nil
      }

      let record = VideoEditorImportedFontRecord(
        id: familyId,
        displayName: familyName,
        filenames: copiedNames
      )
      importedFonts.removeAll { $0.id == familyId }
      importedFonts.append(record)
      persistManifest()
      lastErrorMessage = nil
      revision += 1
      return familyId
    } catch {
      lastErrorMessage = error.localizedDescription
      return nil
    }
  }

  private func persistManifest() {
    guard let data = try? JSONEncoder().encode(importedFonts) else { return }
    try? FileManager.default.createDirectory(
      at: storageRootURL,
      withIntermediateDirectories: true
    )
    try? data.write(to: manifestURL, options: .atomic)
  }
}
