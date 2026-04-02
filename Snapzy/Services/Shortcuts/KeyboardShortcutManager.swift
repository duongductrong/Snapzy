//
//  KeyboardShortcutManager.swift
//  Snapzy
//
//  Manages global keyboard shortcuts for screen capture
//

import AppKit
import Carbon.HIToolbox

/// Represents a keyboard shortcut configuration
struct ShortcutConfig: Equatable, Codable {
  let keyCode: UInt32
  let modifiers: UInt32

  /// Memberwise initializer
  init(keyCode: UInt32, modifiers: UInt32) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  /// Cmd + Shift + 3
  static let defaultFullscreen = ShortcutConfig(
    keyCode: UInt32(kVK_ANSI_3),
    modifiers: UInt32(cmdKey | shiftKey)
  )

  /// Cmd + Shift + 4
  static let defaultArea = ShortcutConfig(
    keyCode: UInt32(kVK_ANSI_4),
    modifiers: UInt32(cmdKey | shiftKey)
  )

  /// Cmd + Shift + 5
  static let defaultRecording = ShortcutConfig(
    keyCode: UInt32(kVK_ANSI_5),
    modifiers: UInt32(cmdKey | shiftKey)
  )

  /// Cmd + Shift + 2
  static let defaultOCR = ShortcutConfig(
    keyCode: UInt32(kVK_ANSI_2),
    modifiers: UInt32(cmdKey | shiftKey)
  )

  /// Cmd + Shift + 1
  static let defaultObjectCutout = ShortcutConfig(
    keyCode: UInt32(kVK_ANSI_1),
    modifiers: UInt32(cmdKey | shiftKey)
  )

  /// Cmd + Shift + A
  static let defaultAnnotate = ShortcutConfig(
    keyCode: UInt32(kVK_ANSI_A),
    modifiers: UInt32(cmdKey | shiftKey)
  )

  /// Cmd + Shift + E
  static let defaultVideoEditor = ShortcutConfig(
    keyCode: UInt32(kVK_ANSI_E),
    modifiers: UInt32(cmdKey | shiftKey)
  )

  /// Cmd + Shift + L
  static let defaultCloudUploads = ShortcutConfig(
    keyCode: UInt32(kVK_ANSI_L),
    modifiers: UInt32(cmdKey | shiftKey)
  )

  var displayString: String {
    var parts: [String] = []

    if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
    if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
    if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
    if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }

    let keyChar = Self.keyCodeToString(keyCode)

