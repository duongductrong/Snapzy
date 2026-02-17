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

  var displayString: String {
    var parts: [String] = []

    if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
    if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
    if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
    if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }

    let keyChar = Self.keyCodeToString(keyCode)

    parts.append(keyChar)
    return parts.joined()
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
    default: return "?"
    }
  }
}

/// Shortcut action types
enum ShortcutAction {
  case captureFullscreen
  case captureArea
  case captureOCR
  case recordVideo
  case openAnnotate
  case openVideoEditor
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
  private(set) var ocrShortcut: ShortcutConfig
  private(set) var isEnabled: Bool = false

  private var fullscreenHotkeyRef: EventHotKeyRef?
  private var areaHotkeyRef: EventHotKeyRef?
  private var recordingHotkeyRef: EventHotKeyRef?
  private var annotateHotkeyRef: EventHotKeyRef?
  private var videoEditorHotkeyRef: EventHotKeyRef?
  private var ocrHotkeyRef: EventHotKeyRef?

  // Hotkey IDs
  private let fullscreenHotkeyID = EventHotKeyID(signature: OSType(0x5A53_4631), id: 1)  // "ZSF1"
  private let areaHotkeyID = EventHotKeyID(signature: OSType(0x5A53_4632), id: 2)  // "ZSF2"
  private let recordingHotkeyID = EventHotKeyID(signature: OSType(0x5A53_4633), id: 3)  // "ZSF3"
  private let annotateHotkeyID = EventHotKeyID(signature: OSType(0x5A53_4634), id: 4)  // "ZSF4"
  private let videoEditorHotkeyID = EventHotKeyID(signature: OSType(0x5A53_4635), id: 5)  // "ZSF5"
  private let ocrHotkeyID = EventHotKeyID(signature: OSType(0x5A53_4636), id: 6)  // "ZSF6"

  private var eventHandler: EventHandlerRef?

  // UserDefaults keys
  private let fullscreenShortcutKey = "fullscreenShortcut"
  private let areaShortcutKey = "areaShortcut"
  private let recordingShortcutKey = "recordingShortcut"
  private let annotateShortcutKey = "annotateShortcut"
  private let videoEditorShortcutKey = "videoEditorShortcut"
  private let ocrShortcutKey = "ocrShortcut"
  private let shortcutsEnabledKey = "shortcutsEnabled"

  private init() {
    fullscreenShortcut = .defaultFullscreen
    areaShortcut = .defaultArea
    recordingShortcut = .defaultRecording
    annotateShortcut = .defaultAnnotate
    videoEditorShortcut = .defaultVideoEditor
    ocrShortcut = .defaultOCR
    loadShortcuts()
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
    registerShortcuts()
    isEnabled = true
    UserDefaults.standard.set(true, forKey: shortcutsEnabledKey)
  }

  /// Disable global shortcuts
  func disable() {
    guard isEnabled else { return }
    unregisterAllShortcuts()
    isEnabled = false
    UserDefaults.standard.set(false, forKey: shortcutsEnabledKey)
  }

  /// Update fullscreen shortcut
  func setFullscreenShortcut(_ config: ShortcutConfig) {
    let wasEnabled = isEnabled
    if wasEnabled { disable() }
    fullscreenShortcut = config
    saveShortcuts()
    if wasEnabled { enable() }
  }

  /// Update area shortcut
  func setAreaShortcut(_ config: ShortcutConfig) {
    let wasEnabled = isEnabled
    if wasEnabled { disable() }
    areaShortcut = config
    saveShortcuts()
    if wasEnabled { enable() }
  }

  /// Update recording shortcut
  func setRecordingShortcut(_ config: ShortcutConfig) {
    let wasEnabled = isEnabled
    if wasEnabled { disable() }
    recordingShortcut = config
    saveShortcuts()
    if wasEnabled { enable() }
  }

  /// Update OCR shortcut
  func setOCRShortcut(_ config: ShortcutConfig) {
    let wasEnabled = isEnabled
    if wasEnabled { disable() }
    ocrShortcut = config
    saveShortcuts()
    if wasEnabled { enable() }
  }

