//
//  MockupExporter.swift
//  Snapzy
//
//  High-quality export functionality for mockup renderer
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Export utilities for mockup rendering
struct MockupExporter {

    // MARK: - Render Final Image

    /// Renders the mockup to an NSImage at specified scale
    static func renderFinalImage(state: MockupState, scale: CGFloat = 2.0) -> NSImage? {
        guard state.sourceImage != nil else { return nil }

        let exportView = MockupExportView(state: state)
        let renderer = ImageRenderer(content: exportView)
        renderer.scale = scale

        return renderer.nsImage
    }

    // MARK: - Save As

    /// Shows save panel and exports mockup to selected location
    static func saveAs(state: MockupState, scale: CGFloat = 2.0) {
        guard let image = renderFinalImage(state: state, scale: scale) else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = generateFilename()
        savePanel.canCreateDirectories = true

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            if let pngData = convertToPNG(image: image) {
                do {
                    try pngData.write(to: url)
                } catch {
                    print("Failed to save mockup: \(error)")
                }
            }
        }
    }

    // MARK: - Copy to Clipboard

    /// Copies the rendered mockup to system clipboard
    static func copyToClipboard(state: MockupState, scale: CGFloat = 2.0) {
        guard let image = renderFinalImage(state: state, scale: scale) else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    // MARK: - Share

    /// Opens share picker for the rendered mockup
    static func share(state: MockupState, scale: CGFloat = 2.0, from view: NSView) {
        guard let image = renderFinalImage(state: state, scale: scale) else { return }

        let picker = NSSharingServicePicker(items: [image])
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    // MARK: - Helpers

    private static func generateFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "mockup-\(formatter.string(from: Date())).png"
    }

    private static func convertToPNG(image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmapRep.representation(using: .png, properties: [:])
    }
}

// MARK: - Export View

/// Simplified view for export rendering (no UI chrome)
struct MockupExportView: View {
    let state: MockupState

    var body: some View {
        ZStack {
            backgroundLayer
                .frame(width: canvasSize.width, height: canvasSize.height)

            if let image = state.sourceImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: imageSize.width, maxHeight: imageSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: state.cornerRadius, style: .continuous))
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
            }
        }
    }

    // MARK: - Size Calculations

    private var imageSize: CGSize {
        guard let image = state.sourceImage else {
            return CGSize(width: 800, height: 600)
        }
        return image.size
    }

    private var canvasSize: CGSize {
        let extraSpace = state.padding * 2 + 100 // Extra for shadow and rotation
        return CGSize(
            width: imageSize.width + extraSpace,
            height: imageSize.height + extraSpace
        )
    }

    // MARK: - Background

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
}