    parts.append(keyChar)
    return parts.joined(separator: " ")
  }

  /// Individual key parts for keycap-style rendering
  var displayParts: [String] {
    var parts: [String] = []
    if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
    if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
    if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
    if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
    parts.append(Self.keyCodeToString(keyCode))
    return parts
  }

  /// Initialize from NSEvent for shortcut recording
  init?(from event: NSEvent) {
    guard event.type == .keyDown else { return nil }

    // Convert Cocoa modifiers to Carbon modifiers
    var carbonModifiers: UInt32 = 0
    if event.modifierFlags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
    if event.modifierFlags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
    if event.modifierFlags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
    if event.modifierFlags.contains(.control) { carbonModifiers |= UInt32(controlKey) }

    // Require at least one modifier
    guard carbonModifiers != 0 else { return nil }

    self.keyCode = UInt32(event.keyCode)
    self.modifiers = carbonModifiers
  }

  /// Map key code to display character
  static func keyCodeToString(_ keyCode: UInt32) -> String {
    switch Int(keyCode) {
    case kVK_ANSI_0: return "0"
    case kVK_ANSI_1: return "1"
    case kVK_ANSI_2: return "2"
    case kVK_ANSI_3: return "3"
    case kVK_ANSI_4: return "4"
    case kVK_ANSI_5: return "5"
    case kVK_ANSI_6: return "6"
    case kVK_ANSI_7: return "7"
    case kVK_ANSI_8: return "8"
    case kVK_ANSI_9: return "9"
    case kVK_ANSI_A: return "A"
    case kVK_ANSI_B: return "B"
    case kVK_ANSI_C: return "C"
    case kVK_ANSI_D: return "D"
    case kVK_ANSI_E: return "E"
    case kVK_ANSI_F: return "F"
    case kVK_ANSI_G: return "G"
    case kVK_ANSI_H: return "H"
    case kVK_ANSI_I: return "I"
    case kVK_ANSI_J: return "J"
    case kVK_ANSI_K: return "K"
    case kVK_ANSI_L: return "L"
    case kVK_ANSI_M: return "M"
    case kVK_ANSI_N: return "N"
    case kVK_ANSI_O: return "O"
    case kVK_ANSI_P: return "P"
    case kVK_ANSI_Q: return "Q"
    case kVK_ANSI_R: return "R"
    case kVK_ANSI_S: return "S"
    case kVK_ANSI_T: return "T"
    case kVK_ANSI_U: return "U"
    case kVK_ANSI_V: return "V"
    case kVK_ANSI_W: return "W"
    case kVK_ANSI_X: return "X"
    case kVK_ANSI_Y: return "Y"
    case kVK_ANSI_Z: return "Z"
    case kVK_F1: return "F1"
    case kVK_F2: return "F2"
    case kVK_F3: return "F3"
    case kVK_F4: return "F4"
    case kVK_F5: return "F5"
    case kVK_F6: return "F6"
    case kVK_F7: return "F7"
    case kVK_F8: return "F8"
    case kVK_F9: return "F9"
    case kVK_F10: return "F10"
    case kVK_F11: return "F11"
    case kVK_F12: return "F12"
    case kVK_Space: return "Space"
    case kVK_Return: return "↩"
    case kVK_Tab: return "⇥"
    case kVK_Delete: return "⌫"
    case kVK_Escape: return "⎋"
    case kVK_LeftArrow: return "←"
    case kVK_RightArrow: return "→"
    case kVK_UpArrow: return "↑"
    case kVK_DownArrow: return "↓"
    // Punctuation & symbol keys
    case kVK_ANSI_Semicolon: return ";"
    case kVK_ANSI_Quote: return "'"
    case kVK_ANSI_Comma: return ","
    case kVK_ANSI_Period: return "."
    case kVK_ANSI_Slash: return "/"
    case kVK_ANSI_Backslash: return "\\"
    case kVK_ANSI_LeftBracket: return "["
    case kVK_ANSI_RightBracket: return "]"
    case kVK_ANSI_Minus: return "-"
    case kVK_ANSI_Equal: return "="
    case kVK_ANSI_Grave: return "`"
    // Keypad keys
    case kVK_ANSI_KeypadDecimal: return "."
    case kVK_ANSI_KeypadMultiply: return "*"
    case kVK_ANSI_KeypadPlus: return "+"
    case kVK_ANSI_KeypadDivide: return "/"
    case kVK_ANSI_KeypadMinus: return "-"
    case kVK_ANSI_KeypadEquals: return "="
    case kVK_ANSI_KeypadEnter: return "↩"
    case kVK_ANSI_Keypad0: return "0"
    case kVK_ANSI_Keypad1: return "1"
    case kVK_ANSI_Keypad2: return "2"
    case kVK_ANSI_Keypad3: return "3"
    case kVK_ANSI_Keypad4: return "4"
    case kVK_ANSI_Keypad5: return "5"
    case kVK_ANSI_Keypad6: return "6"
    case kVK_ANSI_Keypad7: return "7"
    case kVK_ANSI_Keypad8: return "8"
    case kVK_ANSI_Keypad9: return "9"
    // Navigation keys
    case kVK_ForwardDelete: return "⌦"
    case kVK_Home: return "↖"
    case kVK_End: return "↘"
    case kVK_PageUp: return "⇞"
    case kVK_PageDown: return "⇟"
    default: return "?"
    }
  }
}

enum GlobalShortcutKind: String, CaseIterable, Codable {
  case fullscreen
  case area
  case recording
  case annotate
  case videoEditor
  case cloudUploads
  case ocr
  case objectCutout

  var isSystemConflictRelevant: Bool {
    switch self {
    case .fullscreen, .area, .recording:
      return true
    default:
      return false
    }
  }
}

/// Shortcut action types
enum ShortcutAction {
  case captureFullscreen
  case captureArea
  case captureOCR
  case captureObjectCutout
  case recordVideo
  case openAnnotate
  case openVideoEditor
  case openCloudUploads
}

/// Protocol for handling shortcut events
protocol KeyboardShortcutDelegate: AnyObject {
  func shortcutTriggered(_ action: ShortcutAction)
}

/// Manager for registering and handling global keyboard shortcuts
@MainActor
final class KeyboardShortcutManager {

