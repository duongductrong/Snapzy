//
//  SnapzyOnboardingEntrance.swift
//  Snapzy
//
//  The staged entrance every onboarding group uses to arrive instead of switch on.
//

import SwiftUI

/// Rises into place `index` beats after the rest of its group.
///
/// `appeared` belongs to the container, not to the member: one view drives the whole sequence so
/// the beats stay in phase, and each member only says how late it joins. Under Reduce Motion the
/// modifier steps aside entirely — content is simply there, which is the point of the setting.
struct SnapzyEntranceModifier: ViewModifier {
  var index: Int
  var appeared: Bool
  /// Seconds between beats. Onboarding's working pages keep the default tight rhythm; a screen
  /// that is meant to land once, like completion, can afford a wider one.
  var step: Double = 0.035

  private var motion: SnapzyMotionPreferences {
    SnapzyMotionPreferences.shared
  }

  func body(content: Content) -> some View {
    if motion.reduceMotion {
      content
    } else {
      content
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .animation(motion.spec(.rise).animation.delay(motion.stagger(index, step: step)), value: appeared)
    }
  }
}

extension View {
  func entrance(_ index: Int, appeared: Bool, step: Double = 0.035) -> some View {
    modifier(SnapzyEntranceModifier(index: index, appeared: appeared, step: step))
  }
}
