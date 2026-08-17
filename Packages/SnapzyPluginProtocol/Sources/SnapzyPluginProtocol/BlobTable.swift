import Foundation

/// Buffers received blob frames, keyed by id, with hard bounds.
///
/// The bounds are the backstop against a peer that streams blobs and never
/// references them: without a cap, a hostile plugin could pin host memory
/// with orphaned frames. Blobs are removed when their payload is resolved,
/// so the table only ever holds what one in-flight exchange needs.
public actor BlobTable {
  /// Maximum distinct blobs buffered at once.
  public let maxBlobCount: Int
  /// Maximum total bytes buffered at once.
  public let maxTotalBytes: Int

  private var entries: [UInt64: Data] = [:]
  private var totalBytes = 0

  public init(maxBlobCount: Int = 16, maxTotalBytes: Int = 128 * 1024 * 1024) {
    self.maxBlobCount = maxBlobCount
    self.maxTotalBytes = maxTotalBytes
  }

  /// Stores a received blob. Throws `ProtocolError.blobLimitExceeded` rather
  /// than evicting: silent eviction would corrupt whichever payload finally
  /// references the id, and failing the connection is the honest answer.
  public func store(_ id: UInt64, data: Data) throws {
    if entries[id] != nil {
      totalBytes -= entries[id]?.count ?? 0
    }
    guard entries.count < maxBlobCount || entries[id] != nil else {
      throw ProtocolError.blobLimitExceeded
    }
    guard totalBytes + data.count <= maxTotalBytes || entries[id] != nil else {
      throw ProtocolError.blobLimitExceeded
    }
    entries[id] = data
    totalBytes += data.count
  }

  /// Removes and returns one blob, so a resolved reference cannot be
  /// resolved twice by accident.
  public func take(_ id: UInt64) -> Data? {
    guard let data = entries.removeValue(forKey: id) else { return nil }
    totalBytes -= data.count
    return data
  }

  public func reset() {
    entries.removeAll()
    totalBytes = 0
  }
}
