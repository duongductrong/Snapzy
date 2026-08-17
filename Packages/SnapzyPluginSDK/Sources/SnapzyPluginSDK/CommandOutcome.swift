import Foundation
import SnapzyPluginAPI

/// Ergonomic outcome returned by a command handler.
public enum CommandOutcome: Sendable, Equatable {
  case completed
  case patch([DocumentEdit])
  case text(String)
  case url(URL)
  case asset(SnapzyAssetRef)
  case failed(String)

  public var isSuccess: Bool {
    if case .failed = self { return false }
    return true
  }

  public static func completed(_ message: String? = nil) -> CommandOutcome {
    if let message { return .text(message) }
    return .completed
  }

  public static func url(_ string: String) -> CommandOutcome {
    if let url = URL(string: string) {
      return .url(url)
    }
    return .failed("Invalid URL: \(string)")
  }

  public func toResponse() -> SnapzyCommandResponse {
    switch self {
    case .completed:
      return SnapzyCommandResponse(outcome: .completed)
    case .patch(let edits):
      return SnapzyCommandResponse(outcome: .patch(edits))
    case .text(let text):
      return SnapzyCommandResponse(outcome: .text(text))
    case .url(let url):
      return SnapzyCommandResponse(outcome: .url(url))
    case .asset(let asset):
      return SnapzyCommandResponse(outcome: .asset(asset))
    case .failed(let message):
      return SnapzyCommandResponse(outcome: .failed(message: message))
    }
  }

  public static func fromResponse(_ response: SnapzyCommandResponse) -> CommandOutcome {
    switch response.outcome {
    case .completed:
      return .completed
    case .patch(let edits):
      return .patch(edits)
    case .text(let text):
      return .text(text)
    case .url(let url):
      return .url(url)
    case .asset(let asset):
      return .asset(asset)
    case .failed(let message):
      return .failed(message)
    }
  }
}
