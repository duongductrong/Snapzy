//
//  CLIRequestRouter.swift
//  Snapzy
//
//  Maps `snapzy` CLI methods to handlers. Decodes typed params, runs the
//  handler, and always answers with an encoded response envelope — every
//  failure becomes a `CLIError` the CLI can turn into an exit code.
//

import Foundation
import SnapzyCLIProtocol

nonisolated struct CLIRequestContext: Sendable {
  let connectionID: UUID
  let peerPID: pid_t?
  /// The app behind the CLI, resolved once at handshake.
  var caller: CLICallerIdentity?
  /// The user chose "Allow Once" earlier on this connection.
  var isAllowedForConnection = false
}

nonisolated protocol CLIRequestHandling: Sendable {
  associatedtype Params: Codable & Sendable
  associatedtype Result: Codable & Sendable

  func handle(_ params: Params, context: CLIRequestContext) async throws -> Result
}

nonisolated struct CLIRequestRouter: Sendable {
  typealias Route = @Sendable (_ payload: Data, _ id: UInt64, _ context: CLIRequestContext) async -> Data

  private var routes: [String: Route] = [:]

  init() {}

  mutating func register<Handler: CLIRequestHandling>(_ method: CLIMethod, _ handler: Handler) {
    routes[method.rawValue] = { payload, id, context in
      let params: Handler.Params
      do {
        params = try CLIJSON.makeDecoder().decode(CLIRequestEnvelope<Handler.Params>.self, from: payload).params
      } catch {
        return Self.encode(
          CLIError(.invalidArguments, "Invalid params for \(method.rawValue): \(Self.describe(error))"),
          id: id
        )
      }

      do {
        return try await Self.encode(result: handler.handle(params, context: context), id: id)
      } catch let error as CLIError {
        return Self.encode(error, id: id)
      } catch {
        DiagnosticLogger.shared.logError(.cli, error, "CLI handler failed", context: ["method": method.rawValue])
        return Self.encode(CLIError(.internal, error.localizedDescription), id: id)
      }
    }
  }

  var registeredMethods: Set<String> {
    Set(routes.keys)
  }

  func response(for payload: Data, header: CLIRequestHeader, context: CLIRequestContext) async -> Data {
    guard let route = routes[header.method] else {
      return Self.encode(
        CLIError(
          .unknownMethod,
          "Snapzy does not support \(header.method)",
          hint: "Update Snapzy to match this snapzy command"
        ),
        id: header.id
      )
    }

    let start = Date()
    let response = await route(payload, header.id, context)
    DiagnosticLogger.shared.log(
      .debug,
      .cli,
      "CLI request handled",
      context: [
        "method": header.method,
        "durationMs": String(Int(Date().timeIntervalSince(start) * 1000)),
      ]
    )
    return response
  }

  // MARK: - Encoding

  static func encode(_ error: CLIError, id: UInt64) -> Data {
    (try? CLIJSON.makeEncoder().encode(CLIResponseEnvelope<CLIEmpty>(id: id, error: error)))
      ?? Data(#"{"error":{"code":"internal","message":"Could not encode error"},"id":\#(id)}"#.utf8)
  }

  static func encode(result: some Codable & Sendable, id: UInt64) -> Data {
    do {
      return try CLIJSON.makeEncoder().encode(CLIResponseEnvelope(id: id, result: result))
    } catch {
      return encode(CLIError(.internal, "Could not encode result: \(error.localizedDescription)"), id: id)
    }
  }

  private static func describe(_ error: Error) -> String {
    guard let decodingError = error as? DecodingError else { return error.localizedDescription }
    switch decodingError {
    case .keyNotFound(let key, let context):
      return "missing \(path(context.codingPath + [key]))"
    case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
      let location = context.codingPath.isEmpty ? "" : "\(path(context.codingPath)): "
      return location + context.debugDescription
    @unknown default:
      return decodingError.localizedDescription
    }
  }

  private static func path(_ codingPath: [CodingKey]) -> String {
    codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
  }
}
