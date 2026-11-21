//
//  CaptureOriginStore.swift
//  Snapzy
//
//  Short-lived map from a saved capture to the screen region it was taken from.
//

import CoreGraphics
import Foundation

/// Surfaces that reopen a capture — currently the pinned screenshot window — use this to grow out
/// of the region the user just selected instead of popping in at the screen center.
///
/// The capture APIs only hand forward a file URL, so the region has to be remembered beside it
/// rather than threaded through every result type. Entries expire on their own: an origin is only
/// meaningful for the seconds between capturing and pinning, and a stale one would animate from a
/// part of the desktop that no longer holds anything.
@MainActor
final class CaptureOriginStore {
  static let shared = CaptureOriginStore()

  /// How long an origin stays usable after its capture was written.
  static let lifetime: TimeInterval = 60

  /// Bound on remembered origins; captures are pinned within seconds, so a short ring is enough.
  static let capacity = 32

  private struct Entry {
    let url: URL
    let screenRect: CGRect
    let recordedAt: Date
  }

  private var entries: [Entry] = []

  private init() {}

  func record(url: URL, screenRect: CGRect, at date: Date = Date()) {
    // `size`, not the `screenRect.width` accessor: CoreGraphics reports an inverted rect's width
    // as if it had already been standardized, so the accessor would let a degenerate region in.
    guard screenRect.size.width > 0, screenRect.size.height > 0 else { return }
    pruneExpired(at: date)
    entries.removeAll { $0.url == url }
    entries.append(Entry(url: url, screenRect: screenRect, recordedAt: date))
    if entries.count > Self.capacity {
      entries.removeFirst(entries.count - Self.capacity)
    }
  }

  func origin(for url: URL, at date: Date = Date()) -> CGRect? {
    guard let entry = entries.last(where: { $0.url == url }) else { return nil }
    guard date.timeIntervalSince(entry.recordedAt) <= Self.lifetime else {
      entries.removeAll { $0.url == url }
      return nil
    }
    return entry.screenRect
  }

  func removeAll() {
    entries.removeAll()
  }

  private func pruneExpired(at date: Date) {
    entries.removeAll { date.timeIntervalSince($0.recordedAt) > Self.lifetime }
  }
}
