import Foundation

public struct Arguments: Sendable {
  public let command: String
  private let flags: [String: String]
  private let switches: Set<String>
  public let positional: [String]

  public init(_ raw: [String]) {
    var remaining = raw
    command = remaining.first.map { $0.hasPrefix("-") ? "help" : $0 } ?? "help"
    if !remaining.isEmpty, !remaining[0].hasPrefix("-") { remaining.removeFirst() }

    var flags: [String: String] = [:]
    var switches: Set<String> = []
    var positional: [String] = []

    var index = 0
    while index < remaining.count {
      let token = remaining[index]
      if token.hasPrefix("--") {
        let name = String(token.dropFirst(2))
        if index + 1 < remaining.count, !remaining[index + 1].hasPrefix("--") {
          flags[name] = remaining[index + 1]
          index += 2
          continue
        }
        switches.insert(name)
      } else if token.hasPrefix("-") {
        let name = String(token.dropFirst())
        if index + 1 < remaining.count, !remaining[index + 1].hasPrefix("-") {
          flags[name] = remaining[index + 1]
          index += 2
          continue
        }
        switches.insert(name)
      } else {
        positional.append(token)
      }
      index += 1
    }

    self.flags = flags
    self.switches = switches
    self.positional = positional
  }

  public func value(_ name: String) -> String? { flags[name] }

  public func has(_ name: String) -> Bool { switches.contains(name) || flags[name] != nil }

  public func requiredValue(_ name: String) throws -> String {
    guard let value = flags[name] else {
      throw CLIError.missingOption("--\(name)")
    }
    return value
  }
}
