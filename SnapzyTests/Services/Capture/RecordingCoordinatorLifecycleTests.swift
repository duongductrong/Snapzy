import AppKit
@testable import Snapzy
import Testing

@MainActor
@Suite(.serialized)
struct RecordingCoordinatorLifecycleTests {
  @Test(arguments: [(false, false), (true, false), (true, true)])
  func stopDuringOverlayRegistrationDoesNotReopenToolbar(
    scenario: (waitForCleanup: Bool, replaceSession: Bool)
  ) async throws {
    let savedArea = UserDefaults.standard.object(forKey: PreferencesKeys.recordingLastAreaRect)
    defer { UserDefaults.standard.set(savedArea, forKey: PreferencesKeys.recordingLastAreaRect) }
    let coordinator = RecordingCoordinator()
    let rect = CGRect(x: 100, y: 100, width: 640, height: 480)
    var sessionEnded: CheckedContinuation<Void, Never>?
    var didEnd = false
    coordinator.showToolbar(for: rect, onSessionEnded: {
      didEnd = true
      sessionEnded?.resume()
    })
    let window = try #require(coordinator.toolbarWindow)
    var registrations = 0

    let completed = await coordinator.completeRecordingStart(for: rect) { _ in
      registrations += 1
      guard registrations == 1 else { return }
      if scenario.waitForCleanup {
        // Suspend the real setup path until Stop has closed the original windows.
        await withCheckedContinuation { continuation in
          sessionEnded = continuation
          window.onStop?()
        }
      } else {
        // Stop must invalidate setup even before asynchronous cleanup runs.
        window.onStop?()
        #expect(coordinator.isActive)
      }
      if scenario.replaceSession {
        didEnd = false
        sessionEnded = nil
        coordinator.showToolbar(for: rect, onSessionEnded: {
          didEnd = true
          sessionEnded?.resume()
        })
      }
    }

    #expect(!completed)
    #expect(registrations == 1)
    if scenario.replaceSession {
      #expect(coordinator.toolbarWindow !== window)
      coordinator.cancel()
    }
    if !didEnd {
      await withCheckedContinuation { sessionEnded = $0 }
    }
    #expect(!window.isVisible)
    #expect(!coordinator.isActive)
    window.close()
  }

  @Test
  func completedSetupRegistersRetainedOverlaysAgain() async throws {
    let defaults = UserDefaults.standard
    let savedArea = defaults.object(forKey: PreferencesKeys.recordingLastAreaRect)
    let keys = [PreferencesKeys.recordingHighlightClicks, PreferencesKeys.recordingShowKeystrokes]
    let savedOptions = keys.map { defaults.object(forKey: $0) }
    defer {
      defaults.set(savedArea, forKey: PreferencesKeys.recordingLastAreaRect)
      for (key, value) in zip(keys, savedOptions) { defaults.set(value, forKey: key) }
    }
    for key in keys { defaults.set(true, forKey: key) }
    let coordinator = RecordingCoordinator()
    let rect = CGRect(x: 100, y: 100, width: 640, height: 480)
    var sessionEnded: CheckedContinuation<Void, Never>?
    coordinator.showToolbar(for: rect, onSessionEnded: { sessionEnded?.resume() })
    let window = try #require(coordinator.toolbarWindow)
    var firstRegistration: [CGWindowID] = []
    var secondRegistration: [CGWindowID] = []

    let started = await coordinator.completeRecordingStart(for: rect) {
      firstRegistration.append($0)
    }
    let restarted = await coordinator.completeRecordingStart(for: rect) {
      secondRegistration.append($0)
    }

    #expect(started && restarted)
    #expect(firstRegistration.count == 3)
    #expect(firstRegistration == secondRegistration)
    #expect(coordinator.toolbarWindow === window)
    #expect(window.isMovableByWindowBackground)
    await withCheckedContinuation { continuation in
      sessionEnded = continuation
      coordinator.cancel()
    }
  }
}
