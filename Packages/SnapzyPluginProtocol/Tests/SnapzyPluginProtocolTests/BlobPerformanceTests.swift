import Foundation
import Testing
import SnapzyPluginProtocol

@Suite struct BlobPerformanceTests {
  /// The phase's headline claim: an 8 MB payload travels faster as a blob
  /// frame than as base64-in-JSON. Both paths are measured in-process over a
  /// real socketpair; the comparison is relative, so machine speed cancels
  /// out. Sizes are large enough that encode/parse costs dominate jitter.
  @Test func blobFasterThanBase64JSON() async throws {
    let size = 8 * 1024 * 1024
    let payload = Data((0..<size).map { UInt8($0 % 251) })
    let base64 = payload.base64EncodedString()

    var fds: [Int32] = [0, 0]
    socketpair(AF_UNIX, SOCK_STREAM, 0, &fds)

    let readFD = fds[0]
    let writeFD = fds[1]

    let base64Time = try await measure {
      // The old path: bytes ride inside the JSON payload itself.
      let jsonPayload = JSONValue.object(["data": .string(base64)])
      let envelope = Envelope(id: 0, kind: "asset", payload: jsonPayload)
      let frame = Frame(json: try envelope.encode().encodeData())
      let encoded = try frame.encode()
      let writeTask = Task.detached { [writeFD, encoded] in
        encoded.withUnsafeBytes { src in
          var written = 0
          while written < src.count {
            let n = Darwin.write(writeFD, src.baseAddress! + written, src.count - written)
            if n <= 0 { break }
            written += n
          }
        }
      }
      var buffer = Data(count: encoded.count)
      buffer.withUnsafeMutableBytes { dst in
        var totalRead = 0
        while totalRead < encoded.count {
          let n = Darwin.read(readFD, dst.baseAddress! + totalRead, dst.count - totalRead)
          if n <= 0 { break }
          totalRead += n
        }
      }
      _ = await writeTask.value
      let (decoded, _) = try Frame.decode(from: buffer)
      let value = try JSONValue.parse(decoded.payload)
      _ = try Envelope.decode(value)
    }

    let blobTime = try await measure {
      // The new path: bytes ride a blob frame, JSON carries only the id.
      let blobFrame = try Frame(blobID: 1, data: payload).encode()
      let envelope = Envelope(id: 0, kind: "asset", payload: .object(["data": .object(["blob": .number(1)])]))
      let jsonFrame = try Frame(json: envelope.encode().encodeData()).encode()
      let writeBlob = Task.detached { [writeFD, blobFrame] in
        blobFrame.withUnsafeBytes { src in
          var written = 0
          while written < src.count {
            let n = Darwin.write(writeFD, src.baseAddress! + written, src.count - written)
            if n <= 0 { break }
            written += n
          }
        }
      }
      var blobBuffer = Data(count: blobFrame.count)
      blobBuffer.withUnsafeMutableBytes { dst in
        var totalRead = 0
        while totalRead < blobFrame.count {
          let n = Darwin.read(readFD, dst.baseAddress! + totalRead, dst.count - totalRead)
          if n <= 0 { break }
          totalRead += n
        }
      }
      _ = await writeBlob.value

      let writeJson = Task.detached { [writeFD, jsonFrame] in
        jsonFrame.withUnsafeBytes { src in
          var written = 0
          while written < src.count {
            let n = Darwin.write(writeFD, src.baseAddress! + written, src.count - written)
            if n <= 0 { break }
            written += n
          }
        }
      }
      var jsonBuffer = Data(count: jsonFrame.count)
      jsonBuffer.withUnsafeMutableBytes { dst in
        var totalRead = 0
        while totalRead < jsonFrame.count {
          let n = Darwin.read(readFD, dst.baseAddress! + totalRead, dst.count - totalRead)
          if n <= 0 { break }
          totalRead += n
        }
      }
      _ = await writeJson.value

      _ = try Frame.decode(from: blobBuffer)
      let (jsonDecoded, _) = try Frame.decode(from: jsonBuffer)
      _ = try Envelope.decode(JSONValue.parse(jsonDecoded.payload))
    }

    Darwin.close(fds[0])
    Darwin.close(fds[1])

    // The blob path skips base64 encode and JSON parse of a 10.6 MB string;
    // it must be measurably faster, not marginally.
    #expect(
      blobTime < base64Time,
      "blob \(blobTime) vs base64 \(base64Time)"
    )
  }

  private func measure(_ operation: () async throws -> Void) async throws -> Duration {
    var total = Duration.zero
    for _ in 0..<5 {
      let start = ContinuousClock.now
      try await operation()
      total += start.duration(to: .now)
    }
    return total / 5
  }
}
