import Foundation
import Testing
import SnapzyPluginProtocol

@Suite struct FrameTests {
  @Test func roundTrip() throws {
    let payload = Data((0..<1000).map { UInt8($0 % 251) })
    for kind in [Frame.Kind.json, .blob] {
      let frame = Frame(kind: kind, payload: payload)
      let encoded = try frame.encode()
      #expect(encoded.count == Frame.headerByteCount + payload.count)
      let (decoded, consumed) = try Frame.decode(from: encoded)
      #expect(decoded == frame)
      #expect(consumed == encoded.count)
    }
  }

  @Test func closeFrameRoundTrip() throws {
    let encoded = try Frame.close.encode()
    let (decoded, _) = try Frame.decode(from: encoded)
    #expect(decoded.kind == .close)
    #expect(decoded.payload.isEmpty)
  }

  @Test func blobFrameCarriesID() throws {
    let data = Data("blob-bytes".utf8)
    let frame = Frame(blobID: 42, data: data)
    #expect(frame.blobID == 42)
    #expect(frame.blobData == data)
    let (decoded, _) = try Frame.decode(from: try frame.encode())
    #expect(decoded.blobID == 42)
    #expect(decoded.blobData == data)
  }

  @Test func truncatedHeaderThrows() {
    #expect(throws: ProtocolError.truncatedFrame) {
      try Frame.decode(from: Data([1, 0, 0]))
    }
  }

  @Test func truncatedBodyThrows() throws {
    let frame = Frame(json: Data(repeating: 0x42, count: 100))
    let encoded = try frame.encode()
    #expect(throws: ProtocolError.truncatedFrame) {
      try Frame.decode(from: encoded.dropLast(37))
    }
  }

  @Test func oversizedFrameThrows() {
    // Declared length above the cap must be refused from the header alone.
    var header = Data([Frame.Kind.json.rawValue])
    header.append(contentsOf: withUnsafeBytes(of: UInt32(Frame.maxPayloadBytes + 1).bigEndian) { Data($0) })
    #expect(throws: ProtocolError.oversizedFrame(declared: Frame.maxPayloadBytes + 1)) {
      try Frame.decode(from: header)
    }
  }

  @Test func unknownKindThrows() {
    var header = Data([9])
    header.append(contentsOf: withUnsafeBytes(of: UInt32(4).bigEndian) { Data($0) })
    header.append(contentsOf: Data("xxxx".utf8))
    #expect(throws: ProtocolError.unknownFrameKind(9)) {
      try Frame.decode(from: header)
    }
  }

  @Test func oversizedEncodeRefused() {
    let big = Data(repeating: 0, count: Frame.maxPayloadBytes + 1)
    #expect(throws: ProtocolError.oversizedFrame(declared: Frame.maxPayloadBytes + 1)) {
      try Frame(json: big).encode()
    }
  }

  @Test func trailingBytesAreIgnored() throws {
    let frame = Frame(json: Data("{}".utf8))
    var encoded = try frame.encode()
    encoded.append(contentsOf: Data("next-frame-junk".utf8))
    let (decoded, consumed) = try Frame.decode(from: encoded)
    #expect(decoded == frame)
    #expect(consumed == encoded.count - "next-frame-junk".utf8.count)
  }
}
