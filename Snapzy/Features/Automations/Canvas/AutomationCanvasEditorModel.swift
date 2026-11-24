//
//  AutomationCanvasEditorModel.swift
//  Snapzy
//
//  State behind one canvas editor window: the automation draft, its node graph,
//  selection, viewport (pan + zoom) and the transient gestures (connecting,
//  the add-node picker). Save hands a normalized automation back to the window.
//

import Combine
import SwiftUI

/// Pan and zoom: `screen = canvas * scale + offset`.
struct AutomationCanvasViewport: Equatable {
  static let minScale: CGFloat = 0.25
  static let maxScale: CGFloat = 2

  var scale: CGFloat = 1
  var offset: CGSize = .zero

  func toScreen(_ point: CGPoint) -> CGPoint {
    CGPoint(x: point.x * scale + offset.width, y: point.y * scale + offset.height)
  }

  func toCanvas(_ point: CGPoint) -> CGPoint {
    CGPoint(x: (point.x - offset.width) / scale, y: (point.y - offset.height) / scale)
  }

  func toScreen(_ rect: CGRect) -> CGRect {
    CGRect(origin: toScreen(rect.origin), size: CGSize(width: rect.width * scale, height: rect.height * scale))
  }

  /// Zooms by `factor`, keeping the canvas point under `anchor` (screen) still.
  mutating func zoom(by factor: CGFloat, around anchor: CGPoint) {
    let newScale = min(Self.maxScale, max(Self.minScale, scale * factor))
    guard newScale != scale else { return }
    let ratio = newScale / scale
    offset = CGSize(
      width: anchor.x - (anchor.x - offset.width) * ratio,
      height: anchor.y - (anchor.y - offset.height) * ratio
    )
    scale = newScale
  }

  mutating func pan(by delta: CGSize) {
    offset.width += delta.width
    offset.height += delta.height
  }

  /// Fits `rect` (canvas) into `size` (screen) with `padding`, never above 100 %.
  mutating func fit(_ rect: CGRect, in size: CGSize, padding: CGFloat = 64) {
    guard !rect.isNull, size.width > 0, size.height > 0 else { return }
    let available = CGSize(width: max(1, size.width - padding * 2), height: max(1, size.height - padding * 2))
    let fitted = min(available.width / max(1, rect.width), available.height / max(1, rect.height), 1)
    scale = min(Self.maxScale, max(Self.minScale, fitted))
    offset = CGSize(
      width: size.width / 2 - rect.midX * scale,
      height: size.height / 2 - rect.midY * scale
    )
  }
}

/// The viewport lives in its own object so panning and zooming (every scroll
/// event, every frame of a pinch) only re-renders the views that draw the canvas,
/// never the inspector or the toolbar.
@MainActor
final class AutomationCanvasCamera: ObservableObject {
  @Published var viewport = AutomationCanvasViewport()
  /// Size of the canvas area on screen (not published: it follows the window).
  var canvasSize: CGSize = .zero
}

@MainActor
final class AutomationCanvasEditorModel: ObservableObject {
  /// Where a step chosen in the add-node picker goes.
  struct PickerRequest: Equatable {
    /// Link it after this node; nil means after the selection / end of the chain.
    var after: AutomationCanvasNodeID?
    /// Leave the new step unconnected (double-click on empty space).
    var detached = false
    /// Canvas point for the new node; nil lets the graph pick.
    var canvasPoint: CGPoint?
    /// Screen point the picker opens at.
    var anchor: CGPoint
  }

  /// A link being dragged out of a node's output handle.
  struct PendingConnection: Equatable {
    var from: AutomationCanvasNodeID
    var location: CGPoint
  }

  @Published var automation: Automation {
    didSet { automationDidChange(from: oldValue) }
  }
  @Published private(set) var graph: AutomationCanvasGraph {
    didSet { graphDidChange(from: oldValue) }
  }
  @Published var selection: AutomationCanvasNodeID?
  @Published var picker: PickerRequest?
  @Published var shortcutIssue: ShortcutValidationIssue?
  @Published var lastCaptureSpec: AutomationCaptureSpec?
  @Published var isInspectorVisible = true
  @Published var isMinimapVisible = true
  @Published private(set) var isNew: Bool {
    didSet { refreshUnsaved() }
  }

  // Derived state, cached: the views read these on every render, and computing
  // them (validation, a full draft comparison, a store lookup) per frame is what
  // made panning and dragging stall.
  @Published private(set) var issues: [AutomationChainIssue] = []
  @Published private(set) var hasUnsavedChanges = false
  @Published private(set) var hasDuplicateName = false
  /// Steps that run, in order (`graph.chain`, cached).
  private(set) var chain: [UUID] = []
  /// Steps not reachable from the source (`graph.detachedIDs`, cached).
  private(set) var detachedIDs: Set<UUID> = []

  let camera = AutomationCanvasCamera()

  var viewport: AutomationCanvasViewport {
    get { camera.viewport }
    set { camera.viewport = newValue }
  }

