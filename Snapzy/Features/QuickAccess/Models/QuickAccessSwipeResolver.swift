//
//  QuickAccessSwipeResolver.swift
//  Snapzy
//
//  Pure decision logic for Quick Access card swipes (mouse drag toward the
//  edge and two-finger trackpad swipes). Kept out of the view so the rules
//  can be unit tested.
//

import CoreGraphics

struct QuickAccessSwipeResolver: Equatable {
  enum Outcome: Equatable {
    /// Spring the card back to its resting position.
    case snapBack
    /// Run the configured action. `hidesCard` means the card leaves the stack
    /// as a result, so it should keep sliding off instead of springing back.
    case perform(QuickAccessActionKind, hidesCard: Bool)
    /// Tuck the card into the screen edge as a peek strip (#591).
    case collapse
  }

  let leftAction: QuickAccessActionKind?
  let rightAction: QuickAccessActionKind?
  let hideCardWhenWindowOpen: Bool
  /// When true, a swipe toward the panel's screen edge collapses the card
  /// instead of running that direction's configured action.
  var collapsesTowardEdge: Bool = false
  /// +1 when the panel sits on the right side of the screen, -1 on the left.
  var edgeDirection: CGFloat = 1

  func action(for direction: QuickAccessSwipeDirection) -> QuickAccessActionKind? {
    switch direction {
    case .left: return leftAction
    case .right: return rightAction
    }
  }

  /// Offset the card should follow while the swipe is in progress. A direction
  /// with nothing to run keeps the card still.
  func liveTranslation(_ translation: CGFloat) -> CGFloat {
    hasHandler(forTranslation: translation) ? translation : 0
  }

  func resolveEnd(
    translation: CGFloat,
    velocity: CGFloat,
    isActionEnabled: (QuickAccessActionKind) -> Bool
  ) -> Outcome {
    var translation = translation
    var velocity = velocity
    if !hasHandler(forTranslation: translation) {
      translation = 0
      velocity = 0
    }

    let passedThreshold =
      abs(translation) > QuickAccessCardDragPolicy.dismissDistanceThreshold
        || abs(velocity) > QuickAccessCardDragPolicy.dismissVelocityThreshold
    guard passedThreshold else { return .snapBack }

    if isTowardEdge(translation) {
      return .collapse
    }

    let direction: QuickAccessSwipeDirection = translation > 0 ? .right : .left
    guard let action = action(for: direction), isActionEnabled(action) else {
      return .snapBack
    }
    // Collapse assigned as a swipe action works from either direction.
    if action == .collapseToEdge {
      return .collapse
    }

    return .perform(action, hidesCard: hidesCard(after: action))
  }

  private func isTowardEdge(_ translation: CGFloat) -> Bool {
    collapsesTowardEdge && translation * edgeDirection > 0
  }

  private func hasHandler(forTranslation translation: CGFloat) -> Bool {
    if isTowardEdge(translation) { return true }
    if translation > 0 { return rightAction != nil }
    if translation < 0 { return leftAction != nil }
    return true
  }

  private func hidesCard(after action: QuickAccessActionKind) -> Bool {
    switch action {
    case .dismiss, .delete:
      return true
    case .pinToScreen, .edit:
      return hideCardWhenWindowOpen
    case .collapseToEdge:
      return true
    case .copy, .saveOrOpen, .uploadToCloud, .optimize:
      return false
    }
  }
}
