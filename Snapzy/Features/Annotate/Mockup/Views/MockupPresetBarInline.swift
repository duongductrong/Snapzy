//
//  MockupPresetBarInline.swift
//  Snapzy
//
//  Inline preset bar for mockup tool in Annotate bottom bar
//

import SwiftUI

/// Horizontal preset bar shown in Annotate bottom bar when mockup tool is active
struct MockupPresetBarInline: View {
    @ObservedObject var state: AnnotateState
    let presets: [MockupPreset] = DefaultPresets.all

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(presets) { preset in
                    MockupPresetButtonInline(
                        preset: preset,
                        isSelected: state.selectedMockupPresetId == preset.id,
                        action: { state.applyMockupPreset(preset) }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(height: 70)
    }
}

// MARK: - Preset Button

struct MockupPresetButtonInline: View {
    let preset: MockupPreset
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                presetThumbnail
                    .frame(width: 60, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                    }
                    .scaleEffect(isHovered ? 1.05 : 1.0)

                Text(preset.name)
                    .font(.system(size: 9))
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
            LinearGradient(
                colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white)
                .frame(width: 30, height: 20)
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
                .shadow(radius: 1, x: 0.5, y: 0.5)
        }
    }
}

#Preview {
    MockupPresetBarInline(state: AnnotateState())
}