  static let shared = KeyboardShortcutManager()

  weak var delegate: KeyboardShortcutDelegate?

  private(set) var fullscreenShortcut: ShortcutConfig
  private(set) var areaShortcut: ShortcutConfig
  private(set) var recordingShortcut: ShortcutConfig
  private(set) var annotateShortcut: ShortcutConfig
  private(set) var videoEditorShortcut: ShortcutConfig
  private(set) var cloudUploadsShortcut: ShortcutConfig
  private(set) var ocrShortcut: ShortcutConfig
  private(set) var objectCutoutShortcut: ShortcutConfig
  private(set) var isEnabled: Bool = false
  private var disabledShortcuts: Set<GlobalShortcutKind> = []
  private var temporarySuspensionCount: Int = 0
  private var areShortcutsRegistered: Bool = false

  private var fullscreenHotkeyRef: EventHotKeyRef?
  private var areaHotkeyRef: EventHotKeyRef?
  private var recordingHotkeyRef: EventHotKeyRef?
  private var annotateHotkeyRef: EventHotKeyRef?
  private var videoEditorHotkeyRef: EventHotKeyRef?
  private var cloudUploadsHotkeyRef: EventHotKeyRef?
  private var ocrHotkeyRef: EventHotKeyRef?
  private var objectCutoutHotkeyRef: EventHotKeyRef?

  // Hotkey IDs
  private let fullscreenHotkeyID = EventHotKeyID(signature: OSType(0x5A53_4631), id: 1)  // "ZSF1"
  private let areaHotkeyID = EventHotKeyID(signature: OSType(0x5A53_4632), id: 2)  // "ZSF2"
  private let recordingHotkeyID = EventHotKeyID(signature: OSType(0x5A53_4633), id: 3)  // "ZSF3"
  private let annotateHotkeyID = EventHotKeyID(signature: OSType(0x5A53_4634), id: 4)  // "ZSF4"
  private let videoEditorHotkeyID = EventHotKeyID(signature: OSType(0x5A53_4635), id: 5)  // "ZSF5"
  private let ocrHotkeyID = EventHotKeyID(signature: OSType(0x5A53_4636), id: 6)  // "ZSF6"
  private let cloudUploadsHotkeyID = EventHotKeyID(signature: OSType(0x5A53_4637), id: 7)  // "ZSF7"
  private let objectCutoutHotkeyID = EventHotKeyID(signature: OSType(0x5A53_4638), id: 8)  // "ZSF8"

  private var eventHandler: EventHandlerRef?

  // UserDefaults keys
  private let fullscreenShortcutKey = "fullscreenShortcut"
  private let areaShortcutKey = "areaShortcut"
  private let recordingShortcutKey = "recordingShortcut"
  private let annotateShortcutKey = "annotateShortcut"
  private let videoEditorShortcutKey = "videoEditorShortcut"
  private let cloudUploadsShortcutKey = "cloudUploadsShortcut"
  private let ocrShortcutKey = "ocrShortcut"
  private let objectCutoutShortcutKey = "objectCutoutShortcut"
  private let shortcutsEnabledKey = "shortcutsEnabled"
  private let disabledShortcutsKey = PreferencesKeys.disabledGlobalShortcuts

  private init() {
    fullscreenShortcut = .defaultFullscreen
    areaShortcut = .defaultArea
    recordingShortcut = .defaultRecording
    annotateShortcut = .defaultAnnotate
    videoEditorShortcut = .defaultVideoEditor
    cloudUploadsShortcut = .defaultCloudUploads
    ocrShortcut = .defaultOCR
    objectCutoutShortcut = .defaultObjectCutout
    loadShortcuts()
    loadDisabledShortcuts()
    setupEventHandler()

    // Auto-enable if previously enabled
    if UserDefaults.standard.bool(forKey: shortcutsEnabledKey) {
      enable()
    }
  }

  // MARK: - Public API

  /// Enable global shortcuts
  func enable() {
    guard !isEnabled else { return }
    isEnabled = true
    UserDefaults.standard.set(true, forKey: shortcutsEnabledKey)
    refreshShortcutRegistration()
  }

  /// Disable global shortcuts
  func disable() {
    guard isEnabled else { return }
    isEnabled = false
    UserDefaults.standard.set(false, forKey: shortcutsEnabledKey)
    refreshShortcutRegistration()
  }

