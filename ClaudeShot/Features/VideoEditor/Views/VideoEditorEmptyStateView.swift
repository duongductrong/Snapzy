//
//  VideoEditorEmptyStateView.swift
//  ClaudeShot
//
//  Empty state view with drag & drop zone for video editor
//

import SwiftUI
import UniformTypeIdentifiers

/// Empty state view displayed when no video is loaded
struct VideoEditorEmptyStateView: View {
  var onVideoDropped: (URL) -> Void

  @State private var isTargeted = false
  @State private var showError = false
  @State private var errorMessage = ""

  private let supportedTypes: [UTType] = [.movie, .video, .quickTimeMovie, .mpeg4Movie]

  var body: some View {
    VStack(spacing: 0) {
      Spacer()

      dropZone

      Spacer()

      // Cancel button at bottom
      HStack {
        Spacer()
        Button("Cancel") {
          NSApp.keyWindow?.close()
        }
        .keyboardShortcut(.cancelAction)
        .padding()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(NSColor.windowBackgroundColor))
    .alert("Invalid File", isPresented: $showError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  private var dropZone: some View {
    VStack(spacing: 16) {
      // Video icon
      Image(systemName: "film")
        .font(.system(size: 48, weight: .light))
        .foregroundColor(isTargeted ? .accentColor : .secondary)

      // Instructions
      VStack(spacing: 4) {
        Text("Drop a video here to edit")
          .font(.headline)
          .foregroundColor(.primary)

        Text("Supports MOV, MP4, and other video formats")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

      // Browse button
      Button("Browse Files...") {
        browseForVideo()
      }
      .buttonStyle(.bordered)
      .padding(.top, 8)
    }
    .frame(width: 400, height: 250)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(
          style: StrokeStyle(lineWidth: 2, dash: [8, 4])
        )
        .foregroundColor(isTargeted ? .accentColor : .secondary.opacity(0.5))
    )
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
    )
    .onDrop(of: supportedTypes, isTargeted: $isTargeted) { providers in
      handleDrop(providers: providers)
    }
    .animation(.easeInOut(duration: 0.2), value: isTargeted)
  }

  private func handleDrop(providers: [NSItemProvider]) -> Bool {
    guard let provider = providers.first else {
      print("[VideoEditor Drop] No provider found")
      return false
    }

    print("[VideoEditor Drop] Provider: \(provider)")
    print("[VideoEditor Drop] Registered types: \(provider.registeredTypeIdentifiers)")

    // Find the first video type the provider can load
    guard let videoType = supportedTypes.first(where: {
      provider.hasItemConformingToTypeIdentifier($0.identifier)
    }) else {
      print("[VideoEditor Drop] No supported video type found")
      DispatchQueue.main.async {
        showError(message: "Unsupported file type")
      }
      return false
    }

    print("[VideoEditor Drop] Loading file representation for type: \(videoType.identifier)")

    // Use loadFileRepresentation - it provides a temp file we need to copy
    _ = provider.loadFileRepresentation(forTypeIdentifier: videoType.identifier) { tempURL, error in
      if let error = error {
        print("[VideoEditor Drop] loadFileRepresentation error: \(error)")
        DispatchQueue.main.async {
          self.showError(message: "Failed to load file: \(error.localizedDescription)")
        }
        return
      }

      guard let tempURL = tempURL else {
        print("[VideoEditor Drop] No temp URL received")
        DispatchQueue.main.async {
          self.showError(message: "Could not read file")
        }
        return
      }

      print("[VideoEditor Drop] Temp URL: \(tempURL)")
      print("[VideoEditor Drop] Temp file exists: \(FileManager.default.fileExists(atPath: tempURL.path))")

      // Copy temp file to a permanent location before it gets deleted
      let fileName = tempURL.lastPathComponent
      let destURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("VideoEditor_\(UUID().uuidString)")
        .appendingPathComponent(fileName)

      do {
        // Create directory if needed
        try FileManager.default.createDirectory(
          at: destURL.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        // Copy file
        try FileManager.default.copyItem(at: tempURL, to: destURL)
        print("[VideoEditor Drop] Copied to: \(destURL)")
        print("[VideoEditor Drop] Dest file exists: \(FileManager.default.fileExists(atPath: destURL.path))")

        DispatchQueue.main.async {
          self.validateAndLoad(url: destURL)
        }
      } catch {
        print("[VideoEditor Drop] Copy error: \(error)")
        DispatchQueue.main.async {
          self.showError(message: "Failed to prepare file: \(error.localizedDescription)")
        }
      }
    }

    return true
  }

  private func browseForVideo() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowedContentTypes = supportedTypes

    panel.begin { response in
      if response == .OK, let url = panel.url {
        validateAndLoad(url: url)
      }
    }
  }

  private func validateAndLoad(url: URL) {
    // Validate file exists
    guard FileManager.default.fileExists(atPath: url.path) else {
      showError(message: "File not found")
      return
    }

    // Validate it's a video file
    guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
          type.conforms(to: .movie) || type.conforms(to: .video) else {
      showError(message: "Please select a valid video file")
      return
    }

    onVideoDropped(url)
  }

  private func showError(message: String) {
    errorMessage = message
    showError = true
  }
}
