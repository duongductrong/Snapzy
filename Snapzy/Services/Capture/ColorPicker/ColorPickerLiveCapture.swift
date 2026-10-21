//
//  ColorPickerLiveCapture.swift
//  Snapzy
//
//  Live pixels for Pick Color: the display under the pointer is streamed through
//  ScreenCaptureKit at native resolution and only the newest frame is kept, so the loupe
//  reads what is on screen right now — video and animations keep playing — without
//  freezing the display or copying whole frames.
//

import AppKit
import CoreMedia
import CoreVideo
import ScreenCaptureKit

/// Where the loupe reads pixels from: a live display stream, or a still image in tests.
protocol ColorPickerPixelSource: AnyObject {
  /// Pixel size of the content, or nil until the first frame arrives.
  var pixelSize: (width: Int, height: Int)? { get }
  /// Called on the main thread whenever new content is available.
  var onUpdate: (() -> Void)? { get set }
  func neighborhood(of pixel: ColorPickerPixel, radius: Int) -> CGImage?
  func color(of pixel: ColorPickerPixel) -> ColorPickerColor?
  /// Starts delivering content. Idempotent.
  func start() async throws
  /// Stops delivering content and drops what was delivered, so a restart never shows stale pixels.
  func stop()
}

/// Supplies one pixel source per display for a Pick Color session.
protocol ColorPickerCapturing: AnyObject {
  /// Called once the overlays are on screen, so they can be left out of the capture.
  func prepare(excludingWindowNumbers windowNumbers: [Int]) async throws
  func source(for screen: NSScreen) -> ColorPickerPixelSource?
}

// MARK: - ScreenCaptureKit

final class ColorPickerScreenCapture: ColorPickerCapturing {
  private var content: SCShareableContent?
  private var excludedWindows: [SCWindow] = []

  func prepare(excludingWindowNumbers windowNumbers: [Int]) async throws {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    let excludedIDs = Set(windowNumbers.map { CGWindowID($0) })
    self.content = content
    excludedWindows = content.windows.filter { excludedIDs.contains($0.windowID) }
  }

  func source(for screen: NSScreen) -> ColorPickerPixelSource? {
    guard let displayID = screen.displayID,
          let display = content?.displays.first(where: { $0.displayID == displayID }) else { return nil }
    let scale = screen.backingScaleFactor
    return ColorPickerStreamPixelSource(
      filter: SCContentFilter(display: display, excludingWindows: excludedWindows),
      pixelWidth: Int((screen.frame.width * scale).rounded()),
      pixelHeight: Int((screen.frame.height * scale).rounded()),
      framesPerSecond: min(max(screen.maximumFramesPerSecond, 30), 120)
    )
  }
}

/// Streams one display and keeps only its newest complete frame.
///
/// Nonisolated on purpose: overlay views hold it, and AppKit can free a view while draining an
/// autorelease pool after a Swift job. A main-actor (isolated) deinit run there aborts on
/// macOS 13–15 (back-deployed `swift_task_deinitOnExecutor`, "pointer being freed was not allocated").
nonisolated final class ColorPickerStreamPixelSource: NSObject, ColorPickerPixelSource, @unchecked Sendable {
  var onUpdate: (() -> Void)?

  private let filter: SCContentFilter
  private let configuration: SCStreamConfiguration
  private let sampleQueue = DispatchQueue(label: "com.trongduong.snapzy.color-picker-stream", qos: .userInteractive)

  private let lock = NSLock()
  private nonisolated(unsafe) var latestFrame: CVPixelBuffer?
  private nonisolated(unsafe) var isUpdateScheduled = false
  private var stream: SCStream?

  init(filter: SCContentFilter, pixelWidth: Int, pixelHeight: Int, framesPerSecond: Int) {
    self.filter = filter
    let configuration = SCStreamConfiguration()
    configuration.width = pixelWidth
    configuration.height = pixelHeight
    configuration.pixelFormat = kCVPixelFormatType_32BGRA
    // ScreenCaptureKit converts from the display profile, so bytes are already sRGB.
    configuration.colorSpaceName = CGColorSpace.sRGB
    configuration.showsCursor = false
    configuration.queueDepth = 3
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
    self.configuration = configuration
    super.init()
  }

  var pixelSize: (width: Int, height: Int)? {
    lock.lock()
    defer { lock.unlock() }
    guard let latestFrame else { return nil }
    return (CVPixelBufferGetWidth(latestFrame), CVPixelBufferGetHeight(latestFrame))
  }

  func neighborhood(of pixel: ColorPickerPixel, radius: Int) -> CGImage? {
    withLatestFrame { ColorPickerPixelBufferReader.neighborhood(of: pixel, radius: radius, in: $0) }
  }

  func color(of pixel: ColorPickerPixel) -> ColorPickerColor? {
    withLatestFrame { ColorPickerPixelBufferReader.color(of: pixel, in: $0) }
  }

  func start() async throws {
    guard stream == nil else { return }
    let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
    self.stream = stream
    do {
      try await stream.startCapture()
    } catch {
      if self.stream === stream { self.stream = nil }
      throw error
    }
    // Stopped while starting (the pointer already moved to another display): `stop()` could
    // not stop a stream that had not started yet, so stop it now.
    if self.stream !== stream {
      try? await stream.stopCapture()
    }
  }

  func stop() {
    let stream = stream
    self.stream = nil
    lock.lock()
    latestFrame = nil
    lock.unlock()
    guard let stream else { return }
    Task { try? await stream.stopCapture() }
  }

  private func withLatestFrame<T>(_ body: (CVPixelBuffer) -> T?) -> T? {
    lock.lock()
    defer { lock.unlock() }
    guard let latestFrame else { return nil }
    return body(latestFrame)
  }

  /// Hands the frame over and wakes the main thread at most once per pending update, so a
  /// burst of frames never queues a backlog of redraws.
  private nonisolated func store(_ frame: CVPixelBuffer) {
    lock.lock()
    latestFrame = frame
    let shouldSchedule = !isUpdateScheduled
    isUpdateScheduled = true
    lock.unlock()
    guard shouldSchedule else { return }
    DispatchQueue.main.async { [weak self] in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.lock.lock()
        self.isUpdateScheduled = false
        self.lock.unlock()
        self.onUpdate?()
      }
    }
  }
}

