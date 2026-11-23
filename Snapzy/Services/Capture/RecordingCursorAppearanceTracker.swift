//
//  RecordingCursorAppearanceTracker.swift
//  Snapzy
//
//  Studio recording: records which system cursor is visible (arrow, I-beam, ...) and
//  every click, on the same clock and pause-exclusion as `RecordingMouseTracker`, so
//  the editor and the flatten pass can redraw the cursor exactly.
//

import AppKit
import Foundation

@MainActor
final class RecordingCursorAppearanceTracker {
  private struct StoredImage {
    let image: RecordedCursorImage
    let pngData: Data
  }

  private static let pollInterval: TimeInterval = 1.0 / 30.0

  private let mouseTracker: RecordingMouseTracker
  private let cursorProvider: () -> NSCursor?

  private var timer: Timer?
  private var monitors: [Any] = []
  private var imagesByHash: [Int: StoredImage] = [:]
  /// Pixel fingerprint → image ID. Keyed by content, never by `ObjectIdentifier` (see `imageID(for:)`).
  private var imageIDByFingerprint: [Int: Int] = [:]
  /// Last polled cursor, retained so the identity fast path can't hit a recycled address.
  private var lastResolvedCursor: (cursor: NSCursor, id: Int)?
  private var appearance: [RecordedCursorChange] = []
  private var clicks: [RecordedClick] = []
  private var pressedButtons: Set<RecordedClickButton> = []

