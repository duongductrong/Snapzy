//
//  GoogleDriveOAuthService.swift
//  Snapzy
//
//  Created by DeepMind on 2026-07-12.
//

import Foundation
import Network
import AppKit
import CryptoKit
import os.log

private nonisolated let logger = Logger(subsystem: "Snapzy", category: "GoogleDriveOAuthService")

/// Service handling the OAuth 2.0 Desktop Flow loopback for Google Drive
nonisolated final class GoogleDriveOAuthService: @unchecked Sendable {
  static let shared = GoogleDriveOAuthService()

  private init() {}

  private var listener: NWListener?
  private var activeConnections: [NWConnection] = []
  private let queue = DispatchQueue(label: "com.trongduong.snapzy.oauth")
  private var continuation: SafeContinuation<String, Error>?

  /// Helper to safely resume continuation exactly once
  private struct SafeContinuation<T, E: Error> {
    private let raw: CheckedContinuation<T, E>
    private let resumed = CheckedState()

    init(_ raw: CheckedContinuation<T, E>) {
      self.raw = raw
    }

    func resume(returning value: T) {
      if resumed.markResumed() {
        raw.resume(returning: value)
      }
    }

    func resume(throwing error: E) {
      if resumed.markResumed() {
        raw.resume(throwing: error)
      }
    }

    private class CheckedState: @unchecked Sendable {
      private var value = false
      private let lock = NSLock()

      func markResumed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if !value {
          value = true
          return true
        }
        return false
      }
    }
  }

  // MARK: - Public API

  /// Starts the authorization flow, starts a local server to wait for redirect,
  /// opens user browser, captures the code, and exchanges it for tokens.
  func startAuthorization(clientId: String, clientSecret: String) async throws -> GoogleDriveTokens {
    // 1. Generate PKCE
    let (verifier, challenge) = generatePKCE()

    // 2. Start loopback listener
    let port = try await startListener()
    let redirectUri = "http://127.0.0.1:\(port)"

    // 3. Wait for authorization code
    let code: String
    do {
      code = try await withCheckedThrowingContinuation { continuation in
        self.continuation = SafeContinuation(continuation)
        
        // Construct Authorization URL
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
          URLQueryItem(name: "response_type", value: "code"),
          URLQueryItem(name: "client_id", value: clientId),
          URLQueryItem(name: "redirect_uri", value: redirectUri),
          URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/drive.file https://www.googleapis.com/auth/userinfo.email"),
          URLQueryItem(name: "access_type", value: "offline"),
          URLQueryItem(name: "prompt", value: "consent"),
          URLQueryItem(name: "code_challenge", value: challenge),
          URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let authURL = components.url else {
          continuation.resume(throwing: CloudError.signingFailed("Could not construct authorization URL"))
          return
        }

        // Open browser
        logger.info("Opening authorization URL: \(authURL.absoluteString)")
        NSWorkspace.shared.open(authURL)
      }
    } catch {
      stopListener()
      throw error
    }

    // Delay stopListener() to allow the HTTP server to finish sending the response to the browser
    queue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.stopListener()
    }

    // 4. Exchange code for tokens
    return try await exchangeCodeForTokens(
      code: code,
      verifier: verifier,
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri
    )
  }

  /// Refreshes the access token using the refresh token
  func refreshAccessToken(
    refreshToken: String,
    clientId: String,
    clientSecret: String
  ) async throws -> GoogleDriveTokens {
    var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

    let bodyParams = [
      "grant_type": "refresh_token",
      "refresh_token": refreshToken,
      "client_id": clientId,
      "client_secret": clientSecret
    ]
    request.httpBody = bodyParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
      .joined(separator: "&")
      .data(using: .utf8)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw CloudError.invalidResponse
    }

    guard httpResponse.statusCode == 200 else {
      let responseString = String(data: data, encoding: .utf8) ?? ""
      logger.error("Token refresh failed: \(httpResponse.statusCode), body: \(responseString)")
      throw CloudError.uploadFailed(statusCode: httpResponse.statusCode, message: "Token refresh failed: \(responseString)")
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let tokenResponse = try decoder.decode(GoogleDriveTokenResponse.self, from: data)

    return GoogleDriveTokens(
      accessToken: tokenResponse.accessToken,
      refreshToken: tokenResponse.refreshToken ?? refreshToken, // keep old if not returned
      expiresIn: tokenResponse.expiresIn
    )
  }

  /// Fetches the user email for display in UI
  func fetchUserEmail(accessToken: String) async throws -> String {
    var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
      throw CloudError.invalidResponse
    }

    struct UserInfo: Codable {
      let email: String
    }
    let userInfo = try JSONDecoder().decode(UserInfo.self, from: data)
    return userInfo.email
  }

  // MARK: - Loopback server (NWListener)

  private func startListener() async throws -> UInt16 {
    stopListener()

    let parameters = NWParameters.tcp
    
    // Bind to 127.0.0.1
    let host = NWEndpoint.Host("127.0.0.1")
    parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: host, port: 0)

    let listener = try NWListener(using: parameters)
    self.listener = listener

    return try await withCheckedThrowingContinuation { continuation in
      listener.stateUpdateHandler = { state in
        switch state {
        case .ready:
          if let port = listener.port?.rawValue {
            logger.info("Local OAuth server ready on port \(port)")
            continuation.resume(returning: port)
          } else {
            continuation.resume(throwing: CloudError.signingFailed("Could not determine local port"))
          }
        case .failed(let error):
          logger.error("Local OAuth server failed: \(error.localizedDescription)")
          continuation.resume(throwing: error)
        default:
          break
        }
      }

      listener.newConnectionHandler = { [weak self] connection in
        self?.handleNewConnection(connection)
      }

      listener.start(queue: queue)

      // Timeout safety: cancel listener after 120s if no auth code arrives
      queue.asyncAfter(deadline: .now() + 120.0) { [weak self] in
        self?.continuation?.resume(throwing: CloudError.signingFailed("Authorization timed out after 120 seconds"))
        self?.stopListener()
      }
    }
  }

  private func stopListener() {
    continuation = nil
    listener?.cancel()
    listener = nil
    for connection in activeConnections {
      connection.cancel()
    }
    activeConnections.removeAll()
  }

  private func handleNewConnection(_ connection: NWConnection) {
    activeConnections.append(connection)
    connection.start(queue: queue)
    receive(on: connection)
  }

  private func receive(on connection: NWConnection) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] content, _, isComplete, error in
      guard let self = self else { return }
      guard error == nil, let content = content, !content.isEmpty else {
        self.closeConnection(connection)
        return
      }

      if let requestString = String(data: content, encoding: .utf8) {
        self.parseHTTPRequest(requestString, connection: connection)
      } else {
        self.closeConnection(connection)
      }
    }
  }

  private func closeConnection(_ connection: NWConnection) {
    connection.cancel()
    queue.async { [weak self] in
      self?.activeConnections.removeAll(where: { $0 === connection })
    }
  }

  private func parseHTTPRequest(_ request: String, connection: NWConnection) {
    let lines = request.components(separatedBy: "\r\n")
    guard let firstLine = lines.first else {
      closeConnection(connection)
      return
    }

    let parts = firstLine.components(separatedBy: " ")
    guard parts.count >= 2, parts[0] == "GET" else {
      sendHTTPResponse(statusCode: 400, html: "Bad Request", connection: connection)
      return
    }

    let path = parts[1]
    guard let urlComponents = URLComponents(string: "http://127.0.0.1" + path) else {
      sendHTTPResponse(statusCode: 400, html: "Bad Request", connection: connection)
      return
    }

    // Filter out favicon or other metadata queries
    if path.contains("favicon.ico") {
      sendHTTPResponse(statusCode: 404, html: "Not Found", connection: connection)
      return
    }

    let queryItems = urlComponents.queryItems ?? []
    if let code = queryItems.first(where: { $0.name == "code" })?.value {
      sendSuccessResponse(connection: connection)
      continuation?.resume(returning: code)
    } else if let error = queryItems.first(where: { $0.name == "error" })?.value {
      sendErrorResponse(error: error, connection: connection)
      continuation?.resume(throwing: CloudError.signingFailed("Google OAuth error: \(error)"))
    } else {
      sendHTTPResponse(statusCode: 400, html: "Bad Request", connection: connection)
    }
  }

  private func sendSuccessResponse(connection: NWConnection) {
    let html = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Snapzy Authorization Successful</title>
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
          background-color: #0d0e12;
          color: #f3f4f6;
          display: flex;
          align-items: center;
          justify-content: center;
          height: 100vh;
          margin: 0;
        }
        .container {
          background: rgba(255, 255, 255, 0.03);
          border: 1px solid rgba(255, 255, 255, 0.08);
          border-radius: 20px;
          padding: 40px;
          text-align: center;
          box-shadow: 0 10px 30px rgba(0, 0, 0, 0.3);
          max-width: 400px;
          backdrop-filter: blur(10px);
        }
        .icon {
          font-size: 64px;
          color: #34d399;
          margin-bottom: 20px;
          animation: scaleIn 0.5s ease-out;
        }
        h1 {
          font-size: 24px;
          font-weight: 700;
          margin: 0 0 10px 0;
          letter-spacing: -0.5px;
        }
        p {
          font-size: 14px;
          color: #9ca3af;
          line-height: 1.5;
          margin: 0;
        }
        .action-btn-container {
          margin-top: 24px;
        }
        .btn {
          display: inline-block;
          background: linear-gradient(135deg, #6366f1 0%, #4f46e5 100%);
          color: #ffffff;
          text-decoration: none;
          padding: 12px 24px;
          border-radius: 8px;
          font-weight: 600;
          font-size: 14px;
          transition: all 0.2s ease;
          box-shadow: 0 4px 12px rgba(79, 70, 229, 0.3);
        }
        .btn:hover {
          transform: translateY(-1px);
          box-shadow: 0 6px 16px rgba(79, 70, 229, 0.4);
        }
        .btn:active {
          transform: translateY(1px);
        }
        @keyframes scaleIn {
          0% { transform: scale(0.5); opacity: 0; }
          100% { transform: scale(1); opacity: 1; }
        }
      </style>
      <script>
        // Automatically attempt to redirect back to Snapzy
        setTimeout(function() {
          window.location.href = "snapzy://settings/cloud";
        }, 1000);
      </script>
    </head>
    <body>
      <div class="container">
        <div class="icon">✓</div>
        <h1>Snapzy Authorized!</h1>
        <p>Google Drive authorization was successful. You can close this browser window and return to Snapzy to complete your setup.</p>
        <div class="action-btn-container">
          <a href="snapzy://settings/cloud" class="btn">Return to Snapzy</a>
        </div>
      </div>
    </body>
    </html>
    """
    sendHTTPResponse(statusCode: 200, html: html, connection: connection)
  }

  private func sendErrorResponse(error: String, connection: NWConnection) {
    let html = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Snapzy Authorization Failed</title>
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
          background-color: #0d0e12;
          color: #f3f4f6;
          display: flex;
          align-items: center;
          justify-content: center;
          height: 100vh;
          margin: 0;
        }
        .container {
          background: rgba(255, 255, 255, 0.03);
          border: 1px solid rgba(255, 255, 255, 0.08);
          border-radius: 20px;
          padding: 40px;
          text-align: center;
          box-shadow: 0 10px 30px rgba(0, 0, 0, 0.3);
          max-width: 400px;
          backdrop-filter: blur(10px);
        }
        .icon {
          font-size: 64px;
          color: #ef4444;
          margin-bottom: 20px;
          animation: scaleIn 0.5s ease-out;
        }
        h1 {
          font-size: 24px;
          font-weight: 700;
          margin: 0 0 10px 0;
          letter-spacing: -0.5px;
        }
        p {
          font-size: 14px;
          color: #9ca3af;
          line-height: 1.5;
          margin: 0;
        }
        .action-btn-container {
          margin-top: 24px;
        }
        .btn {
          display: inline-block;
          background: rgba(255, 255, 255, 0.08);
          border: 1px solid rgba(255, 255, 255, 0.15);
          color: #f3f4f6;
          text-decoration: none;
          padding: 12px 24px;
          border-radius: 8px;
          font-weight: 600;
          font-size: 14px;
          transition: all 0.2s ease;
        }
        .btn:hover {
          background: rgba(255, 255, 255, 0.12);
          transform: translateY(-1px);
        }
        .btn:active {
          transform: translateY(1px);
        }
        @keyframes scaleIn {
          0% { transform: scale(0.5); opacity: 0; }
          100% { transform: scale(1); opacity: 1; }
        }
      </style>
      <script>
        // Automatically attempt to redirect back to Snapzy
        setTimeout(function() {
          window.location.href = "snapzy://settings/cloud";
        }, 1500);
      </script>
    </head>
    <body>
      <div class="container">
        <div class="icon">✕</div>
        <h1>Authorization Failed</h1>
        <p>Google Drive authorization failed with error: <strong>\(error)</strong>. Please return to Snapzy and try again.</p>
        <div class="action-btn-container">
          <a href="snapzy://settings/cloud" class="btn">Return to Snapzy</a>
        </div>
      </div>
    </body>
    </html>
    """
    sendHTTPResponse(statusCode: 400, html: html, connection: connection)
  }

  private func sendHTTPResponse(statusCode: Int, html: String, connection: NWConnection) {
    let responseBody = html.data(using: .utf8) ?? Data()
    let responseHeader = """
    HTTP/1.1 \(statusCode) \(statusCode == 200 ? "OK" : "Bad Request")\r
    Content-Type: text/html; charset=UTF-8\r
    Content-Length: \(responseBody.count)\r
    Connection: close\r
    \r
    """

    guard let responseHeaderData = responseHeader.data(using: .utf8) else {
      closeConnection(connection)
      return
    }

    var fullData = Data()
    fullData.append(responseHeaderData)
    fullData.append(responseBody)

    connection.send(content: fullData, completion: .contentProcessed({ [weak self] error in
      if let error = error {
        logger.error("Failed to send HTTP response: \(error.localizedDescription)")
      }
      // Delay closing/cancelling the connection by 0.5s to ensure the client fully reads it
      self?.queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        self?.closeConnection(connection)
      }
    }))
  }

  // MARK: - OAuth Helpers

  func generatePKCE() -> (verifier: String, challenge: String) {
    let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
    let verifier = String((0..<64).compactMap { _ in characters.randomElement() })
    guard let data = verifier.data(using: .utf8) else { return (verifier, "") }
    let digest = SHA256.hash(data: data)
    let challenge = Data(digest)
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    return (verifier, challenge)
  }

  private func exchangeCodeForTokens(
    code: String,
    verifier: String,
    clientId: String,
    clientSecret: String,
    redirectUri: String
  ) async throws -> GoogleDriveTokens {
    var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

    let bodyParams = [
      "code": code,
      "client_id": clientId,
      "client_secret": clientSecret,
      "redirect_uri": redirectUri,
      "grant_type": "authorization_code",
      "code_verifier": verifier
    ]
    request.httpBody = bodyParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
      .joined(separator: "&")
      .data(using: .utf8)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw CloudError.invalidResponse
    }

    guard httpResponse.statusCode == 200 else {
      let responseString = String(data: data, encoding: .utf8) ?? ""
      logger.error("Token exchange failed: \(httpResponse.statusCode), body: \(responseString)")
      throw CloudError.uploadFailed(statusCode: httpResponse.statusCode, message: "Token exchange failed: \(responseString)")
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let tokenResponse = try decoder.decode(GoogleDriveTokenResponse.self, from: data)

    guard let refreshToken = tokenResponse.refreshToken else {
      throw CloudError.signingFailed("No refresh token received. Ensure prompt=consent or access_type=offline is set.")
    }

    return GoogleDriveTokens(
      accessToken: tokenResponse.accessToken,
      refreshToken: refreshToken,
      expiresIn: tokenResponse.expiresIn
    )
  }
}

// MARK: - API Types

struct GoogleDriveTokens {
  let accessToken: String
  let refreshToken: String
  let expiresIn: Int
}

private nonisolated struct GoogleDriveTokenResponse: Codable {
  let accessToken: String
  let refreshToken: String?
  let expiresIn: Int
  let tokenType: String
}
