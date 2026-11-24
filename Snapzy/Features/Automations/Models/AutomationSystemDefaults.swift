//
//  AutomationSystemDefaults.swift
//  Snapzy
//
//  Milestone 6: the after-capture matrix is stored as two system automations,
//  "Default after screenshot" and "Default after recording". `.standard`
//  routing runs them. They have no triggers, cannot be deleted, and are kept
//  apart from the user's list (and its 20-item cap).
//
//  Matrix ↔ steps:
//    Save            → source `saveToExportDirectory`
//    Copy file       → `copyFile`
//    Quick Access    → `showQuickAccess`
//    Open Annotate   → `openAnnotate` (screenshots only; the recording cell is disabled)
//
//  A default automation is "simple" while its steps are exactly what the
//  matrix would build (`project`); anything else is a custom pipeline.
//

import Foundation

enum AutomationSystemDefault {
  static let presetPrefix = "system-default-"

  static func presetID(for type: CaptureType) -> String {
    presetPrefix + type.rawValue
  }

  static func captureType(presetID: String?) -> CaptureType? {
    guard let presetID, presetID.hasPrefix(presetPrefix) else { return nil }
    return CaptureType(rawValue: String(presetID.dropFirst(presetPrefix.count)))
  }

  /// Stable ids so a config file / two Macs agree on which automation is which.
  static func id(for type: CaptureType) -> UUID {
    switch type {
    case .screenshot: UUID(uuidString: "5A1D0000-0000-4000-8000-000000000001")!
    case .recording: UUID(uuidString: "5A1D0000-0000-4000-8000-000000000002")!
    }
  }

  /// Name written to storage (English); shown localized while untouched.
  static func storedName(for type: CaptureType) -> String {
    switch type {
    case .screenshot: "Default after screenshot"
    case .recording: "Default after recording"
    }
  }

  static func localizedName(for type: CaptureType) -> String {
    switch type {
    case .screenshot: L10n.Automations.systemDefaultScreenshotName
    case .recording: L10n.Automations.systemDefaultRecordingName
    }
  }

  /// Matrix actions a capture type can use (Open Annotate is screenshot-only).
  static func actions(for type: CaptureType) -> [AfterCaptureAction] {
    switch type {
    case .screenshot: [.save, .copyFile, .showQuickAccess, .openAnnotate]
    case .recording: [.save, .copyFile, .showQuickAccess]
    }
  }

  /// Defaults the matrix used before any setting was stored.
  static func defaultMatrix(for type: CaptureType) -> [AfterCaptureAction: Bool] {
    var matrix: [AfterCaptureAction: Bool] = [:]
    for action in AfterCaptureAction.allCases {
      matrix[action] = action != .openAnnotate
    }
    if type == .recording { matrix[.openAnnotate] = false }
    return matrix
  }

  // MARK: - Matrix → automation

  /// Step kinds in the order the legacy handler ran them: copy, Quick Access, Annotate.
  static func stepKinds(for type: CaptureType, matrix: [AfterCaptureAction: Bool]) -> [AutomationStepKind] {
    var kinds: [AutomationStepKind] = []
    if matrix[.copyFile] == true { kinds.append(.copyFile) }
    if matrix[.showQuickAccess] == true { kinds.append(.showQuickAccess) }
    if type == .screenshot, matrix[.openAnnotate] == true { kinds.append(.openAnnotate) }
    return kinds
  }

