//
//  CaptureOutputNaming.swift
//  Snapzy
//
//  Shared output filename generation for screenshots and recordings.
//

import AppKit
import Foundation

/// Contextual metadata about the capture source, used for template token replacement.
struct CaptureContext: Equatable {
  let appName: String?
  let windowTitle: String?

  static let empty = CaptureContext(appName: nil, windowTitle: nil)

  /// Max characters for windowTitle in filenames to prevent excessively long paths.
  private static let maxTitleLength = 80

  var sanitizedWindowTitle: String? {
    guard let title = windowTitle, !title.isEmpty else { return nil }
    if title.count <= Self.maxTitleLength { return title }
    return String(title.prefix(Self.maxTitleLength))
  }

  /// Creates a CaptureContext from a process ID, resolving app name from NSRunningApplication.
  static func fromPID(_ pid: Int32?, windowTitle: String? = nil) -> CaptureContext {
    guard let pid else { return CaptureContext(appName: nil, windowTitle: windowTitle) }
    let app = NSRunningApplication(processIdentifier: pid)
    let name = app?.localizedName
      ?? app?.bundleIdentifier.flatMap { $0.split(separator: ".").last.map(String.init) }
    return CaptureContext(appName: name, windowTitle: windowTitle)
  }

  /// Creates a CaptureContext from the frontmost application (for fullscreen/area captures).
  static func fromFrontmostApp() -> CaptureContext {
    guard let app = NSWorkspace.shared.frontmostApplication else { return .empty }
    let ownBundleID = Bundle.main.bundleIdentifier
    // Don't resolve Snapzy itself as the app name
    if app.bundleIdentifier == ownBundleID { return .empty }
    return CaptureContext(
      appName: app.localizedName,
      windowTitle: nil
    )
  }
}

enum CaptureOutputKind {
  case screenshot
  case recording

  var defaultTemplate: String {
    switch self {
    case .screenshot:
      return "Snapzy_{datetime}_{ms}"
    case .recording:
      return "Snapzy_Recording_{datetime}"
    }
  }

  var typeTokenValue: String {
    switch self {
    case .screenshot:
      return "screenshot"
    case .recording:
      return "recording"
    }
  }

  var templatePreferenceKey: String {
    switch self {
    case .screenshot:
      return PreferencesKeys.screenshotFileNameTemplate
    case .recording:
      return PreferencesKeys.recordingFileNameTemplate
    }
  }
}

