import Foundation

enum ProcessRunner {
  struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
  }

  @discardableResult
  static func run(
    _ executable: String,
    arguments: [String],
    currentDirectory: URL? = nil,
    environment: [String: String]? = nil
  ) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if let currentDirectory {
      process.currentDirectoryURL = currentDirectory
    }
    if let environment {
      process.environment = environment
    }

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

    let result = ProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    if result.exitCode != 0 {
      throw CLIError.commandFailed(
        command: ([executable] + arguments).joined(separator: " "),
        exitCode: result.exitCode,
        stderr: stderr.isEmpty ? stdout : stderr
      )
    }
    return result
  }

  static func which(_ tool: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = [tool]
    let pipe = Pipe()
    process.standardOutput = pipe
    try? process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return path?.isEmpty == false ? path : nil
  }
}
