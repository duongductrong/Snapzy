//
//  ScreenRulerPreferences.swift
//  Snapzy
//
//  Screen Ruler settings kept between sessions.
//

import Foundation

struct ScreenRulerPreferences {
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var unit: ScreenRulerUnit {
    get {
      defaults.string(forKey: PreferencesKeys.screenRulerUnit).flatMap(ScreenRulerUnit.init(rawValue:)) ?? .points
    }
    nonmutating set {
      defaults.set(newValue.rawValue, forKey: PreferencesKeys.screenRulerUnit)
    }
  }

  var edgeTolerance: Int {
    get {
      let stored = defaults.object(forKey: PreferencesKeys.screenRulerEdgeTolerance) as? Int
        ?? ScreenRulerEdgeScanner.defaultTolerance
      return min(max(stored, ScreenRulerEdgeScanner.toleranceRange.lowerBound), ScreenRulerEdgeScanner.toleranceRange.upperBound)
    }
    nonmutating set {
      defaults.set(newValue, forKey: PreferencesKeys.screenRulerEdgeTolerance)
    }
  }
}
