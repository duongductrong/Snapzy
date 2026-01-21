//
//  VideoEditorState.swift
//  ClaudeShot
//
//  Central state management for video editor
//

import AVFoundation
import AppKit
import Combine

/// Observable state for video editor window
@MainActor
final class VideoEditorState: ObservableObject {

  // MARK: - Video Source

  let sourceURL: URL
  let asset: AVAsset
  let player: AVPlayer

  // MARK: - Metadata

  @Published private(set) var duration: CMTime = .zero
  @Published private(set) var naturalSize: CGSize = .zero
  @Published private(set) var currentTime: CMTime = .zero
  @Published private(set) var isPlaying: Bool = false

  // MARK: - Trim Range

  @Published var trimStart: CMTime = .zero
  @Published var trimEnd: CMTime = .zero
  @Published private(set) var isScrubbing: Bool = false

  // MARK: - Audio Control

  @Published var isMuted: Bool = false {
    didSet {
      player.isMuted = isMuted
    }
  }
  private var initialIsMuted: Bool = false

  // MARK: - Frame Thumbnails

  @Published private(set) var frameThumbnails: [NSImage] = []
  @Published private(set) var isExtractingFrames: Bool = false

  // MARK: - Unsaved Changes

  @Published var hasUnsavedChanges: Bool = false
  private var initialTrimStart: CMTime = .zero
  private var initialTrimEnd: CMTime = .zero

  // MARK: - Private

  private var timeObserver: Any?
  private var endObserver: NSObjectProtocol?
  private var cancellables = Set<AnyCancellable>()

  // MARK: - Computed Properties

  var trimmedDuration: CMTime {
    CMTimeSubtract(trimEnd, trimStart)
  }

  var filename: String {
    sourceURL.lastPathComponent
  }

  var fileExtension: String {
    sourceURL.pathExtension.lowercased()
  }

  var formattedDuration: String {
    formatTime(duration)
  }

  var formattedCurrentTime: String {
    formatTime(currentTime)
  }

  var formattedTrimmedDuration: String {
    formatTime(trimmedDuration)
  }

  var resolutionString: String {
    guard naturalSize.width > 0 && naturalSize.height > 0 else { return "—" }
    return "\(Int(naturalSize.width)) × \(Int(naturalSize.height))"
  }

  // MARK: - Initialization

  init(url: URL) {
    self.sourceURL = url
    self.asset = AVAsset(url: url)
    self.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))

    setupTimeObserver()
    setupEndObserver()
    setupChangeTracking()
  }

  deinit {
    if let observer = timeObserver {
      player.removeTimeObserver(observer)
    }
    if let observer = endObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    cancellables.removeAll()
  }

  // MARK: - Metadata Loading

  func loadMetadata() async {
    do {
      let loadedDuration = try await asset.load(.duration)
      duration = loadedDuration
      trimStart = .zero
      trimEnd = loadedDuration
      initialTrimStart = .zero
      initialTrimEnd = loadedDuration

      if let track = try await asset.loadTracks(withMediaType: .video).first {
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        // Apply transform to get correct orientation
        let transformedSize = size.applying(transform)
        naturalSize = CGSize(
          width: abs(transformedSize.width),
          height: abs(transformedSize.height)
        )
      }
    } catch {
      print("Failed to load video metadata: \(error)")
    }
  }

  // MARK: - Playback Control

  func play() {
    player.play()
    isPlaying = true
  }

  func pause() {
    player.pause()
    isPlaying = false
  }

  func togglePlayback() {
    if isPlaying {
      pause()
    } else {
      play()
    }
  }

  func toggleMute() {
    isMuted.toggle()
  }

  func seek(to time: CMTime) {
    let clampedTime = clampTime(time)
    player.seek(to: clampedTime, toleranceBefore: .zero, toleranceAfter: .zero)
  }

  // MARK: - Scrubbing

  func startScrubbing() {
    isScrubbing = true
    pause()
  }

  func scrub(to time: CMTime) {
    let clampedTime = clampTime(time)
    currentTime = clampedTime
    player.seek(to: clampedTime, toleranceBefore: .zero, toleranceAfter: .zero)
  }

  func endScrubbing() {
    isScrubbing = false
  }

  // MARK: - Trim Control

  func setTrimStart(_ time: CMTime) {
    let minDuration = CMTime(seconds: 1.0, preferredTimescale: 600)
    let maxStart = CMTimeSubtract(trimEnd, minDuration)
    let clampedStart = CMTimeClampToRange(time, range: CMTimeRange(start: .zero, end: maxStart))
    trimStart = clampedStart

    // If current time is before new start, seek to start
    if CMTimeCompare(currentTime, trimStart) < 0 {
      seek(to: trimStart)
    }
  }

  func setTrimEnd(_ time: CMTime) {
    let minDuration = CMTime(seconds: 1.0, preferredTimescale: 600)
    let minEnd = CMTimeAdd(trimStart, minDuration)
    let clampedEnd = CMTimeClampToRange(time, range: CMTimeRange(start: minEnd, end: duration))
    trimEnd = clampedEnd

    // If current time is after new end, seek to end
    if CMTimeCompare(currentTime, trimEnd) > 0 {
      seek(to: trimEnd)
    }
  }

  func resetTrim() {
    trimStart = .zero
    trimEnd = duration
  }

  // MARK: - Frame Extraction

  func extractFrames() async {
    guard CMTimeGetSeconds(duration) > 0 else { return }

    isExtractingFrames = true
    defer { isExtractingFrames = false }

    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 120, height: 68)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero

    let count = 25
    let totalSeconds = CMTimeGetSeconds(duration)
    let interval = totalSeconds / Double(count)

    var images: [NSImage] = []
    for i in 0..<count {
      let time = CMTime(seconds: Double(i) * interval, preferredTimescale: 600)
      if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
        let image = NSImage(cgImage: cgImage, size: NSSize(width: 120, height: 68))
        images.append(image)
      }
    }
    frameThumbnails = images
  }

  // MARK: - Save State

  func markAsSaved() {
    hasUnsavedChanges = false
    initialTrimStart = trimStart
    initialTrimEnd = trimEnd
    initialIsMuted = isMuted
  }

  // MARK: - Private Methods

  private func setupTimeObserver() {
    let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: interval,
      queue: .main
    ) { [weak self] time in
      Task { @MainActor in
        guard let self = self, !self.isScrubbing else { return }
        self.currentTime = time

        // Stop at trim end
        if CMTimeCompare(time, self.trimEnd) >= 0 {
          self.pause()
          self.seek(to: self.trimStart)
        }
      }
    }
  }

  private func setupEndObserver() {
    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: player.currentItem,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.pause()
        self?.seek(to: self?.trimStart ?? .zero)
      }
    }
  }

  private func setupChangeTracking() {
    Publishers.CombineLatest3($trimStart, $trimEnd, $isMuted)
      .dropFirst()
      .sink { [weak self] start, end, muted in
        guard let self = self else { return }
        let startChanged = CMTimeCompare(start, self.initialTrimStart) != 0
        let endChanged = CMTimeCompare(end, self.initialTrimEnd) != 0
        let muteChanged = muted != self.initialIsMuted
        self.hasUnsavedChanges = startChanged || endChanged || muteChanged
      }
      .store(in: &cancellables)
  }

  private func clampTime(_ time: CMTime) -> CMTime {
    CMTimeClampToRange(time, range: CMTimeRange(start: trimStart, end: trimEnd))
  }

  private func formatTime(_ time: CMTime) -> String {
    let totalSeconds = Int(CMTimeGetSeconds(time))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%02d:%02d", minutes, seconds)
    }
  }
}
