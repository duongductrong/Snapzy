//
//  AutomationCanvasView.swift
//  Snapzy
//
//  The interactive canvas: drag the background (or two-finger scroll) to pan,
//  pinch or ⌘-scroll to zoom, drag nodes to move them, drag an output handle
//  onto a node to link it (or onto empty space to add a step there), and hover
//  a link to insert a step or cut it.
//
//  Gestures in flight (a node being dragged, a link being pulled out) live in
//  this view's state and reach the model once, on release, so a drag only
//  redraws the canvas and never the inspector or the toolbar.
//

import SwiftUI

struct AutomationCanvasView: View {
  @ObservedObject var model: AutomationCanvasEditorModel
  @ObservedObject var camera: AutomationCanvasCamera

  /// Node being dragged and how far, in canvas units.
  @State private var nodeDrag: (node: AutomationCanvasNodeID, translation: CGSize)?
  @State private var pending: AutomationCanvasEditorModel.PendingConnection?
  @State private var panOrigin: CGSize?
  @State private var hoveredLink: AutomationCanvasLink?
  @State private var didInitialFit = false
  @State private var pointer: CGPoint?

  private static let gridSnap: CGFloat = 8

  private var viewport: AutomationCanvasViewport { camera.viewport }

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .topLeading) {
        background
        links
          .allowsHitTesting(false)
        linkControls
        nodes
        pendingConnection
          .allowsHitTesting(false)
        pickerLayer
      }
      .animation(.easeOut(duration: 0.16), value: model.picker != nil)
      .frame(width: geometry.size.width, height: geometry.size.height)
      .coordinateSpace(name: AutomationCanvasNodeInfo.coordinateSpace)
      .background(
        AutomationCanvasEventMonitor(
          onPan: { camera.viewport.pan(by: $0) },
          onZoom: { model.zoom(by: $0, around: $1) },
          onKey: handleKey,
          isOverPanel: isOverPanel
        )
      )
      .clipped()
      .onAppear {
        model.canvasSize = geometry.size
        if !didInitialFit {
          didInitialFit = true
          model.initialFit()
        }
      }
      .onChange(of: geometry.size) { model.canvasSize = $0 }
    }
    .background(AutomationCanvasTheme.backdrop)
  }

  // MARK: - Geometry with the drag applied

  private func position(of node: AutomationCanvasNodeID) -> CGPoint {
    var point = model.graph.position(of: node)
    if let nodeDrag, nodeDrag.node == node {
      point.x += nodeDrag.translation.width
      point.y += nodeDrag.translation.height
    }
    return point
  }

  private func canvasFrame(of node: AutomationCanvasNodeID) -> CGRect {
    let center = position(of: node)
    let size = AutomationCanvasGraph.nodeSize
    return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
  }

  private func screenFrame(of node: AutomationCanvasNodeID) -> CGRect {
    viewport.toScreen(canvasFrame(of: node))
  }

  // MARK: - Background

  private var background: some View {
    AutomationCanvasGrid(viewport: viewport)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 2)
          .onChanged { value in
            let origin = panOrigin ?? camera.viewport.offset
            if panOrigin == nil { panOrigin = origin; NSCursor.closedHand.push() }
            camera.viewport.offset = CGSize(
              width: origin.width + value.translation.width,
              height: origin.height + value.translation.height
            )
          }
          .onEnded { _ in
            if panOrigin != nil { NSCursor.pop() }
            panOrigin = nil
          }
      )
      .onContinuousHover(coordinateSpace: .named(AutomationCanvasNodeInfo.coordinateSpace)) { phase in
        if case .active(let location) = phase { pointer = location }
      }
      .onTapGesture(count: 2) {
        // Double-click empty space: add an unconnected step there.
        let location = pointer ?? CGPoint(x: model.canvasSize.width / 2, y: model.canvasSize.height / 2)
        model.openPicker(after: nil, detached: true, canvasPoint: viewport.toCanvas(location), anchor: location)
      }
      .onTapGesture {
        model.picker = nil
        model.selection = nil
      }
  }

  // MARK: - Links

  private var frames: [AutomationCanvasNodeID: CGRect] {
    var result: [AutomationCanvasNodeID: CGRect] = [:]
    for node in model.graph.allNodes where isVisible(node) {
      result[node] = screenFrame(of: node)
    }
    return result
  }

  private var links: some View {
    let frames = frames
    let scale = viewport.scale
    let detached = model.detachedIDs
    let selection = model.selection
    let inset = max(3, 5 * scale)
    return ZStack(alignment: .topLeading) {
      ForEach(model.graph.links.filter { isVisible($0.from) }, id: \.self) { link in
        if let fromFrame = frames[link.from], let toFrame = frames[link.to] {
          let end = AutomationCanvasGeometry.inPort(of: toFrame)
          AutomationCanvasLinkView(
            start: CGPoint(x: fromFrame.maxX + inset, y: fromFrame.midY),
            end: CGPoint(x: end.x - inset, y: end.y),
            scale: scale,
            isHot: selection == link.from || selection == link.to,
            isDetached: link.to.stepID.map(detached.contains) ?? false
          )
        }
      }
      ForEach(otherwiseJumps, id: \.self) { jump in
        if let fromFrame = frames[.step(jump.condition)] {
          let start = CGPoint(x: fromFrame.midX, y: fromFrame.maxY)
          if let target = jump.target, let toFrame = frames[.step(target)] {
            AutomationCanvasJumpView(
              start: start,
              end: CGPoint(x: toFrame.midX, y: toFrame.maxY + 4 * scale),
              scale: scale,
              isStub: false,
              label: L10n.Automations.canvasOtherwise
            )
          } else {
            AutomationCanvasJumpView(
              start: start,
              end: CGPoint(x: start.x, y: start.y + 40 * scale),
              scale: scale,
              isStub: true,
              label: "\(L10n.Automations.canvasOtherwise) → \(L10n.Automations.canvasEnd)"
            )
          }
        }
      }
    }
  }

  private var otherwiseJumps: [AutomationCanvasOtherwiseJump] {
    let chain = model.chain
    var jumps: [AutomationCanvasOtherwiseJump] = []
    for (index, id) in chain.enumerated() {
      guard let step = model.step(id), step.isEnabled,
            case .condition(let config)? = step.action else { continue }
      switch config.otherwise {
      case .stop:
        jumps.append(AutomationCanvasOtherwiseJump(condition: id, target: nil))
      case .skip(let count):
        let targetIndex = index + 1 + count
        jumps.append(AutomationCanvasOtherwiseJump(
          condition: id,
          target: chain.indices.contains(targetIndex) ? chain[targetIndex] : nil
        ))
      }
    }
    return jumps
  }

  /// Hover zone at each link's midpoint: insert a step there, or cut the link.
  private var linkControls: some View {
    let frames = frames
    let scale = viewport.scale
    return ForEach(model.graph.links.filter { $0.from != .trigger && isVisible($0.from) }, id: \.self) { link in
      if let fromFrame = frames[link.from], let toFrame = frames[link.to] {
        let mid = AutomationCanvasGeometry.midpoint(
          from: AutomationCanvasGeometry.outPort(of: fromFrame),
          to: AutomationCanvasGeometry.inPort(of: toFrame),
          scale: scale
        )
        let isHovered = hoveredLink == link && nodeDrag == nil && pending == nil
        AutomationCanvasLinkActions(
          canInsert: model.canAddStep,
          onInsert: { model.openPicker(after: link.from, anchor: mid) },
          onDisconnect: { model.disconnect(from: link.from) }
        )
        .opacity(isHovered ? 1 : 0)
        .allowsHitTesting(isHovered)
        .frame(width: 92, height: 44)
        .contentShape(Rectangle())
        .onHover { inside in
          if inside { hoveredLink = link } else if hoveredLink == link { hoveredLink = nil }
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .position(mid)
      }
    }
  }

  // MARK: - Nodes

  private var nodes: some View {
    let issues = model.issues
    let detached = model.detachedIDs
    let scale = viewport.scale
    let dropTarget = currentDropTarget
    var stepNumbers: [UUID: Int] = [:]
    for (index, id) in model.chain.enumerated() { stepNumbers[id] = index + 1 }
    return ForEach(model.graph.allNodes.filter(isVisible), id: \.self) { node in
      let step = node.stepID.flatMap(model.step)
      let hasSuccessor = model.graph.successor(of: node) != nil
      AutomationCanvasNodeView(
        info: AutomationCanvasNodeInfo.make(for: node, model: model),
        scale: scale,
        stepNumber: node.stepID.flatMap { stepNumbers[$0] },
        isSelected: model.selection == node,
        isDetached: node.stepID.map(detached.contains) ?? false,
        isDisabled: step.map { !$0.isEnabled } ?? false,
        isDropTarget: dropTarget == node,
        isDragging: nodeDrag?.node == node,
        issue: node.stepID.flatMap { id in issues.first { $0.stepID == id } },
        hasInput: !isStart(node),
        hasOutput: true,
        canDragOutput: node != .trigger,
        showsAddButton: node != .trigger && !hasSuccessor && model.canAddStep,
        onOutputDrag: { location in
          pending = .init(from: node, location: location)
        },
        onOutputDragEnd: { location in finishConnection(from: node, at: location) },
        onAdd: {
          let frame = model.graph.frame(of: node)
          model.openPicker(after: node, anchor: viewport.toScreen(CGPoint(x: frame.maxX + 40, y: frame.midY)))
        }
      )
      .position(viewport.toScreen(position(of: node)))
      .zIndex(nodeDrag?.node == node ? 2 : (model.selection == node ? 1 : 0))
      .transition(.opacity)
      .gesture(dragGesture(for: node))
      .onTapGesture {
        model.picker = nil
        model.selection = node
        model.reveal(node)
      }
      // Simultaneous so the single click still selects without a delay.
      .simultaneousGesture(TapGesture(count: 2).onEnded { model.openSettings(for: node) })
      .contextMenu { contextMenu(for: node) }
    }
  }

  /// The first node drawn: the trigger, or the source of a default after-capture automation.
  private func isStart(_ node: AutomationCanvasNodeID) -> Bool {
    model.automation.isSystemDefault ? node == .source : node == .trigger
  }

  /// The trigger/source pair of a default after-capture automation is one "After capture" node.
  private func isVisible(_ node: AutomationCanvasNodeID) -> Bool {
    !(model.automation.isSystemDefault && node == .trigger)
  }

  private func dragGesture(for node: AutomationCanvasNodeID) -> some Gesture {
    DragGesture(minimumDistance: 3, coordinateSpace: .named(AutomationCanvasNodeInfo.coordinateSpace))
      .onChanged { value in
        if nodeDrag?.node != node {
          if model.selection != node { model.selection = node }
          if model.picker != nil { model.picker = nil }
        }
        let scale = viewport.scale
        nodeDrag = (node, CGSize(width: value.translation.width / scale, height: value.translation.height / scale))
      }
      .onEnded { _ in
        let point = position(of: node)
        let snap = Self.gridSnap
        withAnimation(.easeOut(duration: 0.12)) {
          model.move(node, to: CGPoint(x: (point.x / snap).rounded() * snap, y: (point.y / snap).rounded() * snap))
          nodeDrag = nil
        }
      }
  }

  @ViewBuilder
  private func contextMenu(for node: AutomationCanvasNodeID) -> some View {
    if let id = node.stepID, let step = model.step(id) {
      Button(step.isEnabled ? L10n.Automations.canvasDisableStep : L10n.Automations.canvasEnableStep) {
        model.toggleEnabled(id)
      }
      Button(L10n.Automations.duplicate) { model.duplicate(id) }
        .disabled(!model.canAddStep)
      if model.graph.successor(of: node) != nil {
        Button(L10n.Automations.canvasDisconnect) { model.disconnect(from: node) }
      }
      Divider()
      Button(L10n.Common.delete, role: .destructive) { model.delete(node) }
    } else if node == .source, model.graph.successor(of: node) != nil {
      Button(L10n.Automations.canvasDisconnect) { model.disconnect(from: node) }
    }
  }

  // MARK: - Connecting

  private var currentDropTarget: AutomationCanvasNodeID? {
    guard let pending,
          let node = model.node(at: pending.location),
          model.canConnect(from: pending.from, to: node) else { return nil }
    return node
  }

  @ViewBuilder
  private var pendingConnection: some View {
    if let pending {
      let scale = viewport.scale
      let start = AutomationCanvasGeometry.outPort(of: screenFrame(of: pending.from))
      let end = currentDropTarget.map { AutomationCanvasGeometry.inPort(of: screenFrame(of: $0)) } ?? pending.location
      AutomationCanvasGeometry.curve(from: start, to: end, scale: scale)
        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: max(1.25, 1.75 * scale), lineCap: .round))
      Circle()
        .fill(Color.accentColor)
        .frame(width: 8, height: 8)
        .position(end)
    }
  }

  private func finishConnection(from node: AutomationCanvasNodeID, at location: CGPoint) {
    defer { pending = nil }
    if let target = model.node(at: location) {
      model.connect(from: node, to: target)
      return
    }
    // Dropped on empty space: add a step there, linked after `node`.
    let canvasPoint = viewport.toCanvas(location)
    model.openPicker(
      after: node,
      canvasPoint: CGPoint(x: canvasPoint.x + AutomationCanvasGraph.nodeSize.width / 2, y: canvasPoint.y),
      anchor: location
    )
  }

  // MARK: - Picker

  /// The step picker floats next to where it was opened, kept inside the part of
  /// the canvas the bars and the inspector leave visible.
  @ViewBuilder
  private var pickerLayer: some View {
    if let request = model.picker {
      let frame = pickerFrame(for: request)
      AutomationCanvasNodePicker(
        onPick: { model.addStep($0, request: model.picker) },
        onClose: { model.picker = nil }
      )
      .position(x: frame.midX, y: frame.midY)
      .transition(.scale(scale: 0.96).combined(with: .opacity))
    }
  }

  /// To the right of the anchor, or to its left when there is no room.
  private func pickerFrame(for request: AutomationCanvasEditorModel.PickerRequest) -> CGRect {
    let size = AutomationCanvasNodePicker.size
    let area = model.unobscuredRect.insetBy(dx: 12, dy: 0)
    let gap: CGFloat = 16
    var x = request.anchor.x + gap
    if x + size.width > area.maxX { x = request.anchor.x - gap - size.width }
    x = min(max(x, area.minX), max(area.minX, area.maxX - size.width))
    var y = request.anchor.y - size.height / 2
    y = min(max(y, area.minY), max(area.minY, area.maxY - size.height))
    return CGRect(origin: CGPoint(x: x, y: y), size: size)
  }

  private func isOverPanel(_ point: CGPoint) -> Bool {
    if model.inspectorFrame.contains(point) { return true }
    if let request = model.picker, pickerFrame(for: request).contains(point) { return true }
    return false
  }

  // MARK: - Keys

  private func handleKey(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    switch event.keyCode {
    case 51, 117: // delete, forward delete
      guard flags.isDisjoint(with: [.command, .option, .control]),
            let node = model.selection, node.stepID != nil, model.picker == nil else { return false }
      model.delete(node)
      return true
    case 48: // tab
      guard flags.isEmpty, model.picker == nil else { return false }
      model.openPicker(after: model.selection)
      return true
    case 53: // escape
      if model.picker != nil { model.picker = nil; return true }
      if pending != nil { pending = nil; return true }
      if model.selection != nil { model.selection = nil; return true }
      return false
    case 2 where flags == .command: // ⌘D
      guard let id = model.selection?.stepID else { return false }
      model.duplicate(id)
      return true
    default:
      return false
    }
  }
}

