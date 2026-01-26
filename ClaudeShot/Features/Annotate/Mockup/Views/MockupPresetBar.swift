//
//  MockupPresetBar.swift
//  ClaudeShot
//
//  Horizontal bar with preset thumbnails (CleanShot style)
//

import SwiftUI

/// Bottom bar with horizontal scrollable preset thumbnails
struct MockupPresetBar: View {
    @ObservedObject var state: MockupState
    let presets: [MockupPreset]

    init(state: MockupState, presets: [MockupPreset] = DefaultPresets.all) {
        self.state = state
        self.presets = presets
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(presets) { preset in
                    PresetButton(
                        preset: preset,
                        isSelected: state.selectedPresetId == preset.id,
                        action: { state.applyPreset(preset) }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .frame(height: 100)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Preset Button

struct PresetButton: View {
    let preset: MockupPreset
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                presetThumbnail
                    .frame(width: 80, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                    }
                    .scaleEffect(isHovered ? 1.05 : 1.0)

                Text(preset.name)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    // MARK: - Thumbnail Preview

    private var presetThumbnail: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Mini mockup preview
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white)
                .frame(width: 40, height: 28)
                .rotation3DEffect(
                    .degrees(preset.rotationY),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: preset.perspective
                )
                .rotation3DEffect(
                    .degrees(preset.rotationX),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: preset.perspective
                )
                .rotation3DEffect(
                    .degrees(preset.rotationZ),
                    axis: (x: 0, y: 0, z: 1)
                )
                .shadow(radius: 2, x: 1, y: 1)
        }
    }
}

#Preview {
    MockupPresetBar(state: MockupState())
}
