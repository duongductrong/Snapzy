//
//  AnnotateState+AutoTranslate.swift
//  Snapzy
//
//  Annotate Auto Translate: detect text on the image, translate it with the Snip to
//  Translate engine, and place each translation over its source text as an editable,
//  movable `.translation` annotation.
//

import AppKit
import Combine
import Foundation
import SwiftUI

// MARK: - Models

enum AnnotateAutoTranslatePhase: Equatable {
  case idle
  /// Vision is reading the image.
  case reading
  /// Blocks are known; the engine is translating.
  case translating
  /// Results arrive block by block before they become annotations.
  case resolving
}

/// A block shown by the loading overlay while a run is in flight.
struct AnnotateAutoTranslateOverlayBlock: Identifiable, Equatable {
  let id: UUID
  /// Reading order, drives the staggered entrance and resolve.
  let index: Int
  let bounds: CGRect
  let coverColor: Color
  let textColor: Color
  let cover: TranslationCoverStyle
  let fontSize: CGFloat
  let isBold: Bool
  let alignment: TranslationTextAlignment
  var translatedText: String?
}

enum AnnotateAutoTranslateNotice: Equatable {
  case success(count: Int, targetLanguage: String)
  case failure(message: String, action: AnnotateAutoTranslateFailureAction?)
}

enum AnnotateAutoTranslateFailureAction: Equatable {
  case openSettings
  case translateWithEndpoint(name: String, id: UUID)
}

struct AnnotateAppleTranslationRequest: Equatable {
  let token: UUID
  let texts: [String]
  let sourceLanguageIdentifier: String?
  let targetLanguageIdentifier: String
}

/// Mutable bookkeeping that is not UI state.
@MainActor
final class AnnotateAutoTranslateRuntime {
  var operationID: UUID?
  var task: Task<Void, Never>?
  var appleContinuation: CheckedContinuation<BlockTranslationOutput, Error>?
  var appleToken: UUID?
  var noticeTask: Task<Void, Never>?
  /// Area of the last run (nil = whole image), so "Translate with …" retries the same area.
  var lastRegion: CGRect?
  /// Where the current Translate Area drag started (annotate space).
  var areaDragStart: CGPoint?
}

// MARK: - Flow

extension AnnotateState {
  /// Pause between blocks as they resolve, in reading order.
  static let autoTranslateResolveStagger: TimeInterval = 0.045
  static let autoTranslateResolveDuration: TimeInterval = 0.42

  var isAutoTranslateRunning: Bool {
    autoTranslatePhase != .idle
  }

  var canAutoTranslate: Bool {
    hasImage
      && editorMode == .annotate
      && !isCombineMode
      && !isCropInteractionActive
      && !isCutOutInteractionActive
      && !agent.isRunning
  }

  var translationAnnotationCount: Int {
    annotations.reduce(0) { $0 + ($1.type.isTranslation ? 1 : 0) }
  }

  /// Snip to Translate's stored target; otherwise the app language when supported, else English.
  var autoTranslateTarget: TranslationLanguage {
    if let stored = TranslationLanguage.storedTarget() { return stored }
    let appLanguage = AppLanguageManager.shared.activeEffectiveLanguageIdentifier
    return TranslationLanguage.language(for: appLanguage)
      ?? TranslationLanguage.all.first {
        AnnotateAutoTranslateLayout.languageCode($0.identifier) == AnnotateAutoTranslateLayout.languageCode(appLanguage)
      }
      ?? TranslationLanguage(identifier: "en")
  }

  func setAutoTranslateTarget(_ language: TranslationLanguage) {
    TranslationLanguage.storeTarget(language)
    objectWillChange.send()
  }

  func toggleAutoTranslate() {
    if isAutoTranslateRunning {
      cancelAutoTranslate()
    } else {
      autoTranslate()
    }
  }

