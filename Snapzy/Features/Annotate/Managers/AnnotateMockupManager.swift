//
//  MockupManager.swift
//  Snapzy
//
//  Singleton manager for mockup renderer window lifecycle
//

import SwiftUI
import AppKit

/// Manages mockup renderer window lifecycle
@MainActor
final class MockupManager {
    static let shared = MockupManager()

    private var windowController: NSWindowController?

    private init() {}

    // MARK: - Open Mockup

    /// Opens mockup renderer with an image
    func openMockup(for image: NSImage) {
        let state = MockupState()
        state.sourceImage = image
        showWindow(with: state)
    }

    /// Opens mockup renderer from a file URL
    func openMockup(from url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        let state = MockupState()
        state.sourceImage = image
        state.sourceURL = url
        showWindow(with: state)
    }

    /// Opens empty mockup renderer for drag-drop
    func openEmptyMockup() {
        showWindow(with: MockupState())
    }

    // MARK: - Window Management

    private func showWindow(with state: MockupState) {
        // Close existing window if any
        close()

        let contentView = MockupMainView()
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Mockup"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 1000, height: 700))
        window.minSize = NSSize(width: 800, height: 600)
        window.center()

        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)

        windowController = controller

        // Observe window close
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.windowController = nil
        }
    }

    /// Closes the mockup window
    func close() {
        windowController?.close()
        windowController = nil
    }
}
