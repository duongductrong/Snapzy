//
//  CaptureToolbarModels.swift
//  Snapzy
//
//  Milestone 6 (#498): the unified capture toolbar. One shortcut → select an
//  area → a toolbar under the selection: Screenshot, Copy, Save, Upload, Pin,
//  Annotate, Text (OCR), Record, GIF, Scroll, plus any automation with the
//  "Capture toolbar" trigger. Each built-in is a small system pipeline of the
//  same automation steps; Record / GIF / Scroll start their flow on the rect.
//

import Foundation

enum CaptureToolbarBuiltin: String, Codable, CaseIterable, Identifiable, Sendable {
  case screenshot
  case copy
  case save
  case upload
  case pin
  case annotate
  case ocr
  case record
  case gif
  case scroll

  var id: String { rawValue }

  /// Single-key accelerator a fresh install uses.
  var defaultAccelerator: String? {
    switch self {
    case .screenshot: nil  // Return
    case .copy: "C"
    case .save: "S"
    case .upload: "U"
    case .pin: "P"
    case .annotate: "A"
    case .ocr: "T"
    case .record: "R"
    case .gif: "G"
    case .scroll: "L"
    }
  }

  /// Needs the selection rect rather than the captured image.
  var startsNewCapture: Bool {
    self == .record || self == .gif || self == .scroll
  }

  /// The steps a still-image built-in runs on the selection's capture.
  /// `nil` for Screenshot (the default after-capture automation) and the
  /// rect-based ones.
  var steps: [AutomationStepAction]? {
    switch self {
    case .copy: [.copyImage]
    case .save: [.saveToFolder(AutomationSaveToFolderConfig(folder: .exportDirectory)), .notify]
    case .upload: [.upload(AutomationUploadConfig()), .copyLink(AutomationLinkTemplate(style: .url)), .notify]
    case .pin: [.pin]
    case .annotate: [.openAnnotate]
    case .ocr: [.ocr(AutomationOCRConfig()), .copyText(AutomationTextTemplate()), .notify]
    case .screenshot, .record, .gif, .scroll: nil
    }
  }
}

/// A toolbar button: a built-in action or a user automation.
enum CaptureToolbarItem: Hashable, Sendable {
  case builtin(CaptureToolbarBuiltin)
  case automation(UUID)
}

extension CaptureToolbarItem: Codable {
  /// `"copy"` for built-ins, `"automation:<uuid>"` for automations.
  var token: String {
    switch self {
    case .builtin(let builtin): builtin.rawValue
    case .automation(let id): "automation:\(id.uuidString.lowercased())"
    }
  }

  init?(token: String) {
    let lowered = token.lowercased()
    if lowered.hasPrefix("automation:"), let id = UUID(uuidString: String(token.dropFirst("automation:".count))) {
      self = .automation(id)
    } else if let builtin = CaptureToolbarBuiltin(rawValue: lowered) {
      self = .builtin(builtin)
    } else {
      return nil
    }
  }

  init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    guard let item = CaptureToolbarItem(token: raw) else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown toolbar item \(raw)"))
    }
    self = item
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(token)
  }
}

struct CaptureToolbarEntry: Codable, Equatable, Hashable, Sendable {
  var item: CaptureToolbarItem
  var isVisible: Bool
  /// One letter or digit; `nil` = no accelerator.
  var accelerator: String?

  init(item: CaptureToolbarItem, isVisible: Bool = true, accelerator: String? = nil) {
    self.item = item
    self.isVisible = isVisible
    self.accelerator = Self.normalizedAccelerator(accelerator)
  }

  /// Upper-cased single letter / digit, else `nil`.
  static func normalizedAccelerator(_ raw: String?) -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespaces).uppercased(), trimmed.count == 1,
          let scalar = trimmed.unicodeScalars.first,
          CharacterSet.alphanumerics.contains(scalar), scalar.isASCII
    else { return nil }
    return trimmed
  }
}

struct CaptureToolbarConfiguration: Codable, Equatable, Sendable {
  /// Built-ins in toolbar order; automations follow (they live in `automationEntries`).
  var entries: [CaptureToolbarEntry]
  /// Order / visibility / accelerators for automation buttons, by automation id.
  var automationEntries: [CaptureToolbarEntry]
  /// Double-click inside the selection; `nil` = nothing.
  var doubleClickAction: CaptureToolbarItem?
  /// The area shortcut (⇧⌘4 by default) also ends in the toolbar.
  var showsForAreaShortcut: Bool

  static let `default` = CaptureToolbarConfiguration(
    entries: CaptureToolbarBuiltin.allCases.map {
      CaptureToolbarEntry(item: .builtin($0), accelerator: $0.defaultAccelerator)
    },
    automationEntries: [],
    doubleClickAction: .builtin(.copy),
    showsForAreaShortcut: false
  )

  private enum CodingKeys: String, CodingKey {
    case entries, automationEntries, doubleClickAction, showsForAreaShortcut
  }

  init(
    entries: [CaptureToolbarEntry],
    automationEntries: [CaptureToolbarEntry],
    doubleClickAction: CaptureToolbarItem?,
    showsForAreaShortcut: Bool
  ) {
    self.entries = entries
    self.automationEntries = automationEntries
    self.doubleClickAction = doubleClickAction
    self.showsForAreaShortcut = showsForAreaShortcut
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let fallback = Self.default
    entries = (try? container.decode([CaptureToolbarEntry].self, forKey: .entries)) ?? fallback.entries
    automationEntries = (try? container.decode([CaptureToolbarEntry].self, forKey: .automationEntries)) ?? []
    doubleClickAction = try? container.decodeIfPresent(CaptureToolbarItem.self, forKey: .doubleClickAction)
    showsForAreaShortcut = (try? container.decode(Bool.self, forKey: .showsForAreaShortcut)) ?? false
    self = normalized()
  }

