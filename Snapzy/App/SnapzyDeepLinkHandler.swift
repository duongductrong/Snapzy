//
//  SnapzyDeepLinkHandler.swift
//  Snapzy
//
//  Handles snapzy:// automation URLs for external launchers and workflows.
//

import AppKit
import Foundation

@MainActor
struct SnapzyDeepLinkHandler {
  private let screenCaptureViewModel: ScreenCaptureViewModel

  init(screenCaptureViewModel: ScreenCaptureViewModel) {
    self.screenCaptureViewModel = screenCaptureViewModel
  }

  func handle(_ url: URL) {
    guard UserDefaults.standard.object(forKey: PreferencesKeys.urlSchemeEnabled) as? Bool ?? true else {
      DiagnosticLogger.shared.log(
        .info,
        .action,
        "Ignored deeplink because URL scheme is disabled in preferences",
        context: ["url": url.absoluteString]
      )
      return
    }

    guard let action = SnapzyDeepLinkAction(url: url) else {
      DiagnosticLogger.shared.log(
        .warning,
        .action,
        "Ignored unsupported deeplink",
        context: [
          "scheme": url.scheme ?? "",
          "host": url.host ?? "",
          "path": url.path,
        ]
      )
      return
    }

    DiagnosticLogger.shared.log(
      .info,
      .action,
      "Handling deeplink",
      context: ["action": action.logName]
    )

    switch action {
    case .captureFullscreen:
      screenCaptureViewModel.captureFullscreen()
    case .captureArea:
      screenCaptureViewModel.captureArea()
    case .captureApplication:
      screenCaptureViewModel.captureApplication()
    case .captureActiveWindow:
      screenCaptureViewModel.captureActiveWindow()
    case .captureAreaAnnotate:
      screenCaptureViewModel.captureAreaAnnotate()
    case .captureScrolling:
      screenCaptureViewModel.captureScrolling()
    case .captureOCR:
      screenCaptureViewModel.captureOCR()
    case .captureSmartElement:
      SmartElementCaptureController.shared.startCapture()
    case .captureObjectCutout:
      screenCaptureViewModel.captureObjectCutout()
    case .recordScreen:
      screenCaptureViewModel.startRecordingFlow()
    case .recordApplication:
      screenCaptureViewModel.startApplicationRecordingFlow()
    case .openAnnotate:
      AnnotateManager.shared.openEmptyAnnotation()
      NSApp.activate(ignoringOtherApps: true)
    case .openCombine(let fileURLs):
      if fileURLs.count >= 2 {
        AnnotateManager.shared.openCombineImages(urls: fileURLs)
      } else {
        CombineImagesCoordinator.shared.presentPicker()
      }
      NSApp.activate(ignoringOtherApps: true)
    case .openVideoEditor:
      VideoEditorManager.shared.openEmptyEditor()
      NSApp.activate(ignoringOtherApps: true)
    case .openCloudUploads:
      if CloudUploadHistoryWindowController.shared.toggleWindow() {
        NSApp.activate(ignoringOtherApps: true)
      }
    case .openHistory:
      HistoryFloatingManager.shared.toggle()
    case .showShortcuts:
      ShortcutOverlayManager.shared.toggle()
    case .openSettings(let tab):
      AppStatusBarController.shared.openPreferencesWindow(tab: tab)
    }
  }
}

enum SnapzyDeepLinkAction: Equatable {
  case captureFullscreen
  case captureArea
  case captureApplication
  case captureActiveWindow
  case captureAreaAnnotate
  case captureScrolling
  case captureOCR
  case captureSmartElement
  case captureObjectCutout
  case recordScreen
  case recordApplication
  case openAnnotate
  case openCombine([URL])
  case openVideoEditor
  case openCloudUploads
  case openHistory
  case showShortcuts
  case openSettings(PreferencesTab?)

