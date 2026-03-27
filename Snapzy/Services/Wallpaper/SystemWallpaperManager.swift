//
//  SystemWallpaperManager.swift
//  Snapzy
//
//  Service to enumerate and manage macOS system wallpapers
//

import AppKit
import Combine
import Foundation

class SystemWallpaperManager: ObservableObject {
  static let shared = SystemWallpaperManager()

  @Published var systemWallpapers: [WallpaperItem] = []
  @Published var isLoading = false
  @Published var accessDenied = false

  // MARK: - Thumbnail Cache (Performance Optimization)

  private let thumbnailCache = NSCache<NSURL, NSImage>()
  private let thumbnailSize: CGFloat = 96  // 48pt grid item @2x retina
  private var loadingURLs = Set<URL>()
  private let cacheQueue = DispatchQueue(label: "wallpaper.thumbnail.cache", qos: .userInitiated)
  private let defaultSystemWallpaperLimit = 3

  // MARK: - Preview Cache (Canvas Display Optimization)

  private let previewCache = NSCache<NSURL, NSImage>()

  /// Preview size from config (default 2048px for retina 1024pt)
  private var previewSize: CGFloat { WallpaperQualityConfig.maxResolution }

  private let systemWallpaperPaths = [
    "/System/Library/Desktop Pictures",
    "/Library/Desktop Pictures",
  ]

  private let supportedExtensions = ["heic", "jpg", "jpeg", "png"]
  private let wallpaperBookmarkKey = PreferencesKeys.wallpaperDirectoryBookmark

  struct WallpaperItem: Identifiable, Hashable {
    var id: URL { fullImageURL }
    let fullImageURL: URL
    let thumbnailURL: URL?
    let name: String

    func hash(into hasher: inout Hasher) {
      hasher.combine(fullImageURL)
    }

    static func == (lhs: WallpaperItem, rhs: WallpaperItem) -> Bool {
      lhs.fullImageURL == rhs.fullImageURL
    }
  }

  private init() {
    // Configure cache limits
    thumbnailCache.countLimit = 100
    thumbnailCache.totalCostLimit = 50 * 1024 * 1024  // 50MB max

    // Preview cache: fewer items but larger (2048px images ~4MB each)
    previewCache.countLimit = 20
    previewCache.totalCostLimit = 100 * 1024 * 1024  // 100MB max
  }

  // MARK: - Cached Thumbnail Access

  /// Get cached thumbnail or nil if not yet loaded
  func cachedThumbnail(for url: URL) -> NSImage? {
    thumbnailCache.object(forKey: url as NSURL)
  }

