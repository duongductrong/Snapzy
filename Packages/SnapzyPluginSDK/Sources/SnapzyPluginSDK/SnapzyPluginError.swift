import Foundation

public enum SnapzyPluginError: Error, LocalizedError, Sendable, CustomStringConvertible {
  case denied(capability: String, reason: String)
  case failed(String)
  case cancelled
  case invalidArgument(String)
  case hostCallFailed(String)
  case missingAsset

  public var errorDescription: String? {
    switch self {
    case .denied(let capability, let reason):
      return "Capability '\(capability)' denied: \(reason)"
    case .failed(let message):
      return message
    case .cancelled:
      return "Operation was cancelled"
    case .invalidArgument(let message):
      return "Invalid argument: \(message)"
    case .hostCallFailed(let message):
      return "Host call failed: \(message)"
    case .missingAsset:
      return "No asset was provided for this invocation"
    }
  }

  public var description: String {
    errorDescription ?? "SnapzyPluginError"
  }
}
