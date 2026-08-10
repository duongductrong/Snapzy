//
//  WindowShadowPreference.swift
//  Snapzy
//
//  Resolves the "Include window shadow in Application Capture" preference
//  (PreferencesKeys.captureIncludeWindowShadow) to the value
//  SCStreamConfiguration.ignoreShadowsSingleWindow expects.
//

import Foundation

/// Resolves the "Include window shadow in Application Capture" preference
/// (PreferencesKeys.captureIncludeWindowShadow, default `defaultIncludeShadow`)
/// to the value `SCStreamConfiguration.ignoreShadowsSingleWindow` expects.
///
/// The API field is INVERTED relative to the user-facing toggle:
/// - shadow included  -> `ignoreShadowsSingleWindow == false`
/// - shadow excluded  -> `ignoreShadowsSingleWindow == true`
///
/// This is the single source of truth for that inversion so a future contributor
/// cannot silently flip the sign at the five capture-configuration call sites.
enum WindowShadowPreference {
  /// Default for the stored preference. `true` preserves legacy single-window
  /// capture output (shadow on) exactly until the user opts out.
  static let defaultIncludeShadow: Bool = true

  /// Maps the stored "include shadow" flag to the `SCStreamConfiguration` value.
  static func ignoreShadowsSingleWindow(includeShadow: Bool) -> Bool { !includeShadow }
}
