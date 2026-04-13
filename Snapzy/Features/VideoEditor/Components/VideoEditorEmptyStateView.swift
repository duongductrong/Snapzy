//
//  VideoEditorEmptyStateView.swift
//  Snapzy
//
//  Empty state view with drag & drop zone for video editor
//

import SwiftUI
import UniformTypeIdentifiers

/// Empty state view displayed when no video is loaded
struct VideoEditorEmptyStateView: View {
  /// Callback with (workingURL, originalURL) - originalURL is the user's actual file for "Replace Original"
  var onVideoDropped: (URL, URL?) -> Void

  @State private var isTargeted = false
  @State private var showError = false
  @State private var errorMessage = ""

  private let supportedTypes: [UTType] = [.movie, .video, .quickTimeMovie, .mpeg4Movie, .gif]

  var body: some View {
    VStack(spacing: 0) {
      Spacer()

      dropZone

      Spacer()

      // Cancel button at bottom
      HStack {
        Spacer()
        Button(L10n.Common.cancel) {
          NSApp.keyWindow?.close()
        }
        .keyboardShortcut(.cancelAction)
        .padding()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .alert(L10n.VideoEditor.invalidFileTitle, isPresented: $showError) {
      Button(L10n.Common.ok, role: .cancel) {}
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
        Text(L10n.VideoEditor.dropVideoHereToEdit)
          .font(.headline)
          .foregroundColor(.primary)

        Text(L10n.VideoEditor.supportsVideoFormats)
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

      // Browse button
      Button(L10n.VideoEditor.browseFiles) {
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
        showError(message: L10n.VideoEditor.unsupportedFileType)
      }
      return false
    }

    print("[VideoEditor Drop] Loading file for type: \(videoType.identifier)")

    // First, extract the original URL using loadItem (provides actual file URL)
    provider.loadItem(forTypeIdentifier: videoType.identifier, options: nil) { item, error in
      if let error = error {
        print("[VideoEditor Drop] loadItem error: \(error)")
        DispatchQueue.main.async {
          self.showError(message: L10n.VideoEditor.failedToLoadFile(error.localizedDescription))
        }
        return
      }

      // Extract original URL from the item
      let originalURL: URL?
      if let url = item as? URL {
        originalURL = url
        print("[VideoEditor Drop] Original URL from loadItem: \(url)")
      } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
        originalURL = url
        print("[VideoEditor Drop] Original URL from Data: \(url)")
      } else {
        originalURL = nil
        print("[VideoEditor Drop] Could not extract original URL from item: \(String(describing: item))")
      }

      // Now load file representation to get a working copy
      _ = provider.loadFileRepresentation(forTypeIdentifier: videoType.identifier) { tempURL, repError in
        if let repError = repError {
          print("[VideoEditor Drop] loadFileRepresentation error: \(repError)")
          DispatchQueue.main.async {
            self.showError(message: L10n.VideoEditor.failedToLoadFile(repError.localizedDescription))
          }
          return
        }

        guard let tempURL = tempURL else {
          print("[VideoEditor Drop] No temp URL received")
          DispatchQueue.main.async {
            self.showError(message: L10n.VideoEditor.couldNotReadFile)
          }
          return
        }

        print("[VideoEditor Drop] Temp URL: \(tempURL)")

        // Copy temp file to a permanent location before it gets deleted
        let fileName = tempURL.lastPathComponent
        let destURL = FileManager.default.temporaryDirectory
          .appendingPathComponent("VideoEditor_\(UUID().uuidString)")
          .appendingPathComponent(fileName)

        do {
          try FileManager.default.createDirectory(
            at: destURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
          )
          try FileManager.default.copyItem(at: tempURL, to: destURL)
          print("[VideoEditor Drop] Copied to: \(destURL)")
          print("[VideoEditor Drop] Original URL to preserve: \(originalURL?.path ?? "nil")")

          DispatchQueue.main.async {
            self.validateAndLoad(url: destURL, originalURL: originalURL)
          }
        } catch {
          print("[VideoEditor Drop] Copy error: \(error)")
          DispatchQueue.main.async {
            self.showError(message: L10n.VideoEditor.failedToPrepareFile(error.localizedDescription))
          }
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
        // Browse uses original file directly - pass same URL as both working and original
        validateAndLoad(url: url, originalURL: url)
      }
    }
  }

  private func validateAndLoad(url: URL, originalURL: URL? = nil) {
    // Validate file exists
    guard FileManager.default.fileExists(atPath: url.path) else {
      showError(message: L10n.VideoEditor.fileNotFound)
      return
    }

    // Validate it's a video or GIF file
    guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
          type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .gif) else {
      showError(message: L10n.VideoEditor.selectValidVideoOrGIFFile)
      return
    }

    onVideoDropped(url, originalURL)
  }

  private func showError(message: String) {
    errorMessage = message
    showError = true
  }
}