enum CaptureOutputNaming {
  private static let invalidPathComponentCharacters = CharacterSet(charactersIn: "\\:?%*|\"<>\n\r\t")
  private static let knownExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "mov", "mp4", "gif"]

  static func resolveBaseName(
    customName: String?,
    kind: CaptureOutputKind,
    date: Date = Date(),
    context: CaptureContext = .empty,
    defaults: UserDefaults = .standard
  ) -> String {
    if let customName {
      let sanitizedCustomName = sanitizeBaseName(customName)
      if !sanitizedCustomName.isEmpty {
        return sanitizedCustomName
      }
    }

    let template = resolvedTemplate(for: kind, defaults: defaults)
    return resolveTemplateBaseName(template, kind: kind, date: date, context: context)
  }

  static func resolvedTemplate(for kind: CaptureOutputKind, defaults: UserDefaults = .standard) -> String {
    guard let raw = defaults.string(forKey: kind.templatePreferenceKey) else {
      return kind.defaultTemplate
    }

    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? kind.defaultTemplate : trimmed
  }

  static func resolveTemplateBaseName(
    _ template: String,
    kind: CaptureOutputKind,
    date: Date = Date(),
    context: CaptureContext = .empty
  ) -> String {
    let parsed = parseTemplate(template, kind: kind, date: date, context: context)
    let sanitizedParsed = sanitizeBaseName(parsed)
    if !sanitizedParsed.isEmpty {
      return sanitizedParsed
    }

    return fallbackName(for: kind, date: date)
  }

  static func makeUniqueFileURL(in directory: URL, baseName: String, fileExtension: String) -> URL {
    var candidate = directory.appendingPathComponent("\(baseName).\(fileExtension)")
    var suffix = 2

    while FileManager.default.fileExists(atPath: candidate.path) {
      candidate = directory.appendingPathComponent("\(baseName)_\(suffix).\(fileExtension)")
      suffix += 1
    }

    return candidate
  }

  private static func parseTemplate(
    _ template: String,
    kind: CaptureOutputKind,
    date: Date,
    context: CaptureContext
  ) -> String {
    var resolved = template
    let replacements: [String: String] = [
      "{type}": kind.typeTokenValue,
      "{year}": format(date, style: "yyyy"),
      "{yearShort}": format(date, style: "yy"),
      "{year_short}": format(date, style: "yy"),
      "{yy}": format(date, style: "yy"),
      "{month}": format(date, style: "MM"),
      "{monthName}": format(date, style: "MMMM"),
      "{monthShort}": format(date, style: "MMM"),
      "{month_name}": format(date, style: "MMMM"),
      "{month_short}": format(date, style: "MMM"),
      "{day}": format(date, style: "dd"),
      "{date}": format(date, style: "yyyy-MM-dd"),
      "{time}": format(date, style: "HH-mm-ss"),
      "{datetime}": format(date, style: "yyyy-MM-dd_HH-mm-ss"),
      "{ms}": format(date, style: "SSS"),
      "{timestamp}": String(Int(date.timeIntervalSince1970)),
      "{appName}": context.appName ?? "",
      "{app_name}": context.appName ?? "",
    ]

    for (token, value) in replacements {
      resolved = resolved.replacingOccurrences(of: token, with: value)
    }

    return resolved
  }

  private static func sanitizeBaseName(_ value: String) -> String {
    let components = value
      .split(separator: "/", omittingEmptySubsequences: true)
      .map { sanitizePathComponent(String($0)) }
      .filter { !$0.isEmpty }

    guard !components.isEmpty else { return "" }

    var sanitizedComponents = components
    sanitizedComponents[sanitizedComponents.count - 1] = stripKnownExtension(
      from: sanitizedComponents[sanitizedComponents.count - 1]
    )
    sanitizedComponents = sanitizedComponents.filter { !$0.isEmpty }

    return sanitizedComponents.joined(separator: "/")
  }

  private static func sanitizePathComponent(_ value: String) -> String {
    var sanitized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sanitized.isEmpty else { return "" }

    sanitized = sanitized.components(separatedBy: invalidPathComponentCharacters).joined(separator: "_")
    sanitized = sanitized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    sanitized = sanitized.replacingOccurrences(of: "_{2,}", with: "_", options: .regularExpression)
    sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    return sanitized
  }

  private static func stripKnownExtension(from component: String) -> String {
    var sanitized = component
    let pathExtension = (sanitized as NSString).pathExtension.lowercased()
    if knownExtensions.contains(pathExtension) {
      sanitized = (sanitized as NSString).deletingPathExtension
    }

    sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    return sanitized
  }

  private static func format(_ date: Date, style: String) -> String {
    let formatter = DateFormatter()
    // Pin only the calendar so date tokens always resolve to Gregorian values
    // regardless of the user's system calendar. Without this, users on a
    // Buddhist calendar (e.g. Thai `th_TH`) get the Buddhist year (e.g. 2569)
    // instead of the Gregorian year (e.g. 2026) in filenames. The locale is
    // left alone so `{monthName}`/`{monthShort}` stay localized.
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = style
    return formatter.string(from: date)
  }

  private static func fallbackName(for kind: CaptureOutputKind, date: Date) -> String {
    switch kind {
    case .screenshot:
      return "Snapzy_\(format(date, style: "yyyy-MM-dd_HH-mm-ss-SSS"))"
    case .recording:
      return "Snapzy_Recording_\(format(date, style: "yyyy-MM-dd_HH-mm-ss"))"
    }
  }
}