  var canvasSize: CGSize {
    get { camera.canvasSize }
    set { camera.canvasSize = newValue }
  }

  private var savedSnapshot: Automation
  /// Annotate canvas presets, read once per window.
  private let canvasPresetIDs = Set(AnnotateCanvasPresetStore.shared.loadPresets().map(\.id))

  init(automation: Automation, isNew: Bool) {
    var editable = automation.migrated()
    editable.name = automation.displayName
    let graph = AutomationCanvasGraph(automation: editable)
    self.graph = graph
    self.automation = graph.applied(to: editable)
    self.isNew = isNew
    savedSnapshot = graph.applied(to: editable)
    refreshStructure()
    refreshIssues()
    refreshUnsaved()
    refreshDuplicateName()
  }

  // MARK: - Derived

  var draft: Automation {
    graph.applied(to: automation)
  }

  var canAddStep: Bool {
    graph.steps.count < Automation.maxSteps
  }

  var detachedCount: Int {
    detachedIDs.count
  }

  func step(_ id: UUID) -> AutomationStep? {
    graph.steps[id]
  }

  func stepBinding(_ id: UUID) -> Binding<AutomationStep> {
    Binding(
      get: { [weak self] in self?.graph.steps[id] ?? AutomationStep(.stop) },
      set: { [weak self] in self?.updateStep($0) }
    )
  }

  /// Steps after `id` in its chain (the inspector uses it for skip ranges).
  func stepsAfter(_ id: UUID) -> Int {
    if let index = chain.firstIndex(of: id) { return chain.count - index - 1 }
    for chain in graph.detachedChains {
      if let index = chain.firstIndex(of: id) { return chain.count - index - 1 }
    }
    return 0
  }

  // MARK: - Editing

  func updateStep(_ step: AutomationStep) {
    graph.update(step)
    syncSteps()
  }

  func move(_ node: AutomationCanvasNodeID, to point: CGPoint) {
    graph.positions[node] = point
  }

  func connect(from: AutomationCanvasNodeID, to: AutomationCanvasNodeID) {
    withAnimation(AutomationCanvasTheme.spring) {
      guard graph.connect(from: from, to: to) else { return }
      syncSteps()
    }
  }

  func disconnect(from: AutomationCanvasNodeID) {
    withAnimation(AutomationCanvasTheme.spring) {
      graph.disconnect(from: from)
      syncSteps()
    }
  }

  func canConnect(from: AutomationCanvasNodeID, to: AutomationCanvasNodeID) -> Bool {
    graph.canConnect(from: from, to: to)
  }

  func addStep(_ kind: AutomationStepKind, request: PickerRequest?) {
    guard canAddStep else { return }
    let step = AutomationStep(kind.defaultAction)
    let after = request?.detached == true ? nil : (request?.after ?? defaultInsertionPoint)
    withAnimation(AutomationCanvasTheme.spring) {
      graph.insert(step, after: after, at: request?.canvasPoint)
      picker = nil
      selection = .step(step.id)
      syncSteps()
    }
    reveal(.step(step.id))
  }

  func duplicate(_ id: UUID) {
    guard canAddStep, var copy = graph.steps[id] else { return }
    copy.id = UUID()
    withAnimation(AutomationCanvasTheme.spring) {
      graph.insert(copy, after: .step(id))
      selection = .step(copy.id)
      syncSteps()
    }
  }

  func delete(_ node: AutomationCanvasNodeID) {
    guard let id = node.stepID else { return }
    let fallback = graph.predecessor(of: node)
    withAnimation(AutomationCanvasTheme.spring) {
      graph.remove(id)
      selection = fallback
      syncSteps()
    }
  }

  func toggleEnabled(_ id: UUID) {
    guard var step = graph.steps[id] else { return }
    step.isEnabled.toggle()
    updateStep(step)
  }

