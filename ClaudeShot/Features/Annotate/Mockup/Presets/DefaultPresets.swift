//
//  DefaultPresets.swift
//  ClaudeShot
//
//  Built-in preset configurations for mockup rendering
//

import Foundation

/// Container for default mockup presets
struct DefaultPresets {
    /// All built-in presets
    static let all: [MockupPreset] = [
        .flat,
        .leftTilt,
        .rightTilt,
        .topView,
        .isometricLeft,
        .isometricRight,
        .heroShot,
        .dramatic
    ]

    /// Get preset by name
    static func preset(named name: String) -> MockupPreset? {
        all.first { $0.name == name }
    }
}
