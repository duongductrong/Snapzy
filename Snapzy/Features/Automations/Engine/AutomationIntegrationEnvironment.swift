//
//  AutomationIntegrationEnvironment.swift
//  Snapzy
//
//  Milestone 4 services behind `AutomationRunEnvironment`: upload
//  destinations, secrets, HTTP, child processes, the share sheet and opening
//  files in another app. Defaults keep test doubles small; the live
//  implementations are on `LiveAutomationRunEnvironment`.
//

import AppKit
import Foundation

@MainActor
extension AutomationRunEnvironment {
  func isUploadConfigured(_ destination: AutomationUploadDestination) -> Bool {
    destination == .default ? isCloudConfigured : false
  }

  func upload(_ url: URL, destination: AutomationUploadDestination) async throws -> CloudUploadResult {
    guard destination == .default else { throw AutomationStepError.uploaderMissing }
    return try await upload(url)
  }

  func secretValue(named _: String) -> String? { nil }

  var allowsCodeSteps: Bool { false }

  func send(_: URLRequest, bodyFile _: URL?) async throws -> (Data, HTTPURLResponse) {
    throw AutomationStepError.failed("HTTP unavailable")
  }

  func runProcess(_: ProcessRequest) async throws -> ProcessOutcome {
    throw AutomationStepError.failed("Processes unavailable")
  }

  func share(_: [Any], service _: AutomationShareService) async throws {
    throw AutomationStepError.shareServiceUnavailable
  }

  func open(_: [URL], appBundleID _: String, appName: String) async throws {
    throw AutomationStepError.appNotFound(appName)
  }
}

// MARK: - Live

extension LiveAutomationRunEnvironment {
  func isUploadConfigured(_ destination: AutomationUploadDestination) -> Bool {
    switch destination {
    case .default:
      return isCloudConfigured
    case .customUploader(let id):
      return AutomationCustomUploads.exists(id)
    }
  }

  func upload(_ url: URL, destination: AutomationUploadDestination) async throws -> CloudUploadResult {
    switch destination {
    case .default:
      return try await upload(url)
    case .customUploader(let id):
      return try await AutomationCustomUploads.upload(url, uploaderID: id)
    }
  }

  func secretValue(named name: String) -> String? {
    AutomationSecretStore.shared.value(for: name)
  }

  var allowsCodeSteps: Bool {
    AutomationTrust.allowsCodeSteps()
  }

  func send(_ request: URLRequest, bodyFile: URL?) async throws -> (Data, HTTPURLResponse) {
    let session = URLSession(configuration: .ephemeral)
    defer { session.finishTasksAndInvalidate() }
    // Redirects are never followed: headers (often secrets) and the body would
    // go to wherever the server points, possibly over plain HTTP.
    let noRedirects = AutomationNoRedirectDelegate()
    let (data, response) = if let bodyFile {
      try await session.upload(for: request, fromFile: bodyFile, delegate: noRedirects)
    } else {
      try await session.data(for: request, delegate: noRedirects)
    }
    guard let http = response as? HTTPURLResponse else { throw AutomationStepError.failed(L10n.CloudOperation.invalidResponse) }
    return (data, http)
  }

  func runProcess(_ request: ProcessRequest) async throws -> ProcessOutcome {
    try await ProcessRunner.run(request)
  }

  func share(_ items: [Any], service: AutomationShareService) async throws {
    try await AutomationSharePresenter.shared.share(items, service: service)
  }

  func open(_ items: [URL], appBundleID: String, appName: String) async throws {
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID) else {
      throw AutomationStepError.appNotFound(appName.isEmpty ? appBundleID : appName)
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    _ = try await NSWorkspace.shared.open(items, withApplicationAt: appURL, configuration: configuration)
  }
}

