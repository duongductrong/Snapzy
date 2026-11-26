//
//  AutomationIntegrationSteps.swift
//  Snapzy
//
//  Milestone 4 steps: webhook (network), shell script and Apple Shortcut
//  (code, gated by Settings → Automations → Advanced), share sheet and open
//  in app (local; any network happens in the service the user picks).
//

import Combine
import Foundation

// MARK: - Webhook

struct WebhookStepHandler: AutomationStepHandler {
  func accepts(_ action: AutomationStepAction) -> Set<AutomationPayloadKind> {
    guard case .webhook(let config) = action, config.bodyKind == .multipart else { return AutomationPayloadKind.all }
    return AutomationPayloadKind.files
  }

  func produces(_ action: AutomationStepAction, given: Set<AutomationPayloadKind>) -> Set<AutomationPayloadKind> {
    guard case .webhook(let config) = action else { return given }
    var kinds = given
    if config.responseToText { kinds.insert(.text) }
    if config.trimmedResponseLinkPath != nil { kinds.insert(.link) }
    return kinds
  }

  var trust: AutomationTrustTier { .network }

  func run(
    _ action: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    guard case .webhook(let config) = action else { return }
    var secretValues: [String] = []
    // Masking starts as soon as a secret was resolved, whatever fails next.
    defer { state.secretValues.formUnion(secretValues) }

    let exchange = try await Self.send(
      config,
      files: files,
      variables: state.variables(),
      context: state.context,
      environment: environment,
      secretValues: &secretValues
    )
    try Task.checkCancellation()

    let data = exchange.data
    guard (200..<300).contains(exchange.response.statusCode) else {
      let snippet = String(decoding: data.prefix(200), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      throw AutomationStepError.httpStatus(
        exchange.response.statusCode,
        AutomationSecretStore.mask(snippet, values: secretValues)
      )
    }

    if config.responseToText {
      let text = String(decoding: data.prefix(AutomationWebhookConfig.maxResponseTextBytes), as: UTF8.self)
      state.payload.text = AutomationSecretStore.mask(text, values: secretValues)
    }
    if let path = config.trimmedResponseLinkPath {
      let link = try Self.link(at: path, in: data)
      state.payload.link = link
      state.linkText = link.absoluteString
      state.lastDelivery = .linkReady
    }
  }

  /// Reads a web link at `path` in a JSON response.
  static func link(at path: String, in data: Data) throws -> URL {
    guard let value = AutomationJSONPath.string(at: path, in: data),
          let link = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
          AutomationWebhookPolicy.isWebURL(link)
    else {
      throw AutomationStepError.failed(L10n.Automations.errorWebhookNoLink(path))
    }
    return link
  }

  /// Renders the request from `variables` and sends it. Resolved secrets are
  /// appended to `secretValues` even when a later part fails.
  static func send(
    _ config: AutomationWebhookConfig,
    files: [URL],
    variables: AutomationVariables,
    context: AutomationRunContext,
    environment: AutomationRunEnvironment,
    secretValues: inout [String]
  ) async throws -> (data: Data, response: HTTPURLResponse) {
    var resolved: [String] = []
    defer { secretValues += resolved }
    let resolve: (String) -> String? = { environment.secretValue(named: $0) }

    func render(_ template: String, escape: AutomationEscape, secretEscape: AutomationEscape? = nil) throws -> String {
      let rendered = try variables.renderAllowingSecrets(
        template,
        escape: escape,
        secretEscape: secretEscape,
        resolveSecret: resolve
      )
      resolved += rendered.secrets
      return rendered.text
    }

    // Payload values are percent-encoded; a secret may be the whole URL, so it goes in as is.
    let urlString = try render(config.url, escape: .url, secretEscape: AutomationEscape.none)
    guard let url = AutomationWebhookPolicy.validatedURL(urlString) else { throw AutomationStepError.invalidURL }

    var request = URLRequest(url: url, timeoutInterval: config.clampedTimeout)
    request.httpMethod = config.method.rawValue
    request.setValue("Snapzy", forHTTPHeaderField: "User-Agent")

    var bodyFile: URL?
    if config.method.hasBody {
      switch config.bodyKind {
      case .none:
        break
      case .json:
        let body = try render(config.jsonTemplate, escape: .json)
        request.httpBody = Data(body.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      case .form:
        let pairs = try config.fields.filter { !$0.name.isEmpty }.map { field in
          (field.name, try render(field.value, escape: .none))
        }
        request.httpBody = Data(AutomationFormEncoding.encode(pairs).utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
      case .multipart:
        guard let file = files.first else { throw AutomationStepError.noFile }
        let fields = try config.fields.filter { !$0.name.isEmpty }.map { field in
          (field.name, try render(field.value, escape: .none))
        }
        let multipart = try await AutomationMultipartBody.write(
          fields: fields,
          fileField: config.fileField.isEmpty ? "file" : config.fileField,
          file: file,
          in: context
        )
        bodyFile = multipart.url
        request.setValue(multipart.contentType, forHTTPHeaderField: "Content-Type")
      }
    }
    defer { if let bodyFile { try? FileManager.default.removeItem(at: bodyFile) } }

    for header in config.headers where !header.name.trimmingCharacters(in: .whitespaces).isEmpty {
      let name = header.name.trimmingCharacters(in: .whitespaces)
      guard AutomationWebhookPolicy.isValidHeaderName(name) else { continue }
      let value = try render(header.value, escape: .none).replacingOccurrences(of: "\r", with: "")
        .replacingOccurrences(of: "\n", with: "")
      request.setValue(value, forHTTPHeaderField: name)
    }

    let (data, response) = try await environment.send(request, bodyFile: bodyFile)
    return (data, response)
  }
}

/// URL and header rules for webhooks.
enum AutomationWebhookPolicy {
  /// `https://…`, or `http://` to this Mac only.
  static func validatedURL(_ raw: String) -> URL? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty else {
      return nil
    }
    if scheme == "https" { return url }
    if scheme == "http", isLoopback(host) { return url }
    return nil
  }

  /// Edit-time check on the template: tokens other than secrets / payload are fine.
  static func isAcceptableTemplate(_ template: String) -> Bool {
    let trimmed = template.trimmingCharacters(in: .whitespaces).lowercased()
    if trimmed.hasPrefix("https://") { return trimmed.count > "https://".count }
    if trimmed.hasPrefix("{secret:") { return true }
    for host in ["localhost", "127.0.0.1", "[::1]"] where trimmed.hasPrefix("http://\(host)") {
      return true
    }
    return false
  }

  static func isLoopback(_ host: String) -> Bool {
    let lowered = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    return lowered == "localhost" || lowered == "127.0.0.1" || lowered == "::1"
  }

  static func isWebURL(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty else { return false }
    return scheme == "https" || scheme == "http"
  }

  static func isValidHeaderName(_ name: String) -> Bool {
    let allowed = CharacterSet(charactersIn: "!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    return !name.isEmpty && name.unicodeScalars.allSatisfy(allowed.contains)
  }
}

enum AutomationFormEncoding {
  static func encode(_ pairs: [(String, String)]) -> String {
    pairs.map { "\(component($0.0))=\(component($0.1))" }.joined(separator: "&")
  }

  private static func component(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._*")
    return (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)
      .replacingOccurrences(of: "%20", with: "+")
  }
}

/// A `multipart/form-data` body written to a file in the run's working
/// directory, so a video is streamed from disk instead of held in memory.
enum AutomationMultipartBody {
  static func write(
    fields: [(String, String)],
    fileField: String,
    file: URL,
    in context: AutomationRunContext
  ) async throws -> (url: URL, contentType: String) {
    let boundary = "SnapzyBoundary-\(UUID().uuidString)"
    let bodyURL = try context.makeWorkingFile(baseName: "webhook-body", fileExtension: "multipart")
    // Copying a multi-GB recording must not block the main actor.
    try await Task.detached(priority: .userInitiated) {
      try writeBody(fields: fields, fileField: fileField, file: file, boundary: boundary, to: bodyURL)
    }.value
    return (bodyURL, "multipart/form-data; boundary=\(boundary)")
  }

  nonisolated static func writeBody(
    fields: [(String, String)],
    fileField: String,
    file: URL,
    boundary: String,
    to bodyURL: URL
  ) throws {
    FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
    let handle = try FileHandle(forWritingTo: bodyURL)
    defer { try? handle.close() }

    func write(_ string: String) throws {
      try handle.write(contentsOf: Data(string.utf8))
    }

    for (name, value) in fields {
      try write("--\(boundary)\r\n")
      try write("Content-Disposition: form-data; name=\"\(quoted(name))\"\r\n\r\n")
      try write("\(value)\r\n")
    }
    try write("--\(boundary)\r\n")
    try write("Content-Disposition: form-data; name=\"\(quoted(fileField))\"; filename=\"\(quoted(file.lastPathComponent))\"\r\n")
    try write("Content-Type: \(mimeType(for: file))\r\n\r\n")
    let input = try FileHandle(forReadingFrom: file)
    defer { try? input.close() }
    while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
      try handle.write(contentsOf: chunk)
    }
    try write("\r\n--\(boundary)--\r\n")
  }

  nonisolated static func quoted(_ value: String) -> String {
    value.replacingOccurrences(of: "\"", with: "%22")
      .replacingOccurrences(of: "\r", with: "")
      .replacingOccurrences(of: "\n", with: "")
  }

  nonisolated static func mimeType(for file: URL) -> String {
    switch file.pathExtension.lowercased() {
    case "png": "image/png"
    case "jpg", "jpeg": "image/jpeg"
    case "webp": "image/webp"
    case "heic": "image/heic"
    case "gif": "image/gif"
    case "mp4": "video/mp4"
    case "mov": "video/quicktime"
    case "txt": "text/plain"
    default: "application/octet-stream"
    }
  }
}

/// `a.b[0].c` lookups in a JSON response. Numbers and booleans are returned as text.
enum AutomationJSONPath {
  enum Component: Equatable {
    case key(String)
    case index(Int)
  }

  static func components(_ path: String) -> [Component]? {
    var components: [Component] = []
    var current = ""
    var index = path.startIndex
    func flushKey() {
      if !current.isEmpty { components.append(.key(current)) }
      current = ""
    }
    while index < path.endIndex {
      let character = path[index]
      switch character {
      case ".":
        flushKey()
      case "[":
        flushKey()
        guard let close = path[index...].firstIndex(of: "]"),
              let number = Int(path[path.index(after: index)..<close]), number >= 0
        else { return nil }
        components.append(.index(number))
        index = close
      default:
        current.append(character)
      }
      index = path.index(after: index)
    }
    flushKey()
    return components.isEmpty ? nil : components
  }

  static func value(at path: String, in object: Any) -> Any? {
    guard let components = components(path) else { return nil }
    var current: Any? = object
    for component in components {
      switch component {
      case .key(let key): current = (current as? [String: Any])?[key]
      case .index(let index):
        guard let array = current as? [Any], array.indices.contains(index) else { return nil }
        current = array[index]
      }
    }
    return current
  }

  static func string(at path: String, in data: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
          let value = value(at: path, in: object)
    else { return nil }
    switch value {
    case let string as String: return string
    case let number as NSNumber: return number.stringValue
    default: return nil
    }
  }
}

// MARK: - Shell script

struct RunScriptStepHandler: AutomationStepHandler {
  /// Variables only; the script decides what it needs.
  func accepts(_: AutomationStepAction) -> Set<AutomationPayloadKind> { AutomationPayloadKind.all }

  func produces(_ action: AutomationStepAction, given: Set<AutomationPayloadKind>) -> Set<AutomationPayloadKind> {
    guard case .runScript(let config) = action else { return given }
    switch config.output {
    case .ignore: return given
    case .text: return given.union([.text])
    case .link: return given.union([.link])
    case .file: return given.union([.image])
    }
  }

  var trust: AutomationTrustTier { .code }

  func run(
    _ action: AutomationStepAction,
    files _: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    guard case .runScript(let config) = action else { return }
    guard environment.allowsCodeSteps else { throw AutomationStepError.codeStepsDisabled }
    guard !config.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AutomationStepError.failed(L10n.Automations.errorScriptEmpty)
    }

    let workDir = state.context.workingDirectory
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    let request = AutomationScriptInvocation.request(
      config: config,
      files: state.files,
      environment: AutomationScriptInvocation.variables(for: state),
      workingDirectory: workDir
    )
    let outcome = try await environment.runProcess(request)
    try Task.checkCancellation()
    try AutomationScriptInvocation.check(outcome, timeout: config.clampedTimeout)

    switch config.output {
    case .ignore:
      break
    case .text:
      let text = outcome.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { throw AutomationStepError.noTextFound }
      state.payload.text = text
    case .link:
      let line = outcome.stdoutText.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
      guard let link = URL(string: line.trimmingCharacters(in: .whitespaces)), AutomationWebhookPolicy.isWebURL(link) else {
        throw AutomationStepError.noLink
      }
      state.payload.link = link
      state.linkText = link.absoluteString
      state.lastDelivery = .linkReady
    case .file:
      let line = outcome.stdoutText.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
      let file = try AutomationScriptInvocation.outputFile(line, workingDirectory: workDir)
      try AutomationScriptInvocation.adopt(file, into: &state)
    }
  }
}

/// How a script step becomes a child process. Payload values reach the script
/// only through `SNAPZY_*` environment variables and `$1…` (the file paths);
/// the script text itself is passed verbatim as the `-c` argument.
enum AutomationScriptInvocation {
  static func variables(for state: AutomationRunState) -> [String: String] {
    var variables: [String: String] = [
      "SNAPZY_AUTOMATION": state.context.automationName,
      "SNAPZY_RUN_ID": state.runID.uuidString,
      "SNAPZY_WORK_DIR": state.context.workingDirectory.path,
      "SNAPZY_FILES": state.files.map(\.path).joined(separator: "\n"),
    ]
    if let file = state.primaryFile { variables["SNAPZY_FILE"] = file.path }
    if let link = state.payload.link { variables["SNAPZY_LINK"] = link.absoluteString }
    if let text = state.payload.text { variables["SNAPZY_TEXT"] = text }
    if let saved = state.payload.savedFile { variables["SNAPZY_SAVED_FILE"] = saved.path }
    return variables
  }

