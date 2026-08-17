import Foundation
import Testing
import SnapzyPluginProtocol

@Suite struct BlobTableTests {
  @Test func storeAndTake() async throws {
    let table = BlobTable()
    let data = Data("payload".utf8)
    try await table.store(7, data: data)
    #expect(await table.take(7) == data)
    // Taking removes: a second take finds nothing, and a stale reference
    // cannot resolve twice.
    #expect(await table.take(7) == nil)
  }

  @Test func replacingSameIDDoesNotDoubleCount() async throws {
    let table = BlobTable(maxBlobCount: 1, maxTotalBytes: 100)
    try await table.store(1, data: Data(repeating: 0, count: 80))
    try await table.store(1, data: Data(repeating: 0, count: 60))
    #expect(await table.take(1)?.count == 60)
  }

  @Test func countCapThrows() async {
    let table = BlobTable(maxBlobCount: 2, maxTotalBytes: 1024)
    try? await table.store(1, data: Data("a".utf8))
    try? await table.store(2, data: Data("b".utf8))
    await #expect(throws: ProtocolError.blobLimitExceeded) {
      try await table.store(3, data: Data("c".utf8))
    }
  }

  @Test func byteCapThrows() async {
    let table = BlobTable(maxBlobCount: 16, maxTotalBytes: 10)
    await #expect(throws: ProtocolError.blobLimitExceeded) {
      try await table.store(1, data: Data(repeating: 0, count: 11))
    }
  }

  @Test func resetClearsEverything() async throws {
    let table = BlobTable()
    try await table.store(1, data: Data("a".utf8))
    await table.reset()
    #expect(await table.take(1) == nil)
  }
}
