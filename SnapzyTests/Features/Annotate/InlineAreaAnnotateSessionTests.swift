//
//  InlineAreaAnnotateSessionTests.swift
//  SnapzyTests
//
//  Unit tests for InlineAreaAnnotateSession coordinate conversion helpers.
//

import AppKit
import CoreGraphics
import XCTest
@testable import Snapzy

final class InlineAreaAnnotateSessionTests: XCTestCase {

  // MARK: - desktopFrame

  func testDesktopFrame_unionsScreenFrames() {
    let frames = [
      CGRect(x: 0, y: 0, width: 1000, height: 600),
      CGRect(x: 1000, y: 100, width: 800, height: 500)
    ]
    let desktop = InlineAreaAnnotateSession.desktopFrame(for: frames)
    XCTAssertEqual(desktop.minX, 0)
    XCTAssertEqual(desktop.maxX, 1800)
    XCTAssertEqual(desktop.minY, 0)
    XCTAssertEqual(desktop.maxY, 600)
  }

  // MARK: - localFrame / screenRect / localRect

  func testLocalFrame_convertsScreenToLocal() {
    let desktop = CGRect(x: 0, y: 0, width: 2000, height: 1200)
    let screen = CGRect(x: 1000, y: 100, width: 800, height: 500)
    let local = InlineAreaAnnotateSession.localFrame(for: screen, in: desktop)
    XCTAssertEqual(local.minX, 1000)
    XCTAssertEqual(local.minY, 600) // desktop.maxY - screen.maxY = 1200 - 600
    XCTAssertEqual(local.width, 800)
    XCTAssertEqual(local.height, 500)
  }

  func testScreenRect_convertsLocalToScreen() {
    let desktop = CGRect(x: 0, y: 0, width: 2000, height: 1200)
    let local = CGRect(x: 1000, y: 600, width: 800, height: 500)
    let screen = InlineAreaAnnotateSession.screenRect(for: local, in: desktop)
    XCTAssertEqual(screen.minX, 1000)
    XCTAssertEqual(screen.minY, 100) // desktop.maxY - local.maxY = 1200 - 1100
    XCTAssertEqual(screen.width, 800)
    XCTAssertEqual(screen.height, 500)
  }

  func testLocalRect_roundTrips() {
    let desktop = CGRect(x: 0, y: 0, width: 2000, height: 1200)
    let screen = CGRect(x: 500, y: 200, width: 400, height: 300)
    let local = InlineAreaAnnotateSession.localFrame(for: screen, in: desktop)
    let back = InlineAreaAnnotateSession.screenRect(for: local, in: desktop)
    XCTAssertEqual(back.minX, screen.minX, accuracy: 0.001)
    XCTAssertEqual(back.minY, screen.minY, accuracy: 0.001)
    XCTAssertEqual(back.width, screen.width, accuracy: 0.001)
    XCTAssertEqual(back.height, screen.height, accuracy: 0.001)
  }

  // MARK: - displayIDsIntersecting

  func testDisplayIDsIntersecting_findsIntersecting() {
    let frames: [CGDirectDisplayID: CGRect] = [
      1: CGRect(x: 0, y: 0, width: 1000, height: 600),
      2: CGRect(x: 1000, y: 0, width: 800, height: 600)
    ]
    let rect = CGRect(x: 1100, y: 100, width: 200, height: 200)
    let ids = InlineAreaAnnotateSession.displayIDsIntersecting(rect, screenFramesByDisplayID: frames)
    XCTAssertEqual(ids.count, 1)
    XCTAssertTrue(ids.contains(2))
  }

  func testDisplayIDsIntersecting_emptyWhenNoOverlap() {
    let frames: [CGDirectDisplayID: CGRect] = [
      1: CGRect(x: 0, y: 0, width: 100, height: 100)
    ]
    let rect = CGRect(x: 200, y: 200, width: 50, height: 50)
    let ids = InlineAreaAnnotateSession.displayIDsIntersecting(rect, screenFramesByDisplayID: frames)
    XCTAssertTrue(ids.isEmpty)
  }

  // MARK: - primaryDisplayID