  static func request(
    config: AutomationRunScriptConfig,
    files: [URL],
    environment variables: [String: String],
    workingDirectory: URL,
    baseEnvironment: [String: String] = ProcessRunner.baseEnvironment()
  ) -> ProcessRequest {
    var arguments: [String] = []
    if config.useLoginShell {
      arguments.append("-l")
    } else {
      switch config.shell {
      case .zsh: arguments.append("-f")
      case .bash: arguments += ["--noprofile", "--norc"]
      case .sh: break
      }
    }
    // `$0` = "snapzy", `$1…` = file paths.
    arguments += ["-c", config.script, "snapzy"] + files.map(\.path)
    return ProcessRequest(
      executable: URL(fileURLWithPath: config.shell.executablePath),
      arguments: arguments,
      environment: baseEnvironment.merging(variables) { _, new in new },
      currentDirectory: workingDirectory,
      timeout: config.clampedTimeout
    )
  }

  static func check(_ outcome: ProcessOutcome, timeout: TimeInterval) throws {
    if outcome.timedOut { throw AutomationStepError.timedOut(Int(timeout)) }
    guard outcome.status == 0 else {
      let stderr = outcome.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
      throw AutomationStepError.processFailed(outcome.status, String(stderr.suffix(512)))
    }
  }