  /// Update annotate shortcut
  func setAnnotateShortcut(_ config: ShortcutConfig) {
    let wasEnabled = isEnabled
    if wasEnabled { disable() }
    annotateShortcut = config
    saveShortcuts()
    if wasEnabled { enable() }
  }

  /// Update video editor shortcut
  func setVideoEditorShortcut(_ config: ShortcutConfig) {
    let wasEnabled = isEnabled
    if wasEnabled { disable() }
    videoEditorShortcut = config
    saveShortcuts()
    if wasEnabled { enable() }
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
    if let ocrData = try? encoder.encode(ocrShortcut) {
      UserDefaults.standard.set(ocrData, forKey: ocrShortcutKey)
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
    if let ocrData = UserDefaults.standard.data(forKey: ocrShortcutKey),
      let config = try? decoder.decode(ShortcutConfig.self, from: ocrData)
    {
      ocrShortcut = config
    }
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

  private func handleHotkey(id: UInt32) {
    // Block all hotkeys when the app is not licensed
    guard LicenseManager.shared.isLicensed else { return }

    let actionName: String
    switch id {
    case fullscreenHotkeyID.id:
      actionName = "fullscreen"
      delegate?.shortcutTriggered(.captureFullscreen)
    case areaHotkeyID.id:
      actionName = "area"
      delegate?.shortcutTriggered(.captureArea)
    case recordingHotkeyID.id:
      actionName = "recording"
      delegate?.shortcutTriggered(.recordVideo)
    case annotateHotkeyID.id:
      actionName = "annotate"
      delegate?.shortcutTriggered(.openAnnotate)
    case videoEditorHotkeyID.id:
      actionName = "video-editor"
      delegate?.shortcutTriggered(.openVideoEditor)
    case ocrHotkeyID.id:
      actionName = "ocr"
      delegate?.shortcutTriggered(.captureOCR)
    default:
      return
    }
    DiagnosticLogger.shared.log(.info, .action, "Shortcut triggered: \(actionName)")
  }

  private func registerShortcuts() {
    // Register fullscreen shortcut
    let fullscreenID = fullscreenHotkeyID
    RegisterEventHotKey(
      fullscreenShortcut.keyCode,
      fullscreenShortcut.modifiers,
      fullscreenID,
      GetApplicationEventTarget(),
      0,
      &fullscreenHotkeyRef
    )

    // Register area shortcut
    let areaID = areaHotkeyID
    RegisterEventHotKey(
      areaShortcut.keyCode,
      areaShortcut.modifiers,
      areaID,
      GetApplicationEventTarget(),
      0,
      &areaHotkeyRef
    )

    // Register recording shortcut
    let recordingID = recordingHotkeyID
    RegisterEventHotKey(
      recordingShortcut.keyCode,
      recordingShortcut.modifiers,
      recordingID,
      GetApplicationEventTarget(),
      0,
      &recordingHotkeyRef
    )

    // Register annotate shortcut
    let annotateID = annotateHotkeyID
    RegisterEventHotKey(
      annotateShortcut.keyCode,
      annotateShortcut.modifiers,
      annotateID,
      GetApplicationEventTarget(),
      0,
      &annotateHotkeyRef
    )

    // Register video editor shortcut
    let videoEditorID = videoEditorHotkeyID
    RegisterEventHotKey(
      videoEditorShortcut.keyCode,
      videoEditorShortcut.modifiers,
      videoEditorID,
      GetApplicationEventTarget(),
      0,
      &videoEditorHotkeyRef
    )

    // Register OCR shortcut
    let ocrID = ocrHotkeyID
    RegisterEventHotKey(
      ocrShortcut.keyCode,
      ocrShortcut.modifiers,
      ocrID,
      GetApplicationEventTarget(),
      0,
      &ocrHotkeyRef
    )
  }

  private func unregisterAllShortcuts() {
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
  }
}