  func testPrimaryDisplayID_returnsLargestOverlap() {
    let frames: [CGDirectDisplayID: CGRect] = [
      1: CGRect(x: 0, y: 0, width: 1000, height: 600),
      2: CGRect(x: 1000, y: 0, width: 800, height: 600)
    ]
    let rect = CGRect(x: 1050, y: 100, width: 400, height: 400)
    let id = InlineAreaAnnotateSession.primaryDisplayID(
      for: rect,
      screenFramesByDisplayID: frames,
      fallback: 99
    )
    XCTAssertEqual(id, 2)
  }

  func testPrimaryDisplayID_usesFallbackWhenNoOverlap() {
    let frames: [CGDirectDisplayID: CGRect] = [
      1: CGRect(x: 0, y: 0, width: 100, height: 100)
    ]
    let rect = CGRect(x: 200, y: 200, width: 50, height: 50)
    let id = InlineAreaAnnotateSession.primaryDisplayID(
      for: rect,
      screenFramesByDisplayID: frames,
      fallback: 99
    )
    XCTAssertEqual(id, 99)
  }

  // MARK: - Shortcut matching

  func testInlineShortcutMatchersRecognizeCommandSaveAndCopy() throws {
    let save = try makeKeyEvent(keyCode: 1, characters: "s", flags: .command)
    let copy = try makeKeyEvent(keyCode: 8, characters: "c", flags: .command)

    XCTAssertTrue(InlineAreaAnnotateSession.matchesCommandSaveShortcut(save))
    XCTAssertTrue(InlineAreaAnnotateSession.matchesCommandCopyShortcut(copy))
  }

  func testInlineCopyShortcutRequiresPlainCommandModifier() throws {
    let shiftCopy = try makeKeyEvent(keyCode: 8, characters: "C", flags: [.command, .shift])
    let optionCopy = try makeKeyEvent(keyCode: 8, characters: "c", flags: [.command, .option])
    let capsLockCopy = try makeKeyEvent(keyCode: 8, characters: "c", flags: [.command, .capsLock])

    XCTAssertFalse(InlineAreaAnnotateSession.matchesCommandCopyShortcut(shiftCopy))
    XCTAssertFalse(InlineAreaAnnotateSession.matchesCommandCopyShortcut(optionCopy))
    XCTAssertTrue(InlineAreaAnnotateSession.matchesCommandCopyShortcut(capsLockCopy))
  }

  func testInlineCopyShortcutRequiresLocalEventOrKeyWindow() throws {
    let copy = try makeKeyEvent(keyCode: 8, characters: "c", flags: .command)

    XCTAssertTrue(InlineAreaAnnotateSession.shouldHandleCommandCopyShortcut(
      copy,
      isLocalEvent: true,
      hasTextResponder: false,
      hasKeyWindow: false
    ))
    XCTAssertTrue(InlineAreaAnnotateSession.shouldHandleCommandCopyShortcut(
      copy,
      isLocalEvent: false,
      hasTextResponder: false,
      hasKeyWindow: true
    ))
    XCTAssertFalse(InlineAreaAnnotateSession.shouldHandleCommandCopyShortcut(
      copy,
      isLocalEvent: false,
      hasTextResponder: false,
      hasKeyWindow: false
    ))
    XCTAssertFalse(InlineAreaAnnotateSession.shouldHandleCommandCopyShortcut(
      copy,
      isLocalEvent: true,
      hasTextResponder: true,
      hasKeyWindow: true
    ))
  }

  func testInlineKeyActionKeepsTextCopyNative() throws {
    let copy = try makeKeyEvent(keyCode: 8, characters: "c", flags: .command)

    XCTAssertEqual(
      InlineAreaAnnotateSession.keyAction(
        for: copy,
        source: .local,
        phase: .annotating,
        hasTextResponder: true,
        hasKeyWindow: true
      ),
      .passThrough
    )
  }

