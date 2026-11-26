//
//  AutomationCanvasGraphTests.swift
//  SnapzyTests
//
//  Canvas editor: graph ↔ automation round trip, linking rules, detached
//  chains, condition skip ranges kept across edits, and persistence.
//

import XCTest
@testable import Snapzy

@MainActor
final class AutomationCanvasGraphTests: XCTestCase {
  private func automation(_ steps: [AutomationStep]) -> Automation {
    Automation(
      name: "Canvas",
      source: .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: false)),
      steps: steps
    )
  }

  private func skip(_ step: AutomationStep?) -> Int? {
    guard case .condition(let config)? = step?.action, case .skip(let count) = config.otherwise else { return nil }
    return count
  }

  func testChainMatchesStepsAndRoundTrips() {
    let steps = [AutomationStep(.copyImage), AutomationStep(.notify), AutomationStep(.reveal)]
    let graph = AutomationCanvasGraph(automation: automation(steps))
    XCTAssertEqual(graph.chain, steps.map(\.id))
    XCTAssertTrue(graph.detachedChains.isEmpty)
    XCTAssertEqual(graph.applied(to: automation(steps)).steps, steps)
    // Trigger → source plus one link per step.
    XCTAssertEqual(graph.links.count, 4)
  }

  func testDisconnectDetachesTailAsOneChain() {
    let steps = [AutomationStep(.copyImage), AutomationStep(.notify), AutomationStep(.reveal)]
    var graph = AutomationCanvasGraph(automation: automation(steps))
    graph.disconnect(from: .step(steps[0].id))
    XCTAssertEqual(graph.chain, [steps[0].id])
    XCTAssertEqual(graph.detachedChains, [[steps[1].id, steps[2].id]])

    let applied = graph.applied(to: automation(steps))
    XCTAssertEqual(applied.steps.map(\.id), [steps[0].id])
    XCTAssertEqual(applied.canvas?.detached.map { $0.map(\.id) }, [[steps[1].id, steps[2].id]])

    // Reloading keeps the detached chain linked.
    let reloaded = AutomationCanvasGraph(automation: applied)
    XCTAssertEqual(reloaded.detachedChains, [[steps[1].id, steps[2].id]])

    // Linking it back restores the run order.
    var relinked = reloaded
    XCTAssertTrue(relinked.connect(from: .step(steps[0].id), to: .step(steps[1].id)))
    XCTAssertEqual(relinked.chain, steps.map(\.id))
  }

  func testConnectRejectsLoopsAndFixedNodes() {
    let steps = [AutomationStep(.copyImage), AutomationStep(.notify)]
    let graph = AutomationCanvasGraph(automation: automation(steps))
    XCTAssertFalse(graph.canConnect(from: .step(steps[1].id), to: .step(steps[0].id)), "closes a loop")
    XCTAssertFalse(graph.canConnect(from: .step(steps[0].id), to: .source))
    XCTAssertFalse(graph.canConnect(from: .trigger, to: .step(steps[0].id)))
    XCTAssertFalse(graph.canConnect(from: .step(steps[0].id), to: .step(steps[0].id)))
  }

  func testConnectSkippingNodeDetachesTheSkippedOne() {
    let steps = [AutomationStep(.copyImage), AutomationStep(.notify), AutomationStep(.reveal)]
    var graph = AutomationCanvasGraph(automation: automation(steps))
    XCTAssertTrue(graph.connect(from: .source, to: .step(steps[2].id)))
    XCTAssertEqual(graph.chain, [steps[2].id])
    XCTAssertEqual(Set(graph.detachedIDs), [steps[0].id, steps[1].id])
  }

  func testInsertOnLinkAndRemoveJoinsNeighbours() {
    let steps = [AutomationStep(.copyImage), AutomationStep(.notify)]
    var graph = AutomationCanvasGraph(automation: automation(steps))
    let inserted = AutomationStep(.reveal)
    graph.insert(inserted, after: .step(steps[0].id))
    XCTAssertEqual(graph.chain, [steps[0].id, inserted.id, steps[1].id])
    XCTAssertGreaterThan(graph.position(of: .step(steps[1].id)).x, graph.position(of: .step(inserted.id)).x)

    graph.remove(inserted.id)
    XCTAssertEqual(graph.chain, steps.map(\.id))
    XCTAssertNil(graph.positions[.step(inserted.id)])
  }

  func testSkipRangeFollowsInsertAndRemove() {
    let condition = AutomationStep(.condition(AutomationConditionConfig(
      predicates: [.frontmostApp(bundleIDs: ["com.figma.Desktop"], negate: false)],
      otherwise: .skip(2)
    )))
    let a = AutomationStep(.copyImage)
    let b = AutomationStep(.reveal)
    let after = AutomationStep(.notify)
    var graph = AutomationCanvasGraph(automation: automation([condition, a, b, after]))

    // Inside the branch: it grows.
    graph.insert(AutomationStep(.pin), after: .step(a.id))
    XCTAssertEqual(skip(graph.steps[condition.id]), 3)

    // After the branch: unchanged.
    graph.insert(AutomationStep(.copyFile), after: .step(after.id))
    XCTAssertEqual(skip(graph.steps[condition.id]), 3)

    // Removing a branch step shrinks it.
    graph.remove(b.id)
    XCTAssertEqual(skip(graph.steps[condition.id]), 2)
  }

  func testSkipToEndStaysOpenEnded() {
    let condition = AutomationStep(.condition(AutomationConditionConfig(
      predicates: [.frontmostApp(bundleIDs: ["com.figma.Desktop"], negate: false)],
      otherwise: .skip(5)
    )))
    let a = AutomationStep(.copyImage)
    var graph = AutomationCanvasGraph(automation: automation([condition, a]))
    graph.insert(AutomationStep(.notify), after: .step(a.id))
    XCTAssertEqual(skip(graph.steps[condition.id]), 5, "appended step joins the open-ended branch")
  }

  func testLayoutPersistsAndUnknownStepsArePlaced() throws {
    let steps = [AutomationStep(.copyImage)]
    var graph = AutomationCanvasGraph(automation: automation(steps))
    graph.positions[.step(steps[0].id)] = CGPoint(x: 1234, y: 56)
    var saved = graph.applied(to: automation(steps))
    // A step added by the list editor has no position yet.
    let added = AutomationStep(.notify)
    saved.steps.append(added)

    let data = try JSONEncoder().encode(saved)
    let decoded = try JSONDecoder().decode(Automation.self, from: data)
    XCTAssertEqual(decoded.canvas?.positions[steps[0].id.uuidString], AutomationCanvasPoint(x: 1234, y: 56))

    let reloaded = AutomationCanvasGraph(automation: decoded)
    XCTAssertEqual(reloaded.position(of: .step(steps[0].id)), CGPoint(x: 1234, y: 56))
    XCTAssertNotNil(reloaded.positions[.step(added.id)])
    XCTAssertEqual(reloaded.chain, [steps[0].id, added.id])
  }

  func testNormalizedPrunesLayoutAndCapsDetached() {
    var value = automation([AutomationStep(.copyImage)])
    let detached = (0..<(Automation.maxSteps + 5)).map { _ in AutomationStep(.notify) }
    value.canvas = AutomationCanvasLayout(
      positions: [UUID().uuidString: AutomationCanvasPoint(x: 1, y: 1), "source": AutomationCanvasPoint(x: 0, y: 0)],
      detached: [detached]
    )
    let normalized = value.normalized()
    XCTAssertEqual(normalized.canvas?.detachedStepCount, Automation.maxSteps - 1)
    XCTAssertEqual(normalized.canvas?.positions.keys.sorted(), ["source"])
  }

  func testRecipeDropsCanvas() throws {
    var value = automation([AutomationStep(.copyImage)])
    value.canvas = AutomationCanvasLayout(detached: [[AutomationStep(.runScript(AutomationRunScriptConfig()))]])
    let stripped = AutomationRecipeCodec.stripped(value, folderPath: { _ in nil })
    XCTAssertNil(stripped.canvas)
  }

  func testViewportZoomKeepsAnchorStill() {
    var viewport = AutomationCanvasViewport()
    viewport.offset = CGSize(width: 40, height: 20)
    let anchor = CGPoint(x: 300, y: 200)
    let before = viewport.toCanvas(anchor)
    viewport.zoom(by: 1.7, around: anchor)
    let after = viewport.toCanvas(anchor)
    XCTAssertEqual(before.x, after.x, accuracy: 0.001)
    XCTAssertEqual(before.y, after.y, accuracy: 0.001)

    viewport.zoom(by: 100, around: anchor)
    XCTAssertEqual(viewport.scale, AutomationCanvasViewport.maxScale)
  }
}