  /// Temporarily suspend registered hotkeys without mutating the persisted enabled setting.
  func beginTemporaryShortcutSuppression() {
    temporarySuspensionCount += 1
    refreshShortcutRegistration()
  }

  /// Resume registered hotkeys once all temporary suppression requests are released.
  func endTemporaryShortcutSuppression() {
    guard temporarySuspensionCount > 0 else { return }
    temporarySuspensionCount -= 1
    refreshShortcutRegistration()
  }

  var isTemporarilySuspended: Bool {
    temporarySuspensionCount > 0
  }

  private var shouldRegisterShortcuts: Bool {
    isEnabled && !isTemporarilySuspended
  }

  private func refreshShortcutRegistration() {
    if shouldRegisterShortcuts {
      registerShortcuts()
    } else {
      unregisterAllShortcuts()
    }
  }

  func shortcut(for kind: GlobalShortcutKind) -> ShortcutConfig {
    switch kind {
    case .fullscreen: return fullscreenShortcut
    case .area: return areaShortcut
    case .recording: return recordingShortcut
    case .annotate: return annotateShortcut
    case .videoEditor: return videoEditorShortcut
    case .cloudUploads: return cloudUploadsShortcut
    case .ocr: return ocrShortcut
    case .objectCutout: return objectCutoutShortcut
    }
  }

  func isShortcutEnabled(for kind: GlobalShortcutKind) -> Bool {
    !disabledShortcuts.contains(kind)
  }

  func setShortcutEnabled(_ enabled: Bool, for kind: GlobalShortcutKind) {
    guard isShortcutEnabled(for: kind) != enabled else { return }
    mutateShortcutRegistration {
      if enabled {
        disabledShortcuts.remove(kind)
      } else {
        disabledShortcuts.insert(kind)
      }
      saveDisabledShortcuts()
    }
  }

  /// Update fullscreen shortcut
  func setFullscreenShortcut(_ config: ShortcutConfig) {
    mutateShortcutRegistration {
      fullscreenShortcut = config
      saveShortcuts()
    }
  }

  /// Update area shortcut
  func setAreaShortcut(_ config: ShortcutConfig) {
    mutateShortcutRegistration {
      areaShortcut = config
      saveShortcuts()
    }
  }

  /// Update recording shortcut
  func setRecordingShortcut(_ config: ShortcutConfig) {
    mutateShortcutRegistration {
      recordingShortcut = config
      saveShortcuts()
    }
  }

  /// Update OCR shortcut
  func setOCRShortcut(_ config: ShortcutConfig) {
    mutateShortcutRegistration {
      ocrShortcut = config
      saveShortcuts()
    }
  }

  /// Update object cutout shortcut
  func setObjectCutoutShortcut(_ config: ShortcutConfig) {
    mutateShortcutRegistration {
      objectCutoutShortcut = config
      saveShortcuts()
    }
  }

  /// Update annotate shortcut
  func setAnnotateShortcut(_ config: ShortcutConfig) {
    mutateShortcutRegistration {
      annotateShortcut = config
      saveShortcuts()
    }
  }

  /// Update video editor shortcut
  func setVideoEditorShortcut(_ config: ShortcutConfig) {
    mutateShortcutRegistration {
      videoEditorShortcut = config
      saveShortcuts()
    }
  }

  /// Update cloud uploads shortcut
  func setCloudUploadsShortcut(_ config: ShortcutConfig) {
    mutateShortcutRegistration {
      cloudUploadsShortcut = config
      saveShortcuts()
    }
  }

  // MARK: - Persistence

  private func saveShortcuts() {
    let encoder = JSONEncoder()
    if let fullscreenData = try? encoder.encode(fullscreenShortcut) {
      UserDefaults.standard.set(fullscreenData, forKey: fullscreenShortcutKey)
    }
    if let areaData = try? encoder.encode(areaShortcut) {
      UserDefaults.standard.set(areaData, forKey: areaShortcutKey)
    }
    if let recordingData = try? encoder.encode(recordingShortcut) {
      UserDefaults.standard.set(recordingData, forKey: recordingShortcutKey)
    }
    if let annotateData = try? encoder.encode(annotateShortcut) {
      UserDefaults.standard.set(annotateData, forKey: annotateShortcutKey)
    }
    if let videoEditorData = try? encoder.encode(videoEditorShortcut) {
      UserDefaults.standard.set(videoEditorData, forKey: videoEditorShortcutKey)
    }
    if let cloudUploadsData = try? encoder.encode(cloudUploadsShortcut) {
      UserDefaults.standard.set(cloudUploadsData, forKey: cloudUploadsShortcutKey)
    }
    if let ocrData = try? encoder.encode(ocrShortcut) {
      UserDefaults.standard.set(ocrData, forKey: ocrShortcutKey)
    }
    if let objectCutoutData = try? encoder.encode(objectCutoutShortcut) {
      UserDefaults.standard.set(objectCutoutData, forKey: objectCutoutShortcutKey)
    }
  }

