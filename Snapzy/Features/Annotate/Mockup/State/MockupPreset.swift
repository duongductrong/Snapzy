//
//  MockupPreset.swift
//  Snapzy
//
//  Preset data model for 3D mockup transformations
//

import Foundation

/// Represents a preset configuration for 3D mockup rendering
struct MockupPreset: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var rotationX: Double
    var rotationY: Double
    var rotationZ: Double
    var perspective: Double
    var padding: CGFloat

    /// Default initializer
    init(
        id: UUID = UUID(),
        name: String,
        rotationX: Double = 0,
        rotationY: Double = 0,
        rotationZ: Double = 0,
        perspective: Double = 0.5,
        padding: CGFloat = 40
    ) {
        self.id = id
        self.name = name
        self.rotationX = rotationX
        self.rotationY = rotationY
        self.rotationZ = rotationZ
        self.perspective = perspective
        self.padding = padding
    }

    /// Flat preset - no rotation
    static let flat = MockupPreset(
        name: "Flat",
        rotationX: 0,
        rotationY: 0,
        rotationZ: 0,
        perspective: 0.5,
        padding: 40
    )

    /// Left tilt preset
    static let leftTilt = MockupPreset(
        name: "Left Tilt",
        rotationX: 0,
        rotationY: -15,
        rotationZ: 0,
        perspective: 0.5,
        padding: 60
    )

    /// Right tilt preset
    static let rightTilt = MockupPreset(
        name: "Right Tilt",
        rotationX: 0,
        rotationY: 15,
        rotationZ: 0,
        perspective: 0.5,
        padding: 60
    )

    /// Top view preset
    static let topView = MockupPreset(
        name: "Top View",
        rotationX: 15,
        rotationY: 0,
        rotationZ: 0,
        perspective: 0.4,
        padding: 60
    )

    /// Isometric left preset
    static let isometricLeft = MockupPreset(
        name: "Isometric Left",
        rotationX: 12,
        rotationY: -20,
        rotationZ: 0,
        perspective: 0.3,
        padding: 80
    )

    /// Isometric right preset
    static let isometricRight = MockupPreset(
        name: "Isometric Right",
        rotationX: 12,
        rotationY: 20,
        rotationZ: 0,
        perspective: 0.3,
        padding: 80
    )

    /// Hero shot preset - dramatic angle
    static let heroShot = MockupPreset(
        name: "Hero Shot",
        rotationX: 8,
        rotationY: -25,
        rotationZ: 2,
        perspective: 0.25,
        padding: 100
    )

    /// Dramatic preset - strong perspective
    static let dramatic = MockupPreset(
        name: "Dramatic",
        rotationX: 20,
        rotationY: -30,
        rotationZ: 5,
        perspective: 0.2,
        padding: 120
    )

    /// All built-in presets
    static let allPresets: [MockupPreset] = [
        .flat,
        .leftTilt,
        .rightTilt,
        .topView,
        .isometricLeft,
        .isometricRight,
        .heroShot,
        .dramatic
    ]
}