  static func source(for type: CaptureType, save: Bool) -> AutomationSource {
    switch type {
    case .screenshot: .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: save))
    case .recording: .capture(AutomationCaptureSpec(mode: .recordingArea, saveToExportDirectory: save))
    }
  }

  /// The default automation the matrix describes. `reusing` keeps step ids
  /// (by kind) so toggling a cell doesn't churn the editor selection.
  static func make(
    for type: CaptureType,
    matrix: [AfterCaptureAction: Bool],
    reusing previous: Automation? = nil
  ) -> Automation {
    let previousIDs = Dictionary(
      (previous?.steps ?? []).compactMap { step in step.action.map { ($0.kind, step.id) } },
      uniquingKeysWith: { first, _ in first }
    )
    let steps = stepKinds(for: type, matrix: matrix).map { kind in
      AutomationStep(id: previousIDs[kind] ?? UUID(), kind.defaultAction)
    }
    return Automation(
      id: id(for: type),
      name: previous?.name ?? storedName(for: type),
      symbol: type == .screenshot ? "camera.viewfinder" : "record.circle",
      isEnabled: true,
      triggers: [],
      source: source(for: type, save: matrix[.save] ?? true),
      steps: steps,
      presetID: presetID(for: type)
    )
  }

  // MARK: - Automation → matrix

  /// The matrix this automation is exactly equal to, or `nil` for a custom
  /// pipeline (other step kinds, other order, disabled or repeated steps).
  static func project(_ automation: Automation, type: CaptureType) -> [AfterCaptureAction: Bool]? {
    guard let spec = automation.captureSpec else { return nil }
    var matrix = lenientMatrix(automation, type: type)
    matrix[.save] = spec.saveToExportDirectory
    let expected = stepKinds(for: type, matrix: matrix)
    let actual = automation.steps.map { step -> AutomationStepKind? in
      guard step.isEnabled else { return nil }
      return step.action?.kind
    }
    guard actual.count == expected.count,
          zip(actual, expected).allSatisfy({ $0 == $1 })
    else { return nil }
    return matrix
  }

  /// Best-effort matrix for any default automation (custom ones included):
  /// a cell is on when an enabled step of its kind is present. Feeds the
  /// legacy `afterCaptureActions` key (downgrade path) and readers such as
  /// the temp-vs-export decision and the edited-capture clipboard copy.
  static func lenientMatrix(_ automation: Automation, type: CaptureType) -> [AfterCaptureAction: Bool] {
    let kinds = Set(automation.activeActions.map(\.kind))
    return [
      .save: automation.captureSpec?.saveToExportDirectory ?? true,
      .copyFile: kinds.contains(.copyFile) || kinds.contains(.copyImage),
      .showQuickAccess: kinds.contains(.showQuickAccess),
      .openAnnotate: type == .screenshot && kinds.contains(.openAnnotate),
    ]
  }

  /// `automation` with one matrix cell changed. Simple pipelines are rebuilt
  /// in matrix order; a custom one only gains / loses steps of that kind.
  static func setting(
    _ action: AfterCaptureAction,
    to enabled: Bool,
    in automation: Automation,
    type: CaptureType
  ) -> Automation {
    if var matrix = project(automation, type: type) {
      matrix[action] = enabled
      return make(for: type, matrix: matrix, reusing: automation)
    }
    var copy = automation
    switch action {
    case .save:
      if var spec = copy.captureSpec {
        spec.saveToExportDirectory = enabled
        copy.source = .capture(spec)
      }
    case .copyFile, .showQuickAccess, .openAnnotate:
      guard action != .openAnnotate || type == .screenshot else { return copy }
      let kind: AutomationStepKind = switch action {
      case .copyFile: .copyFile
      case .showQuickAccess: .showQuickAccess
      default: .openAnnotate
      }
      let matches: (AutomationStep) -> Bool = {
        $0.action?.kind == kind || (kind == .copyFile && $0.action?.kind == .copyImage)
      }
      if enabled {
        if let index = copy.steps.firstIndex(where: matches) {
          copy.steps[index].isEnabled = true
        } else {
          // Copy first, Annotate last, Quick Access before Annotate.
          let position: Int = switch kind {
          case .copyFile: 0
          case .showQuickAccess: copy.steps.firstIndex { $0.action?.kind == .openAnnotate } ?? copy.steps.count
          default: copy.steps.count
          }
          copy.steps.insert(AutomationStep(kind.defaultAction), at: position)
        }
      } else {
        copy.steps.removeAll(where: matches)
      }
    }
    return copy
  }

  // MARK: - Runtime flags

  /// Steps a standard capture runs: `skipQuickAccess` (recording toolbars
  /// that already show a card) drops Quick Access; `pinToScreen` adds a Pin
  /// before Open Annotate, where the legacy handler pinned.
  static func runtimeSteps(
    _ steps: [AutomationStep],
    type: CaptureType,
    pinToScreen: Bool,
    skipQuickAccess: Bool
  ) -> [AutomationStep] {
    var result = steps
    if skipQuickAccess {
      result.removeAll { $0.action?.kind == .showQuickAccess }
    }
    if pinToScreen, type == .screenshot {
      let index = result.firstIndex { $0.isEnabled && $0.action?.kind == .openAnnotate } ?? result.count
      result.insert(AutomationStep(.pin), at: index)
    }
    return result
  }

  /// What the legacy `executeActions` did for this matrix and flags, in order.
  /// Used by the dual-run diagnostics (and the parity tests).
  static func legacyEffects(
    type: CaptureType,
    matrix: [AfterCaptureAction: Bool],
    pinToScreen: Bool,
    skipQuickAccess: Bool
  ) -> [AutomationStepKind] {
    var effects: [AutomationStepKind] = []
    if matrix[.copyFile] == true { effects.append(.copyFile) }
    if !skipQuickAccess, matrix[.showQuickAccess] == true { effects.append(.showQuickAccess) }
    if type == .screenshot, pinToScreen { effects.append(.pin) }
    if type == .screenshot, matrix[.openAnnotate] == true { effects.append(.openAnnotate) }
    return effects
  }

  /// Enabled step kinds a run will execute, in order (`copyImage` counts as `copyFile`).
  static func effects(of steps: [AutomationStep]) -> [AutomationStepKind] {
    steps.compactMap { step in
      guard step.isEnabled, let kind = step.action?.kind else { return nil }
      return kind == .copyImage ? .copyFile : kind
    }
  }
}

extension Automation {
  /// One of the two default after-capture automations.
  var isSystemDefault: Bool {
    systemCaptureType != nil
  }

  /// The capture type this default automation handles.
  var systemCaptureType: CaptureType? {
    AutomationSystemDefault.captureType(presetID: presetID)
  }

  /// True when the default automation is no longer what the matrix can show.
  var isCustomizedSystemDefault: Bool {
    guard let type = systemCaptureType else { return false }
    return AutomationSystemDefault.project(self, type: type) == nil
  }
}
