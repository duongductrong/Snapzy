//
//  VideoEditorCaptionTranslator.swift
//  Snapzy
//
//  Translates caption texts for the agent's translate_captions tool, through the
//  engine picked in Settings (`TranslationEngineResolver`): Apple Translation on this
//  Mac, or the user's own endpoint. Apple Translation hands out sessions only through
//  SwiftUI's `.translationTask` before macOS 26, so a hidden host in the editor window
//  runs the request and resumes the waiting tool. Same pattern as Annotate's Auto Translate.
//

import Combine
import SwiftUI
import Translation

nonisolated enum VideoEditorCaptionTranslationError: Error, Equatable {
  case requiresMacOS15
}

@MainActor
final class VideoEditorCaptionTranslator: ObservableObject {
  struct Request: Equatable {
    let token: UUID
    let texts: [String]
    let sourceLanguageIdentifier: String?
    let targetLanguageIdentifier: String
  }

  /// What the host should translate next; nil when idle.
  @Published private(set) var request: Request?
  private var continuation: CheckedContinuation<BlockTranslationOutput, Error>?
  private var token: UUID?

  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}

  /// One result per text, in order (nil = nothing came back for it).
  func translate(
    _ texts: [String],
    sourceLanguage: String?,
    target: TranslationLanguage,
    route: TranslationRoute
  ) async throws -> BlockTranslationOutput {
    switch route {
    case .remote(let model):
      return try await RemoteBlockTranslator(model: model).translate(texts, to: target)
    case .unavailable:
      throw VideoEditorCaptionTranslationError.requiresMacOS15
    case .apple:
      try Task.checkCancellation()
      // Apple Translation rejects source languages it doesn't know; let it detect those.
      let source = sourceLanguage.flatMap { identifier -> String? in
        let code = VideoEditorAgentToolbox.languageCode(identifier)
        return TranslationLanguage.all.contains { VideoEditorAgentToolbox.languageCode($0.identifier) == code } ? identifier : nil
      }
      let token = UUID()
      return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          finish(with: .failure(CancellationError()))
          self.continuation = continuation
          self.token = token
          request = Request(
            token: token, texts: texts, sourceLanguageIdentifier: source, targetLanguageIdentifier: target.identifier
          )
        }
      } onCancel: {
        Task { @MainActor [weak self] in self?.complete(token: token, result: .failure(CancellationError())) }
      }
    }
  }

  func complete(token: UUID, result: Result<BlockTranslationOutput, Error>) {
    guard self.token == token else { return }
    request = nil
    finish(with: result)
  }

  private func finish(with result: Result<BlockTranslationOutput, Error>) {
    guard let continuation else { return }
    self.continuation = nil
    token = nil
    continuation.resume(with: result)
  }

  /// Error text for the model, which relays it to the user.
  static func message(for error: Error) -> String? {
    if error as? VideoEditorCaptionTranslationError == .requiresMacOS15 {
      return "Translating needs macOS 15 or later, or a translation endpoint in Snapzy's settings. Tell the user."
    }
    guard #available(macOS 15.0, *), !(error is CancellationError) else { return nil }
    switch AppleTranslationRunner.failure(from: error) {
    case .unsupportedLanguagePair:
      return "Apple Translation can't translate between these languages. Tell the user; a translation endpoint in Snapzy's settings may."
    case .unableToIdentifyLanguage:
      return "Apple Translation couldn't tell which language the captions are in. Tell the user."
    case .cancelled:
      return "The language download was cancelled, so nothing was translated."
    case .other(let detail):
      return "The translation failed (\(detail)). Tell the user."
    }
  }
}

// MARK: - Host

/// Hidden host that runs Apple Translation requests for the editor window. No-op before macOS 15.
struct VideoEditorCaptionTranslationHost: ViewModifier {
  @ObservedObject var translator: VideoEditorCaptionTranslator

  func body(content: Content) -> some View {
    if #available(macOS 15.0, *) {
      content.background(VideoEditorCaptionTranslationTaskView(translator: translator))
    } else {
      content
    }
  }
}

@available(macOS 15.0, *)
private struct VideoEditorCaptionTranslationTaskView: View {
  @ObservedObject var translator: VideoEditorCaptionTranslator
  @State private var configuration: TranslationSession.Configuration?
  @State private var pending: VideoEditorCaptionTranslator.Request?

  var body: some View {
    Color.clear
      .frame(width: 1, height: 1)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      .translationTask(configuration) { @MainActor session in
        guard let request = pending else { return }
        pending = nil
        do {
          let output = try await AppleBlockTranslator.run(request.texts, session: session)
          translator.complete(token: request.token, result: .success(output))
        } catch {
          translator.complete(token: request.token, result: .failure(error))
        }
      }
      .onAppear { sync(translator.request) }
      .onChange(of: translator.request) { sync($0) }
  }

  /// A new request means "translate now": build the configuration, or invalidate the
  /// existing one so the task runs again.
  private func sync(_ request: VideoEditorCaptionTranslator.Request?) {
    guard let request, request != pending else { return }
    pending = request
    let next = TranslationSession.Configuration(
      source: request.sourceLanguageIdentifier.map { Locale.Language(identifier: $0) },
      target: Locale.Language(identifier: request.targetLanguageIdentifier)
    )
    if configuration?.source == next.source, configuration?.target == next.target {
      configuration?.invalidate()
    } else {
      configuration = next
    }
  }
}