  /// Runs Auto Translate on the current image, or only inside `region` (annotate space)
  /// for Translate Area. `endpoint` forces a custom endpoint for this run only (an
  /// explicit "Translate with …" after Apple failed).
  func autoTranslate(using endpoint: CustomOCRModel? = nil, region: CGRect? = nil) {
    guard !isAutoTranslateRunning, canAutoTranslate, let image = effectiveSourceImage else { return }
    if isTranslateAreaSelecting {
      endTranslateAreaSelection()
    }
    if editingTextAnnotationId != nil {
      commitTextEditing()
    }

    let resolver = TranslationEngineResolver()
    let route: TranslationRoute = endpoint.map { .remote($0) } ?? resolver.resolve()
    if case .unavailable = route {
      showAutoTranslateNotice(.failure(message: L10n.Translate.requiresMacOS15Title, action: .openSettings))
      return
    }

    let target = autoTranslateTarget
    let operationID = UUID()
    autoTranslateRuntime.operationID = operationID
    autoTranslateRuntime.noticeTask?.cancel()
    autoTranslateNotice = nil
    autoTranslateBlocks = []
    autoTranslateRegion = region
    autoTranslateRuntime.lastRegion = region
    autoTranslatePhase = .reading
    DiagnosticLogger.shared.log(.info, .annotate, "Auto Translate started", context: [
      "target": target.identifier,
      "engine": Self.engineName(route),
      "scope": region == nil ? "image" : "area",
    ])

    autoTranslateRuntime.task = Task { [weak self] in
      guard let self else { return }
      do {
        let candidates = try await AnnotateAutoTranslateLayout.detectCandidates(
          in: image,
          region: region,
          languageIdentifier: AppLanguageManager.shared.activeOCRLanguageIdentifier,
          targetLanguage: target
        )
        guard isCurrentAutoTranslate(operationID) else { return }

        autoTranslateBlocks = candidates.enumerated().map { index, candidate in
          Self.overlayBlock(for: candidate, index: index)
        }
        autoTranslatePhase = .translating

        let texts = candidates.map(\.sourceText)
        let output = try await translate(texts, route: route, target: target)
        guard isCurrentAutoTranslate(operationID) else { return }

        try await resolveAndCommit(
          candidates: candidates,
          output: output,
          target: target,
          region: region,
          operationID: operationID
        )
      } catch {
        guard isCurrentAutoTranslate(operationID) else { return }
        failAutoTranslate(error, route: route)
      }
    }
  }

  func cancelAutoTranslate() {
    guard autoTranslateRuntime.operationID != nil || isAutoTranslateRunning else { return }
    autoTranslateRuntime.operationID = nil
    autoTranslateRuntime.task?.cancel()
    autoTranslateRuntime.task = nil
    resumeAppleTranslation(with: .failure(CancellationError()))
    appleTranslationRequest = nil
    autoTranslateBlocks = []
    autoTranslateRegion = nil
    autoTranslatePhase = .idle
  }

  // MARK: Translate Area

  /// Starts Translate Area: the next drag on the canvas picks the area to translate.
  func beginTranslateAreaSelection() {
    guard !isAutoTranslateRunning, canAutoTranslate else { return }
    if editingTextAnnotationId != nil {
      commitTextEditing()
    }
    dismissAutoTranslateNotice()
    setSelectedAnnotationIds([])
    translateAreaDraft = nil
    autoTranslateRuntime.areaDragStart = nil
    isTranslateAreaSelecting = true
  }

  func toggleTranslateAreaSelection() {
    if isAutoTranslateRunning {
      cancelAutoTranslate()
    } else if isTranslateAreaSelecting {
      endTranslateAreaSelection()
    } else {
      beginTranslateAreaSelection()
    }
  }

  func endTranslateAreaSelection() {
    isTranslateAreaSelecting = false
    translateAreaDraft = nil
    autoTranslateRuntime.areaDragStart = nil
  }

