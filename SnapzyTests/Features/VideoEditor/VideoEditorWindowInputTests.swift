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
  private var testVideoURL: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("docs/attachments/pin-drag-macos-27-demo.mp4")
  }

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
    let state = VideoEditorState(url: testVideoURL)
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
    let playerView = AVPlayerView()
    playerView.player = AVPlayer()
    playerView.controlsStyle = .none
    var isPlaying = false
    let window = VideoEditorWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 450)
    )
    window.contentView = playerView
    window.onTogglePlayback = { isPlaying.toggle() }
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

    XCTAssertTrue(isPlaying, "Space must use the editor's playback command")
    window.sendEvent(event)
    XCTAssertFalse(isPlaying, "A second Space must pause the same editor transport")
  }

  func testSpaceRemainsTextInputWhenRenamingFile() throws {
    let state = VideoEditorState(url: testVideoURL)
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

  func testTransportKeysJKLCommaPeriodBypassAVPlayerViewAndYieldToTextField() throws {
    let playerView = AVPlayerView()
    playerView.player = AVPlayer()
    playerView.controlsStyle = .none
    var received: [VideoEditorWindow.TransportKey] = []

    let window = VideoEditorWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 450)
    )
    window.contentView = playerView
    window.onTransportKey = { key in
      received.append(key)
      return true
    }
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }
    XCTAssertTrue(window.makeFirstResponder(playerView))

    let cases: [(String, UInt16, VideoEditorWindow.TransportKey)] = [
      ("j", 38, .shuttleReverse),
      ("k", 40, .shuttlePause),
      ("l", 37, .shuttleForward),
      (",", 43, .stepBackward),
      (".", 47, .stepForward),
    ]
    for (char, code, _) in cases {
      let ev = try XCTUnwrap(NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        characters: char,
        charactersIgnoringModifiers: char,
        isARepeat: false,
        keyCode: code
      ))
      window.sendEvent(ev)
    }
    XCTAssertEqual(received, cases.map(\.2), "J/K/L/,/. must reach editor transport ahead of AVPlayerView")

    // When an NSTextField is first responder, J/K/L/,/. must remain text input.
    received.removeAll()
    let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
    window.contentView = textField
    XCTAssertTrue(window.makeFirstResponder(textField))
    for (char, code, _) in cases {
      let ev = try XCTUnwrap(NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        characters: char,
        charactersIgnoringModifiers: char,
        isARepeat: false,
        keyCode: code
      ))
      window.sendEvent(ev)
    }
    XCTAssertTrue(received.isEmpty, "Typing J/K/L/,/. inside a text field must never trigger transport shortcuts")
  }

  func testPlainKeyEditorShortcutsTMNBracketsYieldToTextField() throws {
    let playerView = AVPlayerView()
    playerView.player = AVPlayer()
    playerView.controlsStyle = .none
    var received: [VideoEditorWindow.TransportKey] = []

    let window = VideoEditorWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 450)
    )
    window.contentView = playerView
    window.onTransportKey = { key in
      received.append(key)
      return true
    }
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }
    XCTAssertTrue(window.makeFirstResponder(playerView))

    let cases: [(String, UInt16, VideoEditorWindow.TransportKey)] = [
      ("t", 17, .addTextOverlay),
      ("m", 46, .toggleBookmark),
      ("n", 45, .toggleSnapping),
      ("[", 33, .trimStartToPlayhead),
      ("]", 30, .trimEndToPlayhead),
    ]
    for (char, code, _) in cases {
      let ev = try XCTUnwrap(NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        characters: char,
        charactersIgnoringModifiers: char,
        isARepeat: false,
        keyCode: code
      ))
      window.sendEvent(ev)
    }
    XCTAssertEqual(received, cases.map(\.2), "T / M / N / [ / ] must route when player view is focused")

    received.removeAll()
    let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
    window.contentView = textField
    XCTAssertTrue(window.makeFirstResponder(textField))
    for (char, code, _) in cases {
      let ev = try XCTUnwrap(NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        characters: char,
        charactersIgnoringModifiers: char,
        isARepeat: false,
        keyCode: code
      ))
      window.sendEvent(ev)
    }
    XCTAssertTrue(received.isEmpty, "Typing T / M / N / [ / ] in a text field must never trigger shortcuts")
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