// MARK: - Link actions

/// Small segmented control shown on a hovered link: insert a step, or cut the link.
private struct AutomationCanvasLinkActions: View {
  let canInsert: Bool
  let onInsert: () -> Void
  let onDisconnect: () -> Void

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.controlM, style: .continuous)
    HStack(spacing: 0) {
      Button(action: onInsert) {
        Image(systemName: "plus")
          .frame(width: 26, height: 22)
          .contentShape(Rectangle())
      }
      .disabled(!canInsert)
      .help(L10n.Automations.canvasInsertStep)
      .accessibilityLabel(L10n.Automations.canvasInsertStep)
      Divider()
        .frame(height: 14)
      Button(action: onDisconnect) {
        Image(systemName: "scissors")
          .frame(width: 26, height: 22)
          .contentShape(Rectangle())
      }
      .help(L10n.Automations.canvasDisconnect)
      .accessibilityLabel(L10n.Automations.canvasDisconnect)
    }
    .buttonStyle(AutomationCanvasBarButtonStyle())
    .font(.system(size: 11, weight: .medium))
    .padding(2)
    .canvasFloating(shape)
  }
}

// MARK: - Add-step picker

/// Floating step library with search, opened from "+" buttons, Tab,
/// double-click or by dropping a link on empty space. Rows highlight like menu items.
struct AutomationCanvasNodePicker: View {
  static let size = CGSize(width: 280, height: 380)

