//
//  SnapzyConfigurationImporterTests.swift
//  SnapzyTests
//
//  Unit tests for TOML configuration import validation and application.
//

import XCTest
@testable import Snapzy

@MainActor
final class SnapzyConfigurationImporterTests: XCTestCase {
  func testImportAppliesCaptureAndRecordingSettingsToProvidedDefaults() {
    let defaults = UserDefaultsFactory.make()
    let source = """
    schema_version = 1

    [capture.screenshot]
    format = "webp"
    show_cursor = true

    [recording]
    fps = 60
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults)

    XCTAssertFalse(result.hasErrors)
    XCTAssertGreaterThanOrEqual(result.appliedChangeCount, 3)
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.screenshotFormat), "webp")
    XCTAssertEqual(defaults.object(forKey: PreferencesKeys.screenshotShowCursor) as? Bool, true)
    XCTAssertEqual(defaults.object(forKey: PreferencesKeys.recordingFPS) as? Int, 60)
  }

  func testImportRejectsUnsupportedSchemaBeforeMutatingDefaults() {
    let defaults = UserDefaultsFactory.make()
    defaults.set("png", forKey: PreferencesKeys.screenshotFormat)
    let source = """
    schema_version = 99

    [capture.screenshot]
    format = "webp"
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults)

