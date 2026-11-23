//
//  AutomationIntegrationConfigs.swift
//  Snapzy
//
//  Settings for milestone 4 integration steps: upload destination, webhook,
//  shell script, Apple Shortcut, share sheet and open in app. Like every step
//  config they decode tolerantly, so a hand-edited TOML never drops a step.
//

import Foundation

// MARK: - Shared

nonisolated enum AutomationHTTPMethod: String, Codable, CaseIterable, Identifiable, Sendable {
  case get = "GET"
  case post = "POST"
  case put = "PUT"
  case patch = "PATCH"
  case delete = "DELETE"

  var id: String { rawValue }

  /// Methods that send a request body.
  var hasBody: Bool { self != .get && self != .delete }
}

/// An ordered name / value pair (HTTP header, form field). Values may hold
/// `{token}`s and, where the field allows it, `{secret:NAME}`.
nonisolated struct AutomationKeyValue: Codable, Equatable, Hashable, Identifiable, Sendable {
  var id: UUID
  var name: String
  var value: String

  init(id: UUID = UUID(), name: String, value: String) {
    self.id = id
    self.name = name
    self.value = value
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = container.value(.id, default: UUID())
    name = container.value(.name, default: "")
    value = container.value(.value, default: "")
  }

  /// Equality ignores the id (it only keeps SwiftUI rows stable).
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.name == rhs.name && lhs.value == rhs.value
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(name)
    hasher.combine(value)
  }
}

// MARK: - Upload

/// Where the upload step sends the file.
nonisolated enum AutomationUploadDestination: Equatable, Hashable, Sendable {
  /// The provider configured in Settings → Cloud.
  case `default`
  /// A custom HTTP uploader from Settings → Cloud → Custom uploaders.
  case customUploader(UUID)
}

nonisolated extension AutomationUploadDestination: Codable {
  static let defaultToken = "default"

  init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    if let id = UUID(uuidString: raw) {
      self = .customUploader(id)
    } else {
      self = .default
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .default: try container.encode(Self.defaultToken)
    case .customUploader(let id): try container.encode(id.uuidString)
    }
  }
}

nonisolated struct AutomationUploadConfig: Codable, Equatable, Sendable {
  var destination: AutomationUploadDestination

  init(destination: AutomationUploadDestination = .default) {
    self.destination = destination
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    destination = container.value(.destination, default: .default)
  }
}

// MARK: - Webhook

nonisolated enum AutomationWebhookBodyKind: String, Codable, CaseIterable, Identifiable, Sendable {
  case none
  /// `jsonTemplate` rendered with JSON escaping.
  case json
  /// `fields` as `application/x-www-form-urlencoded`.
  case form
  /// `fields` plus the file as `fileField`, `multipart/form-data`.
  case multipart

  var id: String { rawValue }
}

nonisolated struct AutomationWebhookConfig: Codable, Equatable, Sendable {
  static let defaultJSONTemplate = "{\"url\": \"{link}\"}"
  static let timeoutRange: ClosedRange<Double> = 1...300
  /// Response bytes kept as `{text}`.
  static let maxResponseTextBytes = 64 * 1024

  var method: AutomationHTTPMethod
  /// Allows `{secret:NAME}`; must be `https://` (or `http://localhost`).
  var url: String
  /// Values allow `{secret:NAME}`.
  var headers: [AutomationKeyValue]
  var bodyKind: AutomationWebhookBodyKind
  /// Allows `{secret:NAME}`; payload tokens are JSON-escaped.
  var jsonTemplate: String
  /// Form / multipart fields; values allow `{secret:NAME}`.
  var fields: [AutomationKeyValue]
  var fileField: String
  var timeout: Double
  /// The response body (up to 64 KB) becomes `{text}`.
  var responseToText: Bool
  /// JSON path (`data.url`, `files[0].link`) read from the response into `{link}`.
  var responseLinkPath: String?

  init(
    method: AutomationHTTPMethod = .post,
    url: String = "",
    headers: [AutomationKeyValue] = [],
    bodyKind: AutomationWebhookBodyKind = .json,
    jsonTemplate: String = Self.defaultJSONTemplate,
    fields: [AutomationKeyValue] = [],
    fileField: String = "file",
    timeout: Double = 30,
    responseToText: Bool = false,
    responseLinkPath: String? = nil
  ) {
    self.method = method
    self.url = url
    self.headers = headers
    self.bodyKind = bodyKind
    self.jsonTemplate = jsonTemplate
    self.fields = fields
    self.fileField = fileField
    self.timeout = timeout
    self.responseToText = responseToText
    self.responseLinkPath = responseLinkPath
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = Self()
    method = container.value(.method, default: defaults.method)
    url = container.value(.url, default: "")
    headers = container.value(.headers, default: [])
    bodyKind = container.value(.bodyKind, default: defaults.bodyKind)
    jsonTemplate = container.value(.jsonTemplate, default: defaults.jsonTemplate)
    fields = container.value(.fields, default: [])
    fileField = container.value(.fileField, default: defaults.fileField)
    timeout = container.value(.timeout, default: defaults.timeout)
    responseToText = container.value(.responseToText, default: false)
    responseLinkPath = container.value(.responseLinkPath, default: nil)
  }

  var clampedTimeout: Double {
    min(max(timeout, Self.timeoutRange.lowerBound), Self.timeoutRange.upperBound)
  }

  var trimmedResponseLinkPath: String? {
    guard let path = responseLinkPath?.trimmingCharacters(in: .whitespaces), !path.isEmpty else { return nil }
    return path
  }

  /// Ready-made templates offered in the inspector.
  enum Preset: String, CaseIterable, Identifiable, Sendable {
    case slack
    case discord
    case genericJSON

    var id: String { rawValue }

    var jsonTemplate: String {
      switch self {
      case .slack: "{\"text\": \"{link}\"}"
      case .discord: "{\"content\": \"{link}\"}"
      case .genericJSON: "{\"url\": \"{link}\", \"file\": \"{file.name}\", \"text\": \"{text}\", \"automation\": \"{automation}\"}"
      }
    }
  }
}