  init(
    mouseTracker: RecordingMouseTracker,
    cursorProvider: @escaping () -> NSCursor? = { NSCursor.currentSystem }
  ) {
    self.mouseTracker = mouseTracker
    self.cursorProvider = cursorProvider
  }

  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}

  /// Call right after `mouseTracker.start()`.
  func start() {
    reset()
    poll()
    let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in self?.poll() }
    }
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
    installClickMonitors()
  }

  /// Stops capturing and returns the captured data (image PNGs not written yet).
  func stop() -> RecordingCursorCapture {
    teardown()
    return RecordingCursorCapture(
      images: imagesByHash.values.map(\.image).sorted { $0.id < $1.id },
      appearance: appearance,
      clicks: clicks
    )
  }

  /// Writes every captured cursor PNG into `folder` (created if needed).
  func writeImages(to folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for stored in imagesByHash.values {
      try stored.pngData.write(to: folder.appendingPathComponent(stored.image.fileName), options: .atomic)
    }
  }

  var hasImages: Bool { !imagesByHash.isEmpty }

  func reset() {
    teardown()
    imagesByHash.removeAll()
    imageIDByFingerprint.removeAll()
    lastResolvedCursor = nil
    appearance.removeAll()
    clicks.removeAll()
    pressedButtons.removeAll()
  }

  // MARK: - Appearance

  /// Samples the visible cursor now (timer-driven; internal for tests).
  func poll() {
    guard mouseTracker.isRunning, !mouseTracker.isPaused, let time = mouseTracker.elapsedTime else { return }
    let cursor = cursorProvider()
    let imageID = cursor.flatMap(imageID(for:))
    let change = RecordedCursorChange(time: time, imageID: imageID, isHidden: cursor == nil)
    if let last = appearance.last, last.imageID == change.imageID, last.isHidden == change.isHidden {
      return
    }
    appearance.append(change)
  }

  /// Resolves the captured image ID for `cursor` by its pixels, never by object identity:
  /// `NSCursor.currentSystem` returns a fresh object on every poll, and a freed cursor's address
  /// is routinely reused by the next one, so an `ObjectIdentifier` cache maps an I-beam onto a
  /// stale arrow ID (the cursor then flickers between shapes on playback).
  private func imageID(for cursor: NSCursor) -> Int? {
    // Fast path: the very same object as last poll. Held strongly, so its address can't be reused.
    if let last = lastResolvedCursor, last.cursor === cursor { return last.id }
    guard let raster = Self.rasterize(cursor) else { return nil }

    let fingerprint = Self.fingerprint(of: raster.cgImage, hotspot: cursor.hotSpot)
    if let cached = imageIDByFingerprint[fingerprint] {
      lastResolvedCursor = (cursor, cached)
      return cached
    }
    guard let encoded = Self.encode(cursor, raster: raster) else { return nil }

    var hasher = Hasher()
    hasher.combine(encoded.pngData)
    hasher.combine(encoded.hotspot.x)
    hasher.combine(encoded.hotspot.y)
    let hash = hasher.finalize()

    let id: Int
    if let existing = imagesByHash[hash] {
      id = existing.image.id
    } else {
      id = imagesByHash.count
      let image = RecordedCursorImage(
        id: id,
        fileName: "cursor-\(id).png",
        hotspot: encoded.hotspot,
        pointSize: encoded.pointSize,
        scale: encoded.scale
      )
      imagesByHash[hash] = StoredImage(image: image, pngData: encoded.pngData)
    }
    imageIDByFingerprint[fingerprint] = id
    lastResolvedCursor = (cursor, id)
    return id
  }

  private static func rasterize(_ cursor: NSCursor) -> (cgImage: CGImage, pointSize: CGSize)? {
    let image = cursor.image
    let pointSize = image.size
    guard pointSize.width > 0, pointSize.height > 0 else { return nil }
    // Ask for a 2x rect so Retina representations win when present.
    var rect = CGRect(origin: .zero, size: CGSize(width: pointSize.width * 2, height: pointSize.height * 2))
    guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
    return (cgImage, pointSize)
  }

  /// Cheap per-poll identity of a cursor's look: raw pixel bytes + geometry + hotspot.
  private static func fingerprint(of cgImage: CGImage, hotspot: CGPoint) -> Int {
    var hasher = Hasher()
    hasher.combine(cgImage.width)
    hasher.combine(cgImage.height)
    hasher.combine(cgImage.bytesPerRow)
    hasher.combine(cgImage.bitmapInfo.rawValue)
    if let data = cgImage.dataProvider?.data as Data? {
      hasher.combine(data)
    }
    hasher.combine(hotspot.x)
    hasher.combine(hotspot.y)
    return hasher.finalize()
  }

  private static func encode(
    _ cursor: NSCursor,
    raster: (cgImage: CGImage, pointSize: CGSize)
  ) -> (pngData: Data, hotspot: CGPoint, pointSize: CGSize, scale: CGFloat)? {
    guard let png = NSBitmapImageRep(cgImage: raster.cgImage).representation(using: .png, properties: [:])
    else { return nil }
    return (png, cursor.hotSpot, raster.pointSize, CGFloat(raster.cgImage.width) / raster.pointSize.width)
  }

  // MARK: - Clicks

  private func installClickMonitors() {
    let mask: NSEvent.EventTypeMask = [
      .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
    ]
    if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
      let type = event.type
      MainActor.assumeIsolated { self?.record(type) }
    }) {
      monitors.append(global)
    }
    if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
      let type = event.type
      MainActor.assumeIsolated { self?.record(type) }
      return event
    }) {
      monitors.append(local)
    }
  }

  /// Records a click event at `location` (AppKit global coordinates).
  func record(_ type: NSEvent.EventType, location: CGPoint = NSEvent.mouseLocation) {
    guard let (button, phase) = Self.classify(type),
          mouseTracker.isRunning, !mouseTracker.isPaused,
          let time = mouseTracker.elapsedTime
    else { return }
    let rect = mouseTracker.captureRect
    switch phase {
    case .down:
      guard rect.contains(location) else { return }
      pressedButtons.insert(button)
    case .up:
      guard pressedButtons.remove(button) != nil else { return }
    }
    clicks.append(RecordedClick(
      time: time,
      button: button,
      phase: phase,
      normalizedX: Self.clamp((location.x - rect.minX) / max(rect.width, 1)),
      normalizedY: Self.clamp(1 - (location.y - rect.minY) / max(rect.height, 1))
    ))
  }

  nonisolated static func classify(_ type: NSEvent.EventType) -> (RecordedClickButton, RecordedClickPhase)? {
    switch type {
    case .leftMouseDown: (.left, .down)
    case .leftMouseUp: (.left, .up)
    case .rightMouseDown: (.right, .down)
    case .rightMouseUp: (.right, .up)
    case .otherMouseDown: (.other, .down)
    case .otherMouseUp: (.other, .up)
    default: nil
    }
  }

  private static func clamp(_ value: CGFloat) -> CGFloat { min(max(value, 0), 1) }

  private func teardown() {
    timer?.invalidate()
    timer = nil
    monitors.forEach(NSEvent.removeMonitor)
    monitors.removeAll()
  }
}
