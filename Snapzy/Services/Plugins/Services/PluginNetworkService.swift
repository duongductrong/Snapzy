import AppKit
import Foundation
import SnapzyPluginAPI

/// `http.fetch` — ephemeral URLSession, no cookies, TLS required (plain HTTP
/// only for localhost), redirects re-validated against the allowlist, 60 s
/// timeout, 25 MB response cap. The allowlist is the *attenuated* granted
/// scope; it is enforced host-side and re-checked per call.
final class PluginNetworkService: NSObject, URLSessionDataDelegate {
  static let maxResponseBytes = 25 * 1024 * 1024
  static let timeout: TimeInterval = 60

  private var pendingBytes: [Int: Int] = [:]
  private let pendingLock = NSLock()

  func fetch(
    _ request: PluginHTTPRequest,
    allowedHosts: [String]
  ) async throws -> PluginHTTPResponse? {
    guard let url = URL(string: request.url) else {
      throw PluginServiceError(code: "badURL", message: "“\(request.url)” is not a valid URL.")
    }
    let host = url.host?.lowercased() ?? ""

    // TLS required, except localhost — enforced before any connection.
    let isLocalHost = host == "localhost" || host == "127.0.0.1" || host == "::1"
    guard url.scheme?.lowercased() == "https" || (url.scheme?.lowercased() == "http" && isLocalHost) else {
      throw PluginServiceError(code: "insecureScheme", message: "Only https:// URLs are allowed (http:// is permitted for localhost only).")
    }
    guard !host.isEmpty else {
      throw PluginServiceError(code: "badHost", message: "The URL has no host.")
    }

    // Allowlist, pre-flight.
    guard allowedHosts.isEmpty || allowedHosts.contains(host) else {
      throw PluginServiceError(code: "hostNotAllowed", message: "Host “\(host)” is outside the granted network scope.")
    }

    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = request.method
    urlRequest.timeoutInterval = Self.timeout
    urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
    for (name, value) in request.headers {
      urlRequest.setValue(value, forHTTPHeaderField: name)
    }
    urlRequest.httpBody = request.body

    let session = URLSession(
      configuration: .ephemeral,
      delegate: self,
      delegateQueue: nil
    )

    return try await withCheckedThrowingContinuation { continuation in
      var task: URLSessionDataTask?
      task = session.dataTask(with: urlRequest) { data, response, error in
        defer { session.invalidateAndCancel() }
        if let error {
          continuation.resume(throwing: PluginServiceError(code: "networkError", message: error.localizedDescription))
          return
        }
        guard let http = response as? HTTPURLResponse else {
          continuation.resume(throwing: PluginServiceError(code: "networkError", message: "No HTTP response."))
          return
        }
        let body = data ?? Data()
        guard body.count <= Self.maxResponseBytes else {
          continuation.resume(throwing: PluginServiceError(code: "responseTooLarge", message: "The response exceeded the 25 MB cap."))
          return
        }
        continuation.resume(
          returning: PluginHTTPResponse(
            status: http.statusCode,
            headers: http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
              guard let key = pair.key as? String, let value = pair.value as? String else { return }
              result[key] = value
            },
            body: body
          )
        )
      }
      task?.resume()
    }
  }

  /// Redirects leaving the granted scope are refused mid-flight.
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    guard let original = task.originalRequest?.url, let redirected = request.url else {
      completionHandler(nil)
      return
    }
    let originalHost = original.host?.lowercased() ?? ""
    let redirectedHost = redirected.host?.lowercased() ?? ""
    // The allowlist was checked pre-flight against the original host; a
    // redirect must stay on the same host (deliberately strict for v1).
    if redirectedHost == originalHost {
      completionHandler(request)
    } else {
      completionHandler(nil)
    }
  }
}