    XCTAssertTrue(result.hasErrors)
    XCTAssertEqual(result.appliedChangeCount, 0)
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.screenshotFormat), "png")
  }

  func testImportRejectsInvalidEnumsBeforeApplyingAnyMutation() {
    let defaults = UserDefaultsFactory.make()
    defaults.set("png", forKey: PreferencesKeys.screenshotFormat)
    let source = """
    schema_version = 1

    [capture.screenshot]
    format = "bmp"
    show_cursor = true
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults)

    XCTAssertTrue(result.hasErrors)
    XCTAssertEqual(result.appliedChangeCount, 0)
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.screenshotFormat), "png")
    XCTAssertNil(defaults.object(forKey: PreferencesKeys.screenshotShowCursor))
  }

  func testImportRejectsUnknownShortcutModifiers() {
    let defaults = UserDefaultsFactory.make()
    let source = """
    schema_version = 1

    [shortcuts.global.fullscreen]
    key = "3"
    modifiers = ["command", "hyper"]
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults)

    XCTAssertTrue(result.hasErrors)
    XCTAssertEqual(result.appliedChangeCount, 0)
  }

  func testImportExpandsTildePathsAgainstUserHomeDirectory() {
    let defaults = UserDefaultsFactory.make()
    let source = """
    schema_version = 1

    [general]
    export_location = "~/Desktop"
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults)

    XCTAssertFalse(result.hasErrors)
    XCTAssertTrue(result.issues.isEmpty)
    XCTAssertEqual(
      defaults.string(forKey: PreferencesKeys.exportLocation),
      SnapzyConfigurationPaths.expandedUserPath("~/Desktop")
    )
  }

  func testImportAppliesQuickAccessTwoFingerSwipeSetting() {
    let defaults = UserDefaultsFactory.make()
    let manager = QuickAccessManager.shared
    let original = manager.twoFingerSwipeToDismissEnabled
    manager.twoFingerSwipeToDismissEnabled = true
    defer { manager.twoFingerSwipeToDismissEnabled = original }
    let source = """
    schema_version = 1

    [quick_access]
    two_finger_swipe_to_dismiss = false
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults)

    XCTAssertFalse(result.hasErrors)
    XCTAssertFalse(manager.twoFingerSwipeToDismissEnabled)
  }

  func testImportWithoutAnnotateShortcutSectionDoesNotResetActionEnablement() {
    let defaults = UserDefaultsFactory.make()
    let manager = AnnotateShortcutManager.shared
    let original = manager.isActionShortcutEnabled(for: .copyAndClose)
    manager.setActionShortcutEnabled(false, for: .copyAndClose)
    defer { manager.setActionShortcutEnabled(original, for: .copyAndClose) }

    let source = """
    schema_version = 1

    [capture.screenshot]
    show_cursor = true
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults)

    XCTAssertFalse(result.hasErrors)
    XCTAssertFalse(manager.isActionShortcutEnabled(for: .copyAndClose))
  }

  func testImportAnnotateToolAcceptsNumericShortcut() {
    let defaults = UserDefaultsFactory.make()
    let manager = AnnotateShortcutManager.shared
    manager.resetToDefaults()
    defer { manager.resetToDefaults() }

    let source = """
    schema_version = 1

    [shortcuts.annotate_tools]
    rectangle = "1"
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults)

    XCTAssertFalse(result.hasErrors)
    XCTAssertEqual(manager.shortcut(for: .rectangle), "1")
  }

  func testImportAnnotateToolNormalizesUppercaseShortcut() {
    let defaults = UserDefaultsFactory.make()
    let manager = AnnotateShortcutManager.shared
    manager.resetToDefaults()
    defer { manager.resetToDefaults() }

    let source = """
    schema_version = 1

    [shortcuts.annotate_tools]
    rectangle = "R"
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults)

    XCTAssertFalse(result.hasErrors)
    XCTAssertEqual(manager.shortcut(for: .rectangle), "r")
    XCTAssertEqual(manager.tool(for: "r"), .rectangle)
  }

  func testImportAnnotateToolAcceptsSpecialCharacterShortcut() {
    let defaults = UserDefaultsFactory.make()
    let manager = AnnotateShortcutManager.shared
    manager.resetToDefaults()
    defer { manager.resetToDefaults() }

    let source = """
    schema_version = 1

    [shortcuts.annotate_tools]
    rectangle = "="
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults)

    XCTAssertFalse(result.hasErrors)
    XCTAssertEqual(manager.shortcut(for: .rectangle), "=")
  }

  func testImportAnnotateToolAllowsEmptyShortcut() {
    let defaults = UserDefaultsFactory.make()
    let manager = AnnotateShortcutManager.shared
    manager.resetToDefaults()
    manager.setShortcut("9", for: .rectangle)
    defer { manager.resetToDefaults() }

    let source = """
    schema_version = 1

    [shortcuts.annotate_tools]
    rectangle = ""
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults)

    XCTAssertFalse(result.hasErrors)
    XCTAssertNil(manager.shortcut(for: .rectangle))
  }

  func testImportAnnotateToolRejectsMultiCharacterShortcut() {
    let defaults = UserDefaultsFactory.make()
    let manager = AnnotateShortcutManager.shared
    manager.resetToDefaults()
    manager.setShortcut("9", for: .rectangle)
    defer { manager.resetToDefaults() }

    let source = """
    schema_version = 1

    [shortcuts.annotate_tools]
    rectangle = "12"
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults)

    XCTAssertTrue(result.hasErrors)
    XCTAssertEqual(result.appliedChangeCount, 0)
    XCTAssertEqual(manager.shortcut(for: .rectangle), "9")
  }

  func testImportAnnotateActionAllowsEmptyShortcutWhileEnabled() {
    let defaults = UserDefaultsFactory.make()
    let manager = AnnotateShortcutManager.shared
    manager.resetToDefaults()
    defer { manager.resetToDefaults() }

    let source = """
    schema_version = 1

    [shortcuts.annotate_actions.auto_redact_sensitive_data]
    enabled = true
    key = ""
    modifiers = []
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults)

    XCTAssertFalse(result.hasErrors)
    XCTAssertNil(manager.shortcut(for: .autoRedactSensitiveData))
    XCTAssertTrue(manager.isActionShortcutEnabled(for: .autoRedactSensitiveData))
  }

  func testImportAnnotateActionAppliesAutoRedactShortcut() {
    let defaults = UserDefaultsFactory.make()
    let manager = AnnotateShortcutManager.shared
    manager.resetToDefaults()
    defer { manager.resetToDefaults() }

    let source = """
    schema_version = 1

    [shortcuts.annotate_actions.auto_redact_sensitive_data]
    enabled = true
    key = "r"
    modifiers = ["command", "shift"]
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults)

    XCTAssertFalse(result.hasErrors)
    XCTAssertNotNil(manager.shortcut(for: .autoRedactSensitiveData))
    XCTAssertTrue(manager.isActionShortcutEnabled(for: .autoRedactSensitiveData))
  }

  func testImportAppliesNewConfigurationFields() {
    let defaults = UserDefaultsFactory.make()
    let manager = QuickAccessManager.shared
    
    let originalHide = manager.hideCardWhenWindowOpen
    let originalStyle = manager.animationStyle
    let originalLeftAction = QuickAccessSwipeActionStore.shared.swipeLeftAction
    let originalRightAction = QuickAccessSwipeActionStore.shared.swipeRightAction
    let originalTrackpadMode = QuickAccessTrackpadSwipeModeStore.shared.mode
    
    defer {
      manager.hideCardWhenWindowOpen = originalHide
      manager.animationStyle = originalStyle
      QuickAccessSwipeActionStore.shared.setAction(.left, action: originalLeftAction)
      QuickAccessSwipeActionStore.shared.setAction(.right, action: originalRightAction)
      QuickAccessTrackpadSwipeModeStore.shared.setMode(originalTrackpadMode)
    }

    let source = """
    schema_version = 1

    [general]
    show_menu_bar_icon = false

    [capture.screenshot]
    freeze_area = true
    show_selection_area_overlay = false
    reverse_magnifier_zoom_direction = true
    show_magnifier_by_default = true

    [recording]
    video_editor_zoom_transition_duration = 0.55

    [annotate]
    combine_save_as_edit = false
    default_tool = "arrow"
    remember_last_tool = true

    [quick_access]
    trackpad_swipe_mode = "natural"
    swipe_left_action = "pinToScreen"
    swipe_right_action = "none"
    hide_card_when_window_open = false
    animation_style = "scale"
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults)

    XCTAssertFalse(result.hasErrors)
    
    // general
    XCTAssertEqual(defaults.object(forKey: PreferencesKeys.showMenuBarIcon) as? Bool, false)
    
    // capture.screenshot
    XCTAssertEqual(defaults.object(forKey: PreferencesKeys.screenshotFreezeArea) as? Bool, true)
    XCTAssertEqual(defaults.object(forKey: PreferencesKeys.screenshotShowSelectionAreaOverlay) as? Bool, false)
    XCTAssertEqual(defaults.object(forKey: PreferencesKeys.screenshotReverseMagnifierZoomDirection) as? Bool, true)
    XCTAssertEqual(defaults.object(forKey: PreferencesKeys.screenshotShowMagnifierByDefault) as? Bool, true)
    
    // recording
    XCTAssertEqual(defaults.object(forKey: PreferencesKeys.videoEditorZoomTransitionDuration) as? Double, 0.55)

    // annotate
    XCTAssertEqual(defaults.object(forKey: PreferencesKeys.annotateCombineSaveAsEdit) as? Bool, false)
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.annotateDefaultTool), "arrow")
    XCTAssertEqual(defaults.object(forKey: PreferencesKeys.annotateRememberLastTool) as? Bool, true)
    
    // quick access
    XCTAssertEqual(QuickAccessTrackpadSwipeModeStore.shared.mode, .natural)
    XCTAssertEqual(QuickAccessSwipeActionStore.shared.swipeLeftAction, .pinToScreen)
    XCTAssertNil(QuickAccessSwipeActionStore.shared.swipeRightAction)
    XCTAssertFalse(manager.hideCardWhenWindowOpen)
    XCTAssertEqual(manager.animationStyle, .scale)
  }

  func testImportRejectsOutOfRangeVideoEditorZoomTransitionDuration() {
    let defaults = UserDefaultsFactory.make()
    let source = """
    schema_version = 1

    [recording]
    video_editor_zoom_transition_duration = 10.0
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults)
    XCTAssertTrue(result.hasErrors)
    XCTAssertNil(defaults.object(forKey: PreferencesKeys.videoEditorZoomTransitionDuration))
  }

  func testImportRejectsInvalidEnumValues() {
    let defaults = UserDefaultsFactory.make()
    
    let sourceInvalidTrackpad = """
    schema_version = 1
    [quick_access]
    trackpad_swipe_mode = "invalid_mode"
    """
    let result1 = SnapzyConfigurationImporter.importTOML(sourceInvalidTrackpad, defaults: defaults)
    XCTAssertTrue(result1.hasErrors)

    let sourceInvalidLeftAction = """
    schema_version = 1
    [quick_access]
    swipe_left_action = "invalid_action"
    """
    let result2 = SnapzyConfigurationImporter.importTOML(sourceInvalidLeftAction, defaults: defaults)
    XCTAssertTrue(result2.hasErrors)

    let sourceInvalidAnim = """
    schema_version = 1
    [quick_access]
    animation_style = "invalid_style"
    """
    let result3 = SnapzyConfigurationImporter.importTOML(sourceInvalidAnim, defaults: defaults)
    XCTAssertTrue(result3.hasErrors)
  }

  func testImportAppliesMenuBarCustomization() {
    let defaults = UserDefaultsFactory.make()
    let store = MenuBarCustomizationStore.shared
    let originalOrder = store.itemOrder
    let originalHidden = store.hiddenItems
    let originalStyle = store.iconStyle
    defer {
      store.applyConfiguration(
        order: originalOrder,
        hiddenItems: originalHidden,
        iconStyle: originalStyle
      )
    }
    let source = """
    schema_version = 1

    [menu_bar]
    icon_style = "cameraFill"
    item_order = ["shortcutList", "captureOCR"]
    hidden_items = ["openHistory"]
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults)

    XCTAssertFalse(result.hasErrors)
    XCTAssertEqual(store.iconStyle, .cameraFill)
    XCTAssertEqual(store.orderedItems(for: .tools).first, .shortcutList)
    XCTAssertEqual(store.orderedItems(for: .capture).first, .captureOCR)
    XCTAssertTrue(store.isHidden(.openHistory))
  }

  func testImportRejectsInvalidMenuBarIconStyle() {
    let defaults = UserDefaultsFactory.make()
    let store = MenuBarCustomizationStore.shared
    let originalStyle = store.iconStyle
    defer { store.setIconStyle(originalStyle) }
    let source = """
    schema_version = 1

    [menu_bar]
    icon_style = "invalid_style"
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults)

    XCTAssertTrue(result.hasErrors)
    XCTAssertEqual(store.iconStyle, originalStyle)
  }

  // MARK: - Custom OCR models

  func testImportAppliesCustomOCRModelsAndClearsAPIKeyFlag() throws {
    let defaults = UserDefaultsFactory.make()
    let keychain = FakeOCRKeychainStore()
    let id = UUID().uuidString
    let source = """
    schema_version = 1

    [capture.ocr]
    custom_models = "[{\\"id\\":\\"\(id)\\",\\"name\\":\\"My API\\",\\"baseURL\\":\\"https://api.example.com\\",\\"modelIdentifier\\":\\"test-model\\",\\"hasAPIKey\\":true}]"
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults, keychainStore: keychain)

    XCTAssertFalse(result.hasErrors)
    let data = try XCTUnwrap(defaults.data(forKey: PreferencesKeys.ocrCustomModels))
    let models = try JSONDecoder().decode([CustomOCRModel].self, from: data)
    XCTAssertEqual(models.count, 1)
    XCTAssertEqual(models.first?.id.uuidString, id)
    XCTAssertEqual(models.first?.name, "My API")
    XCTAssertEqual(models.first?.baseURL, "https://api.example.com")
    XCTAssertEqual(models.first?.modelIdentifier, "test-model")
    // API keys never travel in config files.
    XCTAssertEqual(models.first?.hasAPIKey, false)
  }

  func testImportCustomOCRModelsReplacesExistingList() throws {
    let defaults = UserDefaultsFactory.make()
    let keychain = FakeOCRKeychainStore()
    let existing = CustomOCRModel(name: "Old", baseURL: "https://old.test", modelIdentifier: "old")
    defaults.set(try JSONEncoder().encode([existing]), forKey: PreferencesKeys.ocrCustomModels)
    let id = UUID().uuidString
    let source = """
    schema_version = 1

    [capture.ocr]
    custom_models = "[{\\"id\\":\\"\(id)\\",\\"name\\":\\"New\\",\\"baseURL\\":\\"https://new.test\\",\\"modelIdentifier\\":\\"new\\"}]"
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults, keychainStore: keychain)

    XCTAssertFalse(result.hasErrors)
    let data = try XCTUnwrap(defaults.data(forKey: PreferencesKeys.ocrCustomModels))
    let models = try JSONDecoder().decode([CustomOCRModel].self, from: data)
    XCTAssertEqual(models.map(\.name), ["New"])
  }

  func testImportCustomOCRModelsDeletesKeychainKeysForDroppedModels() throws {
    let defaults = UserDefaultsFactory.make()
    let keychain = FakeOCRKeychainStore()
    let dropped = CustomOCRModel(name: "Old", baseURL: "https://old.test", modelIdentifier: "old")
    defaults.set(try JSONEncoder().encode([dropped]), forKey: PreferencesKeys.ocrCustomModels)
    keychain.seedKey("sk-old", for: dropped.id)
    let id = UUID().uuidString
    let source = """
    schema_version = 1

    [capture.ocr]
    custom_models = "[{\\"id\\":\\"\(id)\\",\\"name\\":\\"New\\",\\"baseURL\\":\\"https://new.test\\",\\"modelIdentifier\\":\\"new\\"}]"
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults, keychainStore: keychain)

    XCTAssertFalse(result.hasErrors)
    XCTAssertEqual(keychain.deletedIDs, [dropped.id])
    XCTAssertNil(keychain.readKey(for: dropped.id))
  }

  func testImportCustomOCRModelsReconcilesAPIKeyFlagWithKeychain() throws {
    let defaults = UserDefaultsFactory.make()
    let keychain = FakeOCRKeychainStore()
    // The kept id survives the replace and already has a key on this machine.
    let keptID = UUID()
    keychain.seedKey("sk-kept", for: keptID)
    let freshID = UUID()
    let source = """
    schema_version = 1

    [capture.ocr]
    custom_models = "[{\\"id\\":\\"\(keptID.uuidString)\\",\\"name\\":\\"Kept\\",\\"baseURL\\":\\"https://k.test\\",\\"modelIdentifier\\":\\"k\\"},{\\"id\\":\\"\(freshID.uuidString)\\",\\"name\\":\\"Fresh\\",\\"baseURL\\":\\"https://f.test\\",\\"modelIdentifier\\":\\"f\\",\\"hasAPIKey\\":true}]"
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults, keychainStore: keychain)

    XCTAssertFalse(result.hasErrors)
    let data = try XCTUnwrap(defaults.data(forKey: PreferencesKeys.ocrCustomModels))
    let models = try JSONDecoder().decode([CustomOCRModel].self, from: data)
    XCTAssertEqual(models.first { $0.id == keptID }?.hasAPIKey, true)
    // "hasAPIKey":true in the file does not import — no key exists locally.
    XCTAssertEqual(models.first { $0.id == freshID }?.hasAPIKey, false)
  }

  func testImportRejectsMalformedCustomOCRModelsJSON() {
    let defaults = UserDefaultsFactory.make()
    let source = """
    schema_version = 1

    [capture.ocr]
    custom_models = "not json"
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults)

    XCTAssertTrue(result.hasErrors)
    XCTAssertEqual(result.appliedChangeCount, 0)
    XCTAssertNil(defaults.data(forKey: PreferencesKeys.ocrCustomModels))
  }

  func testImportRejectsCustomOCRModelWithEmptyFields() {
    let defaults = UserDefaultsFactory.make()
    let id = UUID().uuidString
    let source = """
    schema_version = 1

    [capture.ocr]
    custom_models = "[{\\"id\\":\\"\(id)\\",\\"name\\":\\"My API\\",\\"baseURL\\":\\"\\",\\"modelIdentifier\\":\\"test-model\\"}]"
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults)

    XCTAssertTrue(result.hasErrors)
    XCTAssertEqual(result.appliedChangeCount, 0)
    XCTAssertNil(defaults.data(forKey: PreferencesKeys.ocrCustomModels))
  }

  func testExportIncludesCustomOCRModelsAsJSON() throws {
    let defaults = UserDefaultsFactory.make()
    let model = CustomOCRModel(
      name: "My API",
      baseURL: "https://api.example.com",
      modelIdentifier: "test-model",
      prompt: "Read text",
      hasAPIKey: true
    )
    defaults.set(try JSONEncoder().encode([model]), forKey: PreferencesKeys.ocrCustomModels)

    let source = SnapzyConfigurationExporter.exportTOML(defaults: defaults)
    let document = try SimpleTOMLParser.parse(source)

    let json = try XCTUnwrap(document.value(at: "capture", "ocr", "custom_models")?.stringValue)
    let exported = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
    XCTAssertEqual(exported.count, 1)
    XCTAssertEqual(exported.first?["id"] as? String, model.id.uuidString)
    XCTAssertEqual(exported.first?["name"] as? String, "My API")
    // The exported payload is model metadata only — never key material.
    XCTAssertNil(exported.first?["apiKey"])
  }

  func testExportOmitsRemovedDownloadableOCRConfiguration() throws {
    let defaults = UserDefaultsFactory.make()

    let source = SnapzyConfigurationExporter.exportTOML(defaults: defaults)
    let document = try SimpleTOMLParser.parse(source)

    XCTAssertNil(document.value(at: "capture", "ocr", "catalog_models"))
  }

  func testImportIgnoresLegacyDownloadableOCRConfiguration() {
    let defaults = UserDefaultsFactory.make()
    let source = """
    schema_version = 1

    [capture.ocr]
    catalog_models = "no longer supported"
    selected_model = "dl:old-model"
    """

    let result = SnapzyConfigurationImporter.importTOML(source, defaults: defaults)

    XCTAssertFalse(result.hasErrors)
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.ocrSelectedModel), "dl:old-model")
    _ = OCRModelResolver(defaults: defaults).resolveStoredSelection()
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.ocrSelectedModel), "builtin")
  }

}
