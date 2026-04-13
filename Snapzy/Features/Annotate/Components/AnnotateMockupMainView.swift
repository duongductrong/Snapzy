//
//  MockupMainView.swift
//  Snapzy
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
                .help(L10n.AnnotateUI.toggleSidebar)

                Divider()
                    .frame(height: 16)

                Button {
                    state.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!state.canUndo)
                .help(L10n.Common.undo)

                Button {
                    state.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!state.canRedo)
                .help(L10n.Common.redo)
            }

            Spacer()

            // Center - Title
            Text(L10n.AnnotateUI.modeMockup)
                .font(.headline)

            Spacer()

            // Right side - Export & Actions
            HStack(spacing: 8) {
                Button {
                    state.resetToDefaults()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help(L10n.AnnotateUI.resetToDefaults)

                Divider()
                    .frame(height: 16)

                Menu {
                    Button(L10n.Common.saveAs) {
                        MockupExporter.saveAs(state: state)
                    }
                    Button(L10n.Common.copyToClipboard) {
                        MockupExporter.copyToClipboard(state: state)
                    }
                    Divider()
                    Button(L10n.Common.share) {
                        // Share functionality
                    }
                } label: {
                    Label(L10n.Common.exportAction, systemImage: "square.and.arrow.up")
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