  init?(url: URL) {
    guard url.scheme?.lowercased() == "snapzy" else { return nil }

    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let host = url.host?.lowercased()
    let pathParts = url.path.split(separator: "/").map { $0.lowercased() }
    let parts = ([host] + pathParts).compactMap { $0 }
    let command = parts.joined(separator: "/")

    switch command {
    case "capture/fullscreen", "capture-screen", "capture-fullscreen", "fullscreen", "screenshot/fullscreen":
      self = .captureFullscreen
    case "capture/area", "capture-area", "area", "screenshot/area":
      self = .captureArea
    case "capture/application", "capture/window", "application-capture", "window-capture", "screenshot/window":
      self = .captureApplication
    case "capture/active-window", "capture/focused-window", "active-window-capture",
      "active-window", "screenshot/active-window":
      self = .captureActiveWindow
    case "capture/area-annotate", "capture-area-annotate", "area-annotate", "screenshot/area-annotate":
      self = .captureAreaAnnotate
    case "capture/scrolling", "scrolling-capture", "capture-scrolling", "scrolling", "screenshot/scrolling":
      self = .captureScrolling
    case "capture/ocr", "capture/text", "capture-text", "ocr", "text":
      self = .captureOCR
    case "capture/smart-element", "smart-element", "capture-smart-element", "smart":
      self = .captureSmartElement
    case "capture/object-cutout", "object-cutout", "capture-object-cutout", "cutout":
      self = .captureObjectCutout
    case "record/screen", "record-screen", "screen-recording", "recording", "record":
      self = .recordScreen
    case "record/application", "record/window", "application-recording", "window-recording", "recording/window":
      self = .recordApplication
    case "open/annotate", "annotate", "open-annotate":
      self = .openAnnotate
    case "open/combine", "combine", "combine-images", "open-combine":
      self = .openCombine(Self.combineFileURLs(from: components))
    case "open/video-editor", "video-editor", "edit-video", "open-video-editor":
      self = .openVideoEditor
    case "open/cloud-uploads", "cloud-uploads", "uploads", "open-uploads":
      self = .openCloudUploads
    case "open/history", "history", "capture-history":
      self = .openHistory
    case "show/shortcuts", "shortcuts", "keyboard-shortcuts", "show-shortcuts":
      self = .showShortcuts
    case "settings", "preferences":
      self = .openSettings(Self.preferencesTab(from: components, pathParts: pathParts))
    case let value where value.hasPrefix("settings/"):
      self = .openSettings(Self.preferencesTab(from: components, pathParts: pathParts))
    case let value where value.hasPrefix("preferences/"):
      self = .openSettings(Self.preferencesTab(from: components, pathParts: pathParts))
    default:
      return nil
    }
  }

  var logName: String {
    switch self {
    case .captureFullscreen: return "captureFullscreen"
    case .captureArea: return "captureArea"
    case .captureApplication: return "captureApplication"
    case .captureActiveWindow: return "captureActiveWindow"
    case .captureAreaAnnotate: return "captureAreaAnnotate"
    case .captureScrolling: return "captureScrolling"
    case .captureOCR: return "captureOCR"
    case .captureSmartElement: return "captureSmartElement"
    case .captureObjectCutout: return "captureObjectCutout"
    case .recordScreen: return "recordScreen"
    case .recordApplication: return "recordApplication"
    case .openAnnotate: return "openAnnotate"
    case .openCombine(let fileURLs): return "openCombine(\(fileURLs.count))"
    case .openVideoEditor: return "openVideoEditor"
    case .openCloudUploads: return "openCloudUploads"
    case .openHistory: return "openHistory"
    case .showShortcuts: return "showShortcuts"
    case .openSettings(let tab): return "openSettings(\(String(describing: tab)))"
    }
  }

  private static func combineFileURLs(from components: URLComponents?) -> [URL] {
    components?.queryItems?
      .filter { $0.name.lowercased() == "file" }
      .compactMap { item in
        guard let value = item.value, !value.isEmpty else { return nil }
        if let url = URL(string: value), url.isFileURL {
          return url.standardizedFileURL
        }
        return URL(fileURLWithPath: (value as NSString).expandingTildeInPath).standardizedFileURL
      } ?? []
  }

  private static func preferencesTab(from components: URLComponents?, pathParts: [String]) -> PreferencesTab? {
    let queryTab = components?.queryItems?
      .first(where: { $0.name.lowercased() == "tab" })?
      .value?
      .lowercased()

    let pathTab = pathParts.first
    return preferencesTab(named: queryTab ?? pathTab)
  }

  private static func preferencesTab(named name: String?) -> PreferencesTab? {
    switch name {
    case "general":
      return .general
    case "capture", "screenshots", "screenshot":
      return .capture
    case "annotate", "annotation", "annotations":
      return .annotate
    case "quick-access", "quickaccess":
      return .quickAccess
    case "history":
      return .history
    case "shortcuts", "keyboard-shortcuts":
      return .shortcuts
    case "permissions", "privacy":
      return .permissions
    case "cloud", "uploads":
      return .cloud
    case "advanced", "configuration", "config", "toml":
      return .advanced
    case "about":
      return .about
    default:
      return nil
    }
  }
}
