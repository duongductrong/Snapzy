//
//  HeadlessTranslationHost.swift
//  Snapzy
//
//  Apple Translation only hands out a `TranslationSession` to a SwiftUI view
//  through `.translationTask` (before macOS 26). Automations have no window,
//  so this hosts a 1×1 transparent view in an offscreen, non-activating panel
//  and resumes the caller from inside the task. The panel is reused and torn
//  down after a minute without requests.
//

import AppKit
import Combine
import SwiftUI
import Translation

@available(macOS 15.0, *)
@MainActor
final class HeadlessTranslationHost {
  static let shared = HeadlessTranslationHost()

  private static let timeout: UInt64 = 30_000_000_000
  private static let idleLifetime: UInt64 = 60_000_000_000

  private let model = HeadlessTranslationModel()
  private var panel: NSPanel?
  private var teardownTask: Task<Void, Never>?
  /// Requests run one at a time: one view, one session.
  private var queue: Task<Void, Never>?

  func translate(_ text: String, target: TranslationLanguage) async throws -> String {
    let previous = queue
    let request = Task { @MainActor () -> Result<String, Error> in
      await previous?.value
      do {
        return .success(try await self.perform(text, target: target))
      } catch {
        return .failure(error)
      }
    }
    queue = Task { _ = await request.value }
    return try await request.value.get()
  }

  private func perform(_ text: String, target: TranslationLanguage) async throws -> String {
    teardownTask?.cancel()
    ensurePanel()
    defer { scheduleTeardown() }

    return try await withCheckedThrowingContinuation { continuation in
      let token = model.begin(text: text, target: target.localeLanguage, continuation: continuation)
      Task { @MainActor [model] in
        try? await Task.sleep(nanoseconds: Self.timeout)
        model.fail(token: token, with: AutomationStepError.translationUnavailable(L10n.Automations.errorTranslationTimedOut))
      }
    }
  }

  private func ensurePanel() {
    guard panel == nil else { return }
    let panel = NSPanel(
      contentRect: NSRect(x: -10_000, y: -10_000, width: 1, height: 1),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isReleasedWhenClosed = false
    panel.alphaValue = 0
    panel.ignoresMouseEvents = true
    panel.hasShadow = false
    panel.level = .normal
    panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
    panel.contentView = NSHostingView(rootView: HeadlessTranslationView(model: model))
    panel.orderFrontRegardless()
    self.panel = panel
  }

  private func scheduleTeardown() {
    teardownTask?.cancel()
    teardownTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: Self.idleLifetime)
      guard !Task.isCancelled, let self, !self.model.isBusy else { return }
      self.panel?.close()
      self.panel = nil
    }
  }
}

@available(macOS 15.0, *)
@MainActor
private final class HeadlessTranslationModel: ObservableObject {
  @Published var configuration: TranslationSession.Configuration?

  private var pending: (token: UUID, text: String, continuation: CheckedContinuation<String, Error>)?

  var isBusy: Bool { pending != nil }

  func begin(text: String, target: Locale.Language, continuation: CheckedContinuation<String, Error>) -> UUID {
    let token = UUID()
    pending = (token, text, continuation)
    if configuration?.target == target, configuration?.source == nil {
      configuration?.invalidate()
    } else {
      configuration = TranslationSession.Configuration(source: nil, target: target)
    }
    return token
  }

  func run(_ session: TranslationSession) async {
    guard let request = pending else { return }
    do {
      let output = try await AppleTranslationRunner.run(request.text, session: session)
      finish(token: request.token, with: .success(output.text))
    } catch {
      let failure = AppleTranslationRunner.failure(from: error)
      let message: String = switch failure {
      case .unsupportedLanguagePair: L10n.Automations.errorTranslationUnsupportedPair
      case .unableToIdentifyLanguage: L10n.Automations.errorTranslationUnknownLanguage
      case .cancelled: L10n.Automations.errorTranslationDownload
      case .other(let description): description
      }
      finish(token: request.token, with: .failure(AutomationStepError.translationUnavailable(message)))
    }
  }

  func fail(token: UUID, with error: Error) {
    finish(token: token, with: .failure(error))
  }

  private func finish(token: UUID, with result: Result<String, Error>) {
    guard let request = pending, request.token == token else { return }
    pending = nil
    request.continuation.resume(with: result)
  }
}

@available(macOS 15.0, *)
private struct HeadlessTranslationView: View {
  @ObservedObject var model: HeadlessTranslationModel

  var body: some View {
    Color.clear
      .frame(width: 1, height: 1)
      .translationTask(model.configuration) { session in
        await model.run(session)
      }
  }
}