  /// Every built-in exactly once (new ones appended visible), automation
  /// entries without duplicates, accelerators unique (later duplicates cleared).
  func normalized() -> CaptureToolbarConfiguration {
    var copy = self
    var seenBuiltins = Set<CaptureToolbarBuiltin>()
    copy.entries = entries.filter { entry in
      guard case .builtin(let builtin) = entry.item else { return false }
      return seenBuiltins.insert(builtin).inserted
    }
    for builtin in CaptureToolbarBuiltin.allCases where !seenBuiltins.contains(builtin) {
      copy.entries.append(CaptureToolbarEntry(item: .builtin(builtin), accelerator: builtin.defaultAccelerator))
    }
    var seenAutomations = Set<UUID>()
    copy.automationEntries = automationEntries.filter { entry in
      guard case .automation(let id) = entry.item else { return false }
      return seenAutomations.insert(id).inserted
    }
    var usedKeys = Set<String>()
    func dedupe(_ list: inout [CaptureToolbarEntry]) {
      for index in list.indices {
        guard let key = list[index].accelerator else { continue }
        if !usedKeys.insert(key).inserted { list[index].accelerator = nil }
      }
    }
    dedupe(&copy.entries)
    dedupe(&copy.automationEntries)
    return copy
  }

  /// The entry using `accelerator`, if any (for the settings duplicate warning).
  func owner(of accelerator: String) -> CaptureToolbarItem? {
    (entries + automationEntries).first { $0.accelerator == accelerator }?.item
  }

  /// Buttons shown, in order: visible built-ins, then visible automations
  /// offered to the toolbar (`available`, in the user's list order unless
  /// reordered here). Automations without an entry get the next free digit.
  func visibleEntries(available automationIDs: [UUID]) -> [CaptureToolbarEntry] {
    let builtins = entries.filter(\.isVisible)
    let known = Dictionary(automationEntries.compactMap { entry -> (UUID, CaptureToolbarEntry)? in
      guard case .automation(let id) = entry.item else { return nil }
      return (id, entry)
    }, uniquingKeysWith: { first, _ in first })
    let order = automationEntries.compactMap { entry -> UUID? in
      guard case .automation(let id) = entry.item, automationIDs.contains(id) else { return nil }
      return id
    } + automationIDs.filter { known[$0] == nil }

    var used = Set((entries + automationEntries).compactMap(\.accelerator))
    var digits = (1...9).map(String.init).makeIterator()
    var automations: [CaptureToolbarEntry] = []
    for id in order {
      if let entry = known[id] {
        if entry.isVisible { automations.append(entry) }
        continue
      }
      var accelerator: String?
      while let digit = digits.next() {
        if used.insert(digit).inserted { accelerator = digit; break }
      }
      automations.append(CaptureToolbarEntry(item: .automation(id), accelerator: accelerator))
    }
    return builtins + automations
  }
}

// MARK: - TOML `[capture.toolbar]`

extension CaptureToolbarConfiguration {
  /// `"copy:C"` (key) or `"pin"` (no key), in toolbar order; automations as `"automation:<id>:1"`.
  var tomlButtons: [String] {
    (entries + automationEntries).map { entry in
      entry.accelerator.map { "\(entry.item.token):\($0)" } ?? entry.item.token
    }
  }

  /// Tokens of hidden buttons.
  var tomlHidden: [String] {
    (entries + automationEntries).filter { !$0.isVisible }.map(\.item.token)
  }

  /// Rebuilds a configuration from the TOML keys; unknown buttons are reported.
  static func fromTOML(
    buttons: [String]?,
    hidden: [String]?,
    doubleClick: String?,
    showsForArea: Bool?,
    base: CaptureToolbarConfiguration,
    warnings: inout [String]
  ) -> CaptureToolbarConfiguration {
    var copy = base
    if let buttons {
      let hiddenSet = Set((hidden ?? []).map { $0.lowercased() })
      var builtins: [CaptureToolbarEntry] = []
      var automations: [CaptureToolbarEntry] = []
      for raw in buttons {
        var token = raw.trimmingCharacters(in: .whitespaces)
        var key: String?
        if let colon = token.lastIndex(of: ":"), token.distance(from: colon, to: token.endIndex) == 2 {
          key = String(token[token.index(after: colon)...])
          token = String(token[..<colon])
        }
        guard let item = CaptureToolbarItem(token: token) else {
          warnings.append("capture.toolbar.buttons: unknown button \"\(raw)\" ignored")
          continue
        }
        let entry = CaptureToolbarEntry(item: item, isVisible: !hiddenSet.contains(item.token), accelerator: key)
        if case .automation = item { automations.append(entry) } else { builtins.append(entry) }
      }
      copy.entries = builtins
      copy.automationEntries = automations
    }
    if let doubleClick {
      if doubleClick.lowercased() == "none" {
        copy.doubleClickAction = nil
      } else if let item = CaptureToolbarItem(token: doubleClick) {
        copy.doubleClickAction = item
      } else {
        warnings.append("capture.toolbar.double_click: unknown action \"\(doubleClick)\"; kept the current one")
      }
    }
    if let showsForArea { copy.showsForAreaShortcut = showsForArea }
    return copy.normalized()
  }
}