  /// Canvas drag, in annotate space. Returns false when not selecting an area.
  @discardableResult
  func updateTranslateAreaDrag(from start: CGPoint?, to point: CGPoint) -> Bool {
    guard isTranslateAreaSelecting else { return false }
    if let start {
      autoTranslateRuntime.areaDragStart = start
    }
    guard let origin = autoTranslateRuntime.areaDragStart else { return true }
    translateAreaDraft = CGRect(
      x: min(origin.x, point.x),
      y: min(origin.y, point.y),
      width: abs(point.x - origin.x),
      height: abs(point.y - origin.y)
    ).intersection(sourceImageBounds)
    return true
  }

  /// Ends the drag: a real area runs Auto Translate inside it; a click keeps the mode on.
  @discardableResult
  func finishTranslateAreaDrag(at point: CGPoint) -> Bool {
    guard isTranslateAreaSelecting else { return false }
    updateTranslateAreaDrag(from: nil, to: point)
    let area = translateAreaDraft ?? .null
    autoTranslateRuntime.areaDragStart = nil
    guard !area.isNull, area.width >= Self.minimumTranslateAreaSide, area.height >= Self.minimumTranslateAreaSide else {
      translateAreaDraft = nil
      return true
    }
    endTranslateAreaSelection()
    autoTranslate(region: area)
    return true
  }

  static let minimumTranslateAreaSide: CGFloat = 8

  /// Called by the hidden `.translationTask` host with the batch result.
  func completeAppleTranslation(token: UUID, result: Result<BlockTranslationOutput, Error>) {
    guard autoTranslateRuntime.appleToken == token else { return }
    appleTranslationRequest = nil
    resumeAppleTranslation(with: result)
  }

  func dismissAutoTranslateNotice() {
    autoTranslateRuntime.noticeTask?.cancel()
    autoTranslateNotice = nil
  }

  /// Keeps the pill up while hovered; restarts the timer when the pointer leaves.
  func holdAutoTranslateNotice(_ isHeld: Bool) {
    autoTranslateRuntime.noticeTask?.cancel()
    guard !isHeld, autoTranslateNotice != nil else { return }
    scheduleNoticeDismissal()
  }

  func performAutoTranslateNoticeAction(_ action: AnnotateAutoTranslateFailureAction) {
    dismissAutoTranslateNotice()
    switch action {
    case .openSettings:
      Self.openTranslationSettings()
    case .translateWithEndpoint(_, let id):
      guard let endpoint = Self.customEndpoints().first(where: { $0.id == id }) else { return }
      autoTranslate(using: endpoint, region: autoTranslateRuntime.lastRegion)
    }
  }

  func removeAllTranslations() {
    guard translationAnnotationCount > 0 else { return }
    saveState()
    annotations.removeAll { $0.type.isTranslation }
    setSelectedAnnotationIds(selectedAnnotationIds.filter { id in annotations.contains { $0.id == id } })
    hasUnsavedChanges = true
    dismissAutoTranslateNotice()
  }

  func setPeekingOriginalTranslations(_ isPeeking: Bool) {
    let next = isPeeking && translationAnnotationCount > 0
    guard isPeekingOriginalTranslations != next else { return }
    isPeekingOriginalTranslations = next
  }

  func setIncludesTranslationsInExport(_ include: Bool) {
    guard includesTranslationsInExport != include else { return }
    includesTranslationsInExport = include
    hasUnsavedChanges = true
  }

  // MARK: Editing translation items

  var selectedTranslation: (id: UUID, block: TranslatedTextBlock, item: AnnotationItem)? {
    guard let id = selectedAnnotationId,
          let item = annotations.first(where: { $0.id == id }),
          case .translation(let block) = item.type else { return nil }
    return (id, block, item)
  }

