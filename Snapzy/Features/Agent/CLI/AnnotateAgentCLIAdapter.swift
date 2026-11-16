//
//  AnnotateAgentCLIAdapter.swift
//  Snapzy
//
//  What differs between agent CLIs: how to start one headless with only
//  Snapzy's MCP server (no shell, file or web tools), and how to read its
//  event stream. Verified against Claude Code 2.1, Codex CLI 0.169, OpenCode 2.1.
//

import Foundation

/// How the agent starts `snapzy mcp`.
nonisolated struct AnnotateAgentMCPLaunch: Equatable {
  /// Absolute path of the embedded helper (`Snapzy.app/Contents/Helpers/snapzy`).
  let helperPath: String
  let token: String
  /// `SNAPZY_SOCKET` when the app runs with an override (tests, long home paths).
  var socketOverride: String?

  static let serverName = "snapzy"

  var environment: [String: String] {
    var environment = ["SNAPZY_AGENT_SESSION": token]
    if let socketOverride { environment["SNAPZY_SOCKET"] = socketOverride }
    return environment
  }

  var arguments: [String] { ["mcp"] }
}

nonisolated struct AnnotateAgentCLIInvocation: Equatable {
  var arguments: [String]
  /// Added to the process environment.
  var environment: [String: String] = [:]
  /// Written into the working directory before launch (file name → contents), removed after.
  var files: [String: String] = [:]
  /// Sent on stdin instead of argv: no `E2BIG` for big scenes, and the screenshot's
  /// text stays out of `ps`. `nil` = /dev/null.
  var stdin: String?
}

nonisolated struct AnnotateAgentCLIRunInput: Equatable {
  /// Full prompt text (instructions are in `systemPrompt` where the CLI supports one).
  let prompt: String
  let systemPrompt: String
  let resumeSessionID: String?
  let model: String?
  /// Reasoning effort ("low", "high"…); `nil` = the CLI's default.
  var effort: String? = nil
  let mcp: AnnotateAgentMCPLaunch
  /// The CLI's private working directory. Stable per CLI, because Claude Code keys
  /// saved conversations by working directory and `--resume` must find them.
  let directory: String
  /// Unique per run, for file names in the shared working directory.
  var runID: String = "run"
  /// Screenshot JPEG to attach, for CLIs that take image files.
  let imagePath: String?
}

nonisolated enum AnnotateAgentCLIEvent: Equatable {
  case session(String)
  /// Assistant text; the last one is the reply.
  case message(String)
  case failure(String)
}

