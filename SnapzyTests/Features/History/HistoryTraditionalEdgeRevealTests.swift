//
//  HistoryTraditionalEdgeRevealTests.swift
//  SnapzyTests
//
//  Unit tests for the traditional panel top-edge reveal preference
//

import AppKit
@testable import Snapzy
import XCTest

@MainActor
final class HistoryTraditionalEdgeRevealTests: XCTestCase {
  deinit {}

  override func tearDown() {
    let manager = HistoryFloatingManager.shared
    manager.isEdgeRevealEnabled = false
    manager.hide()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    super.tearDown()
  }

  func testEdgeRevealPreferencePersists() {
    let manager = HistoryFloatingManager.shared
    let original = manager.isEdgeRevealEnabled
    defer { manager.isEdgeRevealEnabled = original }

    manager.isEdgeRevealEnabled = false
    XCTAssertEqual(UserDefaults.standard.object(forKey: "history.floating.edgeRevealEnabled") as? Bool, false)
    manager.isEdgeRevealEnabled = true
    XCTAssertEqual(UserDefaults.standard.object(forKey: "history.floating.edgeRevealEnabled") as? Bool, true)
  }

  func testEdgeRevealMonitoringRequiresTraditionalEnabledPanelAndToggle() {
    let manager = HistoryFloatingManager.shared
    let defaults = UserDefaults.standard
    let originalStyle = manager.displayStyle
    let originalEnabled = manager.isEnabled
    let originalEdge = manager.isEdgeRevealEnabled
    let originalHistory = defaults.object(forKey: PreferencesKeys.historyEnabled) as? Bool
    defer {
      manager.isEdgeRevealEnabled = originalEdge
      manager.isEnabled = originalEnabled
      manager.displayStyle = originalStyle
      if let originalHistory {
        defaults.set(originalHistory, forKey: PreferencesKeys.historyEnabled)
      } else {
        defaults.removeObject(forKey: PreferencesKeys.historyEnabled)
      }
    }

    defaults.set(true, forKey: PreferencesKeys.historyEnabled)
    manager.displayStyle = .traditional
    manager.isEnabled = true
    manager.isEdgeRevealEnabled = false
    XCTAssertFalse(manager.isEdgeRevealMonitoring)

    manager.isEdgeRevealEnabled = true
    XCTAssertTrue(manager.isEdgeRevealMonitoring)

    manager.isEnabled = false
    XCTAssertFalse(manager.isEdgeRevealMonitoring)

    manager.isEnabled = true
    manager.displayStyle = .hanging
    XCTAssertFalse(manager.isEdgeRevealMonitoring)

    defaults.set(false, forKey: PreferencesKeys.historyEnabled)
    manager.displayStyle = .traditional
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    XCTAssertFalse(manager.isEdgeRevealMonitoring)
  }
}