  func testAnnotateObjectShortcutsRouteOnlyPlainCommandKeyDown() throws {
    let copy = try makeKeyEvent(keyCode: 8, characters: "c", flags: .command)
    let layoutAwareCopy = try makeKeyEvent(keyCode: 99, characters: "c", flags: .command)
    let keyCodeFallbackCopy = try makeKeyEvent(keyCode: 8, characters: "", flags: .command)
    let mismatchedKeyCode = try makeKeyEvent(keyCode: 8, characters: "x", flags: .command)
    let paste = try makeKeyEvent(keyCode: 9, characters: "v", flags: .command)
    let duplicate = try makeKeyEvent(keyCode: 2, characters: "d", flags: .command)
    let shiftCopy = try makeKeyEvent(keyCode: 8, characters: "C", flags: [.command, .shift])
    let keyUp = try makeKeyEvent(type: .keyUp, keyCode: 8, characters: "c", flags: .command)

    XCTAssertEqual(AnnotateWindow.annotationObjectShortcut(for: copy, isTextInputActive: false), .copy)
    XCTAssertEqual(AnnotateWindow.annotationObjectShortcut(for: layoutAwareCopy, isTextInputActive: false), .copy)
    XCTAssertEqual(AnnotateWindow.annotationObjectShortcut(for: keyCodeFallbackCopy, isTextInputActive: false), .copy)
    XCTAssertNil(AnnotateWindow.annotationObjectShortcut(for: mismatchedKeyCode, isTextInputActive: false))
    XCTAssertEqual(AnnotateWindow.annotationObjectShortcut(for: paste, isTextInputActive: false), .paste)
    XCTAssertEqual(AnnotateWindow.annotationObjectShortcut(for: duplicate, isTextInputActive: false), .duplicate)
    XCTAssertNil(AnnotateWindow.annotationObjectShortcut(for: shiftCopy, isTextInputActive: false))
    XCTAssertNil(AnnotateWindow.annotationObjectShortcut(for: keyUp, isTextInputActive: false))
  }

  func testAnnotateObjectShortcutsKeepTextAndInputFieldCommandsNative() throws {
    let copy = try makeKeyEvent(keyCode: 8, characters: "c", flags: .command)
    let paste = try makeKeyEvent(keyCode: 9, characters: "v", flags: .command)
    let duplicate = try makeKeyEvent(keyCode: 2, characters: "d", flags: .command)

    XCTAssertNil(AnnotateWindow.annotationObjectShortcut(for: copy, isTextInputActive: true))
    XCTAssertNil(AnnotateWindow.annotationObjectShortcut(for: paste, isTextInputActive: true))
    XCTAssertNil(AnnotateWindow.annotationObjectShortcut(for: duplicate, isTextInputActive: true))
  }

