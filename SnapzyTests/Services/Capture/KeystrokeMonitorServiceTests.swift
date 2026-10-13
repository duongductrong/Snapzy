import AppKit
import CoreGraphics
@testable import Snapzy
import Testing

@MainActor
struct KeystrokeMonitorServiceTests {
  @Test(arguments: [CGEventType.flagsChanged, .tapDisabledByTimeout, .tapDisabledByUserInput])
  func lostAppKitReleaseDoesNotExposePlainTyping(resetEventType: CGEventType) throws {
    let service = KeystrokeMonitorService()
    service.handleModifierFlagsChanged([.command])
    var keystrokes: [String] = []
    service.onKeystroke = { keystrokes.append($0) }
    let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 35, keyDown: true))
    event.flags = []

    // The head tap sees the release, but the remapper consumes it before AppKit.
    _ = service.handleTapEvent(type: resetEventType, event: event)
    _ = service.handleTapEvent(type: .keyDown, event: event)

    #expect(keystrokes.isEmpty)
  }

  @Test
  func headSessionTapObservesShortcutWithoutConsumingIt() throws {
    #expect(KeystrokeMonitorService.tapLocation == .cgSessionEventTap)
    #expect(KeystrokeMonitorService.tapPlacement == .headInsertEventTap)
    #expect(KeystrokeMonitorService.tapOptions == .defaultTap)
    #expect(KeystrokeMonitorService.eventMask & (CGEventMask(1) << CGEventType.flagsChanged.rawValue) != 0)

    let service = KeystrokeMonitorService()
    let event = try #require(
      CGEvent(keyboardEventSource: nil, virtualKey: 123, keyDown: true)
    )

    let forwarded = service.handleTapEvent(type: .keyDown, event: event)

    #expect(forwarded?.takeUnretainedValue() === event)
  }

  @Test(arguments: [
    (CGKeyCode(18), "1"),
    (CGKeyCode(124), "→"),
  ])
  func tapCombinesDownstreamModifierRewrite(testCase: (keyCode: CGKeyCode, key: String)) throws {
    let service = KeystrokeMonitorService()
    var keystrokes: [String] = []
    service.onKeystroke = { keystrokes.append($0) }
    let event = try #require(
      CGEvent(keyboardEventSource: nil, virtualKey: testCase.keyCode, keyDown: true)
    )
    event.flags = []
    _ = service.handleTapEvent(type: .flagsChanged, event: event)
    service.handleModifierFlagsChanged([.control, .option, .command])

    _ = service.handleTapEvent(type: .keyDown, event: event)

    #expect(keystrokes == ["⌃ ⌥ ⌘ \(testCase.key)"])
  }
}