// MARK: - Shell script

nonisolated enum AutomationScriptShell: String, Codable, CaseIterable, Identifiable, Sendable {
  case zsh
  case bash
  case sh

  var id: String { rawValue }

  var executablePath: String {
    switch self {
    case .zsh: "/bin/zsh"
    case .bash: "/bin/bash"
    case .sh: "/bin/sh"
    }
  }
}

/// What a script's standard output becomes.
nonisolated enum AutomationScriptOutput: String, Codable, CaseIterable, Identifiable, Sendable {
  case ignore
  /// Trimmed stdout → `{text}`.
  case text
  /// First line of stdout, an http(s) URL → `{link}`.
  case link
  /// Last line of stdout, a path to an existing file → replaces the payload file.
  case file

  var id: String { rawValue }
}

nonisolated struct AutomationRunScriptConfig: Codable, Equatable, Sendable {
  static let timeoutRange: ClosedRange<Double> = 1...600

  /// Shown verbatim in the editor. Payload values reach it only through
  /// `SNAPZY_*` environment variables and `$1…`, never by interpolation.
  var script: String
  var shell: AutomationScriptShell
  /// Run as a login shell (`-l`) so `PATH` includes Homebrew and friends.
  var useLoginShell: Bool
  var timeout: Double
  var output: AutomationScriptOutput

  init(
    script: String = "",
    shell: AutomationScriptShell = .zsh,
    useLoginShell: Bool = false,
    timeout: Double = 30,
    output: AutomationScriptOutput = .ignore
  ) {
    self.script = script
    self.shell = shell
    self.useLoginShell = useLoginShell
    self.timeout = timeout
    self.output = output
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = Self()
    script = container.value(.script, default: "")
    shell = container.value(.shell, default: defaults.shell)
    useLoginShell = container.value(.useLoginShell, default: false)
    timeout = container.value(.timeout, default: defaults.timeout)
    output = container.value(.output, default: defaults.output)
  }

  var clampedTimeout: Double {
    min(max(timeout, Self.timeoutRange.lowerBound), Self.timeoutRange.upperBound)
  }
}

// MARK: - Apple Shortcut

nonisolated enum AutomationShortcutInput: String, Codable, CaseIterable, Identifiable, Sendable {
  case file
  case text
  case link
  case none

  var id: String { rawValue }
}

nonisolated enum AutomationShortcutOutput: String, Codable, CaseIterable, Identifiable, Sendable {
  case ignore
  /// The shortcut's output read as text → `{text}`.
  case text
  /// The shortcut's output file replaces the payload file.
  case file

  var id: String { rawValue }
}

nonisolated struct AutomationRunShortcutConfig: Codable, Equatable, Sendable {
  static let timeoutRange: ClosedRange<Double> = 1...600

  /// Name of the shortcut in Shortcuts.app.
  var name: String
  var input: AutomationShortcutInput
  var output: AutomationShortcutOutput
  var timeout: Double

  init(
    name: String = "",
    input: AutomationShortcutInput = .file,
    output: AutomationShortcutOutput = .ignore,
    timeout: Double = 60
  ) {
    self.name = name
    self.input = input
    self.output = output
    self.timeout = timeout
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = Self()
    name = container.value(.name, default: "")
    input = container.value(.input, default: defaults.input)
    output = container.value(.output, default: defaults.output)
    timeout = container.value(.timeout, default: defaults.timeout)
  }

  var clampedTimeout: Double {
    min(max(timeout, Self.timeoutRange.lowerBound), Self.timeoutRange.upperBound)
  }

  var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

// MARK: - Share sheet / open in app

nonisolated enum AutomationShareService: Equatable, Hashable, Sendable {
  /// The system share picker, anchored at the mouse.
  case picker
  case airDrop
  case messages
  case mail
  /// Any `NSSharingService.Name` raw value.
  case named(String)
}

nonisolated extension AutomationShareService: Codable {
  static let builtInTokens: [(String, AutomationShareService)] = [
    ("picker", .picker), ("airdrop", .airDrop), ("messages", .messages), ("mail", .mail),
  ]

  var token: String {
    switch self {
    case .picker: "picker"
    case .airDrop: "airdrop"
    case .messages: "messages"
    case .mail: "mail"
    case .named(let name): name
    }
  }

  init(token: String) {
    let trimmed = token.trimmingCharacters(in: .whitespaces)
    self = Self.builtInTokens.first { $0.0 == trimmed.lowercased() }?.1 ?? (trimmed.isEmpty ? .picker : .named(trimmed))
  }

  init(from decoder: Decoder) throws {
    self.init(token: try decoder.singleValueContainer().decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(token)
  }
}

nonisolated struct AutomationShareSheetConfig: Codable, Equatable, Sendable {
  var service: AutomationShareService

  init(service: AutomationShareService = .picker) {
    self.service = service
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    service = container.value(.service, default: .picker)
  }
}

nonisolated struct AutomationOpenInAppConfig: Codable, Equatable, Sendable {
  var appBundleID: String
  /// Shown in the editor and error messages.
  var appName: String

  init(appBundleID: String = "", appName: String = "") {
    self.appBundleID = appBundleID
    self.appName = appName
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    appBundleID = container.value(.appBundleID, default: "")
    appName = container.value(.appName, default: "")
  }

  var trimmedBundleID: String {
    appBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
