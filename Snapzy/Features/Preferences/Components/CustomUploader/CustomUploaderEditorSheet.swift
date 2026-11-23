//
//  CustomUploaderEditorSheet.swift
//  Snapzy
//
//  Create/edit sheet for a custom HTTP uploader, with a Test button that uploads
//  a 1×1 PNG through the real engine and shows the raw response.
//

import AppKit
import SwiftUI

struct CustomUploaderEditorSheet: View {
  let isNew: Bool
  /// Persists the edited uploader; a thrown error is shown in the sheet.
  let onSave: (CustomUploader) throws -> Void
  let onCancel: () -> Void

  private let original: CustomUploader

  @State private var name: String
  @State private var method: CustomUploader.HTTPMethod
  @State private var url: String
  @State private var headers: [CustomUploaderEditableRow]
  @State private var query: [CustomUploaderEditableRow]
  @State private var bodyKind: CustomUploader.Body.Kind
  @State private var fileField: String
  @State private var formFields: [CustomUploaderEditableRow]
  @State private var responseURL: CustomUploaderExtractorDraft
  @State private var deletionURL: CustomUploaderExtractorDraft
  @State private var errorMessage: CustomUploaderExtractorDraft
  @State private var timeout: Double

  @State private var saveError: String?
  @State private var isTesting = false
  @State private var testOutcome: CustomUploaderTestOutcome?
  @State private var testTask: Task<Void, Never>?