  let onPick: (AutomationStepKind) -> Void
  let onClose: () -> Void

  @State private var query = ""
  @State private var hovered: AutomationStepKind?
  @FocusState private var isSearchFocused: Bool

  private var groups: [(group: AutomationStepGroup, kinds: [AutomationStepKind])] {
    let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
    return AutomationStepGroup.allCases.compactMap { group in
      let kinds = group.kinds.filter {
        needle.isEmpty
          || $0.displayName.lowercased().contains(needle)
          || group.title.lowercased().contains(needle)
      }
      return kinds.isEmpty ? nil : (group, kinds)
    }
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
        TextField(L10n.Automations.canvasSearchSteps, text: $query)
          .textFieldStyle(.plain)
          .font(.system(size: 14))
          .focused($isSearchFocused)
          .onSubmit {
            if let first = groups.first?.kinds.first { onPick(first) }
          }
        Button(action: onClose) {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(AutomationCanvasBarButtonStyle())
        .help(L10n.Common.cancel)
        .accessibilityLabel(L10n.Common.cancel)
      }
      .padding(.leading, 14)
      .padding(.trailing, 8)
      .frame(height: 44)
      Divider()
        .padding(.horizontal, 10)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if groups.isEmpty {
            Text(L10n.Automations.canvasNoMatchingSteps)
              .font(.callout)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 24)
          }
          ForEach(groups, id: \.group) { entry in
            Text(entry.group.title)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.secondary)
              .padding(.horizontal, 10)
              .padding(.top, 8)
              .padding(.bottom, 3)
            ForEach(entry.kinds) { kind in
              AutomationCanvasPickerRow(
                kind: kind,
                tint: entry.group.canvasTint,
                isHighlighted: hovered == kind,
                onHover: { inside in
                  if inside { hovered = kind } else if hovered == kind { hovered = nil }
                },
                action: { onPick(kind) }
              )
            }
          }
        }
        .padding(6)
      }
    }
    .frame(width: Self.size.width, height: Self.size.height)
    .clipShape(shape)
    .canvasFloating(shape)
    .onAppear { isSearchFocused = true }
    .onExitCommand(perform: onClose)
  }
}

private struct AutomationCanvasPickerRow: View {
  let kind: AutomationStepKind
  let tint: PreferencesIconTint
  let isHighlighted: Bool
  let onHover: (Bool) -> Void
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        RoundedRectangle(cornerRadius: Radius.ornament, style: .continuous)
          .fill(tint.gradient)
          .frame(width: 20, height: 20)
          .overlay(
            Image(systemName: kind.symbol)
              .font(.system(size: 10.5, weight: .semibold))
              .foregroundStyle(.white)
          )
        Text(kind.displayName)
          .font(.system(size: 13))
          .foregroundStyle(isHighlighted ? Color.white : Color.primary)
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 8)
      .frame(height: 30)
      .background(
        RoundedRectangle(cornerRadius: Radius.controlS, style: .continuous)
          .fill(isHighlighted ? Color.accentColor : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover(perform: onHover)
  }
}
