//
//  RecordingMetadataCleanupScheduler.swift
//  Snapzy
//
//  Periodically prunes orphaned recording metadata entries.
//

import Foundation
import os.log

private let recordingMetadataCleanupLogger = Logger(
  subsystem: "Snapzy",
  category: "RecordingMetadataCleanup"
)

@MainActor
final class RecordingMetadataCleanupScheduler {
  static let shared = RecordingMetadataCleanupScheduler()

  private let cleanupInterval: TimeInterval = 30 * 60 // 30 minutes
  private var timer: Timer?

  private init() {}

  func start() {
    performCleanup()

    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: cleanupInterval, repeats: true) { _ in
      Task { @MainActor in
        RecordingMetadataCleanupScheduler.shared.performCleanup()
      }
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  private func performCleanup() {
    DispatchQueue.global(qos: .utility).async {
      Task { @MainActor in
        do {
          try RecordingMetadataStore.performOrphanCleanup()
        } catch {
          recordingMetadataCleanupLogger.error(
            "Failed to prune orphaned recording metadata: \(error.localizedDescription, privacy: .public)"
          )
        }
      }
    }
  }
}