  /// A path the script printed: must be an existing regular file inside the
  /// run's working directory or the user's home folder.
  static func outputFile(_ line: String, workingDirectory: URL) throws -> URL {
    let path = (line.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
    guard !path.isEmpty else { throw AutomationStepError.outputFileInvalid }
    let url = (path.hasPrefix("/") ? URL(fileURLWithPath: path) : workingDirectory.appendingPathComponent(path))
      .standardizedFileURL.resolvingSymlinksInPath()
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
      throw AutomationStepError.outputFileInvalid
    }
    let roots = [
      workingDirectory.standardizedFileURL.resolvingSymlinksInPath().path,
      FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.resolvingSymlinksInPath().path,
    ]
    guard roots.contains(where: { url.path.hasPrefix($0 + "/") }) else { throw AutomationStepError.outputFileInvalid }
    return url
  }

  /// Makes `file` the run's primary file (kind from its extension).
  static func adopt(_ file: URL, into state: inout AutomationRunState) throws {
    guard let kind = AutomationFileKind.of(file) else { throw AutomationStepError.outputFileInvalid }
    if let primary = state.primaryFile {
      guard primary.standardizedFileURL != file.standardizedFileURL else { return }
      state.replace(primary, with: file, kind: kind)
    } else {
      state.payload.files.append(AutomationFile(url: file, kind: kind))
    }
  }
}

// MARK: - Apple Shortcut

struct RunShortcutStepHandler: AutomationStepHandler {
  static let shortcutsPath = "/usr/bin/shortcuts"

