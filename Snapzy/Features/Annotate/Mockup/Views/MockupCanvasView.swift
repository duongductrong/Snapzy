//
//  MockupCanvasView.swift
//  Snapzy
//
//  Canvas view for displaying 3D mockup preview with background
//

import SwiftUI
import UniformTypeIdentifiers

/// Canvas view that displays the 3D mockup preview
struct MockupCanvasView: View {
    @ObservedObject var state: MockupState
    @State private var isDropTargeted = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundLayer

                Mockup3DRenderer(state: state)
                    .frame(maxWidth: geometry.size.width * 0.7)
                    .padding(state.padding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                dropOverlay
            }
        }
    }

    // MARK: - Background Layer

    @ViewBuilder
    private var backgroundLayer: some View {
        switch state.backgroundStyle {
        case .none:
            Color.clear
        case .gradient(let preset):
            LinearGradient(
                colors: preset.colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .solidColor(let color):
            color
        case .wallpaper(let url):
            // Check if this is a preset wallpaper
            if url.scheme == "preset", let presetName = url.host,
               let preset = WallpaperPreset(rawValue: presetName) {
                preset.gradient
            } else if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.3)
            }
        case .blurred(let url):
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 30)
            } else {
                Color.gray.opacity(0.3)
            }
        }
    }

    // MARK: - Drop Overlay

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.accentColor, lineWidth: 3)
            .background(Color.accentColor.opacity(0.1))
            .padding(8)
    }

    // MARK: - Drop Handling

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadObject(ofClass: NSImage.self) { image, _ in
                if let nsImage = image as? NSImage {
                    Task { @MainActor in
                        state.setImage(nsImage)
                    }
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    state.loadImage(from: url)
                }
            }
            return true
        }

        return false
    }
}

#Preview {
    MockupCanvasView(state: MockupState())
        .frame(width: 600, height: 400)
}
