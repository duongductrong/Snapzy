//
//  ClipboardImageContentOption.swift
//  Snapzy
//
//  What an image copy puts on the clipboard: image data plus a file
//  reference (default), or image data only.
//

import Foundation

/// Controls whether image copies include a file reference next to the pixel data.
///
/// `imageAndFile` keeps the file URL so sandboxed receivers get a sandbox extension
/// and Finder/Preview paste a real file. `imageOnly` drops it for receivers that
/// mishandle file references, e.g. Citrix/RDP sessions forwarding the file so
/// Outlook adds an attachment instead of an inline image (issue #699).
enum ClipboardImageContentOption: String, CaseIterable, Identifiable {
  case imageAndFile = "image_and_file"
  case imageOnly = "image_only"

  static let defaultValue: ClipboardImageContentOption = .imageAndFile

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .imageAndFile: return L10n.PreferencesCapture.clipboardContentImageAndFile
    case .imageOnly: return L10n.PreferencesCapture.clipboardContentImageOnly
    }
  }

  /// Unset or unknown stored values fall back to the default.
  nonisolated static func resolve(_ rawValue: String?) -> ClipboardImageContentOption {
    rawValue.flatMap(ClipboardImageContentOption.init(rawValue:)) ?? defaultValue
  }

  nonisolated static func current(defaults: UserDefaults = .standard) -> ClipboardImageContentOption {
    resolve(defaults.string(forKey: PreferencesKeys.clipboardImageContent))
  }
}