  func accepts(_ action: AutomationStepAction) -> Set<AutomationPayloadKind> {
    guard case .runShortcut(let config) = action else { return AutomationPayloadKind.all }
    switch config.input {
    case .file: return AutomationPayloadKind.files
    case .text: return [.text]
    case .link: return [.link]
    case .none: return AutomationPayloadKind.all
    }
  }

  func produces(_ action: AutomationStepAction, given: Set<AutomationPayloadKind>) -> Set<AutomationPayloadKind> {
    guard case .runShortcut(let config) = action else { return given }
    switch config.output {
    case .ignore: return given
    case .text: return given.union([.text])
    case .file: return given.union([.image])
    }
  }

  var trust: AutomationTrustTier { .code }

  func run(
    _ action: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    guard case .runShortcut(let config) = action else { return }
    guard environment.allowsCodeSteps else { throw AutomationStepError.codeStepsDisabled }
    let name = config.trimmedName
    guard !name.isEmpty else { throw AutomationStepError.shortcutNotFound(name) }

    var arguments = ["run", name]
    switch config.input {
    case .file:
      guard let file = files.first else { throw AutomationStepError.noFile }
      arguments += ["--input-path", file.path]
    case .text:
      guard let text = state.payload.text else { throw AutomationStepError.noText }
      arguments += ["--input-path", try writeInput(text, state: state).path]
    case .link:
      guard let link = state.payload.link else { throw AutomationStepError.noLink }
      arguments += ["--input-path", try writeInput(link.absoluteString, state: state).path]
    case .none:
      break
    }

    var outputURL: URL?
    switch config.output {
    case .ignore:
      break
    case .text:
      let url = try state.context.makeWorkingFile(baseName: "shortcut-output", fileExtension: "txt")
      arguments += ["--output-path", url.path, "--output-type", "public.plain-text"]
      outputURL = url
    case .file:
      let ext = state.primaryFile?.pathExtension.isEmpty == false ? state.primaryFile!.pathExtension : "png"
      let base = (state.primaryFile?.deletingPathExtension().lastPathComponent ?? "shortcut") + "-shortcut"
      let url = try state.context.makeWorkingFile(baseName: base, fileExtension: ext)
      arguments += ["--output-path", url.path]
      outputURL = url
    }

    let request = ProcessRequest(
      executable: URL(fileURLWithPath: Self.shortcutsPath),
      arguments: arguments,
      environment: ProcessRunner.baseEnvironment(),
      currentDirectory: state.context.workingDirectory,
      timeout: config.clampedTimeout
    )
    let outcome = try await environment.runProcess(request)
    try Task.checkCancellation()
    if outcome.timedOut { throw AutomationStepError.timedOut(Int(config.clampedTimeout)) }
    guard outcome.status == 0 else {
      let stderr = outcome.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
      if Self.isNotFound(stderr) { throw AutomationStepError.shortcutNotFound(name) }
      throw AutomationStepError.processFailed(outcome.status, String(stderr.suffix(512)))
    }

    switch config.output {
    case .ignore:
      break
    case .text:
      let text = outputURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !text.isEmpty else { throw AutomationStepError.noTextFound }
      state.payload.text = text
    case .file:
      guard let outputURL, FileManager.default.fileExists(atPath: outputURL.path),
            (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 0
      else { throw AutomationStepError.outputFileInvalid }
      try AutomationScriptInvocation.adopt(outputURL, into: &state)
    }
  }

  private func writeInput(_ text: String, state: AutomationRunState) throws -> URL {
    let url = try state.context.makeWorkingFile(baseName: "shortcut-input", fileExtension: "txt")
    try Data(text.utf8).write(to: url)
    return url
  }

  static func isNotFound(_ stderr: String) -> Bool {
    let lowered = stderr.lowercased()
    return lowered.contains("couldn’t find") || lowered.contains("couldn't find")
      || lowered.contains("not found") || lowered.contains("no shortcut")
  }
}

/// Names from `shortcuts list`, cached for a minute (the editor's picker).
@MainActor
final class AutomationShortcutsCatalog: ObservableObject {
  static let shared = AutomationShortcutsCatalog()
  static let lifetime: TimeInterval = 60