/// Refuses every HTTP redirect; the 3xx response becomes the step's result.
private nonisolated final class AutomationNoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(
    _: URLSession,
    task _: URLSessionTask,
    willPerformHTTPRedirection _: HTTPURLResponse,
    newRequest _: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

// MARK: - Custom uploads

/// Bridge from the upload step to Settings → Cloud → Custom uploaders.
@MainActor
enum AutomationCustomUploads {
  static func exists(_ id: UUID) -> Bool {
    CustomUploaderStore.shared.uploader(id: id) != nil
  }

  static func upload(_ url: URL, uploaderID: UUID) async throws -> CloudUploadResult {
    guard let uploader = CustomUploaderStore.shared.uploader(id: uploaderID) else {
      throw AutomationStepError.uploaderMissing
    }
    do {
      return try await CustomUploaderEngine().upload(
        fileURL: url,
        using: uploader,
        secrets: CustomUploaderSecrets.provider,
        progress: { _ in }
      )
    } catch CustomUploaderError.unresolvedSecret(let name) {
      throw AutomationStepError.secretMissing(name)
    } catch {
      // The server's error text may echo a header; the runner can't see these
      // secrets (the engine resolved them), so mask them here.
      let values = secretReferences(in: uploader).compactMap { AutomationSecretStore.shared.value(for: $0) }
      let masked = AutomationSecretStore.mask(error.localizedDescription, values: values)
      guard masked != error.localizedDescription else { throw error }
      throw AutomationStepError.failed(masked)
    }
  }

  static func secretReferences(in uploader: CustomUploader) -> [String] {
    var templates = [uploader.url] + uploader.headers.map(\.value) + uploader.query.map(\.value)
    switch uploader.body {
    case .multipart(_, let fields), .formURLEncoded(let fields): templates += fields.map(\.value)
    case .binary: break
    }
    return templates.flatMap(AutomationSecretStore.references(in:))
  }
}

// MARK: - Share sheet

/// Presents `NSSharingServicePicker` (anchored to a tiny transparent panel at
/// the mouse, since Snapzy is a menu bar app with no window to anchor to) or
/// performs a named sharing service, and waits until the user is done.
@MainActor
final class AutomationSharePresenter: NSObject {
  static let shared = AutomationSharePresenter()

  private var panel: NSPanel?
  private var pickerContinuation: CheckedContinuation<Void, Error>?
  private var serviceContinuation: CheckedContinuation<Void, Error>?

  static func sharingService(for service: AutomationShareService) -> NSSharingService? {
    switch service {
    case .picker: nil
    case .airDrop: NSSharingService(named: .sendViaAirDrop)
    case .messages: NSSharingService(named: .composeMessage)
    case .mail: NSSharingService(named: .composeEmail)
    case .named(let raw): NSSharingService(named: NSSharingService.Name(raw))
    }
  }

  func share(_ items: [Any], service: AutomationShareService) async throws {
    guard pickerContinuation == nil, serviceContinuation == nil else {
      throw AutomationStepError.failed(L10n.Automations.errorShareBusy)
    }
    guard !items.isEmpty else { throw AutomationStepError.noFile }

    // Some services never call their delegate; cancelling the run (HUD) must
    // still end the wait, or every later share would report "busy".
    try await withTaskCancellationHandler {
      if service == .picker {
        try await presentPicker(items)
        return
      }
      guard let sharing = Self.sharingService(for: service), sharing.canPerform(withItems: items) else {
        throw AutomationStepError.shareServiceUnavailable
      }
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        serviceContinuation = continuation
        sharing.delegate = self
        NSApp.activate(ignoringOtherApps: true)
        sharing.perform(withItems: items)
      }
    } onCancel: {
      Task { @MainActor in AutomationSharePresenter.shared.cancelPending() }
    }
  }

  /// Ends whatever share is waiting (run cancelled).
  func cancelPending() {
    finishPicker(.failure(CancellationError()))
    finishService(.failure(CancellationError()))
  }

  private func presentPicker(_ items: [Any]) async throws {
    let mouse = NSEvent.mouseLocation
    let panel = NSPanel(
      contentRect: NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.level = .popUpMenu
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.orderFrontRegardless()
    self.panel = panel

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      pickerContinuation = continuation
      let picker = NSSharingServicePicker(items: items)
      picker.delegate = self
      NSApp.activate(ignoringOtherApps: true)
      guard let view = panel.contentView else {
        finishPicker(.failure(AutomationStepError.shareServiceUnavailable))
        return
      }
      picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
  }

  private func finishPicker(_ result: Result<Void, Error>) {
    panel?.orderOut(nil)
    panel = nil
    let continuation = pickerContinuation
    pickerContinuation = nil
    continuation?.resume(with: result)
  }

  private func finishService(_ result: Result<Void, Error>) {
    let continuation = serviceContinuation
    serviceContinuation = nil
    continuation?.resume(with: result)
  }
}

extension AutomationSharePresenter: NSSharingServicePickerDelegate, NSSharingServiceDelegate {
  nonisolated func sharingServicePicker(_: NSSharingServicePicker, didChoose service: NSSharingService?) {
    MainActor.assumeIsolated {
      guard let service else {
        // Dismissed without a choice: nothing was shared, but that is the user's call.
        finishPicker(.success(()))
        return
      }
      panel?.orderOut(nil)
      panel = nil
      service.delegate = self
      // The picker hands over to the service; its delegate finishes the step.
      serviceContinuation = pickerContinuation
      pickerContinuation = nil
    }
  }

  nonisolated func sharingService(_: NSSharingService, didShareItems _: [Any]) {
    MainActor.assumeIsolated { finishService(.success(())) }
  }

  nonisolated func sharingService(_: NSSharingService, didFailToShareItems _: [Any], error: Error) {
    MainActor.assumeIsolated {
      let cancelled = (error as NSError).code == NSUserCancelledError
      finishService(cancelled ? .success(()) : .failure(error))
    }
  }
}