  func updateTranslation(
    id: UUID,
    recordsUndo: Bool = true,
    refit: Bool = false,
    _ change: (inout TranslatedTextBlock, inout AnnotationProperties) -> Void
  ) {
    guard let index = annotations.firstIndex(where: { $0.id == id }),
          case .translation(var block) = annotations[index].type else { return }
    var properties = annotations[index].properties
    change(&block, &properties)
    if recordsUndo { saveState() }
    annotations[index].properties = properties
    annotations[index].type = .translation(block)
    if refit {
      refitTranslation(at: index, allowsGrowth: true)
    }
    hasUnsavedChanges = true
  }

  func setTranslationText(id: UUID, text: String) {
    updateTranslation(id: id, refit: true) { block, _ in
      block.translatedText = text
    }
  }

  func setTranslationFontSize(id: UUID, size: CGFloat) {
    updateTranslation(id: id) { block, properties in
      properties.fontSize = min(max(size, AnnotateTranslationTextLayout.minimumFontSize), AnnotateTranslationTextLayout.maximumFontSize)
      block.isFontSizeManual = true
    }
  }

  /// Drops a manual size and fits the text to the box again.
  func fitTranslationText(id: UUID) {
    updateTranslation(id: id, refit: true) { block, _ in
      block.isFontSizeManual = false
    }
  }

  /// Keeps fitted text in step with the box while it is resized.
  func refitTranslationAfterResize(at index: Int, oldBounds: CGRect) {
    guard annotations.indices.contains(index),
          case .translation(var block) = annotations[index].type,
          !block.isFontSizeManual else { return }
    let newBounds = annotations[index].bounds.standardized
    if oldBounds.height > 0.5, abs(newBounds.height - oldBounds.height) > 0.01 {
      block.baseFontSize *= newBounds.height / oldBounds.height
      annotations[index].type = .translation(block)
    }
    refitTranslation(at: index, allowsGrowth: false)
  }

  private func refitTranslation(at index: Int, allowsGrowth: Bool) {
    guard case .translation(let block) = annotations[index].type, !block.isFontSizeManual else { return }
    let fitted = AnnotateTranslationTextLayout.fit(
      text: block.translatedText,
      in: annotations[index].bounds,
      baseFontSize: block.baseFontSize,
      fontName: annotations[index].properties.fontName,
      isBold: block.isBold,
      allowsGrowth: allowsGrowth
    )
    annotations[index].properties.fontSize = fitted.fontSize
    annotations[index].bounds = fitted.bounds
  }

  // MARK: Private

  private func isCurrentAutoTranslate(_ operationID: UUID) -> Bool {
    autoTranslateRuntime.operationID == operationID && !Task.isCancelled
  }

  private func translate(
    _ texts: [String],
    route: TranslationRoute,
    target: TranslationLanguage
  ) async throws -> BlockTranslationOutput {
    switch route {
    case .apple:
      let source = TranslationSourceLanguageDetector.detect(texts.joined(separator: "\n"))
      if let source,
         AnnotateAutoTranslateLayout.languageCode(source) == AnnotateAutoTranslateLayout.languageCode(target.identifier) {
        throw AnnotateAutoTranslateError.alreadyInTargetLanguage
      }
      let supportedSource = source.flatMap { identifier -> String? in
        let code = AnnotateAutoTranslateLayout.languageCode(identifier)
        return TranslationLanguage.all.contains { AnnotateAutoTranslateLayout.languageCode($0.identifier) == code }
          ? identifier : nil
      }
      return try await withCheckedThrowingContinuation { continuation in
        resumeAppleTranslation(with: .failure(CancellationError()))
        let token = UUID()
        autoTranslateRuntime.appleContinuation = continuation
        autoTranslateRuntime.appleToken = token
        appleTranslationRequest = AnnotateAppleTranslationRequest(
          token: token,
          texts: texts,
          sourceLanguageIdentifier: supportedSource,
          targetLanguageIdentifier: target.identifier
        )
      }
    case .remote(let model):
      return try await RemoteBlockTranslator(model: model).translate(texts, to: target)
    case .unavailable:
      throw AnnotateAutoTranslateError.noText
    }
  }