  @Published private(set) var names: [String] = []
  @Published private(set) var isLoading = false
  private var loadedAt: Date?

  func refresh(force: Bool = false) {
    if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < Self.lifetime { return }
    guard !isLoading else { return }
    isLoading = true
    Task {
      let request = ProcessRequest(
        executable: URL(fileURLWithPath: RunShortcutStepHandler.shortcutsPath),
        arguments: ["list"],
        environment: ProcessRunner.baseEnvironment(),
        timeout: 15
      )
      let outcome = try? await ProcessRunner.run(request)
      let names = outcome.map { result in
        result.stdoutText.split(whereSeparator: \.isNewline)
          .map { $0.trimmingCharacters(in: .whitespaces) }
          .filter { !$0.isEmpty }
      } ?? []
      self.names = Array(Set(names)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
      self.loadedAt = Date()
      self.isLoading = false
    }
  }

  static func openInShortcutsURL(_ name: String) -> URL? {
    var components = URLComponents()
    components.scheme = "shortcuts"
    components.host = "open-shortcut"
    components.queryItems = [URLQueryItem(name: "name", value: name)]
    return components.url
  }
}

// MARK: - Share sheet / open in app

struct ShareSheetStepHandler: AutomationStepHandler {
  func accepts(_: AutomationStepAction) -> Set<AutomationPayloadKind> { AutomationPayloadKind.all }

