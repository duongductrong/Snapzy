//
//  AutomationTrust.swift
//  Snapzy
//
//  Least privilege for automations (milestone 4). Every step handler declares
//  a tier; the launcher refuses runs above what the user allowed:
//
//  - `.local`: always allowed.
//  - `.network`: allowed; the destination is whatever the user configured.
//  - `.code` (shell script, Apple Shortcut): only with Settings → Automations →
//    Advanced → "Allow script & Shortcut steps" (off by default), and from the
//    URL scheme or Shortcuts only with the automation's second opt-in.
//
//  Automations imported from a config file or recipe whose network / code steps
//  changed are flagged `needsReview` and refused until saved from the editor.
//

import Foundation

/// Where a step may reach.
enum AutomationTrustTier: String, Comparable, Sendable {
  case local
  case network
  case code

  private var rank: Int {
    switch self {
    case .local: 0
    case .network: 1
    case .code: 2
    }
  }

  static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rank < rhs.rank
  }
}

@MainActor
enum AutomationTrust {
  /// Settings → Automations → Advanced → "Allow script & Shortcut steps".
  static func allowsCodeSteps(_ defaults: UserDefaults = .standard) -> Bool {
    defaults.bool(forKey: PreferencesKeys.automationsAllowCodeSteps)
  }

  static func tier(of action: AutomationStepAction) -> AutomationTrustTier {
    AutomationStepRegistry.handler(for: action.kind).trust
  }

  /// Steps an import must not be able to slip in unnoticed: anything that runs
  /// code, or sends data to a destination the imported file itself chooses.
  /// A plain upload to the user's own cloud provider and Translate (the user's
  /// own engine) are network steps but don't pick a destination, so they don't
  /// need a review.
  static func needsReviewWhenImported(_ action: AutomationStepAction) -> Bool {
    switch action {
    case .webhook, .runScript, .runShortcut:
      return true
    case .upload(let config):
      return config.destination != .default
    default:
      return tier(of: action) == .code
    }
  }
}

@MainActor
extension Automation {
  /// Highest tier among enabled, supported steps.
  var maxTrust: AutomationTrustTier {
    activeActions.map(AutomationTrust.tier(of:)).max() ?? .local
  }

  var containsCodeSteps: Bool {
    maxTrust == .code
  }

  /// The review-relevant part of the automation: sensitive steps (in order,
  /// with their settings and enabled state) plus the external opt-in. Compared
  /// with `==`, which ignores row ids (headers, fields) and step ids.
  struct ReviewSubject: Equatable {
    let externalInvocation: Bool
    let steps: [AutomationStep]
  }

  var reviewSubject: ReviewSubject {
    let sensitive = steps.compactMap { step -> AutomationStep? in
      guard let action = step.action, AutomationTrust.needsReviewWhenImported(action) else { return nil }
      var copy = step
      copy.id = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
      copy.onFailure = .stop
      return copy
    }
    return ReviewSubject(externalInvocation: externalInvocation, steps: sensitive)
  }

  var hasReviewSensitiveSteps: Bool {
    steps.contains { $0.action.map(AutomationTrust.needsReviewWhenImported) ?? false }
  }

  /// Review rule for an imported automation: flag it when it has sensitive steps
  /// and they differ from the stored automation with the same id (or there is
  /// none). An already flagged automation stays flagged until reviewed.
  func flaggedForReview(comparedTo existing: Automation?) -> Automation {
    var copy = self
    // The second external opt-in is never taken from a file.
    copy.allowExternalCode = existing?.allowExternalCode ?? false
    guard hasReviewSensitiveSteps else {
      copy.needsReview = false
      return copy
    }
    if let existing, !existing.needsReview, existing.reviewSubject == reviewSubject {
      copy.needsReview = false
    } else {
      copy.needsReview = true
    }
    return copy
  }
}