  private func loadShortcuts() {
    let decoder = JSONDecoder()
    if let fullscreenData = UserDefaults.standard.data(forKey: fullscreenShortcutKey),
      let config = try? decoder.decode(ShortcutConfig.self, from: fullscreenData)
    {
      fullscreenShortcut = config
    }
    if let areaData = UserDefaults.standard.data(forKey: areaShortcutKey),
      let config = try? decoder.decode(ShortcutConfig.self, from: areaData)
    {
      areaShortcut = config
    }
    if let recordingData = UserDefaults.standard.data(forKey: recordingShortcutKey),
      let config = try? decoder.decode(ShortcutConfig.self, from: recordingData)
    {
      recordingShortcut = config
    }
    if let annotateData = UserDefaults.standard.data(forKey: annotateShortcutKey),
      let config = try? decoder.decode(ShortcutConfig.self, from: annotateData)
    {
      annotateShortcut = config
    }
    if let videoEditorData = UserDefaults.standard.data(forKey: videoEditorShortcutKey),
      let config = try? decoder.decode(ShortcutConfig.self, from: videoEditorData)
    {
      videoEditorShortcut = config
    }
    if let cloudUploadsData = UserDefaults.standard.data(forKey: cloudUploadsShortcutKey),
      let config = try? decoder.decode(ShortcutConfig.self, from: cloudUploadsData)
    {
      cloudUploadsShortcut = config
    }
    if let ocrData = UserDefaults.standard.data(forKey: ocrShortcutKey),
      let config = try? decoder.decode(ShortcutConfig.self, from: ocrData)
    {
      ocrShortcut = config
    }
    if let objectCutoutData = UserDefaults.standard.data(forKey: objectCutoutShortcutKey),
      let config = try? decoder.decode(ShortcutConfig.self, from: objectCutoutData)
    {
      objectCutoutShortcut = config
    }
  }

  private func saveDisabledShortcuts() {
    let rawValues = disabledShortcuts.map(\.rawValue).sorted()
    UserDefaults.standard.set(rawValues, forKey: disabledShortcutsKey)
  }

  private func loadDisabledShortcuts() {
    guard let rawValues = UserDefaults.standard.array(forKey: disabledShortcutsKey) as? [String] else {
      disabledShortcuts = []
      return
    }
    disabledShortcuts = Set(rawValues.compactMap(GlobalShortcutKind.init(rawValue:)))
  }

  // MARK: - Private Methods

  private func setupEventHandler() {
    // Install Carbon event handler for hotkey events
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

    let handlerBlock: EventHandlerUPP = { _, event, _ -> OSStatus in
      var hotkeyID = EventHotKeyID()
      let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotkeyID
      )

      guard status == noErr else { return status }

      // Dispatch to main actor
      Task { @MainActor in
        KeyboardShortcutManager.shared.handleHotkey(id: hotkeyID.id)
      }

      return noErr
    }