extension ColorPickerStreamPixelSource: SCStreamOutput {
  nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
    guard type == .screen, let frame = sampleBuffer.imageBuffer else { return }
    // Idle frames repeat the last one; only complete frames carry new pixels.
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
      as? [[SCStreamFrameInfo: Any]],
      let statusRaw = attachments.first?[.status] as? Int,
      let status = SCFrameStatus(rawValue: statusRaw),
      status != .complete {
      return
    }
    store(frame)
  }
}

extension ColorPickerStreamPixelSource: SCStreamDelegate {
  nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
    DiagnosticLogger.shared.log(.warning, .capture, "Pick color stream stopped: \(error.localizedDescription)")
  }
}

// MARK: - Pixel buffer reading

/// Reads 32BGRA sRGB pixel buffers, the format `ColorPickerStreamPixelSource` asks for.
nonisolated enum ColorPickerPixelBufferReader {
  private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

  /// The `(2 * radius + 1)²` pixels centered on `pixel`, black where the window runs off the
  /// frame. Copies only those rows, never the whole frame.
  static func neighborhood(of pixel: ColorPickerPixel, radius: Int, in buffer: CVPixelBuffer) -> CGImage? {
    let side = radius * 2 + 1
    guard side > 0, CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
    guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }

    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    let bytesPerRow = side * 4
    var bytes = [UInt8](repeating: 0, count: bytesPerRow * side)

    let minX = pixel.x - radius
    let firstX = max(minX, 0)
    let lastX = min(pixel.x + radius, width - 1)
    if firstX <= lastX {
      let rowLength = (lastX - firstX + 1) * 4
      bytes.withUnsafeMutableBytes { destination in
        for row in 0..<side {
          let sourceY = pixel.y - radius + row
          guard sourceY >= 0, sourceY < height else { continue }
          let source = base.advanced(by: sourceY * sourceBytesPerRow + firstX * 4)
          let target = destination.baseAddress!.advanced(by: row * bytesPerRow + (firstX - minX) * 4)
          target.copyMemory(from: source, byteCount: rowLength)
        }
      }
    }

    guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
    return CGImage(
      width: side,
      height: side,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: bytesPerRow,
      space: sRGB,
      bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )
  }

  static func color(of pixel: ColorPickerPixel, in buffer: CVPixelBuffer) -> ColorPickerColor? {
    guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
          CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let clamped = ColorPickerPixelSampler.clamp(pixel, imageWidth: width, imageHeight: height)
    let bytes = base.advanced(by: clamped.y * CVPixelBufferGetBytesPerRow(buffer) + clamped.x * 4)
      .assumingMemoryBound(to: UInt8.self)
    return ColorPickerColor(red: bytes[2], green: bytes[1], blue: bytes[0])
  }
}

// MARK: - Still image

/// A fixed image as a pixel source — for tests and previews. Nonisolated for the same reason as
/// `ColorPickerStreamPixelSource`.
nonisolated final class ColorPickerImagePixelSource: ColorPickerPixelSource {
  var onUpdate: (() -> Void)?
  private let image: CGImage
  private var isRunning = false

  init(image: CGImage) {
    self.image = image
  }

  var pixelSize: (width: Int, height: Int)? {
    isRunning ? (image.width, image.height) : nil
  }

  func neighborhood(of pixel: ColorPickerPixel, radius: Int) -> CGImage? {
    isRunning ? ColorPickerPixelSampler.neighborhood(of: pixel, radius: radius, in: image) : nil
  }

  func color(of pixel: ColorPickerPixel) -> ColorPickerColor? {
    isRunning ? ColorPickerPixelSampler.color(of: pixel, in: image) : nil
  }

  func start() async throws {
    guard !isRunning else { return }
    isRunning = true
    onUpdate?()
  }

  func stop() {
    isRunning = false
  }
}
