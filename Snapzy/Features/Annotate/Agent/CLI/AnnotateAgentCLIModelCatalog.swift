//
//  AnnotateAgentCLIModelCatalog.swift
//  Snapzy
//
//  Models and reasoning-effort levels each agent CLI offers, so Settings can
//  show a picker instead of asking for a raw model string. Claude Code takes
//  stable aliases; Codex lists its models in ~/.codex/models_cache.json;
//  OpenCode prints `provider/model` lines from `opencode models`.
//

import Combine
import Foundation

nonisolated struct AnnotateAgentCLIModelOption: Hashable, Identifiable, Sendable {
  /// The value passed to `--model`.
  let id: String
  let name: String
  /// OpenCode's provider, for grouping the menu.
  var group: String?
  /// Reasoning effort levels the model takes, lowest first.
  var efforts: [String]
}

nonisolated enum AnnotateAgentCLIEffort {
  /// Effort levels a CLI takes when the model doesn't say.
  static func levels(for kind: AnnotateAgentCLIKind) -> [String] {
    switch kind {
    case .claudeCode: ["low", "medium", "high", "xhigh", "max"]
    case .codex: ["low", "medium", "high", "xhigh"]
    case .openCode: ["low", "medium", "high", "max"]
    }
  }

  private static let order = ["minimal", "low", "medium", "high", "xhigh", "max", "ultra"]

  static func sorted(_ levels: [String]) -> [String] {
    var seen = Set<String>()
    return levels.filter { seen.insert($0).inserted }.sorted {
      (order.firstIndex(of: $0) ?? order.count) < (order.firstIndex(of: $1) ?? order.count)
    }
  }
}

nonisolated enum AnnotateAgentCLIModelCatalog {
  /// Blocking (runs `opencode models`); call off the main thread.
  static func load(_ kind: AnnotateAgentCLIKind, executable: String?) -> [AnnotateAgentCLIModelOption] {
    switch kind {
    case .claudeCode:
      let efforts = AnnotateAgentCLIEffort.levels(for: .claudeCode)
      return [
        AnnotateAgentCLIModelOption(id: "opus", name: "Opus", efforts: efforts),
        AnnotateAgentCLIModelOption(id: "sonnet", name: "Sonnet", efforts: efforts),
        AnnotateAgentCLIModelOption(id: "haiku", name: "Haiku", efforts: efforts),
      ]
    case .codex:
      return codexModels()
    case .openCode:
      guard let executable else { return [] }
      let environment = AnnotateAgentCLIEnvironment.environment(forExecutable: executable)
      let output = AnnotateAgentCLIEnvironment.run(executable, ["models"], environment: environment, timeout: 20) ?? ""
      return openCodeModels(from: output)
    }
  }

  static func codexModels(home: String = NSHomeDirectory()) -> [AnnotateAgentCLIModelOption] {
    let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 }
      ?? (home as NSString).appendingPathComponent(".codex")
    let url = URL(fileURLWithPath: codexHome).appendingPathComponent("models_cache.json")
    guard let data = try? Data(contentsOf: url) else { return [] }
    return codexModels(from: data)
  }

  static func codexModels(from data: Data) -> [AnnotateAgentCLIModelOption] {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let models = object["models"] as? [[String: Any]] else { return [] }
    return models
      .filter { ($0["visibility"] as? String ?? "list") == "list" }
      .sorted { ($0["priority"] as? Int ?? .max) < ($1["priority"] as? Int ?? .max) }
      .compactMap { model in
        guard let slug = model["slug"] as? String, !slug.isEmpty else { return nil }
        let levels = (model["supported_reasoning_levels"] as? [[String: Any]] ?? []).compactMap { $0["effort"] as? String }
        return AnnotateAgentCLIModelOption(
          id: slug,
          name: model["display_name"] as? String ?? slug,
          efforts: levels.isEmpty ? AnnotateAgentCLIEffort.levels(for: .codex) : AnnotateAgentCLIEffort.sorted(levels)
        )
      }
  }

  static func openCodeModels(from output: String) -> [AnnotateAgentCLIModelOption] {
    var seen = Set<String>()
    return output.split(whereSeparator: \.isNewline).compactMap { raw in
      let line = raw.trimmingCharacters(in: .whitespaces)
      guard !line.contains(" "), let slash = line.firstIndex(of: "/"), slash != line.startIndex,
            line.index(after: slash) != line.endIndex, seen.insert(line).inserted else { return nil }
      return AnnotateAgentCLIModelOption(
        id: line,
        name: String(line[line.index(after: slash)...]),
        group: String(line[..<slash]),
        efforts: AnnotateAgentCLIEffort.levels(for: .openCode)
      )
    }
  }
}

/// Settings' cache of the catalogs, loaded once per page visit (or on Refresh).
@MainActor
final class AnnotateAgentCLIModelCatalogStore: ObservableObject {
  static let shared = AnnotateAgentCLIModelCatalogStore()

  @Published private(set) var models: [AnnotateAgentCLIKind: [AnnotateAgentCLIModelOption]] = [:]
  @Published private(set) var loading: Set<AnnotateAgentCLIKind> = []

  func refresh(_ kind: AnnotateAgentCLIKind, executable: String?, force: Bool = false) {
    guard !loading.contains(kind), force || models[kind] == nil else { return }
    loading.insert(kind)
    Task {
      let result = await Task.detached(priority: .utility) {
        AnnotateAgentCLIModelCatalog.load(kind, executable: executable)
      }.value
      models[kind] = result
      loading.remove(kind)
    }
  }
}