  private func resumeAppleTranslation(with result: Result<BlockTranslationOutput, Error>) {
    guard let continuation = autoTranslateRuntime.appleContinuation else { return }
    autoTranslateRuntime.appleContinuation = nil
    autoTranslateRuntime.appleToken = nil
    continuation.resume(with: result)
  }

  private func resolveAndCommit(
    candidates: [AnnotateTranslationCandidate],
    output: BlockTranslationOutput,
    target: TranslationLanguage,
    region: CGRect?,
    operationID: UUID
  ) async throws {
    let groupID = UUID()
    let baseProperties = annotationCreationProperties(for: .text)
    var items: [AnnotationItem] = []
    var resolvedBlocks = autoTranslateBlocks

    for (index, candidate) in candidates.enumerated() {
      guard let text = output.texts.indices.contains(index) ? output.texts[index] : nil,
            !text.isEmpty,
            text.trimmingCharacters(in: .whitespacesAndNewlines) != candidate.sourceText else { continue }
      let block = TranslatedTextBlock(
        sourceText: candidate.sourceText,
        translatedText: text,
        sourceLanguage: output.sourceLanguageIdentifier,
        targetLanguage: target.identifier,
        cover: candidate.style.cover,
        alignment: candidate.alignment,
        isBold: candidate.style.isBold,
        isFontSizeManual: false,
        baseFontSize: candidate.baseFontSize,
        groupID: groupID
      )
      let fitted = AnnotateTranslationTextLayout.fit(
        text: text,
        in: candidate.bounds,
        baseFontSize: candidate.baseFontSize,
        fontName: baseProperties.fontName,
        isBold: block.isBold
      )
      var properties = baseProperties
      properties.strokeColor = Color(nsColor: candidate.style.text.nsColor)
      properties.fillColor = Color(nsColor: candidate.style.background.nsColor)
      properties.fontSize = fitted.fontSize
      properties.textPresentation = .plain
      properties.opacity = 1
      properties.rotationDegrees = 0
      items.append(AnnotationItem(id: candidate.id, type: .translation(block), bounds: fitted.bounds, properties: properties))

      if let overlayIndex = resolvedBlocks.firstIndex(where: { $0.id == candidate.id }) {
        resolvedBlocks[overlayIndex] = Self.overlayBlock(for: candidate, index: resolvedBlocks[overlayIndex].index,
                                                         fontSize: fitted.fontSize, bounds: fitted.bounds, text: text)
      }
    }

    guard !items.isEmpty else {
      throw AnnotateAutoTranslateError.alreadyInTargetLanguage
    }

    // Blocks without a result fade out; the rest resolve in reading order.
    autoTranslateBlocks = resolvedBlocks.filter { $0.translatedText != nil }
    autoTranslatePhase = .resolving
    let resolveTime = Self.autoTranslateResolveDuration
      + Self.autoTranslateResolveStagger * Double(max(min(items.count, 24) - 1, 0))
    try await Task.sleep(nanoseconds: UInt64(resolveTime * 1_000_000_000))
    guard isCurrentAutoTranslate(operationID) else { return }

    saveState()
    // A whole-image run replaces every translation; an area run only those it overlaps.
    annotations.removeAll { item in
      guard item.type.isTranslation else { return false }
      guard let region else { return true }
      return item.bounds.intersects(region)
    }
    annotations.append(contentsOf: items)
    setSelectedAnnotationIds([])
    selectedTool = .selection
    hasUnsavedChanges = true

    autoTranslateRuntime.operationID = nil
    autoTranslateRuntime.task = nil
    autoTranslateBlocks = []
    autoTranslateRegion = nil
    autoTranslatePhase = .idle
    showAutoTranslateNotice(.success(count: items.count, targetLanguage: target.displayName))
    DiagnosticLogger.shared.log(.info, .annotate, "Auto Translate completed", context: [
      "blocks": "\(items.count)",
      "candidates": "\(candidates.count)",
    ])
  }

