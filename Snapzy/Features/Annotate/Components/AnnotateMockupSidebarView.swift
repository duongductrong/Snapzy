//
//  MockupSidebarView.swift
//  Snapzy
//
//  Sidebar with parameter sliders for mockup adjustments
//

import SwiftUI

/// Sidebar view with grouped sliders for mockup parameters
struct MockupSidebarView: View {
    @ObservedObject var state: MockupState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                rotationSection
                perspectiveSection
                appearanceSection
                backgroundSection
            }
            .padding()
        }
        .frame(width: 260)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Rotation Section

    private var rotationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(L10n.Common.rotation, action: resetRotation)

            MockupSliderRow(
                label: L10n.AnnotateUI.xAxis,
                value: $state.rotationX,
                range: -45...45,
                format: "%.1f°"
            )

            MockupSliderRow(
                label: L10n.AnnotateUI.yAxis,
                value: $state.rotationY,
                range: -45...45,
                format: "%.1f°"
            )

            MockupSliderRow(
                label: L10n.AnnotateUI.zAxis,
                value: $state.rotationZ,
                range: -180...180,
                format: "%.1f°"
            )
        }
    }

    // MARK: - Perspective Section

    private var perspectiveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(L10n.Common.perspective, action: resetPerspective)

            MockupSliderRow(
                label: L10n.AnnotateUI.depth,
                value: $state.perspective,
                range: 0.1...1.0,
                format: "%.2f"
            )
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(L10n.Common.style, action: resetAppearance)

            MockupSliderRow(
                label: L10n.Common.padding,
                value: Binding(
                    get: { Double(state.padding) },
                    set: { state.padding = CGFloat($0) }
                ),
                range: 0...200,
                format: "%.0f"
            )

            MockupSliderRow(
                label: L10n.Common.shadow,
                value: $state.shadowIntensity,
                range: 0...1,
                format: "%.2f"
            )

            MockupSliderRow(
                label: L10n.Common.corners,
                value: $state.cornerRadius,
                range: 0...50,
                format: "%.0f"
            )
        }
    }

    // MARK: - Background Section

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(L10n.Common.background, action: nil)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 32))], spacing: 8) {
                ForEach(GradientPreset.allCases) { preset in
                    gradientButton(preset)
                }
            }

            HStack {
                Button(L10n.Common.none) {
                    state.backgroundStyle = .none
                }
                .buttonStyle(.bordered)

                ColorPicker(L10n.Common.solid, selection: solidColorBinding)
                    .labelsHidden()
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, action: (() -> Void)?) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            if let action = action {
                Button(L10n.Common.reset) {
                    action()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func gradientButton(_ preset: GradientPreset) -> some View {
        Button {
            state.backgroundStyle = .gradient(preset)
        } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 32, height: 32)
                .overlay {
                    if case .gradient(let current) = state.backgroundStyle, current == preset {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var solidColorBinding: Binding<Color> {
        Binding(
            get: {
                if case .solidColor(let color) = state.backgroundStyle {
                    return color
                }
                return .white
            },
            set: { state.backgroundStyle = .solidColor($0) }
        )
    }

    // MARK: - Reset Actions

    private func resetRotation() {
        state.saveState()
        state.rotationX = 0
        state.rotationY = 0
        state.rotationZ = 0
    }

    private func resetPerspective() {
        state.saveState()
        state.perspective = 0.5
    }

    private func resetAppearance() {
        state.saveState()
        state.padding = 40
        state.shadowIntensity = 0.3
        state.cornerRadius = 12
    }
}

// MARK: - Slider Row Component

struct MockupSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: format, value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: $value, in: range)
        }
    }
}

#Preview {
    MockupSidebarView(state: MockupState())
        .frame(height: 600)
}
