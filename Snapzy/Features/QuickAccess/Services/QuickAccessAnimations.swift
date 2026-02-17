//
//  QuickAccessAnimations.swift
//  Snapzy
//
//  Shared animation constants for QuickAccess panel - CleanShot X inspired
//

import SwiftUI

/// Centralized animation definitions for QuickAccess feature
enum QuickAccessAnimations {

  // MARK: - Panel Animations

  /// Panel slide-in from corner
  static let panelEnter = Animation.spring(response: 0.4, dampingFraction: 0.75)

  /// Panel slide-out to corner
  static let panelExit = Animation.easeIn(duration: 0.25)

  /// Panel enter duration for NSAnimationContext
  static let panelEnterDuration: TimeInterval = 0.4

  /// Panel exit duration for NSAnimationContext
  static let panelExitDuration: TimeInterval = 0.25

  // MARK: - Card Animations

  /// Card insertion animation — smooth easeOut to avoid bouncy repositioning
  static let cardInsert = Animation.easeOut(duration: 0.25)

  /// Card removal animation
  static let cardRemove = Animation.spring(response: 0.35, dampingFraction: 0.8)

  /// Swipe-to-dismiss animation
  static let cardSwipeDismiss = Animation.spring(response: 0.3, dampingFraction: 0.65)

  // MARK: - Hover Animations

  /// Hover overlay fade in/out
  static let hoverOverlay = Animation.easeOut(duration: 0.15)

  /// Button reveal with bounce
  static let buttonReveal = Animation.spring(response: 0.25, dampingFraction: 0.6)

  /// Delay between button reveals (stagger effect)
  static let buttonStaggerDelay: Double = 0.05

  // MARK: - Depth Stack Animations

  /// Parallax movement on hover
  static let depthParallax = Animation.spring(response: 0.3, dampingFraction: 0.8)

  // MARK: - Progress Animations

  /// Progress ring rotation
  static let progressRotation = Animation.linear(duration: 1.0).repeatForever(autoreverses: false)

  /// Checkmark draw animation
  static let checkmarkDraw = Animation.easeOut(duration: 0.3)

  // MARK: - Accessibility

  /// Reduced motion alternative - simple fade
  static let reducedFade = Animation.easeInOut(duration: 0.2)

  /// Returns appropriate animation based on accessibility settings
  static func animation(for base: Animation, reduceMotion: Bool) -> Animation {
    reduceMotion ? reducedFade : base
  }

  /// Returns nil animation when reduce motion is enabled
  static func optionalAnimation(_ base: Animation, reduceMotion: Bool) -> Animation? {
    reduceMotion ? nil : base
  }
}