  private func failAutoTranslate(_ error: Error, route: TranslationRoute) {
    autoTranslateRuntime.operationID = nil
    autoTranslateRuntime.task = nil
    appleTranslationRequest = nil
    autoTranslateBlocks = []
    autoTranslateRegion = nil
    autoTranslatePhase = .idle

    if error is CancellationError { return }

    let message: String
    var action: AnnotateAutoTranslateFailureAction?
    if let error = error as? AnnotateAutoTranslateError {
      message = error.errorDescription ?? error.localizedDescription
    } else if case .apple = route, #available(macOS 15.0, *) {
      let failure = AppleTranslationRunner.failure(from: error)
      switch failure {
      case .cancelled:
        return
      case .unsupportedLanguagePair:
        message = L10n.Translate.errorUnsupportedPair
      case .unableToIdentifyLanguage:
        message = L10n.Translate.errorUnidentifiedLanguage
      case .other(let description):
        message = L10n.Translate.errorGeneric(description)
      }
      if failure.canRetryWithEndpoint, let endpoint = TranslationEngineResolver().firstAvailableEndpoint() {
        action = .translateWithEndpoint(name: endpoint.name, id: endpoint.id)
      }
    } else {
      message = L10n.Translate.errorGeneric(error.localizedDescription)
      action = .openSettings
    }

    showAutoTranslateNotice(.failure(message: message, action: action))
    DiagnosticLogger.shared.log(.warning, .annotate, "Auto Translate failed", context: [
      "error": String(describing: type(of: error)),
    ])
  }

  private func showAutoTranslateNotice(_ notice: AnnotateAutoTranslateNotice) {
    autoTranslateRuntime.noticeTask?.cancel()
    autoTranslateNotice = notice
    scheduleNoticeDismissal()
  }

  private func scheduleNoticeDismissal() {
    let duration: TimeInterval
    switch autoTranslateNotice {
    case .success: duration = 5
    case .failure: duration = 9
    case nil: return
    }
    autoTranslateRuntime.noticeTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
      guard !Task.isCancelled else { return }
      self?.autoTranslateNotice = nil
    }
  }

  private static func overlayBlock(
    for candidate: AnnotateTranslationCandidate,
    index: Int,
    fontSize: CGFloat? = nil,
    bounds: CGRect? = nil,
    text: String? = nil
  ) -> AnnotateAutoTranslateOverlayBlock {
    AnnotateAutoTranslateOverlayBlock(
      id: candidate.id,
      index: index,
      bounds: bounds ?? candidate.bounds,
      coverColor: Color(nsColor: candidate.style.background.nsColor),
      textColor: Color(nsColor: candidate.style.text.nsColor),
      cover: candidate.style.cover,
      fontSize: fontSize ?? candidate.baseFontSize,
      isBold: candidate.style.isBold,
      alignment: candidate.alignment,
      translatedText: text
    )
  }

  private static func engineName(_ route: TranslationRoute) -> String {
    switch route {
    case .apple: "apple"
    case .remote: "remote"
    case .unavailable: "unavailable"
    }
  }

  static func customEndpoints() -> [CustomOCRModel] {
    guard let data = UserDefaults.standard.data(forKey: PreferencesKeys.ocrCustomModels) else { return [] }
    return (try? JSONDecoder().decode([CustomOCRModel].self, from: data)) ?? []
  }

  static func openTranslationSettings() {
    AppStatusBarController.shared.openPreferencesWindow(tab: .capture)
    PreferencesNavigationState.shared.reveal(
      PreferencesSearchEntry(
        .capture,
        section: L10n.Translate.settingsSection,
        title: L10n.Translate.settingsEngineTitle,
        keywords: []
      ).inPane("ocr")
    )
  }
}
