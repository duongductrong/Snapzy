import AppKit
import CoreGraphics
@testable import Snapzy
import Testing

@MainActor
struct KeystrokeMonitorServiceTests {
  @Test
  func headSessionTapObservesShortcutWithoutConsumingIt() throws {
    #expect(KeystrokeMonitorService.tapLocation == .cgSessionEventTap)
    #expect(KeystrokeMonitorService.tapPlacement == .headInsertEventTap)
    #expect(KeystrokeMonitorService.tapOptions == .defaultTap)

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
    service.handleModifierFlagsChanged([.control, .option, .command])
    var keystrokes: [String] = []
    service.onKeystroke = { keystrokes.append($0) }
    let event = try #require(
      CGEvent(keyboardEventSource: nil, virtualKey: testCase.keyCode, keyDown: true)
    )

    _ = service.handleTapEvent(type: .keyDown, event: event)

    #expect(keystrokes == ["⌃ ⌥ ⌘ \(testCase.key)"])
  }
}
