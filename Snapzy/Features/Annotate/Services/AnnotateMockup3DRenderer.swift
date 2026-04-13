//
//  Mockup3DRenderer.swift
//  Snapzy
//
//  3D transformation renderer for mockup images
//

import SwiftUI

/// Renders an image with 3D perspective transformations
struct Mockup3DRenderer: View {
    @ObservedObject var state: MockupState

    var body: some View {
        Group {
            if let image = state.sourceImage {
                imageContent(image)
            } else {
                placeholderView
            }
        }
    }

    // MARK: - Image Content

    @ViewBuilder
    private func imageContent(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: state.cornerRadius, style: .continuous))
            // Apply rotations in Y -> X -> Z order for intuitive control
            .rotation3DEffect(
                .degrees(state.rotationY),
                axis: (x: 0, y: 1, z: 0),
                anchor: .center,
                anchorZ: 0,
                perspective: state.perspective
            )
            .rotation3DEffect(
                .degrees(state.rotationX),
                axis: (x: 1, y: 0, z: 0),
                anchor: .center,
                anchorZ: 0,
                perspective: state.perspective
            )
            .rotation3DEffect(
                .degrees(state.rotationZ),
                axis: (x: 0, y: 0, z: 1),
                anchor: .center
            )
            .shadow(
                color: .black.opacity(state.shadowIntensity),
                radius: state.shadowRadius,
                x: state.shadowOffsetX,
                y: state.shadowOffsetY
            )
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: state.rotationX)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: state.rotationY)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: state.rotationZ)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: state.perspective)
    }

    // MARK: - Placeholder

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.gray.opacity(0.2))
            .frame(width: 300, height: 200)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(L10n.AnnotateUI.dropImageHere)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
    }
}

// MARK: - Preview Content View (for export)

/// A view that renders the mockup without animations for static export
struct MockupStaticRenderer: View {
    let image: NSImage
    let rotationX: Double
    let rotationY: Double
    let rotationZ: Double
    let perspective: Double
    let cornerRadius: Double
    let shadowIntensity: Double
    let shadowOffsetX: CGFloat
    let shadowOffsetY: CGFloat
    let shadowRadius: CGFloat

    init(state: MockupState) {
        self.image = state.sourceImage ?? NSImage()
        self.rotationX = state.rotationX
        self.rotationY = state.rotationY
        self.rotationZ = state.rotationZ
        self.perspective = state.perspective
        self.cornerRadius = state.cornerRadius
        self.shadowIntensity = state.shadowIntensity
        self.shadowOffsetX = state.shadowOffsetX
        self.shadowOffsetY = state.shadowOffsetY
        self.shadowRadius = state.shadowRadius
    }

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .rotation3DEffect(
                .degrees(rotationY),
                axis: (x: 0, y: 1, z: 0),
                anchor: .center,
                anchorZ: 0,
                perspective: perspective
            )
            .rotation3DEffect(
                .degrees(rotationX),
                axis: (x: 1, y: 0, z: 0),
                anchor: .center,
                anchorZ: 0,
                perspective: perspective
            )
            .rotation3DEffect(
                .degrees(rotationZ),
                axis: (x: 0, y: 0, z: 1),
                anchor: .center
            )
            .shadow(
                color: .black.opacity(shadowIntensity),
                radius: shadowRadius,
                x: shadowOffsetX,
                y: shadowOffsetY
            )
    }
}

#Preview {
    let state = MockupState()
    state.rotationX = 10
    state.rotationY = -15
    state.perspective = 0.4

    return Mockup3DRenderer(state: state)
        .frame(width: 400, height: 300)
        .padding()
}