  @MainActor
  func testAnnotateWindowConsumesCopyAndDuplicateWhenNothingIsSelected() throws {
    try skipIfRunningInCI(
      "Exercises NSWindow key-equivalent routing, which is unreliable on headless CI runners"
    )
    let state = AnnotateState()
    let window = AnnotateWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600))
    window.interactionState = state
    let copy = try makeKeyEvent(keyCode: 8, characters: "c", flags: .command)
    let duplicate = try makeKeyEvent(keyCode: 2, characters: "d", flags: .command)

    XCTAssertTrue(window.performKeyEquivalent(with: copy))
    XCTAssertTrue(window.performKeyEquivalent(with: duplicate))
    XCTAssertFalse(state.canUndo)
  }

  func testInlineKeyActionGatesGlobalCopyByKeyWindow() throws {
    let copy = try makeKeyEvent(keyCode: 8, characters: "c", flags: .command)

    XCTAssertEqual(
      InlineAreaAnnotateSession.keyAction(
        for: copy,
        source: .global,
        phase: .annotating,
        hasTextResponder: false,
        hasKeyWindow: false
      ),
      .passThrough
    )
    XCTAssertEqual(
      InlineAreaAnnotateSession.keyAction(
        for: copy,
        source: .global,
        phase: .annotating,
        hasTextResponder: false,
        hasKeyWindow: true
      ),
      .copyCurrentImage
    )
  }

  func testInlineKeyAction_plainCDuringSelecting_returnsCopyMagnifierColor() throws {
    let copy = try makeKeyEvent(keyCode: 8, characters: "c", flags: [])

    XCTAssertEqual(
      InlineAreaAnnotateSession.keyAction(
        for: copy,
        source: .local,
        phase: .selecting,
        hasTextResponder: false,
        hasKeyWindow: true
      ),
      .copyMagnifierColor
    )
  }

  func testInlineKeyAction_modifiedCDuringSelecting_passesThrough() throws {
    let commandC = try makeKeyEvent(keyCode: 8, characters: "c", flags: .command)

    XCTAssertEqual(
      InlineAreaAnnotateSession.keyAction(
        for: commandC,
        source: .local,
        phase: .selecting,
        hasTextResponder: false,
        hasKeyWindow: true
      ),
      .passThrough
    )
  }

  func testInlineKeyAction_plainCDuringAnnotating_isUnaffected() throws {
    // The magnifier only exists during `.selecting`; once annotating, plain "C" must not be
    // swallowed (it still falls through to `.passThrough` as before this feature existed).
    let copy = try makeKeyEvent(keyCode: 8, characters: "c", flags: [])

    XCTAssertEqual(
      InlineAreaAnnotateSession.keyAction(
        for: copy,
        source: .local,
        phase: .annotating,
        hasTextResponder: false,
        hasKeyWindow: true
      ),
      .passThrough
    )
  }

  func testInlineKeyActionKeepsSaveWhileTextEditing() throws {
    let save = try makeKeyEvent(keyCode: 1, characters: "s", flags: .command)

    XCTAssertEqual(
      InlineAreaAnnotateSession.keyAction(
        for: save,
        source: .local,
        phase: .annotating,
        hasTextResponder: true,
        hasKeyWindow: true
      ),
      .finish
    )
  }

  func testInlineKeyActionResetsMoveModifierWhileTextEditing() throws {
    let spaceUp = try makeKeyEvent(type: .keyUp, keyCode: 49, characters: " ", flags: [])

    XCTAssertEqual(
      InlineAreaAnnotateSession.keyAction(
        for: spaceUp,
        source: .local,
        phase: .annotating,
        hasTextResponder: true,
        hasKeyWindow: true
      ),
      .resetMoveModifierAndPassThrough
    )
  }

  func testInlineShortcutMatchersIgnoreKeyUpEvents() throws {
    let saveKeyUp = try makeKeyEvent(type: .keyUp, keyCode: 1, characters: "s", flags: .command)
    let copyKeyUp = try makeKeyEvent(type: .keyUp, keyCode: 8, characters: "c", flags: .command)

    XCTAssertFalse(InlineAreaAnnotateSession.matchesCommandSaveShortcut(saveKeyUp))
    XCTAssertFalse(InlineAreaAnnotateSession.matchesCommandCopyShortcut(copyKeyUp))
  }

  func testInlineShortcutMatchersPreserveFinishCancelAndMoveKeys() throws {
    let returnKey = try makeKeyEvent(keyCode: 36, characters: "\r", flags: [])
    let escapeKey = try makeKeyEvent(keyCode: 53, characters: "\u{1b}", flags: [])
    let spaceDown = try makeKeyEvent(keyCode: 49, characters: " ", flags: [])
    let spaceUp = try makeKeyEvent(type: .keyUp, keyCode: 49, characters: " ", flags: [])

    XCTAssertTrue(InlineAreaAnnotateSession.matchesFinishShortcut(returnKey))
    XCTAssertTrue(InlineAreaAnnotateSession.matchesCancelShortcut(escapeKey))
    XCTAssertTrue(InlineAreaAnnotateSession.matchesMoveModifierKey(spaceDown))
    XCTAssertTrue(InlineAreaAnnotateSession.matchesMoveModifierKey(spaceUp))
  }

  private func makeKeyEvent(
    type: NSEvent.EventType = .keyDown,
    keyCode: UInt16,
    characters: String,
    flags: NSEvent.ModifierFlags
  ) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(
      with: type,
      location: .zero,
      modifierFlags: flags,
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: characters,
      charactersIgnoringModifiers: characters.lowercased(),
      isARepeat: false,
      keyCode: keyCode
    ))
  }
}