  func tidyUp() {
    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
      graph.autoLayout()
      zoomToFit()
    }
  }

  // MARK: - Viewport

  func zoom(by factor: CGFloat, around anchor: CGPoint? = nil) {
    let center = anchor ?? CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
    viewport.zoom(by: factor, around: center)
  }

  func resetZoom() {
    let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
    viewport.zoom(by: 1 / viewport.scale, around: center)
  }

  func zoomToFit() {
    viewport.fit(graph.bounds, in: canvasSize, padding: 64)
  }

  /// First view of the window: fit everything, but never so small the cards are hard
  /// to read; a long chain then starts at the left edge instead.
  func initialFit() {
    zoomToFit()
    let minimum: CGFloat = 0.85
    guard viewport.scale < minimum else { return }
    let bounds = graph.bounds
    viewport.scale = minimum
    viewport.offset = CGSize(
      width: 64 - bounds.minX * minimum,
      height: canvasSize.height / 2 - bounds.midY * minimum
    )
  }

  /// Centers the canvas point `point` on screen (minimap clicks).
  func center(on point: CGPoint) {
    viewport.offset = CGSize(
      width: canvasSize.width / 2 - point.x * viewport.scale,
      height: canvasSize.height / 2 - point.y * viewport.scale
    )
  }

  /// Pans just enough to bring `node` fully on screen.
  func reveal(_ node: AutomationCanvasNodeID) {
    guard canvasSize.width > 0 else { return }
    let frame = viewport.toScreen(graph.frame(of: node)).insetBy(dx: -32, dy: -32)
    let visible = CGRect(origin: .zero, size: canvasSize)
    var delta = CGSize.zero
    if frame.minX < visible.minX { delta.width = visible.minX - frame.minX } else if frame.maxX > visible.maxX {
      delta.width = visible.maxX - frame.maxX
    }
    if frame.minY < visible.minY { delta.height = visible.minY - frame.minY } else if frame.maxY > visible.maxY {
      delta.height = visible.maxY - frame.maxY
    }
    guard delta != .zero else { return }
    withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { viewport.pan(by: delta) }
  }

  func openPicker(
    after: AutomationCanvasNodeID?,
    detached: Bool = false,
    canvasPoint: CGPoint? = nil,
    anchor: CGPoint? = nil
  ) {
    guard canAddStep else { return }
    let screen = anchor
      ?? canvasPoint.map(viewport.toScreen)
      ?? CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
    picker = PickerRequest(after: after, detached: detached, canvasPoint: canvasPoint, anchor: screen)
  }

  /// The node at `screen`, if any (hit area a little larger than the card).
  func node(at screen: CGPoint) -> AutomationCanvasNodeID? {
    let canvasPoint = viewport.toCanvas(screen)
    return graph.allNodes.reversed().first { graph.frame(of: $0).insetBy(dx: -12, dy: -12).contains(canvasPoint) }
  }

  // MARK: - Save

  /// The normalized automation to store. Updates the editor to what was saved.
  func prepareSave() -> Automation {
    var saved = draft.normalized().storedForm()
    // Saving from the editor is the review an imported automation waits for.
    saved.needsReview = false
    return saved
  }

  func didSave(_ saved: Automation) {
    var editable = saved
    editable.name = saved.displayName
    let positions = graph.positions
    var rebuilt = AutomationCanvasGraph(automation: editable)
    // Keep the positions the user set even for steps normalization added.
    for (node, point) in positions where rebuilt.positions[node] != nil {
      rebuilt.positions[node] = point
    }
    graph = rebuilt
    automation = rebuilt.applied(to: editable)
    savedSnapshot = draft
    isNew = false
    refreshUnsaved()
  }

  // MARK: - Private

  /// Where a step added without a target goes: after the selection, else at the end of the run chain.
  private var defaultInsertionPoint: AutomationCanvasNodeID {
    if let selection, selection != .trigger { return selection }
    return chain.last.map { .step($0) } ?? .source
  }

  private func syncSteps() {
    automation.steps = graph.chainSteps
  }

  // MARK: - Derived state

  private func graphDidChange(from old: AutomationCanvasGraph) {
    let structural = old.steps != graph.steps || old.stepOrder != graph.stepOrder || old.links != graph.links
    if structural {
      refreshStructure()
      refreshIssues()
      refreshUnsaved()
    } else if !hasUnsavedChanges {
      // Only positions moved: once the draft is dirty, moving more can't clean it.
      refreshUnsaved()
    }
  }

  private func automationDidChange(from old: Automation) {
    // `syncSteps` copies the graph's steps in; the graph already revalidated those.
    var settingsBefore = old
    settingsBefore.steps = automation.steps
    settingsBefore.canvas = automation.canvas
    if settingsBefore != automation { refreshIssues() }
    if old.name != automation.name { refreshDuplicateName() }
    refreshUnsaved()
  }

  private func refreshStructure() {
    chain = graph.chain
    detachedIDs = graph.detachedIDs
  }

  private func refreshIssues() {
    let presets = canvasPresetIDs
    let updated = AutomationChainValidator.validate(draft, canvasPresetExists: { presets.contains($0) })
    if updated != issues { issues = updated }
  }

  private func refreshUnsaved() {
    let updated = isNew || draft != savedSnapshot
    if updated != hasUnsavedChanges { hasUnsavedChanges = updated }
  }

  private func refreshDuplicateName() {
    let updated = !automation.isSystemDefault
      && !AutomationStore.shared.duplicateNameIDs(for: draft.storedForm()).isEmpty
    if updated != hasDuplicateName { hasDuplicateName = updated }
  }
}

extension Automation {
  /// An untouched preset name goes back to its stored form so it keeps following the app language.
  func storedForm() -> Automation {
    var copy = self
    if let type = copy.systemCaptureType, copy.name == AutomationSystemDefault.localizedName(for: type) {
      copy.name = AutomationSystemDefault.storedName(for: type)
    }
    if let preset = copy.presetID.flatMap(AutomationPreset.init(rawValue:)), copy.name == preset.localizedName {
      copy.name = preset.storedName
    }
    return copy
  }
}
