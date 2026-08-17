import Foundation
import Testing
@testable import SnapzyPluginProtocol

@Suite struct JSONValueTests {
  @Test func parseRoundTrip() throws {
    let json = #"{"a":[1,2.5,true,false,null,"x"],"b":{"c":"d"}}"#
    let value = try JSONValue.parse(Data(json.utf8))
    let reencoded = try value.encodeData()
    let reparsed = try JSONValue.parse(reencoded)
    #expect(reparsed == value)
  }

  @Test func fragmentsAllowed() throws {
    #expect(try JSONValue.parse(Data("42".utf8)) == .number(42))
    #expect(try JSONValue.parse(Data(#""str""#.utf8)) == .string("str"))
    #expect(try JSONValue.parse(Data("null".utf8)) == .null)
  }

  @Test func malformedJSONThrows() {
    #expect(throws: ProtocolError.malformedJSON) {
      try JSONValue.parse(Data("{not json".utf8))
    }
    #expect(throws: ProtocolError.malformedJSON) {
      try JSONValue.parse(Data("".utf8))
    }
  }

  @Test func nestingAtLimitPasses() throws {
    let depth = JSONValue.defaultMaxDepth
    let nested = String(repeating: "[", count: depth) + "0" + String(repeating: "]", count: depth)
    _ = try JSONValue.parse(Data(nested.utf8))
  }

  @Test func nestingOverLimitThrows() {
    let depth = JSONValue.defaultMaxDepth + 1
    let nested = String(repeating: "[", count: depth) + "0" + String(repeating: "]", count: depth)
    #expect(throws: ProtocolError.jsonNestingTooDeep) {
      try JSONValue.parse(Data(nested.utf8))
    }
  }

  @Test func bracketBombRefusedInLinearTime() throws {
    // 200k-deep nesting: the pre-scan must refuse it without recursing.
    let depth = 200_000
    var data = Data(repeating: 0x5B, count: depth) // [
    data.append(contentsOf: Data("0".utf8))
    data.append(contentsOf: Data(repeating: 0x5D, count: depth)) // ]
    let start = ContinuousClock.now
    #expect(throws: ProtocolError.jsonNestingTooDeep) {
      try JSONValue.parse(data)
    }
    let elapsed = start.duration(to: .now)
    #expect(elapsed < .seconds(2))
  }

  @Test func bracesInsideStringsDoNotCount() throws {
    let json = #"{"s":"[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]"}"#
    _ = try JSONValue.parse(Data(json.utf8))
  }

  @Test func escapedQuotesInStringsHandled() throws {
    // JSON text: {"s":"a\"b\\c["} — escaped quote, escaped backslash,
    // then a bracket inside the string.
    let json = #"{"s":"a\"b\\c["}"#
    let value = try JSONValue.parse(Data(json.utf8))
    #expect(value == .object(["s": .string("a\"b\\c[")]))
  }

  @Test func blobReferences() {
    let reference = JSONValue.blobReference(7)
    #expect(reference.blobReferenceID == 7)
    #expect(JSONValue.string("x").blobReferenceID == nil)
    #expect(JSONValue.object(["blob": .number(7), "other": .null]).blobReferenceID == nil)
    #expect(JSONValue.object(["blob": .number(-1)]).blobReferenceID == nil)

    let payload = JSONValue.object(["a": reference, "b": .object(["c": reference])])
    #expect(payload.blobIDs == [7, 7])
    // Counting cannot distinguish real ids from indices — both are
    // `{"blob": n}` at this layer. Senders always use indices.
    #expect(payload.blobPlaceholderCount == 2)
  }

  @Test func blobEmbeddingRewritesPlaceholders() throws {
    let payload = JSONValue.object([
      "image": .object(["blob": .number(0)]),
      "extra": .array([.object(["blob": .number(1)]), .number(3)])
    ])
    #expect(payload.blobPlaceholderCount == 2)
    let blobA = Data("aaaa".utf8)
    let blobB = Data("bbbb".utf8)
    let (rewritten, frames) = try payload.embeddingBlobs([blobA, blobB], ids: [101, 202])
    #expect(frames.count == 2)
    #expect(frames[0].id == 101 && frames[0].data == blobA)
    #expect(frames[1].id == 202 && frames[1].data == blobB)
    #expect(rewritten.blobIDs == [202, 101])
  }

  @Test func blobIndexOutOfRangeThrows() {
    let payload = JSONValue.object(["image": .object(["blob": .number(3)])])
    #expect(throws: ProtocolError.blobIndexOutOfRange) {
      try payload.embeddingBlobs([Data("x".utf8)], ids: [1])
    }
  }

  @Test func resolvingBlobsBridgesToBase64() {
    let payload = JSONValue.object(["image": .object(["blob": .number(5)])])
    let resolved = payload.resolvingBlobs(from: [5: Data("bytes".utf8)])
    #expect(resolved == .object(["image": .string("Ynl0ZXM=")]))
    // Unresolved references stay untouched so the caller can react.
    #expect(payload.resolvingBlobs(from: [:]) == payload)
  }

  @Test func codableConformance() throws {
    let value = JSONValue.object(["n": .number(1), "s": .string("x"), "a": .array([.bool(true)])])
    let encoded = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: encoded)
    #expect(decoded == value)
  }
}
