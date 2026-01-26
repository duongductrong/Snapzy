//
//  MockupMainView.swift
//  ClaudeShot
//
//  Main container view for the mockup renderer
//

import SwiftUI

/// Root container view for mockup rendering feature
struct MockupMainView: View {
    @StateObject private var state: MockupState

    init(image: NSImage? = nil) {
        let initialState = MockupState()
        if let image = image {
            initialState.sourceImage = image
        }
        _state = StateObject(wrappedValue: initialState)
    }

    var body: some View {
        VStack(spacing: 0) {
            MockupToolbarView(state: state)

            HSplitView {
                if state.showSidebar {
                    MockupSidebarView(state: state)
                }

                MockupCanvasView(state: state)
                    .frame(minWidth: 400)
            }

            MockupPresetBar(state: state)
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

// MARK: - Toolbar View

struct MockupToolbarView: View {
    @ObservedObject var state: MockupState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            // Left side - Toggle & Undo/Redo
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.showSidebar.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Sidebar")

                Divider()
                    .frame(height: 16)

                Button {
                    state.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!state.canUndo)
                .help("Undo")

                Button {
                    state.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!state.canRedo)
                .help("Redo")
            }

            Spacer()

            // Center - Title
            Text("Mockup")
                .font(.headline)

            Spacer()

            // Right side - Export & Actions
            HStack(spacing: 8) {
                Button {
                    state.resetToDefaults()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Reset to Defaults")

                Divider()
                    .frame(height: 16)

                Menu {
                    Button("Save As...") {
                        MockupExporter.saveAs(state: state)
                    }
                    Button("Copy to Clipboard") {
                        MockupExporter.copyToClipboard(state: state)
                    }
                    Divider()
                    Button("Share...") {
                        // Share functionality
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    MockupMainView()
}
