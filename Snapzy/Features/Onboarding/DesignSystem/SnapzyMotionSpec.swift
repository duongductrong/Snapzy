//
//  SnapzyMotionSpec.swift
//  Snapzy
//
//  Motion and animation token specifications with macOS 13+ backward compatibility.
//

import AppKit
import SwiftUI

struct SnapzyMotionSpec: Equatable {
  var duration: Double
  var curve: Curve

  enum Curve: Equatable {
    case custom(Double, Double, Double, Double)
    case spring(bounce: Double)
    case easeInOut
    case easeOut
    case easeIn
    case linear
  }

  var animation: Animation {
    switch curve {
    case .custom(let a, let b, let c, let d):
      return .timingCurve(a, b, c, d, duration: duration)
    case .spring(let bounce):
      if #available(macOS 14.0, *) {
        return .spring(duration: duration, bounce: bounce)
      } else {
        let dampingFraction = 1.0 - (bounce * 0.5)
        return .spring(response: duration, dampingFraction: dampingFraction)
      }
    case .easeInOut:
      return .easeInOut(duration: duration)
    case .easeOut:
      return .easeOut(duration: duration)
    case .easeIn:
      return .easeIn(duration: duration)
    case .linear:
      return .linear(duration: duration)
    }
  }

  func respectingReduceMotion(_ reduce: Bool) -> SnapzyMotionSpec {
    reduce ? SnapzyMotionSpec(duration: 0, curve: .linear) : self
  }

  var timingFunction: CAMediaTimingFunction? {
    switch curve {
    case .custom(let a, let b, let c, let d):
      return CAMediaTimingFunction(controlPoints: Float(a), Float(b), Float(c), Float(d))
    case .easeInOut:
      return CAMediaTimingFunction(name: .easeInEaseOut)
    case .easeOut:
      return CAMediaTimingFunction(name: .easeOut)
    case .easeIn:
      return CAMediaTimingFunction(name: .easeIn)
    case .linear:
      return CAMediaTimingFunction(name: .linear)
    case .spring:
      return nil
    }
  }

  // MARK: - Named Vocabulary

  static let morph = SnapzyMotionSpec(duration: 0.42, curve: .spring(bounce: 0.45))
  static let anticipation = SnapzyMotionSpec(duration: 0.13, curve: .easeOut)
  static let glide = SnapzyMotionSpec(duration: 0.45, curve: .custom(0.22, 0.9, 0.24, 1))
  static let contentIn = SnapzyMotionSpec(duration: 0.22, curve: .easeOut)
  static let contentOut = SnapzyMotionSpec(duration: 0.12, curve: .easeIn)
  static let hover = SnapzyMotionSpec(duration: 0.12, curve: .easeOut)
  static let settle = SnapzyMotionSpec(duration: 0.4, curve: .spring(bounce: 0.22))
  static let instant = SnapzyMotionSpec(duration: 0, curve: .linear)
}

@MainActor
final class SnapzyMotionPreferences {
  static let shared = SnapzyMotionPreferences()

  var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  func spec(_ base: SnapzyMotionSpec) -> SnapzyMotionSpec {
    base.respectingReduceMotion(reduceMotion)
  }
}