  init(
    uploader: CustomUploader,
    isNew: Bool,
    onSave: @escaping (CustomUploader) throws -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.original = uploader
    self.isNew = isNew
    self.onSave = onSave
    self.onCancel = onCancel
    _name = State(initialValue: uploader.name)
    _method = State(initialValue: uploader.method)
    _url = State(initialValue: uploader.url)
    _headers = State(initialValue: CustomUploaderEditableRow.rows(from: uploader.headers))
    _query = State(initialValue: CustomUploaderEditableRow.rows(from: uploader.query))
    _bodyKind = State(initialValue: uploader.body.kind)
    switch uploader.body {
    case .multipart(let field, let fields):
      _fileField = State(initialValue: field)
      _formFields = State(initialValue: CustomUploaderEditableRow.rows(from: fields))
    case .formURLEncoded(let fields):
      _fileField = State(initialValue: CustomUploader.defaultFileField)
      _formFields = State(initialValue: CustomUploaderEditableRow.rows(from: fields))
    case .binary:
      _fileField = State(initialValue: CustomUploader.defaultFileField)
      _formFields = State(initialValue: [])
    }
    _responseURL = State(initialValue: CustomUploaderExtractorDraft(uploader.responseURL))
    _deletionURL = State(initialValue: CustomUploaderExtractorDraft(uploader.deletionURL))
    _errorMessage = State(initialValue: CustomUploaderExtractorDraft(uploader.errorMessage))
    _timeout = State(initialValue: uploader.timeout)
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "server.rack")
          .font(.system(size: 20))
          .foregroundColor(.accentColor)
        Text(isNew ? L10n.CustomUploader.editorNewTitle : L10n.CustomUploader.editorEditTitle)
          .font(.headline)
        Spacer()
      }
      .padding(.horizontal, 20)
      .padding(.top, 16)
      .padding(.bottom, 4)

      Form {
        requestSection
        bodySection
        responseSection
        testSection
      }
      .formStyle(.grouped)

      Divider()

      HStack(spacing: 12) {
        if let saveError {
          Label(saveError, systemImage: "xmark.circle.fill")
            .font(.system(size: 11))
            .foregroundColor(.red)
            .lineLimit(2)
        }
        Spacer()
        Button(L10n.Common.cancel) {
          testTask?.cancel()
          onCancel()
        }
        .keyboardShortcut(.escape, modifiers: [])
        Button(L10n.Common.save, action: save)
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.return, modifiers: .command)
          .disabled(!isValid)
      }
      .padding(16)
    }
    .frame(width: 600, height: 700)
    .onDisappear { testTask?.cancel() }
  }

  // MARK: - Sections

  private var requestSection: some View {
    Section(L10n.CustomUploader.requestSection) {
      TextField(L10n.Common.name, text: $name)

      Picker(L10n.CustomUploader.method, selection: $method) {
        ForEach(CustomUploader.HTTPMethod.allCases, id: \.self) { method in
          Text(verbatim: method.rawValue).tag(method)
        }
      }

      TextField(
        L10n.CustomUploader.requestURL,
        text: $url,
        prompt: Text(verbatim: "https://example.com/api/upload")
      )
      .font(.system(.body, design: .monospaced))

      CustomUploaderKeyValueList(title: L10n.CustomUploader.headers, rows: $headers)
      CustomUploaderKeyValueList(title: L10n.CustomUploader.queryParameters, rows: $query)

      Stepper(value: $timeout, in: 5...600, step: 5) {
        LabeledContent(L10n.CustomUploader.timeout) {
          Text(verbatim: "\(Int(timeout))")
            .monospacedDigit()
        }
      }
    }
  }

  private var bodySection: some View {
    Section(L10n.CustomUploader.bodySection) {
      Picker(L10n.CustomUploader.bodyType, selection: $bodyKind) {
        Text(L10n.CustomUploader.bodyMultipart).tag(CustomUploader.Body.Kind.multipart)
        Text(L10n.CustomUploader.bodyBinary).tag(CustomUploader.Body.Kind.binary)
        Text(L10n.CustomUploader.bodyFormURLEncoded).tag(CustomUploader.Body.Kind.formURLEncoded)
      }

      if bodyKind == .multipart {
        TextField(L10n.CustomUploader.fileField, text: $fileField, prompt: Text(verbatim: CustomUploader.defaultFileField))
          .font(.system(.body, design: .monospaced))
      }
      if bodyKind != .binary {
        CustomUploaderKeyValueList(title: L10n.CustomUploader.formFields, rows: $formFields)
      }
    }
  }

  private var responseSection: some View {
    Section {
      extractorRow(L10n.CustomUploader.responseURL, draft: $responseURL, isOptional: false)
      extractorRow(L10n.CustomUploader.deletionURL, draft: $deletionURL, isOptional: true)
      extractorRow(L10n.CustomUploader.errorMessage, draft: $errorMessage, isOptional: true)
    } header: {
      Text(L10n.CustomUploader.responseSection)
    } footer: {
      Text(L10n.CustomUploader.syntaxHint)
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func extractorRow(_ title: String, draft: Binding<CustomUploaderExtractorDraft>, isOptional: Bool) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Picker(title, selection: draft.kind) {
        if isOptional {
          Text(L10n.CustomUploader.extractorNone).tag(CustomUploaderExtractorDraft.Choice.none)
        }
        Text(L10n.CustomUploader.extractorPlainText).tag(CustomUploaderExtractorDraft.Choice.plainText)
        Text(L10n.CustomUploader.extractorJSONPath).tag(CustomUploaderExtractorDraft.Choice.jsonPath)
        Text(L10n.CustomUploader.extractorRegex).tag(CustomUploaderExtractorDraft.Choice.regex)
        Text(L10n.CustomUploader.extractorTemplate).tag(CustomUploaderExtractorDraft.Choice.template)
      }
      if draft.wrappedValue.kind.needsExpression {
        TextField("", text: draft.expression, prompt: Text(verbatim: draft.wrappedValue.kind.placeholder))
          .textFieldStyle(.roundedBorder)
          .font(.system(.body, design: .monospaced))
      }
    }
  }

  private var testSection: some View {
    Section {
      HStack(spacing: 10) {
        Button(action: runTest) {
          if isTesting {
            HStack(spacing: 6) {
              ProgressView().controlSize(.small)
              Text(L10n.CustomUploader.testing)
            }
          } else {
            Label(L10n.CustomUploader.test, systemImage: "paperplane")
          }
        }
        .disabled(!isValid || isTesting)

        Text(L10n.CustomUploader.testDescription)
          .font(.system(size: 11))
          .foregroundColor(.secondary)
      }

      if let testOutcome {
        testOutcomeView(testOutcome)
      }
    }
  }

  @ViewBuilder
  private func testOutcomeView(_ outcome: CustomUploaderTestOutcome) -> some View {
    if let status = outcome.statusCode {
      LabeledContent(L10n.Common.status) {
        Text(L10n.CustomUploader.testStatus(status))
          .foregroundColor((200..<300).contains(status) ? .green : .red)
          .monospacedDigit()
      }
    }
    if let body = outcome.responseBody {
      VStack(alignment: .leading, spacing: 4) {
        Text(L10n.CustomUploader.testResponseBody)
        ScrollView {
          Text(verbatim: body.isEmpty ? L10n.CustomUploader.testEmptyBody : body)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
        .frame(height: 120)
        .background(Color(NSColor.textBackgroundColor))
        .overlay(
          RoundedRectangle(cornerRadius: 4)
            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
      }
    }
    if let link = outcome.extractedURL {
      LabeledContent(L10n.CustomUploader.testExtractedURL) {
        Text(verbatim: link)
          .textSelection(.enabled)
          .foregroundColor(.green)
          .lineLimit(2)
          .truncationMode(.middle)
      }
    }
    if let error = outcome.error {
      LabeledContent(L10n.CustomUploader.testError) {
        Text(error)
          .foregroundColor(.red)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  // MARK: - Draft

  private var isValid: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var draft: CustomUploader {
    let body: CustomUploader.Body
    switch bodyKind {
    case .multipart:
      let field = fileField.trimmingCharacters(in: .whitespacesAndNewlines)
      body = .multipart(
        fileField: field.isEmpty ? CustomUploader.defaultFileField : field,
        extraFields: CustomUploaderEditableRow.pairs(from: formFields)
      )
    case .binary:
      body = .binary
    case .formURLEncoded:
      body = .formURLEncoded(fields: CustomUploaderEditableRow.pairs(from: formFields))
    }
    return CustomUploader(
      id: original.id,
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      method: method,
      url: url.trimmingCharacters(in: .whitespacesAndNewlines),
      headers: CustomUploaderEditableRow.pairs(from: headers),
      query: CustomUploaderEditableRow.pairs(from: query),
      body: body,
      responseURL: responseURL.extractor ?? .plainText,
      thumbnailURL: original.thumbnailURL,
      deletionURL: deletionURL.extractor,
      errorMessage: errorMessage.extractor,
      timeout: timeout
    )
  }

  private func save() {
    do {
      try onSave(draft)
    } catch {
      saveError = error.localizedDescription
    }
  }

  // MARK: - Test

  private func runTest() {
    let uploader = draft
    isTesting = true
    testOutcome = nil
    testTask = Task {
      let outcome = await CustomUploaderTestRunner.run(uploader)
      guard !Task.isCancelled else { return }
      testOutcome = outcome
      isTesting = false
    }
  }
}

// MARK: - Extractor Draft

/// Editable form of an optional `ResponseExtractor`.
struct CustomUploaderExtractorDraft: Equatable {
  enum Choice: Hashable {
    case none
    case plainText
    case jsonPath
    case regex
    case template

    var needsExpression: Bool {
      switch self {
      case .none, .plainText: return false
      case .jsonPath, .regex, .template: return true
      }
    }

    var placeholder: String {
      switch self {
      case .jsonPath: return "data.url"
      case .regex: return #"https?://\S+"#
      case .template: return "{json:data.url}"
      case .none, .plainText: return ""
      }
    }
  }

  var kind: Choice
  var expression: String

  init(_ extractor: CustomUploader.ResponseExtractor?) {
    expression = extractor?.expression ?? ""
    switch extractor?.kind {
    case nil: kind = .none
    case .plainText?: kind = .plainText
    case .jsonPath?: kind = .jsonPath
    case .regex?: kind = .regex
    case .template?: kind = .template
    }
  }

  var extractor: CustomUploader.ResponseExtractor? {
    let value = expression.trimmingCharacters(in: .whitespacesAndNewlines)
    switch kind {
    case .none: return nil
    case .plainText: return .plainText
    case .jsonPath: return .jsonPath(value)
    case .regex: return .regex(value)
    case .template: return .template(value)
    }
  }
}

// MARK: - Test Runner

struct CustomUploaderTestOutcome: Equatable {
  var statusCode: Int?
  var responseBody: String?
  var extractedURL: String?
  var error: String?
}

/// Sends a generated 1×1 PNG with the uploader and summarises the raw response.
enum CustomUploaderTestRunner {
  static let responsePreviewBytes = 2048

  /// A transparent 1×1 PNG.
  private static let pngData = Data(
    base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
  )!

  static func run(_ uploader: CustomUploader) async -> CustomUploaderTestOutcome {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyCustomUploaderTest-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directory.appendingPathComponent("snapzy-test.png")
    defer { try? FileManager.default.removeItem(at: directory) }

    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try pngData.write(to: fileURL)
      let response = try await CustomUploaderEngine().send(
        fileURL: fileURL,
        using: uploader,
        secrets: CustomUploaderSecrets.provider,
        contentType: "image/png",
        progress: { _ in }
      )
      return outcome(for: response, uploader: uploader, fileName: fileURL.lastPathComponent)
    } catch {
      return CustomUploaderTestOutcome(error: error.localizedDescription)
    }
  }

  static func outcome(for response: CustomUploaderResponse, uploader: CustomUploader, fileName: String) -> CustomUploaderTestOutcome {
    var outcome = CustomUploaderTestOutcome(statusCode: response.statusCode, responseBody: preview(of: response.body))
    guard response.isSuccess else {
      outcome.error = CustomUploaderResponseParser.errorMessage(for: response, uploader: uploader)
      return outcome
    }
    do {
      let extraction = try CustomUploaderResponseParser.extraction(from: response, uploader: uploader, fileName: fileName)
      outcome.extractedURL = extraction.url.absoluteString
    } catch {
      outcome.error = error.localizedDescription
    }
    return outcome
  }

  /// The first 2 KB of the body as text.
  static func preview(of body: Data) -> String {
    let prefix = body.prefix(responsePreviewBytes)
    let text = String(decoding: prefix, as: UTF8.self)
    return body.count > responsePreviewBytes ? text + "…" : text
  }
}
