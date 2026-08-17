import Foundation

/// A tiny hand-rolled option parser.
///
/// Hand-rolled because PluginKit has no external dependencies, and a plugin
/// author's toolchain is the last place to introduce one — this CLI exists so an
/// author can inspect a host and check a manifest, and it should be installable
/// without dragging a package graph along.
struct Arguments {
    let command: String
    private let flags: [String: String]
    private let switches: Set<String>
    let positional: [String]

    init(_ raw: [String]) {
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
                // `--flag value` is a flag; `--flag --other` and a trailing
                // `--flag` are switches. Inferring from the next token keeps the
                // parser one pass and needs no per-command schema.
                if index + 1 < remaining.count, !remaining[index + 1].hasPrefix("--") {
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

    func value(_ name: String) -> String? { flags[name] }

    func has(_ name: String) -> Bool { switches.contains(name) || flags[name] != nil }

    func requiredValue(_ name: String) throws -> String {
        guard let value = flags[name] else {
            throw CLIError.missingOption("--\(name)")
        }
        return value
    }
}

enum CLIError: Error, CustomStringConvertible {
    case missingOption(String)
    case notFound(String)
    case invalid(String)
    case failed(String)

    var description: String {
        switch self {
        case .missingOption(let name): return "Missing required option \(name)."
        case .notFound(let what): return "Not found: \(what)"
        case .invalid(let what): return "Invalid: \(what)"
        case .failed(let message): return message
        }
    }
}

/// Writes to stderr, so a shell pipeline reading `describe` output is not polluted
/// by diagnostics.
func printError(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
}
