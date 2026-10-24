//
//  CLIClient.swift
//  SnapzyCLIClient
//
//  Typed request/response calls over a handshaken connection. Every failure
//  surfaces as a `CLIError` so commands only map one error type to exit codes.
//

import Foundation
import SnapzyCLIProtocol

public final class CLIClient {
  public private(set) var hello: HelloResponse
  public let requestTimeout: TimeInterval

  private let connection: SocketConnection
  private var nextRequestID: UInt64 = 1

  /// Performs the `hello` handshake on an open connection.
  public init(connection: SocketConnection, cliVersion: String, requestTimeout: TimeInterval) throws {
    self.connection = connection
    self.requestTimeout = requestTimeout
    hello = HelloResponse(appVersion: "", appBuild: "", bundleID: "")

    let response = try send(
      .hello,
      params: HelloRequest(cliVersion: cliVersion, pid: ProcessInfo.processInfo.processIdentifier),
      as: HelloResponse.self,
      timeout: min(requestTimeout, 5)
    )
    guard response.protocolVersion.isCompatible(with: .current) else {
      throw CLIError(
        .versionMismatch,
        "Snapzy speaks CLI protocol \(response.protocolVersion), this snapzy command speaks \(ProtocolVersion.current)",
        hint: "Use the snapzy command from the running Snapzy.app (Contents/Helpers/snapzy) or update Snapzy"
      )
    }
    hello = response
  }

  public func call<Result: Codable & Sendable>(
    _ method: CLIMethod,
    params: some Codable & Sendable,
    as resultType: Result.Type
  ) throws -> Result {
    try send(method, params: params, as: resultType, timeout: requestTimeout)
  }

  public func call<Result: Codable & Sendable>(_ method: CLIMethod, as resultType: Result.Type) throws -> Result {
    try call(method, params: CLIEmpty(), as: resultType)
  }

  public func close() {
    connection.close()
  }

  private func send<Result: Codable & Sendable>(
    _ method: CLIMethod,
    params: some Codable & Sendable,
    as _: Result.Type,
    timeout: TimeInterval
  ) throws -> Result {
    let id = nextRequestID
    nextRequestID += 1

    let payload: Data
    do {
      payload = try CLIJSON.makeEncoder().encode(CLIRequestEnvelope(id: id, method: method, params: params))
    } catch {
      throw CLIError(.internal, "Could not encode \(method.rawValue) request: \(error)")
    }

    let responseData: Data
    do {
      do {
        try connection.send(payload, timeout: timeout)
      } catch SocketConnectionError.closedByPeer {
        // The app may have answered and closed before reading this request
        // (e.g. `busy` when too many commands run); read that answer if it's there.
      }
      responseData = try connection.receive(timeout: timeout)
    } catch let error as SocketConnectionError {
      throw Self.cliError(for: error, method: method)
    }

    let response: CLIResponseEnvelope<Result>
    do {
      response = try CLIJSON.makeDecoder().decode(CLIResponseEnvelope<Result>.self, from: responseData)
    } catch {
      throw CLIError(.internal, "Snapzy sent an unreadable \(method.rawValue) response: \(error)")
    }

    // id 0 is the app's answer to a request it could not read; its error is
    // more useful than an id mismatch.
    if let error = response.error, response.id == id || response.id == 0 {
      throw error
    }
    guard response.id == id else {
      throw CLIError(.internal, "Snapzy answered request \(response.id), expected \(id)")
    }
    guard let result = response.result else {
      throw CLIError(.internal, "Snapzy sent an empty \(method.rawValue) response")
    }
    return result
  }

  static func cliError(for error: SocketConnectionError, method: CLIMethod) -> CLIError {
    switch error {
    case .timedOut:
      CLIError(
        .appUnavailable,
        "Snapzy did not answer \(method.rawValue) in time",
        hint: "Retry with a larger --timeout, or run `snapzy doctor`"
      )
    case .closedByPeer:
      CLIError(.appUnavailable, "Snapzy closed the connection during \(method.rawValue)")
    case .frame(let frameError):
      CLIError(.internal, "Invalid frame during \(method.rawValue): \(frameError)")
    case .socketMissing, .connectionRefused, .pathTooLong, .system:
      CLIError(.appUnavailable, "Lost the connection to Snapzy: \(error)")
    }
  }
}