  func run(
    _ action: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    guard case .shareSheet(let config) = action else { return }
    let items = Self.items(files: files, state: state)
    guard !items.isEmpty else { throw AutomationStepError.noFile }
    // The shared file must outlive the run: the service may read it later.
    state.retain(files)
    try await environment.share(items, service: config.service)
  }

  /// Files first; otherwise the link, otherwise the text.
  static func items(files: [URL], state: AutomationRunState) -> [Any] {
    if !files.isEmpty { return files }
    if let link = state.payload.link { return [link] }
    if let text = state.payload.text, !text.isEmpty { return [text] }
    return []
  }
}

struct OpenInAppStepHandler: AutomationStepHandler {
  func accepts(_: AutomationStepAction) -> Set<AutomationPayloadKind> {
    AutomationPayloadKind.files.union([.link])
  }

  func run(
    _ action: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    guard case .openInApp(let config) = action else { return }
    let bundleID = config.trimmedBundleID
    guard !bundleID.isEmpty else { throw AutomationStepError.appNotFound(config.appName) }
    let items: [URL]
    if !files.isEmpty {
      items = files
      // The app opens the file after the run's cleanup; keep it.
      state.retain(files)
    } else if let link = state.payload.link {
      items = [link]
    } else {
      throw AutomationStepError.noFile
    }
    try await environment.open(items, appBundleID: bundleID, appName: config.appName)
  }
}
