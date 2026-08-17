import Darwin
import Foundation
import Testing
@testable import SnapzyPluginProtocol

/// Two `FrameChannel`s connected by a real socketpair — host parity on one
/// end, plugin parity on the other, exactly as the runtime will wire them.
// All mutable state (fd0Open/fd1Open) is confined to the test's own task;
// child Tasks only touch the channels, which are actors. @unchecked is
// sound here and keeps the test closures uncluttered.
final class ChannelPair: @unchecked Sendable {
  let host: FrameChannel
  let plugin: FrameChannel
  let fds: (Int32, Int32)
  private var fd0Open = true
  private var fd1Open = true

  init() throws {
    var fds: [Int32] = [0, 0]
    guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else {
      throw ProtocolError.peerDied
    }
    self.fds = (fds[0], fds[1])
    host = FrameChannel(readFD: fds[0], writeFD: fds[0], parity: .even, label: "test.host")
    plugin = FrameChannel(readFD: fds[1], writeFD: fds[1], parity: .odd, label: "test.plugin")
  }

  func tearDown() async {
    await host.close()
    await plugin.close()
    // Exactly-once close, only for ends still open: a severed end's fd
    // number may already belong to another test's socketpair.
    if fd0Open { Darwin.close(fds.0) }
    if fd1Open { Darwin.close(fds.1) }
  }

  /// Simulates the peer dying without a close frame. Marks the end closed so
  /// tearDown never touches the recycled fd number again.
  func sever(_ end: Int32) {
    if end == fds.0 { fd0Open = false } else { fd1Open = false }
    Darwin.close(end)
  }

  /// Awaits the next event on the channel's stream. Hang protection comes
  /// from Swift Testing's per-test time limit, so no second task is needed
  /// here — the iterator stays owned by one task, which is what Swift 6
  /// wants to see.
  func nextEvent(from channel: FrameChannel) async throws -> FrameChannel.Event {
    var iterator = await channel.events.makeAsyncIterator()
    guard let event = await iterator.next() else { throw ProtocolError.peerDied }
    return event
  }

  /// Blocks until `condition` holds or the timeout elapses.
  func eventually(
    timeout: Duration = .seconds(5),
    _ condition: () async -> Bool
  ) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      if await condition() { return true }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
  }

  /// Writes raw bytes straight onto the wire — the adversarial peer.
  func injectRaw(_ data: Data, on end: Int32) {
    data.withUnsafeBytes { bytes in
      _ = Darwin.write(end, bytes.baseAddress, bytes.count)
    }
  }
}

/// Runs `body` with a connected pair, always tearing the pair down.
func withPair(_ body: (ChannelPair) async throws -> Void) async throws {
  let pair = try ChannelPair()
  await pair.host.start()
  await pair.plugin.start()
  do {
    try await body(pair)
  } catch {
    await pair.tearDown()
    throw error
  }
  await pair.tearDown()
}

@Suite struct FrameChannelTests {
  @Test(.timeLimit(.minutes(1))) func requestReplyRoundTripBothDirections() async throws {
    try await withPair { pair in
      // Host → plugin: request/reply.
      let hostRequest = Task {
        try await pair.host.request("invoke", payload: .object(["n": .number(1)]))
      }
      let event = try await pair.nextEvent(from: pair.plugin)
      #expect(event.envelope.kind == "invoke")
      #expect(event.envelope.payload == .object(["n": .number(1)]))
      try await pair.plugin.reply(
        to: event.envelope.id, kind: "result", payload: .object(["ok": .bool(true)])
      )
      let reply = try await hostRequest.value
      #expect(reply.kind == "result")
      #expect(reply.payload == .object(["ok": .bool(true)]))

      // Plugin → host: request/reply (hostCall shape).
      let pluginRequest = Task {
        try await pair.plugin.request("hostCall", payload: .object(["service": .string("ui.form")]))
      }
      let hostEvent = try await pair.nextEvent(from: pair.host)
      #expect(hostEvent.envelope.kind == "hostCall")
      try await pair.host.reply(
        to: hostEvent.envelope.id, kind: "hostCallReply", payload: .object(["v": .number(2)])
      )
      let hostCallReply = try await pluginRequest.value
      #expect(hostCallReply.kind == "hostCallReply")
      #expect(hostCallReply.payload == .object(["v": .number(2)]))
    }
  }

