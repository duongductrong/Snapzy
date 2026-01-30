//
//  MockupControlsSection.swift
//  Snapzy
//
//  Sidebar section for mockup 3D controls
//

import SwiftUI

/// Sidebar section with mockup controls when mockup tool is selected
struct MockupControlsSection: View {
    @ObservedObject var state: AnnotateState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            rotationSection
            perspectiveSection
            resetButton
        }
    }

    // MARK: - Rotation Section

    private var rotationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarSectionHeader(title: "Rotation")

            MockupSlider(
                label: "X Axis",
                value: $state.mockupRotationX,
                range: -45...45,
                format: "%.1f°"
            )

            MockupSlider(
                label: "Y Axis",
                value: $state.mockupRotationY,
                range: -45...45,
                format: "%.1f°"
            )

            MockupSlider(
                label: "Z Axis",
                value: $state.mockupRotationZ,
                range: -180...180,
                format: "%.1f°"
            )
        }
    }

    // MARK: - Perspective Section

    private var perspectiveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarSectionHeader(title: "Perspective")

            MockupSlider(
                label: "Depth",
                value: $state.mockupPerspective,
                range: 0.1...1.0,
                format: "%.2f"
            )
        }
    }

    // MARK: - Reset Button

    private var resetButton: some View {
        Button {
            state.resetMockup()
        } label: {
            Text("Reset Mockup")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mockup Slider Component

struct MockupSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: format, value))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Slider(value: $value, in: range)
                .controlSize(.small)
        }
    }
}

#Preview {
    MockupControlsSection(state: AnnotateState())
        .frame(width: 240)
        .padding()
}
