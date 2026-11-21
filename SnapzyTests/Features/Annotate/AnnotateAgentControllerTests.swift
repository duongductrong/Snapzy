//
//  AnnotateAgentControllerTests.swift
//  SnapzyTests
//
//  Annotate AI prompt, phase 2: the run loop behind the dock (submit, stop, result,
//  undo, conversation) with a scripted provider, plus the debug mock's planning.
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class AnnotateAgentControllerTests: XCTestCase {
  private static var retained: [AnyObject] = []

  /// Calls a fixed list of tools; can wait on a gate to test Stop mid-run.
  private final class ScriptedProvider: AnnotateAgentProvider {
    let displayName = "Scripted"
    let symbolName = "hammer"
    var calls: [(String, String)]
    var reply = "Done."
    var error: Error?
    var gate: CheckedContinuation<Void, Never>?
    var waitsAfterFirstCall = false
    private(set) var requests: [AnnotateAgentRequest] = []
    private(set) var lastSession: AnnotateAgentSession?

    init(calls: [(String, String)]) {
      self.calls = calls
    }

    func run(_ request: AnnotateAgentRequest, session: AnnotateAgentSession) async throws -> String {
      requests.append(request)
      lastSession = session
      for (index, call) in calls.enumerated() {
        _ = try await session.callTool(call.0, arguments: call.1)
        if index == 0, waitsAfterFirstCall {
          await withCheckedContinuation { gate = $0 }
          try Task.checkCancellation()
        }
      }
      if let error { throw error }
      return reply
    }
  }

  private func makeState() throws -> AnnotateState {
    let state = AnnotateState()
    Self.retained.append(state)
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: 400, height: 300))
    state.loadImage(NSImage(cgImage: cgImage, size: NSSize(width: 400, height: 300)))
    return state
  }

  private func makeController(_ state: AnnotateState, provider: AnnotateAgentProvider?) -> AnnotateAgentController {
    let controller = AnnotateAgentController(state: state, pacingEnabled: false, resolveProvider: { provider })
    Self.retained.append(controller)
    return controller
  }

  private func waitUntilIdle(_ controller: AnnotateAgentController, file: StaticString = #filePath, line: UInt = #line) async {
    for _ in 0 ..< 400 where controller.isRunning {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertFalse(controller.isRunning, "run did not finish", file: file, line: line)
  }

  private let boxCall = ("add_box", #"{"target":{"rect":[10,10,50,40]}}"#)
  private let counterCall = ("add_counter", #"{"target":{"point":[200,150]}}"#)

  // MARK: - Runs

  func testSubmitRunsProviderAndReportsResult() async throws {
    let state = try makeState()
    let provider = ScriptedProvider(calls: [boxCall, counterCall])
    let controller = makeController(state, provider: provider)

    controller.draft = "  box it  "
    controller.submit()
    XCTAssertTrue(controller.isRunning)
    XCTAssertEqual(controller.draft, "")
    await waitUntilIdle(controller)

    XCTAssertEqual(state.annotations.count, 2)
    XCTAssertEqual(provider.requests.first?.prompt, "box it")
    XCTAssertTrue(provider.requests.first?.sceneJSON.contains("\"image\"") == true)
    XCTAssertEqual(controller.turns, [AnnotateAgentTurn(prompt: "box it", reply: "Done.")])
    XCTAssertEqual(controller.notice, .finished(message: "Done.", changeCount: 2, canUndo: true))
    XCTAssertEqual(state.selectedAnnotationIds, Set(state.annotations.map(\.id)))
  }

  func testUndoLastRunRevertsAnnotationsAndCanvasInOneStep() async throws {
    let state = try makeState()
    state.padding = 0
    let provider = ScriptedProvider(calls: [boxCall, ("set_canvas", #"{"background":"pinkOrange"}"#)])
    let controller = makeController(state, provider: provider)
    controller.draft = "style it"
    controller.submit()
    await waitUntilIdle(controller)
    XCTAssertEqual(state.padding, 48)
    XCTAssertTrue(controller.canUndoLastRun)

    controller.undoLastRun()
    XCTAssertTrue(state.annotations.isEmpty)
    XCTAssertEqual(state.padding, 0)
    XCTAssertEqual(state.backgroundStyle, .none)
    XCTAssertNil(controller.notice)
    XCTAssertFalse(controller.canUndoLastRun)
  }

  func testUndoIsWithdrawnOnceTheUserEdits() async throws {
    let state = try makeState()
    let controller = makeController(state, provider: ScriptedProvider(calls: [boxCall]))
    controller.draft = "box"
    controller.submit()
    await waitUntilIdle(controller)
    XCTAssertTrue(controller.canUndoLastRun)

    state.annotations.append(AnnotationItem(type: .oval, bounds: CGRect(x: 0, y: 0, width: 9, height: 9), properties: AnnotationProperties()))
    XCTAssertFalse(controller.canUndoLastRun)
    controller.undoLastRun()
    XCTAssertEqual(state.annotations.count, 2, "the user's own edit is never undone by the run's Undo")
  }

  func testStopKeepsChangesSoFarAndIgnoresLateResults() async throws {
    let state = try makeState()
    let provider = ScriptedProvider(calls: [boxCall, counterCall])
    provider.waitsAfterFirstCall = true
    let controller = makeController(state, provider: provider)
    controller.draft = "two things"
    controller.submit()
    for _ in 0 ..< 200 where provider.gate == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertEqual(state.annotations.count, 1)

    controller.stop()
    XCTAssertFalse(controller.isRunning)
    XCTAssertEqual(controller.notice, .stopped(changeCount: 1, canUndo: true))
    provider.gate?.resume()
    try await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertEqual(state.annotations.count, 1, "nothing lands after Stop")
    XCTAssertTrue(controller.turns.isEmpty)
  }

  func testProviderFailureShowsMessageAndKeepsChanges() async throws {
    let state = try makeState()
    let provider = ScriptedProvider(calls: [boxCall])
    provider.error = AnnotateAgentProviderError.failed("Quota exceeded")
    let controller = makeController(state, provider: provider)
    controller.draft = "box"
    controller.submit()
    await waitUntilIdle(controller)
    XCTAssertEqual(controller.notice, .failed(message: "Quota exceeded", offersSettings: false))
    XCTAssertEqual(state.annotations.count, 1)
    XCTAssertTrue(controller.canUndoLastRun)
  }

  func testNoProviderExplainsSetup() throws {
    let state = try makeState()
    let controller = makeController(state, provider: nil)
    controller.draft = "box"
    controller.submit()
    XCTAssertFalse(controller.isRunning)
    XCTAssertEqual(controller.notice, .failed(message: L10n.AnnotateAI.notConfigured, offersSettings: true))
    XCTAssertEqual(controller.draft, "box", "the prompt is kept so it can be sent once AI is set up")
  }

  func testFollowUpCarriesHistoryAndStableIDs() async throws {
    let state = try makeState()
    let provider = ScriptedProvider(calls: [boxCall])
    let controller = makeController(state, provider: provider)
    controller.draft = "box"
    controller.submit()
    await waitUntilIdle(controller)

    provider.calls = [("update_annotation", #"{"id":"a1","color":"blue"}"#)]
    controller.draft = "make it blue"
    controller.submit()
    await waitUntilIdle(controller)

    XCTAssertEqual(provider.requests.last?.history.map(\.prompt), ["box"])
    XCTAssertEqual(AnnotateAgentColor.describe(try XCTUnwrap(state.annotations.first).properties.strokeColor), "blue")
    XCTAssertEqual(controller.turns.count, 2)

    controller.startNewConversation()
    XCTAssertTrue(controller.turns.isEmpty)
  }

  func testEscapeClearsDraftThenLeavesPrompt() throws {
    let state = try makeState()
    let controller = makeController(state, provider: ScriptedProvider(calls: []))
    controller.isPromptPresented = true
    controller.draft = "half typed"
    controller.handleEscape()
    XCTAssertEqual(controller.draft, "")
    XCTAssertTrue(controller.isPromptPresented)
    controller.handleEscape()
    XCTAssertFalse(controller.isPromptPresented)
  }

  func testOverlayMarksFollowTargetsAndAdditions() async throws {
    let state = try makeState()
    let controller = makeController(state, provider: ScriptedProvider(calls: [boxCall]))
    controller.draft = "box"
    controller.submit()
    await waitUntilIdle(controller)
    XCTAssertEqual(controller.marks.map(\.kind), [.target, .added])
  }

  func testShortcutDefaultsToCommandK() {
    let config = AnnotateShortcutManager.defaultAIPrompt
    XCTAssertEqual(config.keyCode, 40)
    XCTAssertEqual(config.modifiers, UInt32(256)) // cmdKey
  }

  // MARK: - Review regressions

  func testStopWhileReadingAFollowUpReportsNothingFromThePreviousRun() async throws {
    let state = try makeState()
    let controller = makeController(state, provider: ScriptedProvider(calls: [boxCall, counterCall]))
    controller.draft = "first"
    controller.submit()
    await waitUntilIdle(controller)
    state.setSelectedAnnotationIds([])

    controller.draft = "second"
    controller.submit()
    XCTAssertEqual(controller.phase, .reading)
    controller.stop()

    XCTAssertEqual(controller.notice, .stopped(changeCount: 0, canUndo: false))
    XCTAssertFalse(controller.canUndoLastRun)
    XCTAssertTrue(state.selectedAnnotationIds.isEmpty, "the previous run's items are not re-selected")
  }

  func testLateToolCallsAfterStopAreRejected() async throws {
    let state = try makeState()
    let provider = ScriptedProvider(calls: [boxCall])
    let controller = makeController(state, provider: provider)
    controller.draft = "box"
    controller.submit()
    await waitUntilIdle(controller)
    let session = try XCTUnwrap(provider.lastSession)

    do {
      _ = try await session.callTool("add_box", arguments: #"{"target":{"point":[50,50]}}"#)
      XCTFail("a finished run's session must not reach the canvas")
    } catch is CancellationError {}
    XCTAssertEqual(state.annotations.count, 1)
  }

  func testUndoIsWithdrawnAfterUserCanvasEditOrNewUndoStep() async throws {
    let state = try makeState()
    let controller = makeController(state, provider: ScriptedProvider(calls: [("set_canvas", #"{"shadow":0.9}"#)]))
    controller.draft = "shadow"
    controller.submit()
    await waitUntilIdle(controller)
    XCTAssertTrue(controller.canUndoLastRun)
    state.shadowIntensity = 0.1
    XCTAssertFalse(controller.canUndoLastRun, "the user's own canvas edit is never reverted")

    let boxes = makeController(state, provider: ScriptedProvider(calls: [boxCall]))
    boxes.draft = "box"
    boxes.submit()
    await waitUntilIdle(boxes)
    XCTAssertTrue(boxes.canUndoLastRun)
    state.saveState() // e.g. a rotate or crop pushed its own undo entry
    XCTAssertFalse(boxes.canUndoLastRun)
  }

  func testUndoAndTranslateAreBlockedWhileRunning() async throws {
    let state = try makeState()
    let provider = ScriptedProvider(calls: [boxCall, counterCall])
    provider.waitsAfterFirstCall = true
    let controller = AnnotateAgentController(state: state, pacingEnabled: false, resolveProvider: { provider })
    Self.retained.append(controller)
    state.agent = controller
    controller.draft = "two"
    controller.submit()
    for _ in 0 ..< 200 where provider.gate == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertFalse(state.canAutoTranslate)
    state.undo()
    XCTAssertEqual(state.annotations.count, 1, "⌘Z waits until the run ends")
    provider.gate?.resume()
    await waitUntilIdle(controller)
    XCTAssertTrue(state.canAutoTranslate)
  }

  // MARK: - Debug mock

  func testMockPlansFromKeywordsAndQuotedTargets() {
    let texts = [
      AnnotateAgentMockProvider.SceneText(id: "t1", text: "Invalid password. Try again."),
      AnnotateAgentMockProvider.SceneText(id: "t2", text: "Email"),
      AnnotateAgentMockProvider.SceneText(id: "t3", text: "Password"),
      AnnotateAgentMockProvider.SceneText(id: "t4", text: "tran@example.com"),
    ]
    let steps = AnnotateAgentMockProvider.plan(for: #"Đánh số "Email", "Password""#, texts: texts, annotationIDs: [])
    XCTAssertEqual(steps.map(\.name), ["add_counter", "add_counter"])
    XCTAssertTrue(steps[1].arguments.contains("t3"), "exact match wins over a longer block containing the word")

    let blur = AnnotateAgentMockProvider.plan(for: "blur the email", texts: texts, annotationIDs: [])
    XCTAssertEqual(blur, [AnnotateAgentMockProvider.Call(name: "add_blur", arguments: #"{"target":"t4"}"#)])

    XCTAssertEqual(AnnotateAgentMockProvider.quotedPhrases(in: #"circle “Sign in” and "OK""#), ["Sign in", "OK"])
  }
}
