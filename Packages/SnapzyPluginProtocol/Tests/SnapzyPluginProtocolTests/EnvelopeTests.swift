import Foundation
import Testing
import SnapzyPluginProtocol

@Suite struct EnvelopeTests {
  @Test func roundTrip() throws {
    let envelope = Envelope(id: 12, kind: "invoke", payload: .object(["a": .number(1)]))
    let encoded = try envelope.encode().encodeData()
    let decoded = try Envelope.decode(JSONValue.parse(encoded))
    #expect(decoded == envelope)
  }

  @Test func forwardCompatibleExtraKeysIgnored() throws {
    // A newer peer adds fields; an older decode must see what it knows.
    let json = #"{"id":3,"kind":"result","payload":{},"futureField":true,"alsoFuture":["x"]}"#
    let envelope = try Envelope.decode(JSONValue.parse(Data(json.utf8)))
    #expect(envelope.id == 3)
    #expect(envelope.kind == "result")
    #expect(envelope.payload == .object([:]))
  }

  @Test func missingFieldsThrow() {
    let cases = [#"{"kind":"x","payload":1}"#, #"{"id":1,"payload":1}"#, #"{"id":1,"kind":"x"}"#]
    for json in cases {
      #expect(throws: ProtocolError.malformedJSON) {
        try Envelope.decode(JSONValue.parse(Data(json.utf8)))
      }
    }
  }

  @Test func nonIntegerIDThrows() {
    let json = #"{"id":1.5,"kind":"x","payload":1}"#
    #expect(throws: ProtocolError.malformedJSON) {
      try Envelope.decode(JSONValue.parse(Data(json.utf8)))
    }
  }
}
