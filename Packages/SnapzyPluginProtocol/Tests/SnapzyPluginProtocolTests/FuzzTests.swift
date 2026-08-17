import Foundation
import Testing
import SnapzyPluginProtocol

/// Seeded fuzzing over the two hostile-input boundaries: `Frame.decode` and
/// `JSONValue.parse` (+ `Envelope.decode`).
///
/// Deterministic — same seed, same inputs, same budget — so CI failures are
/// reproducible, and the budget is small enough to run on every build. The
/// invariant: every input either decodes or throws a `ProtocolError`. A
/// crash, a hang, or any other error type is a finding.
@Suite struct FuzzTests {
  /// xorshift64*: tiny, deterministic, good enough to exercise branches.
  struct PRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
      state ^= state >> 12
      state ^= state << 25
      state ^= state >> 27
      return state &* 0x2545F4914F6CDD1D
    }
    mutating func int(in range: Range<Int>) -> Int {
      guard range.lowerBound < range.upperBound else { return range.lowerBound }
      return Int(next() % UInt64(range.upperBound - range.lowerBound)) + range.lowerBound
    }
  }

  private func validFrameSeed() throws -> Data {
    let envelope = Envelope(
      id: 2, kind: "invoke",
      payload: .object([
        "service": .string("ocr.recognize"),
        "args": .array([.object(["lang": .string("vi")]), .number(42), .bool(true), .null])
      ])
    )
    return try Frame(json: envelope.encode().encodeData()).encode()
  }

  private func validJSONSeed() -> Data {
    Data(#"{"id":2,"kind":"invoke","payload":{"a":[1,2,3],"b":{"c":"d"},"e":true,"f":null}}"#.utf8)
  }

  private func mutate(_ data: Data, with rng: inout PRNG) -> Data {
    var bytes = [UInt8](data)
    let mutations = rng.int(in: 1..<9)
    for _ in 0..<mutations where !bytes.isEmpty {
      switch rng.int(in: 0..<5) {
      case 0: // bit flip
        bytes[rng.int(in: 0..<bytes.count)] ^= UInt8(1 << rng.int(in: 0..<8))
      case 1: // byte overwrite
        bytes[rng.int(in: 0..<bytes.count)] = UInt8(rng.next() % 256)
      case 2: // truncate
        bytes.removeSubrange(rng.int(in: 0..<bytes.count)...)
      case 3: // insert garbage
        bytes.insert(UInt8(rng.next() % 256), at: rng.int(in: 0..<bytes.count))
      case 4: // length-prefix corruption: nuke 4 bytes somewhere
        guard bytes.count >= 5 else { continue }
        let start = rng.int(in: 0..<bytes.count - 4)
        for i in 0..<4 { bytes[start + i] = UInt8(rng.next() % 256) }
      default:
        break
      }
    }
    return Data(bytes)
  }

  @Test func fuzzFrameDecode() throws {
    var rng = PRNG(seed: 0x5EED_FA4E)
    let seed = try validFrameSeed()
    for _ in 0..<5_000 {
      let candidate: Data
      if rng.int(in: 0..<10) == 0 {
        candidate = Data((0..<rng.int(in: 0..<64)).map { _ in UInt8(rng.next() % 256) })
      } else {
        candidate = mutate(seed, with: &rng)
      }
      do {
        _ = try Frame.decode(from: candidate)
      } catch let error as ProtocolError {
        _ = error // expected
      } catch {
        Issue.record("non-ProtocolError escape: \(error)")
        return
      }
    }
  }

  @Test func fuzzJSONParseAndEnvelope() throws {
    var rng = PRNG(seed: 0x5EED_7509)
    let seed = validJSONSeed()
    for _ in 0..<5_000 {
      let candidate: Data
      if rng.int(in: 0..<10) == 0 {
        candidate = Data((0..<rng.int(in: 0..<64)).map { _ in UInt8(rng.next() % 256) })
      } else {
        candidate = mutate(seed, with: &rng)
      }
      do {
        let value = try JSONValue.parse(candidate)
        // Envelope.decode must also be total over any parsed value.
        do {
          _ = try Envelope.decode(value)
        } catch let error as ProtocolError {
          _ = error
        } catch {
          Issue.record("non-ProtocolError escape from Envelope.decode: \(error)")
          return
        }
      } catch let error as ProtocolError {
        _ = error // expected
      } catch {
        Issue.record("non-ProtocolError escape: \(error)")
        return
      }
    }
  }

  @Test func fuzzDeepBracketStructures() throws {
    var rng = PRNG(seed: 0x5EED_DEE7)
    for _ in 0..<500 {
      // Random bracket soup around a valid core — the depth pre-scan must
      // bound this regardless of balance.
      let core = validJSONSeed()
      var soup = Data()
      let prefix = rng.int(in: 0..<4_000)
      let suffix = rng.int(in: 0..<4_000)
      for _ in 0..<prefix { soup.append([0x5B, 0x7B, 0x22, 0x5C][rng.int(in: 0..<4)]) }
      soup.append(core)
      for _ in 0..<suffix { soup.append([0x5D, 0x7D, 0x22, 0x5C][rng.int(in: 0..<4)]) }
      do {
        _ = try JSONValue.parse(soup)
      } catch let error as ProtocolError {
        _ = error
      } catch {
        Issue.record("non-ProtocolError escape: \(error)")
        return
      }
    }
  }
}
