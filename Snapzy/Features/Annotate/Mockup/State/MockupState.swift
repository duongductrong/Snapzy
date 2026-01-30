//
//  MockupState.swift
//  Snapzy
//
//  Central state management for 3D mockup rendering
//

import SwiftUI
import AppKit
import Combine

/// State snapshot for undo/redo
private struct MockupStateSnapshot: Equatable {
    let rotationX: Double
    let rotationY: Double
    let rotationZ: Double
    let perspective: Double
    let padding: CGFloat
    let shadowIntensity: Double
    let cornerRadius: Double
    let backgroundStyle: BackgroundStyle
}

/// Central state object for mockup renderer
@MainActor
final class MockupState: ObservableObject {
    // MARK: - Source Image
    @Published var sourceImage: NSImage?
    @Published var sourceURL: URL?

    // MARK: - 3D Transform Parameters
    @Published var rotationX: Double = 0 {
        didSet { rotationX = clamp(rotationX, min: -45, max: 45) }
    }
    @Published var rotationY: Double = 0 {
        didSet { rotationY = clamp(rotationY, min: -45, max: 45) }
    }
    @Published var rotationZ: Double = 0 {
        didSet { rotationZ = clamp(rotationZ, min: -180, max: 180) }
    }
    @Published var perspective: Double = 0.5 {
        didSet { perspective = clamp(perspective, min: 0.1, max: 1.0) }
    }

    // MARK: - Styling
    @Published var padding: CGFloat = 40
    @Published var shadowIntensity: Double = 0.3
    @Published var cornerRadius: Double = 12
    @Published var backgroundStyle: BackgroundStyle = .gradient(.bluePurple)

    // MARK: - Preset Selection
    @Published var selectedPresetId: UUID?

    // MARK: - UI State
    @Published var showSidebar: Bool = false
    @Published var zoomLevel: CGFloat = 1.0

    // MARK: - Undo/Redo
    private var undoStack: [MockupStateSnapshot] = []
    private var redoStack: [MockupStateSnapshot] = []
    private let maxUndoStackSize = 20

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Computed Properties

    /// Shadow X offset based on Y rotation
    var shadowOffsetX: CGFloat {
        CGFloat(rotationY) * 0.8
    }

    /// Shadow Y offset based on X rotation
    var shadowOffsetY: CGFloat {
        CGFloat(rotationX) * 0.5 + 8
    }

    /// Shadow radius scales with perspective
    var shadowRadius: CGFloat {
        CGFloat(20 * (1.1 - perspective) * shadowIntensity * 2)
    }

    // MARK: - Initialization

    init() {}

    init(sourceImage: NSImage) {
        self.sourceImage = sourceImage
    }

    // MARK: - Image Loading

    func loadImage(from url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        saveState()
        self.sourceImage = image
        self.sourceURL = url
    }

    func setImage(_ image: NSImage) {
        saveState()
        self.sourceImage = image
        self.sourceURL = nil
    }

    // MARK: - Preset Application

    func applyPreset(_ preset: MockupPreset) {
        saveState()
        rotationX = preset.rotationX
        rotationY = preset.rotationY
        rotationZ = preset.rotationZ
        perspective = preset.perspective
        padding = preset.padding
        selectedPresetId = preset.id
    }

    func resetToDefaults() {
        saveState()
        rotationX = 0
        rotationY = 0
        rotationZ = 0
        perspective = 0.5
        padding = 40
        shadowIntensity = 0.3
        cornerRadius = 12
        backgroundStyle = .gradient(.bluePurple)
        selectedPresetId = nil
    }

    // MARK: - Undo/Redo

    func saveState() {
        let snapshot = MockupStateSnapshot(
            rotationX: rotationX,
            rotationY: rotationY,
            rotationZ: rotationZ,
            perspective: perspective,
            padding: padding,
            shadowIntensity: shadowIntensity,
            cornerRadius: cornerRadius,
            backgroundStyle: backgroundStyle
        )

        // Avoid duplicates
        if undoStack.last != snapshot {
            undoStack.append(snapshot)
            if undoStack.count > maxUndoStackSize {
                undoStack.removeFirst()
            }
            redoStack.removeAll()
        }
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }

        // Save current state to redo stack
        let currentSnapshot = MockupStateSnapshot(
            rotationX: rotationX,
            rotationY: rotationY,
            rotationZ: rotationZ,
            perspective: perspective,
            padding: padding,
            shadowIntensity: shadowIntensity,
            cornerRadius: cornerRadius,
            backgroundStyle: backgroundStyle
        )
        redoStack.append(currentSnapshot)

        // Restore snapshot
        applySnapshot(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }

        // Save current state to undo stack
        let currentSnapshot = MockupStateSnapshot(
            rotationX: rotationX,
            rotationY: rotationY,
            rotationZ: rotationZ,
            perspective: perspective,
            padding: padding,
            shadowIntensity: shadowIntensity,
            cornerRadius: cornerRadius,
            backgroundStyle: backgroundStyle
        )
        undoStack.append(currentSnapshot)

        // Restore snapshot
        applySnapshot(snapshot)
    }

    private func applySnapshot(_ snapshot: MockupStateSnapshot) {
        rotationX = snapshot.rotationX
        rotationY = snapshot.rotationY
        rotationZ = snapshot.rotationZ
        perspective = snapshot.perspective
        padding = snapshot.padding
        shadowIntensity = snapshot.shadowIntensity
        cornerRadius = snapshot.cornerRadius
        backgroundStyle = snapshot.backgroundStyle
    }

    // MARK: - Helpers

    private func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.min(Swift.max(value, min), max)
    }
}
