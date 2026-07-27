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
}
