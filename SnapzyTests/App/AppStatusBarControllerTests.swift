//
//  AppStatusBarControllerTests.swift
//  SnapzyTests
//
//  Unit tests for AppStatusBarController activation policy.
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class AppStatusBarControllerTests: XCTestCase {
  private var controller: AppStatusBarController!
  private var initialPolicy: NSApplication.ActivationPolicy!

  override func setUp() {
    super.setUp()
    controller = AppStatusBarController.shared
    initialPolicy = NSApp.activationPolicy()
  }

  override func tearDown() {
    // Restore initial state
    NSApp.setActivationPolicy(initialPolicy)
    controller.didElevateForSettingsForTesting = false
    controller.trackedPreferencesWindowForTesting = nil
    UserDefaults.standard.removeObject(forKey: PreferencesKeys.recordingHoverBarVisible)
    UserDefaults.standard.removeObject(forKey: PreferencesKeys.recordingShowTimeOnMenuBar)
    super.tearDown()
  }

  // MARK: - Recording UI preference defaults (issue #351)

  func testRecordingUIPreferences_defaultToTrueWhenUnset() {
    UserDefaults.standard.removeObject(forKey: PreferencesKeys.recordingHoverBarVisible)
    UserDefaults.standard.removeObject(forKey: PreferencesKeys.recordingShowTimeOnMenuBar)

    // Defaults must preserve prior behavior: hover bar visible, time shown.
    XCTAssertTrue(controller.isHoverBarVisibleForTesting)
    XCTAssertTrue(controller.showsRecordingTimeOnMenuBarForTesting)
  }

  func testRecordingUIPreferences_reflectStoredFalseValues() {
    UserDefaults.standard.set(false, forKey: PreferencesKeys.recordingHoverBarVisible)
    UserDefaults.standard.set(false, forKey: PreferencesKeys.recordingShowTimeOnMenuBar)

    XCTAssertFalse(controller.isHoverBarVisibleForTesting)
    XCTAssertFalse(controller.showsRecordingTimeOnMenuBarForTesting)
  }

  // MARK: - Hidden status item detection (issue #587)

  // Frames measured on a 14" notched MacBook Pro at default scaling.
  private let notchedScreen = CGRect(x: 0, y: 0, width: 1800, height: 1169)
  private let notchGap: ClosedRange<CGFloat> = 790...1010

  func testStatusItemObscured_falseWhenRightOfNotchAndVisible() {
    XCTAssertFalse(
      AppStatusBarController.isStatusItemObscured(
        itemFrame: CGRect(x: 1046, y: 1130, width: 137, height: 39),
        screenFrame: notchedScreen,
        notchGap: notchGap,
        isOcclusionVisible: true
      )
    )
  }

  func testStatusItemObscured_trueWhenOverlappingNotch() {
    XCTAssertTrue(
      AppStatusBarController.isStatusItemObscured(
        itemFrame: CGRect(x: 911, y: 1130, width: 137, height: 39),
        screenFrame: notchedScreen,
        notchGap: notchGap,
        isOcclusionVisible: true
      )
    )
  }

  func testStatusItemObscured_trueWhenPushedOffScreen() {
    XCTAssertTrue(
      AppStatusBarController.isStatusItemObscured(
        itemFrame: CGRect(x: -47, y: 1130, width: 137, height: 39),
        screenFrame: notchedScreen,
        notchGap: notchGap,
        isOcclusionVisible: true
      )
    )
  }

  func testStatusItemObscured_trueWhenOccluded() {
    XCTAssertTrue(
      AppStatusBarController.isStatusItemObscured(
        itemFrame: CGRect(x: 500, y: 1130, width: 137, height: 39),
        screenFrame: notchedScreen,
        notchGap: notchGap,
        isOcclusionVisible: false
      )
    )
  }

  func testStatusItemObscured_trueWithoutScreen() {
    XCTAssertTrue(
      AppStatusBarController.isStatusItemObscured(
        itemFrame: CGRect(x: 1046, y: 1130, width: 137, height: 39),
        screenFrame: nil,
        notchGap: nil,
        isOcclusionVisible: true
      )
    )
  }

  func testStatusItemObscured_ignoresNotchGapOnScreensWithoutNotch() {
    XCTAssertFalse(
      AppStatusBarController.isStatusItemObscured(
        itemFrame: CGRect(x: 911, y: 1130, width: 137, height: 39),
        screenFrame: notchedScreen,
        notchGap: nil,
        isOcclusionVisible: true
      )
    )
  }

  // MARK: - Menu bar title gating (issue #351)

  func testMenuBarTitle_hiddenWhenTimeDisplayOff_forAllStates() {
    for state in [RecordingState.recording, .paused, .idle, .preparing, .stopping] {
      let title = AppStatusBarController.menuBarTitleString(for: state, duration: "01:23", showTime: false)
      XCTAssertEqual(title, "", "expected empty title for \(state) when time display off")
    }
  }

  func testMenuBarTitle_showsDurationWhileRecording() {
    XCTAssertEqual(
      AppStatusBarController.menuBarTitleString(for: .recording, duration: "01:23", showTime: true),
      "01:23"
    )
  }

  func testMenuBarTitle_prefixesPauseMarkerWhilePaused() {
    XCTAssertEqual(
      AppStatusBarController.menuBarTitleString(for: .paused, duration: "01:23", showTime: true),
      "|| 01:23"
    )
  }

  func testMenuBarTitle_emptyWhenIdleEvenWithTimeOn() {
    for state in [RecordingState.idle, .preparing, .stopping] {
      XCTAssertEqual(
        AppStatusBarController.menuBarTitleString(for: state, duration: "01:23", showTime: true),
        "",
        "expected empty title for non-active state \(state)"
      )
    }
  }

  func testWindowDidClose_revertsActivationPolicyWhenNoOtherVisibleWindows() {
    // 1. Setup initial elevated state
    controller.didElevateForSettingsForTesting = true
    NSApp.setActivationPolicy(.regular)

    // 2. Create a mock closing window and make it visible
    let closingWindow = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    closingWindow.title = "Settings"
    closingWindow.orderFront(nil)
    controller.trackedPreferencesWindowForTesting = closingWindow

    // 3. Post notification/Simulate close
    let notification = Notification(
      name: NSWindow.willCloseNotification,
      object: closingWindow
    )
    controller.simulateWindowDidClose(notification: notification)

    // 4. Verify that activation policy reverted to .accessory
    XCTAssertEqual(NSApp.activationPolicy(), .accessory)
    XCTAssertFalse(controller.didElevateForSettingsForTesting)
    XCTAssertNil(controller.trackedPreferencesWindowForTesting)

    // 5. Cleanup window to prevent leakage
    closingWindow.close()
  }

  // MARK: - Settings menu item lookup (issue #311)

  private func makeMainMenu(appMenuItems: [NSMenuItem], extraMenus: [NSMenu] = []) -> NSMenu {
    let mainMenu = NSMenu()
    let appMenuItem = NSMenuItem()
    let appMenu = NSMenu()
    for item in appMenuItems {
      appMenu.addItem(item)
    }
    appMenuItem.submenu = appMenu
    mainMenu.addItem(appMenuItem)
    for menu in extraMenus {
      let item = NSMenuItem()
      item.submenu = menu
      mainMenu.addItem(item)
    }
    return mainMenu
  }

  private func makeMenuItem(title: String, action: String?, keyEquivalent: String) -> NSMenuItem {
    let item = NSMenuItem(
      title: title,
      action: action.map { Selector(($0)) },
      keyEquivalent: keyEquivalent
    )
    item.keyEquivalentModifierMask = .command
    return item
  }

  func testFindSettingsMenuItem_matchesStandardActionSelectors() {
    for actionName in ["showSettingsWindow:", "showPreferencesWindow:"] {
      let settingsItem = makeMenuItem(title: "Settings…", action: actionName, keyEquivalent: "")
      let menu = makeMainMenu(appMenuItems: [
        makeMenuItem(title: "About Snapzy", action: nil, keyEquivalent: ""),
        settingsItem,
        makeMenuItem(title: "Quit Snapzy", action: "terminate:", keyEquivalent: "q"),
      ])

      XCTAssertTrue(
        AppStatusBarController.findSettingsMenuItem(in: menu, shortcutCharacter: ",") === settingsItem,
        "expected match for action \(actionName)"
      )
    }
  }

  func testFindSettingsMenuItem_matchesCommaKeyEquivalentOnUSLayout() {
    // The SwiftUI Settings scene item uses a private action (menuAction:),
    // so it is identified by its Cmd+, shortcut.
    let settingsItem = makeMenuItem(title: "Settings…", action: "menuAction:", keyEquivalent: ",")
    let menu = makeMainMenu(appMenuItems: [
      makeMenuItem(title: "About Snapzy", action: nil, keyEquivalent: ""),
      settingsItem,
      makeMenuItem(title: "Quit Snapzy", action: "terminate:", keyEquivalent: "q"),
    ])

    XCTAssertTrue(
      AppStatusBarController.findSettingsMenuItem(in: menu, shortcutCharacter: ",") === settingsItem
    )
  }

  func testFindSettingsMenuItem_matchesMirroredKeyEquivalentOnTurkishLayout() {
    // AppKit mirrors the Settings key equivalent to the physical comma key's
    // character on the active layout ("ö" on Turkish Q) - the root cause of
    // the simulated Cmd+, event no longer matching (issue #311).
    let settingsItem = makeMenuItem(title: "Settings…", action: "menuAction:", keyEquivalent: "ö")
    let menu = makeMainMenu(appMenuItems: [
      makeMenuItem(title: "About Snapzy", action: nil, keyEquivalent: ""),
      settingsItem,
      makeMenuItem(title: "Quit Snapzy", action: "terminate:", keyEquivalent: "q"),
    ])

    XCTAssertTrue(
      AppStatusBarController.findSettingsMenuItem(in: menu, shortcutCharacter: "ö") === settingsItem
    )
  }

  func testFindSettingsMenuItem_ignoresCommaShortcutOutsideAppMenu() {
    // The shortcut match is scoped to the application menu so unrelated
    // Cmd+, items elsewhere in the menu bar are never triggered.
    let commaItem = makeMenuItem(title: "Custom Command", action: "menuAction:", keyEquivalent: ",")
    let fileMenu = NSMenu(title: "File")
    fileMenu.addItem(commaItem)
    let menu = makeMainMenu(
      appMenuItems: [makeMenuItem(title: "About Snapzy", action: nil, keyEquivalent: "")],
      extraMenus: [fileMenu]
    )

    XCTAssertNil(AppStatusBarController.findSettingsMenuItem(in: menu, shortcutCharacter: ","))
  }

  func testFindSettingsMenuItem_returnsNilWhenNoSettingsItemExists() {
    let menu = makeMainMenu(appMenuItems: [
      makeMenuItem(title: "About Snapzy", action: nil, keyEquivalent: ""),
      makeMenuItem(title: "Quit Snapzy", action: "terminate:", keyEquivalent: "q"),
    ])

    XCTAssertNil(AppStatusBarController.findSettingsMenuItem(in: menu, shortcutCharacter: "ö"))
  }
}