  @Test(.timeLimit(.minutes(1))) func fireMessagesBothDirections() async throws {
    try await withPair { pair in
      try await pair.host.fire("cancel", payload: .object(["invocationID": .string("x")]))
      let pluginEvent = try await pair.nextEvent(from: pair.plugin)
      #expect(pluginEvent.envelope.kind == "cancel")

      try await pair.plugin.fire("progress", payload: .object(["fraction": .number(0.5)]))
      let hostEvent = try await pair.nextEvent(from: pair.host)
      #expect(hostEvent.envelope.kind == "progress")
      #expect(hostEvent.envelope.payload == .object(["fraction": .number(0.5)]))
    }
  }

  @Test(.timeLimit(.minutes(1))) func concurrentInFlightFullDuplex() async throws {
    try await withPair { pair in
      // Host awaits invoke while plugin awaits hostCall — both directions at
      // once, replies in reverse order.
      let hostInvoke = Task {
        try await pair.host.request("invoke", payload: .object(["n": .number(1)]))
      }
      let pluginHostCall = Task {
        try await pair.plugin.request("hostCall", payload: .object(["service": .string("ui.form")]))
      }

      let invokeEvent = try await pair.nextEvent(from: pair.plugin)
      #expect(invokeEvent.envelope.kind == "invoke")
      let hostCallEvent = try await pair.nextEvent(from: pair.host)
      #expect(hostCallEvent.envelope.kind == "hostCall")

      // Reverse order: host answers the plugin's call first.
      try await pair.host.reply(to: hostCallEvent.envelope.id, kind: "hostCallReply", payload: .object(["form": .null]))
      let hostCallReply = try await pluginHostCall.value
      #expect(hostCallReply.kind == "hostCallReply")

      try await pair.plugin.reply(to: invokeEvent.envelope.id, kind: "result", payload: .object(["n": .number(2)]))
      let invokeReply = try await hostInvoke.value
      #expect(invokeReply.payload == .object(["n": .number(2)]))
    }
  }

