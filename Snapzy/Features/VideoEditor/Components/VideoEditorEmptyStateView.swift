//
//  VideoEditorEmptyStateView.swift
//  Snapzy
//
//  Empty state view with drag & drop zone for video editor
//

import SwiftUI
import UniformTypeIdentifiers

/// Empty state view displayed when no video is loaded.
///
/// Monochrome and quiet: the plain window background, one dashed drop card, and the
/// app's Liquid Glass buttons. Drag-over is the only state that changes the scene.
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

      footer
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onDrop(of: [.fileURL] + supportedTypes, isTargeted: $isTargeted) { providers in
      handleDrop(providers: providers)
    }
    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isTargeted)
    .alert(L10n.VideoEditor.invalidFileTitle, isPresented: $showError) {
      Button(L10n.Common.ok, role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  // MARK: - Drop Zone

  private var dropZone: some View {
    VStack(spacing: Spacing.lg) {
      Image(systemName: "film")
        .font(.system(size: 44, weight: .light))
        .foregroundColor(isTargeted ? Color.primary.opacity(0.8) : .secondary)
        .scaleEffect(isTargeted ? 1.08 : 1)

      VStack(spacing: Spacing.xs) {
        Text(L10n.VideoEditor.dropVideoHereToEdit)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.primary)

        Text(L10n.VideoEditor.supportsVideoFormats)
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

      LiquidGlassActionButton(
        title: L10n.VideoEditor.browseFiles,
        icon: "folder",
        emphasis: .secondary,
        action: { browseForVideo() }
      )
      .keyboardShortcut(.defaultAction)
    }
    .padding(.horizontal, Spacing.xl)
    .padding(.vertical, Spacing.lg)
    .frame(width: 420)
    .background(
      Radius.rect(Radius.panel)
        .fill(Color.primary.opacity(isTargeted ? 0.05 : 0.02))
    )
    .overlay(
      Radius.rect(Radius.panel).strokeBorder(
        Color.primary.opacity(isTargeted ? 0.45 : 0.15),
        style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [6, 5])
      )
    )
    .contentShape(Radius.rect(Radius.panel))
    .onTapGesture {
      browseForVideo()
    }
    .onHover { hovering in
      if hovering {
        NSCursor.pointingHand.set()
      } else {
        NSCursor.arrow.set()
      }
    }
  }

  // MARK: - Footer

  private var footer: some View {
    HStack {
      Spacer()
      LiquidGlassActionButton(
        title: L10n.Common.cancel,
        emphasis: .secondary,
        action: { NSApp.keyWindow?.close() }
      )
      .keyboardShortcut(.cancelAction)
    }
    .padding(Spacing.md)
  }

  // MARK: - Drop Handling

  private func handleDrop(providers: [NSItemProvider]) -> Bool {
    guard let provider = providers.first else {
      DiagnosticLogger.shared.log(.warning, .editor, "Video editor drop skipped; provider missing")
      return false
    }

    DiagnosticLogger.shared.log(
      .info,
      .editor,
      "Video editor drop received",
      context: ["registeredTypeCount": "\(provider.registeredTypeIdentifiers.count)"]
    )

    // Fast path for local Finder files: reference the dropped file URL directly without
    // duplicating multi-gigabyte video files into temporary storage.
    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
        let rawDroppedURL: URL? = if let url = item as? URL {
          url
        } else if let data = item as? Data {
          URL(dataRepresentation: data, relativeTo: nil)
        } else {
          nil
        }
        let droppedURL = rawDroppedURL.map { ($0 as NSURL).filePathURL ?? $0 }

        guard let droppedURL else {
          DispatchQueue.main.async {
            showError(message: L10n.VideoEditor.couldNotReadFile)
          }
          return
        }

        DispatchQueue.main.async {
          validateAndLoad(url: droppedURL, originalURL: droppedURL)
        }
      }
      return true
    }

    // Fallback for non-fileURL providers (e.g. Photos): copy off main and clean up on window close.
    guard let videoType = supportedTypes.first(where: {
      provider.hasItemConformingToTypeIdentifier($0.identifier)
    }) else {
      DiagnosticLogger.shared.log(.warning, .editor, "Video editor drop rejected; unsupported type")
      DispatchQueue.main.async {
        showError(message: L10n.VideoEditor.unsupportedFileType)
      }
      return false
    }

    _ = provider.loadFileRepresentation(forTypeIdentifier: videoType.identifier) { tempURL, repError in
      if let repError {
        DiagnosticLogger.shared.logError(
          .editor,
          repError,
          "Video editor drop file representation failed",
          context: ["type": videoType.identifier]
        )
        DispatchQueue.main.async {
          showError(message: L10n.VideoEditor.failedToLoadFile(repError.localizedDescription))
        }
        return
      }

      guard let tempURL else {
        DiagnosticLogger.shared.log(.warning, .editor, "Video editor drop file representation missing temp URL")
        DispatchQueue.main.async {
          showError(message: L10n.VideoEditor.couldNotReadFile)
        }
        return
      }

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
        DispatchQueue.main.async {
          validateAndLoad(url: destURL, originalURL: nil)
        }
      } catch {
        try? FileManager.default.removeItem(at: destURL.deletingLastPathComponent())
        DiagnosticLogger.shared.logError(
          .editor,
          error,
          "Video editor drop working copy failed",
          context: ["fileName": tempURL.lastPathComponent]
        )
        DispatchQueue.main.async {
          showError(message: L10n.VideoEditor.failedToPrepareFile(error.localizedDescription))
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
        DiagnosticLogger.shared.log(
          .info,
          .editor,
          "Video editor browse selected file",
          context: ["fileName": url.lastPathComponent]
        )
        validateAndLoad(url: url, originalURL: url)
      } else {
        DiagnosticLogger.shared.log(.debug, .editor, "Video editor browse cancelled")
      }
    }
  }

  private func validateAndLoad(url: URL, originalURL: URL? = nil) {
    guard FileManager.default.fileExists(atPath: url.path) else {
      DiagnosticLogger.shared.log(
        .warning,
        .editor,
        "Video editor load rejected; file missing",
        context: ["fileName": url.lastPathComponent]
      )
      showError(message: L10n.VideoEditor.fileNotFound)
      return
    }

    guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
          type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .gif) else {
      DiagnosticLogger.shared.log(
        .warning,
        .editor,
        "Video editor load rejected; invalid type",
        context: ["fileName": url.lastPathComponent]
      )
      showError(message: L10n.VideoEditor.selectValidVideoOrGIFFile)
      return
    }

    DiagnosticLogger.shared.log(
      .info,
      .editor,
      "Video editor loading file",
      context: ["fileName": url.lastPathComponent, "hasOriginalURL": originalURL == nil ? "false" : "true"]
    )
    onVideoDropped(url, originalURL)
  }

  private func showError(message: String) {
    errorMessage = message
    showError = true
  }
}
