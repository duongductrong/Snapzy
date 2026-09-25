//
//  VideoEditorWindowInputTests.swift
//  SnapzyTests
//
//  Regression tests for editor-window key-equivalent routing.
//

import AppKit
import AVKit
@testable import Snapzy
import SwiftUI
import XCTest

@MainActor
final class VideoEditorWindowInputTests: XCTestCase {
  func testUnhandledCommandCIsConsumedWithoutFallingThroughToWindowKeyDown() {
    let window = VideoEditorWindow(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 300)
    )
    guard let event = NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [.command],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      characters: "c",
      charactersIgnoringModifiers: "c",
      isARepeat: false,
      keyCode: 8
    ) else {
      XCTFail("Could not create Command-C event")
      return
    }

    XCTAssertTrue(window.performKeyEquivalent(with: event))
  }

  func testEscapeCancelsRenameWhenToolbarTextFieldIsFirstResponder() throws {
    let state = VideoEditorState(url: URL(fileURLWithPath: "/tmp/test-video.mov"))
    state.isRenamingFile = true

    let hostingView = NSHostingView(rootView: VideoEditorToolbarView(state: state))
    let window = VideoEditorWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 100)
    )
    window.contentView = hostingView
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }

    hostingView.layoutSubtreeIfNeeded()
    let textField = try XCTUnwrap(firstTextField(in: hostingView))
    XCTAssertTrue(window.makeFirstResponder(textField))

    let event = try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      characters: "\u{1B}",
      charactersIgnoringModifiers: "\u{1B}",
      isARepeat: false,
      keyCode: 53
    ))

    window.sendEvent(event)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

    XCTAssertFalse(state.isRenamingFile)
  }

  func testSpaceControlsEditorPlaybackWhenVideoViewHasFocus() throws {
    let state = VideoEditorState(url: URL(fileURLWithPath: "/tmp/test-video.mov"))
    let playerView = AVPlayerView()
    playerView.player = state.player
    playerView.controlsStyle = .none
    let window = VideoEditorWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 450)
    )
    window.contentView = playerView
    window.onTogglePlayback = { state.togglePlayback() }
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }
    XCTAssertTrue(window.makeFirstResponder(playerView))

    let event = try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      characters: " ",
      charactersIgnoringModifiers: " ",
      isARepeat: false,
      keyCode: 49
    ))
    window.sendEvent(event)

    XCTAssertTrue(state.isPlaying, "Space must use the editor's playback command")
    window.sendEvent(event)
    XCTAssertFalse(state.isPlaying, "A second Space must pause the same editor transport")
  }

  func testSpaceRemainsTextInputWhenRenamingFile() throws {
    let state = VideoEditorState(url: URL(fileURLWithPath: "/tmp/test-video.mov"))
    state.isRenamingFile = true
    let hostingView = NSHostingView(rootView: VideoEditorToolbarView(state: state))
    let window = VideoEditorWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 100)
    )
    window.onTogglePlayback = { state.togglePlayback() }
    window.contentView = hostingView
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }

    hostingView.layoutSubtreeIfNeeded()
    let textField = try XCTUnwrap(firstTextField(in: hostingView))
    XCTAssertTrue(window.makeFirstResponder(textField))
    let event = try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      characters: " ",
      charactersIgnoringModifiers: " ",
      isARepeat: false,
      keyCode: 49
    ))
    window.sendEvent(event)

    XCTAssertFalse(state.isPlaying, "Typing a space must not toggle playback")
  }

  private func firstTextField(in view: NSView) -> NSTextField? {
    if let textField = view as? NSTextField {
      return textField
    }

    for subview in view.subviews {
      if let textField = firstTextField(in: subview) {
        return textField
      }
    }

    return nil
  }
}