  @Test(.timeLimit(.minutes(1))) func garbageFrameFailsTypedAndCloses() async throws {
    try await withPair { pair in
      let request = Task {
        try await pair.host.request("invoke", payload: .null)
      }
      try await Task.sleep(for: .milliseconds(50))
      var garbage = Data([0x7F])
      garbage.append(contentsOf: withUnsafeBytes(of: UInt32(4).bigEndian) { Data($0) })
      garbage.append(contentsOf: Data("xxxx".utf8))
      pair.injectRaw(garbage, on: pair.fds.1)

      await #expect(throws: ProtocolError.unknownFrameKind(0x7F)) {
        try await request.value
      }
      // The channel is now closed: further sends refuse.
      await #expect(throws: ProtocolError.channelClosed) {
        try await pair.host.request("invoke", payload: .null)
      }
    }
  }

  @Test(.timeLimit(.minutes(1))) func truncatedFrameFailsTyped() async throws {
    try await withPair { pair in
      let request = Task {
        try await pair.host.request("invoke", payload: .null)
      }
      try await Task.sleep(for: .milliseconds(50))
      var partial = Data([Frame.Kind.json.rawValue])
      partial.append(contentsOf: withUnsafeBytes(of: UInt32(100).bigEndian) { Data($0) })
      partial.append(contentsOf: Data("abc".utf8))
      pair.injectRaw(partial, on: pair.fds.1)
      pair.sever(pair.fds.1)

      await #expect(throws: ProtocolError.truncatedFrame) {
        try await request.value
      }
    }
  }

  @Test(.timeLimit(.minutes(1))) func oversizedFrameFailsTyped() async throws {
    try await withPair { pair in
      let request = Task {
        try await pair.host.request("invoke", payload: .null)
      }
      try await Task.sleep(for: .milliseconds(50))
      var header = Data([Frame.Kind.json.rawValue])
      header.append(contentsOf: withUnsafeBytes(of: UInt32(Frame.maxPayloadBytes + 1).bigEndian) { Data($0) })
      pair.injectRaw(header, on: pair.fds.1)
      pair.sever(pair.fds.1)

      await #expect(throws: ProtocolError.oversizedFrame(declared: Frame.maxPayloadBytes + 1)) {
        try await request.value
      }
    }
  }

  @Test(.timeLimit(.minutes(1))) func deeplyNestedPayloadFailsTyped() async throws {
    try await withPair { pair in
      let request = Task {
        try await pair.host.request("invoke", payload: .null)
      }
      try await Task.sleep(for: .milliseconds(50))
      let depth = JSONValue.defaultMaxDepth + 5
      let nested = String(repeating: "[", count: depth) + "0" + String(repeating: "]", count: depth)
      let envelope = #"{"id":0,"kind":"invoke","payload":\#(nested)}"#
      let frame = Frame(json: Data(envelope.utf8))
      pair.injectRaw(try frame.encode(), on: pair.fds.1)
      pair.sever(pair.fds.1)

      await #expect(throws: ProtocolError.jsonNestingTooDeep) {
        try await request.value
      }
    }
  }

  @Test(.timeLimit(.minutes(1))) func peerDeathFailsEveryOutstandingContinuation() async throws {
    try await withPair { pair in
      let requests = (0..<3).map { index in
        Task {
          try await pair.host.request("invoke", payload: .object(["i": .number(Double(index))]))
        }
      }
      _ = try await pair.nextEvent(from: pair.plugin)
      // Abrupt death: no close frame, just the socket going away.
      pair.sever(pair.fds.1)

      for request in requests {
        await #expect(throws: ProtocolError.peerDied) {
          try await request.value
        }
      }
      #expect(await pair.host.pendingRequestCount == 0)
    }
  }

  @Test(.timeLimit(.minutes(1))) func gracefulCloseFailsPendingWithChannelClosed() async throws {
    try await withPair { pair in
      let request = Task {
        try await pair.plugin.request("hostCall", payload: .null)
      }
      _ = try await pair.nextEvent(from: pair.host)
      await pair.host.close()
      await #expect(throws: ProtocolError.channelClosed) {
        try await request.value
      }
    }
  }

  @Test(.timeLimit(.minutes(1))) func inFlightCapEnforced() async throws {
    try await withPair { pair in
      let tasks = (0..<FrameChannel.maxInFlight).map { index in
        Task {
          try await pair.host.request("invoke", payload: .object(["i": .number(Double(index))]))
        }
      }
      let allPending = await pair.eventually {
        await pair.host.pendingRequestCount == FrameChannel.maxInFlight
      }
      #expect(allPending)

      await #expect(throws: ProtocolError.tooManyInFlight) {
        try await pair.host.request("invoke", payload: .null)
      }

      for task in tasks { task.cancel() }
      try? await pair.plugin.fire("result", payload: .null)
    }
  }

  @Test(.timeLimit(.minutes(1))) func timeoutFailsOnlyThatRequest() async throws {
    try await withPair { pair in
      await #expect(throws: ProtocolError.timedOut) {
        try await pair.host.request("invoke", payload: .null, timeout: .milliseconds(100))
      }
      // The orphaned invoke (id 0) still arrives; consume it so the next
      // request's event is unambiguous.
      let stale = try await pair.nextEvent(from: pair.plugin)
      #expect(stale.envelope.kind == "invoke")

      let second = Task {
        try await pair.host.request("invoke", payload: .object(["n": .number(2)]))
      }
      let event = try await pair.nextEvent(from: pair.plugin)
      try await pair.plugin.reply(to: event.envelope.id, kind: "result", payload: .null)
      #expect((try await second.value).kind == "result")
    }
  }

  @Test(.timeLimit(.minutes(1))) func unsolicitedReplyWithOurParityFailsChannel() async throws {
    try await withPair { pair in
      let request = Task {
        try await pair.host.request("invoke", payload: .null)
      }
      try await Task.sleep(for: .milliseconds(50))
      // An envelope with host parity (even) that answers nothing we asked.
      let forged = Envelope(id: 100, kind: "result", payload: .null)
      let frame = Frame(json: try forged.encode().encodeData())
      pair.injectRaw(try frame.encode(), on: pair.fds.1)
      pair.sever(pair.fds.1)

      await #expect(throws: ProtocolError.protocolViolation("unsolicited reply id 100")) {
        try await request.value
      }
    }
  }

  @Test(.timeLimit(.minutes(1))) func replyWithOwnParityRefused() async throws {
    try await withPair { pair in
      await #expect(throws: ProtocolError.protocolViolation("reply id 4 has the wrong parity")) {
        try await pair.host.reply(to: 4, kind: "result", payload: .null)
      }
    }
  }

  @Test(.timeLimit(.minutes(1))) func unknownKindDeliveredAsEvent() async throws {
    try await withPair { pair in
      try await pair.plugin.fire("futureMessageKind", payload: .object(["x": .number(1)]))
      let event = try await pair.nextEvent(from: pair.host)
      #expect(event.envelope.kind == "futureMessageKind")
      #expect(event.envelope.payload == .object(["x": .number(1)]))
    }
  }

  @Test(.timeLimit(.minutes(1))) func missingBlobReferenceFailsTyped() async throws {
    try await withPair { pair in
      let request = Task {
        try await pair.host.request("invoke", payload: .null)
      }
      try await Task.sleep(for: .milliseconds(50))
      // A reply to the pending request (id 0) referencing a blob id that was
      // never sent.
      let forged = Envelope(id: 0, kind: "result", payload: .object(["image": .object(["blob": .number(777)])]))
      let frame = Frame(json: try forged.encode().encodeData())
      pair.injectRaw(try frame.encode(), on: pair.fds.1)
      pair.sever(pair.fds.1)

      await #expect(throws: ProtocolError.missingBlob(id: 777)) {
        try await request.value
      }
    }
  }

  @Test(.timeLimit(.minutes(1))) func blobRoundTrip() async throws {
    try await withPair { pair in
      let imageA = Data((0..<(2 * 1024 * 1024)).map { UInt8($0 % 251) })
      let imageB = Data(repeating: 0xAB, count: 64 * 1024)

      let request = Task {
        try await pair.host.request(
          "invoke",
          payload: .object(["image": .object(["blob": .number(0)]), "thumb": .object(["blob": .number(1)])]),
          blobs: [imageA, imageB]
        )
      }
      let event = try await pair.nextEvent(from: pair.plugin)
      // The plugin sees blob ids, not the bytes in JSON. Host parity ids:
      // envelope 0, blobs 0 and 2.
      #expect(event.envelope.payload.blobIDs == [0, 2])

      try await pair.plugin.reply(
        to: event.envelope.id,
        kind: "result",
        payload: .object(["echo": .object(["blob": .number(0)])]),
        blobs: [imageA]
      )
      let reply = try await request.value
      #expect(reply.blobs.values.contains(imageA))
      #expect(
        reply.payload.resolvingBlobs(from: reply.blobs)
          == .object(["echo": .string(imageA.base64EncodedString())])
      )
    }
  }
}
