import AppKit
import UniformTypeIdentifiers

@MainActor
final class CombineImagesCoordinator {
  static let shared = CombineImagesCoordinator()

  private init() {}

  func presentPicker() {
    let panel = NSOpenPanel()
    panel.title = L10n.Combine.pickerTitle
    panel.message = L10n.Combine.pickerMessage
    panel.prompt = L10n.Combine.pickerConfirm
    panel.allowedContentTypes = [.png, .jpeg, .webP, .gif, .tiff, .heic]
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false

    guard panel.runModal() == .OK, panel.urls.count >= 2 else { return }
    AnnotateManager.shared.openCombineImages(urls: panel.urls)
  }
}

