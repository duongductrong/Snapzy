import Foundation

public enum CLIError: Error, LocalizedError, CustomStringConvertible {
  case missingOption(String)
  case invalidOption(String, reason: String)
  case missingArgument(String)
  case fileNotFound(String)
  case commandFailed(command: String, exitCode: Int32, stderr: String)
  case validationFailed(String)
  case signingFailed(String)
  case custom(String)

  public var description: String {
    switch self {
    case .missingOption(let opt):
      return "Missing required option: \(opt)"
    case .invalidOption(let opt, let reason):
      return "Invalid option \(opt): \(reason)"
    case .missingArgument(let arg):
      return "Missing required argument: \(arg)"
    case .fileNotFound(let path):
      return "File not found at \(path)"
    case .commandFailed(let cmd, let code, let stderr):
      return "Command '\(cmd)' failed with exit code \(code): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
    case .validationFailed(let msg):
      return "Validation failed: \(msg)"
    case .signingFailed(let msg):
      return "Signing failed: \(msg)"
    case .custom(let msg):
      return msg
    }
  }

  public var errorDescription: String? { description }
}

public func printError(_ message: String) {
  FileHandle.standardError.write(Data((message + "\n").utf8))
}