  /// Load and cache thumbnail with downsampling (async, non-blocking)
  func loadThumbnail(for item: WallpaperItem, completion: @escaping (NSImage?) -> Void) {
    let url = item.thumbnailURL ?? item.fullImageURL

    // Check cache first
    if let cached = thumbnailCache.object(forKey: url as NSURL) {
      completion(cached)
      return
    }

    // Prevent duplicate loads
    cacheQueue.sync {
      guard !loadingURLs.contains(url) else {
        completion(nil)
        return
      }
      loadingURLs.insert(url)
    }

    // Load and downsample on background thread
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else { return }

      let thumbnail = self.createDownsampledThumbnail(from: url)

      if let thumbnail = thumbnail {
        self.thumbnailCache.setObject(thumbnail, forKey: url as NSURL)
      }

      self.cacheQueue.sync {
        _ = self.loadingURLs.remove(url)
      }

      DispatchQueue.main.async {
        completion(thumbnail)
      }
    }
  }

  /// Create downsampled thumbnail using ImageIO (memory efficient)
  private func createDownsampledThumbnail(from url: URL) -> NSImage? {
    createDownsampledImage(from: url, maxSize: thumbnailSize)
  }

  /// Create downsampled image using ImageIO (memory efficient)
  /// - Parameters:
  ///   - url: Source image URL
  ///   - maxSize: Maximum pixel dimension for the output
  private func createDownsampledImage(from url: URL, maxSize: CGFloat) -> NSImage? {
    let options: [CFString: Any] = [
      kCGImageSourceShouldCache: false
    ]

    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
      return nil
    }

    // Get source image dimensions to avoid requesting thumbnail larger than source
    // This prevents "kCGImageSourceThumbnailMaxPixelSize is larger than image-dimension" warnings
    var effectiveMaxSize = maxSize
    if let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
       let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
       let height = properties[kCGImagePropertyPixelHeight] as? CGFloat {
      let sourceMaxDimension = max(width, height)
      effectiveMaxSize = min(maxSize, sourceMaxDimension)
    }

    let downsampleOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: effectiveMaxSize
    ]

    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions as CFDictionary) else {
      return nil
    }

    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
  }

  // MARK: - Preview Image Loading (Canvas Display)

  /// Load preview-sized image for canvas display (2048px max dimension)
  /// Uses ImageIO downsampling for memory efficiency (~4MB vs 50MB+ full-res)
  func loadPreviewImage(for url: URL, completion: @escaping (NSImage?) -> Void) {
    // Check cache first
    if let cached = previewCache.object(forKey: url as NSURL) {
      completion(cached)
      return
    }

    // Load and downsample on background thread
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else { return }

      let preview = self.createDownsampledImage(from: url, maxSize: self.previewSize)

      if let preview = preview {
        self.previewCache.setObject(preview, forKey: url as NSURL)
      }

      DispatchQueue.main.async {
        completion(preview)
      }
    }
  }

  /// Preload visible thumbnails (call when view appears)
  func preloadThumbnails(for items: [WallpaperItem]) {
    for item in items.prefix(6) {  // Keep preloading lightweight to avoid sidebar jank
      loadThumbnail(for: item) { _ in }
    }
  }

  @MainActor
  func loadSystemWallpapers() async {
    guard !isLoading else { return }
    guard systemWallpapers.isEmpty else { return }  // Only load once
    isLoading = true
    accessDenied = false

    var wallpapers = await Task.detached(priority: .userInitiated) {
      self.enumerateAllDirectories()
    }.value

    if wallpapers.isEmpty, let persistedDirectory = loadPersistedWallpaperDirectoryURL() {
      let didStartAccess = persistedDirectory.startAccessingSecurityScopedResource()
      wallpapers = enumerateUserSelectedDirectory(persistedDirectory)
      if didStartAccess {
        persistedDirectory.stopAccessingSecurityScopedResource()
      }
    }

    if wallpapers.isEmpty && !hasAccessibleDirectory() && loadPersistedWallpaperDirectoryURL() == nil {
      accessDenied = true
    }

    let limitedWallpapers = Array(wallpapers.prefix(defaultSystemWallpaperLimit))
    systemWallpapers = limitedWallpapers
    isLoading = false

    // Preload first batch of thumbnails
    preloadThumbnails(for: limitedWallpapers)
  }

  /// Load currently active desktop wallpaper(s) from display settings.
  /// By default this returns the wallpaper for the preferred/active screen only.
  /// Set includeAllScreens to true to return unique wallpapers across all screens.
  @MainActor
  func loadCurrentDesktopWallpapers(
    preferredDisplayID: CGDirectDisplayID? = nil,
    includeAllScreens: Bool = false
  ) async -> [WallpaperItem] {
    guard !isLoading else { return [] }
    isLoading = true
    accessDenied = false
    defer { isLoading = false }

    let wallpapers = enumerateCurrentDesktopWallpapers(
      preferredDisplayID: preferredDisplayID,
      includeAllScreens: includeAllScreens
    )
    accessDenied = wallpapers.isEmpty

    // Preload visible thumbnails for fast first paint in the sidebar.
    preloadThumbnails(for: wallpapers)
    return wallpapers
  }

  private func hasAccessibleDirectory() -> Bool {
    systemWallpaperPaths.contains { canAccessDirectory($0) }
  }

  private func canAccessDirectory(_ path: String) -> Bool {
    FileManager.default.isReadableFile(atPath: path)
  }

  private func enumerateAllDirectories() -> [WallpaperItem] {
    var items: [WallpaperItem] = []
    let fm = FileManager.default

    for basePath in systemWallpaperPaths {
      guard canAccessDirectory(basePath) else { continue }

      let baseURL = URL(fileURLWithPath: basePath)
      guard
        let contents = try? fm.contentsOfDirectory(
          at: baseURL,
          includingPropertiesForKeys: [.isRegularFileKey],
          options: [.skipsHiddenFiles]
        )
      else { continue }

      for url in contents {
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { continue }

        let name = url.deletingPathExtension().lastPathComponent
        let thumbnail = thumbnailURL(for: url, basePath: basePath)

        items.append(
          WallpaperItem(
            fullImageURL: url,
            thumbnailURL: thumbnail,
            name: name
          ))
      }
    }

    return items.sorted { $0.name < $1.name }
  }

  private func enumerateCurrentDesktopWallpapers(
    preferredDisplayID: CGDirectDisplayID?,
    includeAllScreens: Bool
  ) -> [WallpaperItem] {
    var items: [WallpaperItem] = []
    var seenURLs = Set<URL>()

    let resolvedPreferredScreen =
      preferredDisplayID.flatMap(findScreen(by:))
      ?? NSApp.keyWindow?.screen
      ?? NSApp.mainWindow?.screen
      ?? NSScreen.main
      ?? NSScreen.screens.first

    let screens: [NSScreen]
    if includeAllScreens {
      screens = NSScreen.screens.isEmpty ? [resolvedPreferredScreen].compactMap { $0 } : NSScreen.screens
    } else {
      screens = [resolvedPreferredScreen].compactMap { $0 }
    }

    for screen in screens {
      guard let wallpaperURL = NSWorkspace.shared.desktopImageURL(for: screen) else { continue }
      let resolvedURL = wallpaperURL.standardizedFileURL
      guard seenURLs.insert(resolvedURL).inserted else { continue }

      items.append(
        WallpaperItem(
          fullImageURL: resolvedURL,
          thumbnailURL: nil,
          name: resolvedURL.deletingPathExtension().lastPathComponent
        ))
    }

    return items.sorted { $0.name < $1.name }
  }

  private func findScreen(by displayID: CGDirectDisplayID) -> NSScreen? {
    NSScreen.screens.first { screen in
      guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
      else { return false }
      return CGDirectDisplayID(screenNumber.uint32Value) == displayID
    }
  }

  private func thumbnailURL(for wallpaper: URL, basePath: String) -> URL? {
    let thumbnailDir = URL(fileURLWithPath: basePath)
      .appendingPathComponent(".thumbnails")
    let thumbnailFile =
      thumbnailDir
      .appendingPathComponent(wallpaper.deletingPathExtension().lastPathComponent)
      .appendingPathExtension("heic")

    return FileManager.default.fileExists(atPath: thumbnailFile.path)
      ? thumbnailFile
      : nil
  }

  /// Fallback: Request user to manually grant access via NSOpenPanel
  @MainActor
  func requestUserAccess() async -> [URL]? {
    let panel = NSOpenPanel()
    panel.message = "Select the Desktop Pictures folder to grant access"
    panel.prompt = "Grant Access"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = URL(fileURLWithPath: "/System/Library/Desktop Pictures")

    let response = await panel.begin()
    guard response == .OK, let url = panel.url else { return nil }

    saveWallpaperBookmark(for: url)

    // Enumerate user-selected directory
    let items = enumerateUserSelectedDirectory(url)
    let limitedItems = Array(items.prefix(defaultSystemWallpaperLimit))
    if !limitedItems.isEmpty {
      systemWallpapers = limitedItems
      accessDenied = false
    }
    return items.isEmpty ? nil : [url]
  }

  private func enumerateUserSelectedDirectory(_ directoryURL: URL) -> [WallpaperItem] {
    var items: [WallpaperItem] = []
    let fm = FileManager.default

    guard
      let contents = try? fm.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else { return [] }

    for url in contents {
      let ext = url.pathExtension.lowercased()
      guard supportedExtensions.contains(ext) else { continue }

      let name = url.deletingPathExtension().lastPathComponent
      let thumbnail = thumbnailURL(for: url, basePath: directoryURL.path)

      items.append(
        WallpaperItem(
          fullImageURL: url,
          thumbnailURL: thumbnail,
          name: name
        ))
    }

    return items.sorted { $0.name < $1.name }
  }

  private func saveWallpaperBookmark(for directoryURL: URL) {
    do {
      let bookmarkData = try directoryURL.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      UserDefaults.standard.set(bookmarkData, forKey: wallpaperBookmarkKey)
    } catch {
      UserDefaults.standard.removeObject(forKey: wallpaperBookmarkKey)
    }
  }

  private func loadPersistedWallpaperDirectoryURL() -> URL? {
    guard let bookmarkData = UserDefaults.standard.data(forKey: wallpaperBookmarkKey) else {
      return nil
    }

    var isStale = false
    do {
      let url = try URL(
        resolvingBookmarkData: bookmarkData,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )

      if isStale {
        saveWallpaperBookmark(for: url)
      }

      return url
    } catch {
      UserDefaults.standard.removeObject(forKey: wallpaperBookmarkKey)
      return nil
    }
  }
}