nonisolated enum AnnotateAgentCLIAdapter {
  static func mcpConfigFileName(_ runID: String) -> String { "snapzy-mcp-\(runID).json" }
  /// Not `opencode.json`: OpenCode would also load that from the working directory.
  static func openCodeConfigFileName(_ runID: String) -> String { "snapzy-opencode-\(runID).json" }

  static func invocation(for kind: AnnotateAgentCLIKind, _ input: AnnotateAgentCLIRunInput) -> AnnotateAgentCLIInvocation {
    switch kind {
    case .claudeCode: claudeCode(input)
    case .codex: codex(input)
    case .openCode: openCode(input)
    }
  }

  // MARK: Claude Code

  private static func claudeCode(_ input: AnnotateAgentCLIRunInput) -> AnnotateAgentCLIInvocation {
    let server: [String: Any] = [
      "type": "stdio",
      "command": input.mcp.helperPath,
      "args": input.mcp.arguments,
      "env": input.mcp.environment,
    ]
    let config = json(["mcpServers": [AnnotateAgentMCPLaunch.serverName: server]])
    let configName = mcpConfigFileName(input.runID)
    let configPath = (input.directory as NSString).appendingPathComponent(configName)
    var arguments = [
      "-p",
      "--output-format", "stream-json",
      "--verbose",
      "--mcp-config", configPath,
      "--strict-mcp-config",
      // No built-in tools (Bash, Read, Edit, WebFetch…): only Snapzy's.
      "--tools", "",
      "--allowedTools", "mcp__\(AnnotateAgentMCPLaunch.serverName)",
      "--permission-mode", "dontAsk",
      "--append-system-prompt", input.systemPrompt,
    ]
    if let resume = input.resumeSessionID { arguments += ["--resume", resume] }
    if let model = input.model { arguments += ["--model", model] }
    if let effort = input.effort { arguments += ["--effort", effort] }
    // `-p` with no prompt argument reads it from stdin.
    return AnnotateAgentCLIInvocation(arguments: arguments, files: [configName: config], stdin: input.prompt)
  }

  // MARK: Codex

  private static func codex(_ input: AnnotateAgentCLIRunInput) -> AnnotateAgentCLIInvocation {
    let name = AnnotateAgentMCPLaunch.serverName
    let env = input.mcp.environment
      .sorted { $0.key < $1.key }
      .map { "\($0.key)=\(toml($0.value))" }
      .joined(separator: ", ")
    let overrides = [
      "mcp_servers.\(name).command=\(toml(input.mcp.helperPath))",
      "mcp_servers.\(name).args=[\(input.mcp.arguments.map(toml).joined(separator: ", "))]",
      "mcp_servers.\(name).env={\(env)}",
      "mcp_servers.\(name).default_tools_approval_mode=\"approve\"",
      "sandbox_mode=\"read-only\"",
      "approval_policy=\"never\"",
    ]
    var arguments = ["exec"]
    if let resume = input.resumeSessionID { arguments += ["resume"] }
    arguments += ["--json", "--skip-git-repo-check"]
    for override in overrides { arguments += ["-c", override] }
    if let model = input.model { arguments += ["--model", model] }
    if let effort = input.effort { arguments += ["-c", "model_reasoning_effort=\(toml(effort))"] }
    if let image = input.imagePath { arguments += ["--image", image] }
    if let resume = input.resumeSessionID { arguments += [resume] }
    // `-` = prompt from stdin. Instructions lead the first message; a resumed thread has them.
    arguments += ["-"]
    return AnnotateAgentCLIInvocation(arguments: arguments, stdin: firstMessage(input))
  }

  // MARK: OpenCode

  private static func openCode(_ input: AnnotateAgentCLIRunInput) -> AnnotateAgentCLIInvocation {
    let server: [String: Any] = [
      "type": "local",
      "command": [input.mcp.helperPath] + input.mcp.arguments,
      "environment": input.mcp.environment,
    ]
    let config = json([
      "$schema": "https://opencode.ai/config.json",
      "mcp": ["servers": [AnnotateAgentMCPLaunch.serverName: server]],
      // Everything built in that reaches files, the shell or the web.
      "permission": Dictionary(uniqueKeysWithValues: openCodeDeniedTools.map { ($0, "deny") }),
    ])
    let configName = openCodeConfigFileName(input.runID)
    let configPath = (input.directory as NSString).appendingPathComponent(configName)
    // --standalone: a private server that reads OPENCODE_CONFIG; the shared background
    // service would ignore it. OpenCode has no system prompt flag, so instructions lead the message.
    var arguments = ["run", "--standalone", "--format", "json"]
    if let resume = input.resumeSessionID { arguments += ["--session", resume] }
    // Effort is the model's variant (`provider/model#high`); it needs an explicit model.
    if var model = input.model {
      if let effort = input.effort, !model.contains("#") { model += "#\(effort)" }
      arguments += ["--model", model]
    }
    if let image = input.imagePath { arguments += ["--file", image] }
    arguments += ["--", firstMessage(input)]
    return AnnotateAgentCLIInvocation(
      arguments: arguments,
      environment: ["OPENCODE_CONFIG": configPath],
      files: [configName: config]
    )
  }

  static let openCodeDeniedTools = ["bash", "edit", "webfetch", "websearch", "read", "grep", "glob", "list", "task", "codesearch"]

  private static func firstMessage(_ input: AnnotateAgentCLIRunInput) -> String {
    input.resumeSessionID == nil ? input.systemPrompt + "\n\n" + input.prompt : input.prompt
  }

  // MARK: Events

  /// Events in one stdout line. Lines that are not JSON (banners, warnings) yield nothing.
  static func events(in line: String, kind: AnnotateAgentCLIKind) -> [AnnotateAgentCLIEvent] {
    guard let data = line.data(using: .utf8),
          let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let type = object["type"] as? String else { return [] }
    switch kind {
    case .claudeCode: return claudeEvents(object, type: type)
    case .codex: return codexEvents(object, type: type)
    case .openCode: return openCodeEvents(object, type: type)
    }
  }

  private static func claudeEvents(_ object: [String: Any], type: String) -> [AnnotateAgentCLIEvent] {
    var events: [AnnotateAgentCLIEvent] = []
    if let session = object["session_id"] as? String, !session.isEmpty, type == "system" || type == "result" {
      events.append(.session(session))
    }
    switch type {
    case "assistant":
      let content = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
      let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
      if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { events.append(.message(text)) }
    case "result":
      let result = object["result"] as? String
      let isError = object["is_error"] as? Bool ?? false
      let subtype = object["subtype"] as? String ?? ""
      if isError || subtype.hasPrefix("error") {
        let detail = result?.isEmpty == false ? result! : (object["errors"] as? [String])?.first ?? subtype
        events.append(.failure(detail))
      } else if let result, !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        events.append(.message(result))
      }
    default:
      break
    }
    return events
  }

  private static func codexEvents(_ object: [String: Any], type: String) -> [AnnotateAgentCLIEvent] {
    switch type {
    case "thread.started":
      return (object["thread_id"] as? String).map { [.session($0)] } ?? []
    case "item.completed":
      guard let item = object["item"] as? [String: Any] else { return [] }
      let itemType = item["type"] as? String ?? item["item_type"] as? String
      guard itemType == "agent_message" || itemType == "assistant_message",
            let text = item["text"] as? String,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
      return [.message(text)]
    case "turn.failed":
      let message = (object["error"] as? [String: Any])?["message"] as? String
      return [.failure(message ?? "Codex could not finish")]
    case "error":
      return [.failure(object["message"] as? String ?? "Codex reported an error")]
    default:
      return []
    }
  }

  private static func openCodeEvents(_ object: [String: Any], type: String) -> [AnnotateAgentCLIEvent] {
    var events: [AnnotateAgentCLIEvent] = []
    if let session = object["sessionID"] as? String, !session.isEmpty {
      events.append(.session(session))
    }
    switch type {
    case "text":
      if let text = (object["part"] as? [String: Any])?["text"] as? String,
         !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        events.append(.message(text))
      }
    case "error":
      let error = object["error"] as? [String: Any]
      let data = error?["data"] as? [String: Any]
      let message = data?["message"] as? String ?? error?["message"] as? String ?? error?["name"] as? String
      events.append(.failure(message ?? "OpenCode reported an error"))
    default:
      break
    }
    return events
  }

  // MARK: Helpers

  private static func json(_ object: [String: Any]) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
    return String(decoding: data, as: UTF8.self)
  }

  /// A TOML basic string.
  static func toml(_ value: String) -> String {
    var escaped = ""
    for scalar in value.unicodeScalars {
      switch scalar {
      case "\\": escaped += "\\\\"
      case "\"": escaped += "\\\""
      case "\n": escaped += "\\n"
      case "\r": escaped += "\\r"
      case "\t": escaped += "\\t"
      default:
        if scalar.value < 0x20 || scalar.value == 0x7F {
          escaped += String(format: "\\u%04X", scalar.value)
        } else {
          escaped.unicodeScalars.append(scalar)
        }
      }
    }
    return "\"\(escaped)\""
  }
}