    InstallEventHandler(
      GetApplicationEventTarget(),
      handlerBlock,
      1,
      &eventType,
      nil,
      &eventHandler
    )
  }

  private func mutateShortcutRegistration(_ mutation: () -> Void) {
    let shouldRestoreRegistration = areShortcutsRegistered
    if shouldRestoreRegistration {
      unregisterAllShortcuts()
    }
    mutation()
    if shouldRestoreRegistration {
      registerShortcuts()
    }
  }

  private func handleHotkey(id: UInt32) {
    let actionName: String
    let action: ShortcutAction

    switch id {
    case fullscreenHotkeyID.id:
      actionName = "fullscreen"
      action = .captureFullscreen
    case areaHotkeyID.id:
      actionName = "area"
      action = .captureArea
    case recordingHotkeyID.id:
      actionName = "recording"
      action = .recordVideo
    case annotateHotkeyID.id:
      actionName = "annotate"
      action = .openAnnotate
    case videoEditorHotkeyID.id:
      actionName = "video-editor"
      action = .openVideoEditor
    case cloudUploadsHotkeyID.id:
      actionName = "cloud-uploads"
      action = .openCloudUploads
    case ocrHotkeyID.id:
      actionName = "ocr"
      action = .captureOCR
    case objectCutoutHotkeyID.id:
      actionName = "object-cutout"
      action = .captureObjectCutout
    default:
      return
    }

    DiagnosticLogger.shared.log(.info, .action, "Shortcut triggered: \(actionName)")

    guard let delegate = delegate else {
      DiagnosticLogger.shared.log(.warning, .action, "Shortcut \(actionName) ignored: delegate is nil")
      return
    }

    delegate.shortcutTriggered(action)
  }

  private func registerShortcuts() {
    guard shouldRegisterShortcuts, !areShortcutsRegistered else { return }

    registerShortcutIfNeeded(
      kind: .fullscreen,
      config: fullscreenShortcut,
      hotkeyID: fullscreenHotkeyID,
      ref: &fullscreenHotkeyRef
    )

    registerShortcutIfNeeded(
      kind: .area,
      config: areaShortcut,
      hotkeyID: areaHotkeyID,
      ref: &areaHotkeyRef
    )

    registerShortcutIfNeeded(
      kind: .recording,
      config: recordingShortcut,
      hotkeyID: recordingHotkeyID,
      ref: &recordingHotkeyRef
    )

    registerShortcutIfNeeded(
      kind: .annotate,
      config: annotateShortcut,
      hotkeyID: annotateHotkeyID,
      ref: &annotateHotkeyRef
    )

    registerShortcutIfNeeded(
      kind: .videoEditor,
      config: videoEditorShortcut,
      hotkeyID: videoEditorHotkeyID,
      ref: &videoEditorHotkeyRef
    )

    registerShortcutIfNeeded(
      kind: .ocr,
      config: ocrShortcut,
      hotkeyID: ocrHotkeyID,
      ref: &ocrHotkeyRef
    )

    registerShortcutIfNeeded(
      kind: .cloudUploads,
      config: cloudUploadsShortcut,
      hotkeyID: cloudUploadsHotkeyID,
      ref: &cloudUploadsHotkeyRef
    )

    registerShortcutIfNeeded(
      kind: .objectCutout,
      config: objectCutoutShortcut,
      hotkeyID: objectCutoutHotkeyID,
      ref: &objectCutoutHotkeyRef
    )

    areShortcutsRegistered = true
  }

  private func registerShortcutIfNeeded(
    kind: GlobalShortcutKind,
    config: ShortcutConfig,
    hotkeyID: EventHotKeyID,
    ref: inout EventHotKeyRef?
  ) {
    guard isShortcutEnabled(for: kind) else { return }
    RegisterEventHotKey(
      config.keyCode,
      config.modifiers,
      hotkeyID,
      GetApplicationEventTarget(),
      0,
      &ref
    )
  }

  private func unregisterAllShortcuts() {
    guard areShortcutsRegistered else { return }

    if let ref = fullscreenHotkeyRef {
      UnregisterEventHotKey(ref)
      fullscreenHotkeyRef = nil
    }
    if let ref = areaHotkeyRef {
      UnregisterEventHotKey(ref)
      areaHotkeyRef = nil
    }
    if let ref = recordingHotkeyRef {
      UnregisterEventHotKey(ref)
      recordingHotkeyRef = nil
    }
    if let ref = annotateHotkeyRef {
      UnregisterEventHotKey(ref)
      annotateHotkeyRef = nil
    }
    if let ref = videoEditorHotkeyRef {
      UnregisterEventHotKey(ref)
      videoEditorHotkeyRef = nil
    }
    if let ref = ocrHotkeyRef {
      UnregisterEventHotKey(ref)
      ocrHotkeyRef = nil
    }
    if let ref = cloudUploadsHotkeyRef {
      UnregisterEventHotKey(ref)
      cloudUploadsHotkeyRef = nil
    }
    if let ref = objectCutoutHotkeyRef {
      UnregisterEventHotKey(ref)
      objectCutoutHotkeyRef = nil
    }

    areShortcutsRegistered = false
  }
}
