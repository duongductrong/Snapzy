//
//  AnnotateAgentToolbox.swift
//  Snapzy
//
//  The one place where an agent's tool calls become Annotate edits. Every provider
//  (Apple Intelligence, custom endpoint, agent CLI over MCP) calls `execute`.
//
//  - Arguments and results are JSON, so providers only pass strings through.
//  - Coordinates in and out are agent space (top-left); see `AnnotateAgentCoordinates`.
//  - A run (one prompt) records a single undo checkpoint, taken lazily before its
//    first annotation change, so a run that only reads leaves no empty undo step.
//  - Canvas settings (background, padding…) are not part of Annotate's undo stack;
//    the toolbox remembers their values before the run (`revertCanvasChanges`).
//  - The toolbox lives for a whole conversation so `a#` ids stay stable across prompts.
//

import AppKit
import CoreGraphics
import Foundation
import SwiftUI

nonisolated struct AnnotateAgentRunSummary: Equatable {
  let createdAnnotationIDs: [UUID]
  let changeCount: Int
  let didChangeCanvas: Bool
  /// The run pushed its own undo checkpoint (annotation changes undo with one ⌘Z).
  let recordedUndo: Bool
}

@MainActor
final class AnnotateAgentToolbox {
  static let maximumChangesPerRun = 60

  private weak var state: AnnotateState?
  private(set) var analysis: AnnotateAgentImageAnalysis
  /// Live feedback for the overlay (annotate space).
  var onEvent: ((AnnotateAgentToolboxEvent) -> Void)?

  private var referenceByID: [UUID: String] = [:]
  private var idByReference: [String: UUID] = [:]
  private var nextAnnotationNumber = 1

  private var didRecordUndo = false
  private var createdAnnotationIDs: [UUID] = []
  private var changeCount = 0
  private var canvasBeforeRun: CanvasSnapshot?

  init(state: AnnotateState, analysis: AnnotateAgentImageAnalysis) {
    self.state = state
    self.analysis = analysis
  }

  /// New image analysis (e.g. after the image changed). Annotation ids are kept.
  func updateAnalysis(_ analysis: AnnotateAgentImageAnalysis) {
    self.analysis = analysis
  }

  // MARK: - Run lifecycle

  func beginRun() {
    didRecordUndo = false
    createdAnnotationIDs = []
    changeCount = 0
    canvasBeforeRun = nil
    // A text edit the user left open is their change, committed (with its own undo step)
    // before the run starts rather than in the middle of a tool call that may then fail.
    if state?.editingTextAnnotationId != nil {
      state?.commitTextEditing()
    }
  }

  /// Selects what the run created so the user can keep editing it.
  @discardableResult
  func finishRun() -> AnnotateAgentRunSummary {
    let created = createdAnnotationIDs.filter { id in state?.annotations.contains { $0.id == id } == true }
    if !created.isEmpty {
      state?.setSelectedAnnotationIds(Set(created))
    }
    return AnnotateAgentRunSummary(
      createdAnnotationIDs: created,
      changeCount: changeCount,
      didChangeCanvas: canvasBeforeRun != nil,
      recordedUndo: didRecordUndo
    )
  }

  /// Restores canvas settings changed by the current run (annotation changes undo with ⌘Z).
  func revertCanvasChanges() {
    guard let snapshot = canvasBeforeRun, let state else { return }
    snapshot.apply(to: state)
    canvasBeforeRun = nil
    onEvent?(.canvasChanged)
  }

  // MARK: - References

  /// Short id (`a7`) for an annotation, assigned on first sight and stable afterwards.
  func reference(for id: UUID) -> String {
    if let existing = referenceByID[id] { return existing }
    let reference = "a\(nextAnnotationNumber)"
    nextAnnotationNumber += 1
    referenceByID[id] = reference
    idByReference[reference] = id
    return reference
  }

  func annotationID(for reference: String) -> UUID? {
    idByReference[reference.trimmingCharacters(in: .whitespaces).lowercased()]
  }

  // MARK: - Scene

  func scene() -> AnnotateAgentScene? {
    guard let state, state.hasImage else { return nil }
    let height = state.imageHeight
    func agent(_ rect: CGRect) -> AnnotateAgentRect {
      AnnotateAgentRect(AnnotateAgentCoordinates.agentRect(fromAnnotate: rect, imageHeight: height))
    }

    let texts = analysis.textBlocks.enumerated().map { index, block in
      AnnotateAgentScene.Text(id: "t\(index + 1)", text: block.text, rect: agent(block.bounds))
    }
    let elements = analysis.elements.enumerated().map { index, rect in
      AnnotateAgentScene.Element(id: "e\(index + 1)", rect: agent(rect))
    }
    let annotations = state.annotations.map { item -> AnnotateAgentScene.Annotation in
      AnnotateAgentScene.Annotation(
        id: reference(for: item.id),
        type: item.type.agentTypeName,
        rect: agent(item.bounds),
        color: Self.colorDescription(of: item),
        text: Self.textContent(of: item).map { String($0.prefix(80)) }
      )
    }
    let selection = state.annotations
      .filter { state.selectedAnnotationIds.contains($0.id) }
      .map { reference(for: $0.id) }

    return AnnotateAgentScene(
      image: .init(width: Int(state.imageWidth.rounded()), height: Int(height.rounded())),
      texts: texts,
      elements: elements,
      annotations: annotations,
      selection: selection,
      canvas: .init(
        background: Self.describe(state.backgroundStyle),
        padding: Int(state.padding.rounded()),
        inset: Int(state.inset.rounded()),
        shadow: (Double(state.shadowIntensity) * 100).rounded() / 100,
        cornerRadius: Int(state.cornerRadius.rounded()),
        alignment: state.imageAlignment.rawValue
      )
    )
  }

  // MARK: - Execute

  /// Runs one tool call. Never throws: failures come back as error results the model can read.
  func execute(name: String, arguments: Data) -> AnnotateAgentToolResult {
    guard let tool = AnnotateAgentToolName(rawValue: name) else {
      return .failure(.unknownTool(name))
    }
    do {
      return try perform(tool, arguments: arguments.isEmpty ? Data("{}".utf8) : arguments)
    } catch let error as AnnotateAgentToolError {
      return .failure(error)
    } catch let error as DecodingError {
      return .failure(.invalidArguments(Self.describe(error)))
    } catch {
      return .failure(.invalidArguments(error.localizedDescription))
    }
  }

  /// Convenience for providers that hand over a JSON string.
  func execute(name: String, argumentsJSON: String) -> AnnotateAgentToolResult {
    execute(name: name, arguments: Data(argumentsJSON.utf8))
  }

  private func perform(_ tool: AnnotateAgentToolName, arguments: Data) throws -> AnnotateAgentToolResult {
    let state = try readyState()
    if !tool.isReadOnly, tool != .select {
      guard changeCount < Self.maximumChangesPerRun else {
        throw AnnotateAgentToolError.limitReached(Self.maximumChangesPerRun)
      }
      if state.editingTextAnnotationId != nil {
        state.commitTextEditing()
      }
    }

    switch tool {
    case .getScene:
      guard let scene = scene() else { throw AnnotateAgentToolError.unavailable("No image is open.") }
      return .encoded(scene)
    case .findText:
      return try findText(decode(FindTextArguments.self, arguments))
    case .addBox:
      return try addBox(decode(BoxArguments.self, arguments), state: state)
    case .addOval:
      return try addOval(decode(OvalArguments.self, arguments), state: state)
    case .addArrow:
      return try addArrow(decode(ArrowArguments.self, arguments), state: state)
    case .addLine:
      return try addLine(decode(LineArguments.self, arguments), state: state)
    case .addText:
      return try addText(decode(TextArguments.self, arguments), state: state)
    case .addHighlight:
      return try addHighlight(decode(HighlightArguments.self, arguments), state: state)
    case .addBlur:
      return try addBlur(decode(BlurArguments.self, arguments), state: state)
    case .addSpotlight:
      return try addSpotlight(decode(SpotlightArguments.self, arguments), state: state)
    case .addCounter:
      return try addCounter(decode(CounterArguments.self, arguments), state: state)
    case .addWatermark:
      return try addWatermark(decode(WatermarkArguments.self, arguments), state: state)
    case .updateAnnotation:
      return try updateAnnotation(decode(UpdateArguments.self, arguments), state: state)
    case .deleteAnnotations:
      return try deleteAnnotations(decode(IDsArguments.self, arguments), state: state)
    case .arrange:
      return try arrange(decode(ArrangeArguments.self, arguments), state: state)
    case .select:
      return try select(decode(IDsArguments.self, arguments), state: state)
    case .setCanvas:
      return try setCanvas(decode(CanvasArguments.self, arguments), state: state)
    }
  }

  private func readyState() throws -> AnnotateState {
    guard let state, state.hasImage else {
      throw AnnotateAgentToolError.unavailable("No image is open.")
    }
    guard state.editorMode == .annotate, !state.isCombineMode else {
      throw AnnotateAgentToolError.unavailable("The editor is not in annotate mode.")
    }
    return state
  }

  private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(type, from: data)
  }

  // MARK: - Read tools

  private func findText(_ args: FindTextArguments) throws -> AnnotateAgentToolResult {
    guard let state else { throw AnnotateAgentToolError.unavailable("No image is open.") }
    let indices = AnnotateAgentTextMatcher.matches(args.query, in: analysis.textBlocks.map(\.text))
    let matches = indices.prefix(12).map { index -> AnnotateAgentScene.Text in
      let block = analysis.textBlocks[index]
      return AnnotateAgentScene.Text(
        id: "t\(index + 1)",
        text: block.text,
        rect: AnnotateAgentRect(AnnotateAgentCoordinates.agentRect(fromAnnotate: block.bounds, imageHeight: state.imageHeight))
      )
    }
    struct Response: Encodable {
      let ok = true
      let matches: [AnnotateAgentScene.Text]
    }
    return .encoded(Response(matches: Array(matches)))
  }

  // MARK: - Drawing tools

  private func addBox(_ args: BoxArguments, state: AnnotateState) throws -> AnnotateAgentToolResult {
    let target = try resolve(args.target, state: state)
    let rect = expanded(target, by: args.padding ?? 6, minimum: CGSize(width: 120, height: 64), state: state)
    let tool: AnnotationToolType = args.filled == true ? .filledRectangle : .rectangle
    var context = creationContext(for: tool, state: state)
    try applyStyle(color: args.color, strokeWidth: args.strokeWidth, to: &context.properties, tool: tool)
    if let radius = args.cornerRadius {
      context.properties.cornerRadius = min(max(radius, 0), 40)
    }
    return try insert(createShape(tool, in: rect, context: context), state: state)
  }

  private func addOval(_ args: OvalArguments, state: AnnotateState) throws -> AnnotateAgentToolResult {
    let target = try resolve(args.target, state: state)
    let padding = args.padding ?? 10
    // An ellipse inscribed in a box misses the box's corners; grow it so the target stays inside.
    let grown = target.isEmpty
      ? target
      : target.insetBy(dx: -target.width * 0.12, dy: -target.height * 0.22)
    let rect = expanded(grown, by: padding, minimum: CGSize(width: 96, height: 64), state: state)
    var context = creationContext(for: .oval, state: state)
    try applyStyle(color: args.color, strokeWidth: args.strokeWidth, to: &context.properties, tool: .oval)
    return try insert(createShape(.oval, in: rect, context: context), state: state)
  }

  private func addArrow(_ args: ArrowArguments, state: AnnotateState) throws -> AnnotateAgentToolResult {
    let toRect = try resolve(args.to, state: state)
    let start: CGPoint
    if let from = args.from {
      start = center(of: try resolve(from, state: state))
    } else {
      start = autoArrowStart(pointingAt: toRect, state: state)
    }
    let end = Self.edgePoint(of: toRect, toward: start, gap: 6)
    guard hypot(end.x - start.x, end.y - start.y) >= 12 else {
      throw AnnotateAgentToolError.invalidArguments("'from' and 'to' are too close for an arrow.")
    }

    var context = creationContext(for: .arrow, state: state)
    try applyStyle(color: args.color, strokeWidth: args.strokeWidth, to: &context.properties, tool: .arrow)
    switch args.style?.lowercased() {
    case nil:
      break
    case "straight":
      context.arrowStyle = .straight
    case "curved":
      context.arrowStyle = .curvedRight
    case let other?:
      throw AnnotateAgentToolError.invalidArguments("style '\(other)' must be straight or curved.")
    }
    context.arrowBendDirection = .primary
    guard let item = AnnotationFactory.createAnnotation(tool: .arrow, from: start, to: end, path: [], context: context) else {
      throw AnnotateAgentToolError.invalidArguments("Could not draw that arrow.")
    }
    return try insert(item, state: state)
  }

  private func addLine(_ args: LineArguments, state: AnnotateState) throws -> AnnotateAgentToolResult {
    let start = center(of: try resolve(args.from, state: state))
    let end = center(of: try resolve(args.to, state: state))
    guard hypot(end.x - start.x, end.y - start.y) >= 4 else {
      throw AnnotateAgentToolError.invalidArguments("'from' and 'to' are the same point.")
    }
    var context = creationContext(for: .line, state: state)
    try applyStyle(color: args.color, strokeWidth: args.strokeWidth, to: &context.properties, tool: .line)
    if let dashed = args.dashed {
      context.properties.lineStyle = dashed ? .dashed : .solid
    }
    guard let item = AnnotationFactory.createAnnotation(tool: .line, from: start, to: end, path: [], context: context) else {
      throw AnnotateAgentToolError.invalidArguments("Could not draw that line.")
    }
    return try insert(item, state: state)
  }

  private func addText(_ args: TextArguments, state: AnnotateState) throws -> AnnotateAgentToolResult {
    let text = args.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw AnnotateAgentToolError.invalidArguments("text is empty.") }

    let target = try args.target.map { try resolve($0, state: state) }
    let placement = try Self.placement(args.placement)
    let presentation: TextPresentation
    switch args.style?.lowercased() {
    case nil:
      presentation = target != nil && placement != .over ? .callout : .label
    case let raw?:
      guard let parsed = TextPresentation(rawValue: raw) else {
        throw AnnotateAgentToolError.invalidArguments("style '\(raw)' must be plain, label or callout.")
      }
      presentation = parsed
    }

    var properties = state.annotationCreationProperties(for: .text)
    properties.counterArrowTarget = nil
    if let fontSize = args.fontSize {
      properties.fontSize = min(max(fontSize, 12), 72)
    }
    properties.textPresentation = presentation
    let color = try args.color.map(Self.parseColor)
    switch presentation {
    case .plain:
      properties.fillColor = .clear
      if let color { properties.strokeColor = color }
    case .label, .callout:
      let fill = color ?? (properties.fillColor == .clear ? properties.strokeColor : properties.fillColor)
      properties.fillColor = fill
      properties.strokeColor = Self.contrastingTextColor(on: fill)
    }

    let font = AnnotateTextLayout.font(size: properties.fontSize, fontName: properties.fontName)
    let maximumWidth = max(state.imageWidth * 0.6, AnnotateTextLayout.minWidth)
    var size = AnnotateTextLayout.bounds(text: text, font: font, origin: .zero, presentation: presentation).size
    let isConstrained = size.width > maximumWidth
    if isConstrained {
      size = AnnotateTextLayout.bounds(
        text: text, font: font, origin: .zero, constrainedWidth: maximumWidth, presentation: presentation
      ).size
    }

    let gap: CGFloat = presentation == .callout ? 22 : 10
    let origin: CGPoint
    if let target {
      origin = Self.place(size: size, near: target, placement: placement, gap: gap, within: state.activeAnnotationBounds)
    } else {
      let bounds = state.activeAnnotationBounds
      origin = CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
    }
    let bounds = Self.clamped(CGRect(origin: origin, size: size), to: state.activeAnnotationBounds)
    if presentation == .callout, let target {
      properties.calloutTailTarget = TextBubbleGeometry.resolvedTailTarget(
        in: bounds,
        requestedTarget: center(of: target),
        fontSize: properties.fontSize
      )
    } else {
      properties.calloutTailTarget = nil
    }

    let item = AnnotationItem(type: .text(text), bounds: bounds, properties: properties)
    let result = try insert(item, state: state)
    if !isConstrained {
      state.useAutomaticTextWidth(for: item.id)
    }
    if presentation == .callout, target == nil {
      state.prepareTextCalloutTail(for: item.id)
    }
    return result
  }

  private func addHighlight(_ args: HighlightArguments, state: AnnotateState) throws -> AnnotateAgentToolResult {
    let rows = try resolveRows(args.target, state: state)
    var context = creationContext(for: .highlighter, state: state)
    if let color = args.color {
      context.properties.strokeColor = try Self.parseColor(color)
    }
    let segments = rows.map { row -> AnnotateTextSnapSegment in
      let height = max(row.height * AnnotateTextSnapping.defaultHeightScale, 4)
      return AnnotateTextSnapSegment(rect: CGRect(x: row.minX, y: row.midY - height / 2, width: max(row.width, height), height: height))
    }
    let items = AnnotationFactory.createTextSnappedHighlights(segments: segments, context: context)
    guard !items.isEmpty else { throw AnnotateAgentToolError.invalidArguments("Nothing to highlight there.") }
    return try insert(items, state: state)
  }

  private func addBlur(_ args: BlurArguments, state: AnnotateState) throws -> AnnotateAgentToolResult {
    let target = try resolve(args.target, state: state)
    let rect = expanded(target, by: 3, minimum: CGSize(width: 80, height: 32), state: state)
    var context = creationContext(for: .blur, state: state)
    if let kind = args.kind {
      guard let blurType = BlurType.allCases.first(where: { $0.rawValue.lowercased() == kind.lowercased() }) else {
        throw AnnotateAgentToolError.invalidArguments("kind must be one of \(BlurType.allCases.map(\.rawValue).joined(separator: ", ")).")
      }
      context.blurType = blurType
    }
    return try insert(createShape(.blur, in: rect, context: context), state: state)
  }

  private func addSpotlight(_ args: SpotlightArguments, state: AnnotateState) throws -> AnnotateAgentToolResult {
    let target = try resolve(args.target, state: state)
    let rect = expanded(target, by: args.padding ?? 8, minimum: CGSize(width: 120, height: 80), state: state)
    let context = creationContext(for: .spotlight, state: state)
    return try insert(createShape(.spotlight, in: rect, context: context), state: state)
  }

  private func addCounter(_ args: CounterArguments, state: AnnotateState) throws -> AnnotateAgentToolResult {
    let target = try resolve(args.target, state: state)
    var context = creationContext(for: .counter, state: state)
    if let color = args.color {
      context.properties.strokeColor = try Self.parseColor(color)
    }
    if let number = args.number {
      guard number > 0, number < 1000 else { throw AnnotateAgentToolError.invalidArguments("number must be 1–999.") }
      context.counterValue = number
    }
    let diameter = AnnotationProperties.counterDiameter(for: context.properties.strokeWidth)
    let size = CGSize(width: diameter, height: diameter)
    let placement = try Self.placement(args.placement)
    var origin: CGPoint
    if target.isEmpty {
      origin = CGPoint(x: target.midX - diameter / 2, y: target.midY - diameter / 2)
    } else {
      let order: [Placement] = placement == .auto ? [.left, .above, .right, .below] : [placement]
      origin = Self.place(size: size, near: target, placement: placement, gap: 6, within: state.activeAnnotationBounds, autoOrder: order)
    }
    origin = Self.clamped(CGRect(origin: origin, size: size), to: state.activeAnnotationBounds).origin
    let centerPoint = CGPoint(x: origin.x + diameter / 2, y: origin.y + diameter / 2)
    guard let item = AnnotationFactory.createAnnotation(
      tool: .counter, from: centerPoint, to: centerPoint, path: [], context: context
    ) else {
      throw AnnotateAgentToolError.invalidArguments("Could not place that counter.")
    }
    return try insert(item, state: state)
  }

  private func addWatermark(_ args: WatermarkArguments, state: AnnotateState) throws -> AnnotateAgentToolResult {
    let text = args.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw AnnotateAgentToolError.invalidArguments("text is empty.") }
    var context = creationContext(for: .watermark, state: state)
    context.watermarkText = text
    if let raw = args.style {
      guard let style = WatermarkStyle(rawValue: raw) else {
        throw AnnotateAgentToolError.invalidArguments("style must be one of \(WatermarkStyle.allCases.map(\.rawValue).joined(separator: ", ")).")
      }
      context.properties.watermarkStyle = style
      context.properties.rotationDegrees = style.defaultRotationDegrees
    }
    let center = CGPoint(x: state.activeAnnotationBounds.midX, y: state.activeAnnotationBounds.midY)
    guard let item = AnnotationFactory.createAnnotation(tool: .watermark, from: center, to: center, path: [], context: context) else {
      throw AnnotateAgentToolError.invalidArguments("Could not add that watermark.")
    }
    return try insert(item, state: state)
  }

  // MARK: - Editing tools

  private func updateAnnotation(_ args: UpdateArguments, state: AnnotateState) throws -> AnnotateAgentToolResult {
    let id = try existingID(args.id, state: state)
    guard let item = state.annotations.first(where: { $0.id == id }) else {
      throw AnnotateAgentToolError.targetNotFound("annotation \(args.id)")
    }

    // Validate everything before touching state, so a bad field changes nothing.
    let color = try args.color.map(Self.parseColor)
    let presentation: TextPresentation? = try args.style.map {
      guard case .text = item.type else { throw AnnotateAgentToolError.invalidArguments("style only applies to text.") }
      guard let parsed = TextPresentation(rawValue: $0.lowercased()) else {
        throw AnnotateAgentToolError.invalidArguments("style must be plain, label or callout.")
      }
      return parsed
    }
    if args.text != nil {
      switch item.type {
      case .text, .watermark: break
      default: throw AnnotateAgentToolError.invalidArguments("text only applies to text and watermark annotations.")
      }
    }
    let moveTarget = try args.moveTo.map { try resolve($0, state: state) }

    // Apply first, then record the checkpoint only if something really changed.
    let before = state.annotations
    if let presentation, let index = state.annotations.firstIndex(where: { $0.id == id }), color == nil {
      // Keep text readable when the pill appears or disappears without an explicit color.
      let current = state.annotations[index].properties
      if presentation != .plain, current.textPresentation == .plain, current.fillColor == .clear {
        state.annotations[index].properties.fillColor = current.strokeColor
        state.annotations[index].properties.strokeColor = Self.contrastingTextColor(on: current.strokeColor)
      } else if presentation == .plain, current.textPresentation != .plain, current.fillColor != .clear {
        state.annotations[index].properties.strokeColor = current.fillColor
        state.annotations[index].properties.fillColor = .clear
      }
    }
    if let presentation {
      state.setTextPresentationWithoutUndo(id: id, presentation)
    }
    if let text = args.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
      if case .text = item.type {
        state.updateAnnotationText(id: id, text: text)
      } else {
        state.updateWatermarkText(id: id, text: text)
      }
    }

    var strokeColor: Color?
    var fillColor: Color?
    if let color {
      let current = state.annotations.first { $0.id == id } ?? item
      if case .text = current.type, current.properties.textPresentation != .plain {
        fillColor = color
        strokeColor = Self.contrastingTextColor(on: color)
      } else if case .filledRectangle = current.type {
        strokeColor = color
        fillColor = color
      } else {
        strokeColor = color
      }
    }
    state.updateAnnotationProperties(
      id: id,
      strokeWidth: args.strokeWidth.map(AnnotationProperties.clampedControlValue),
      fontSize: args.fontSize.map { min(max($0, 12), 72) },
      strokeColor: strokeColor,
      fillColor: fillColor,
      opacity: args.opacity.map { min(max($0, 0.1), 1) },
      recordsUndo: false
    )

    if let moveTarget, let index = state.annotations.firstIndex(where: { $0.id == id }) {
      let current = state.annotations[index]
      let destination = center(of: moveTarget)
      let dx = destination.x - current.bounds.midX
      let dy = destination.y - current.bounds.midY
      state.annotations[index] = current.translatedBy(dx: dx, dy: dy)
      onEvent?(.targetResolved(state.annotations[index].bounds))
    }

    guard commitChange(state, annotationsBefore: before) else {
      return .success(["id": reference(for: id), "changed": false])
    }
    onEvent?(.annotationsUpdated([id]))
    return .success(["id": reference(for: id)])
  }

  /// Counts a change and records the run's checkpoint (from `before`) only when the
  /// annotations really differ, so no-op calls leave no undo step.
  private func commitChange(_ state: AnnotateState, annotationsBefore before: [AnnotationItem]) -> Bool {
    guard Self.differ(before, state.annotations) else { return false }
    if !didRecordUndo {
      state.recordUndoCheckpoint(annotationsBeforeChange: before)
      didRecordUndo = true
    }
    state.hasUnsavedChanges = true
    changeCount += 1
    return true
  }

  /// `AnnotationItem ==` compares ids only; this compares content and order.
  nonisolated static func differ(_ lhs: [AnnotationItem], _ rhs: [AnnotationItem]) -> Bool {
    guard lhs.count == rhs.count else { return true }
    return zip(lhs, rhs).contains { a, b in
      a.id != b.id || a.type != b.type || a.bounds != b.bounds || a.properties != b.properties
    }
  }

  private func deleteAnnotations(_ args: IDsArguments, state: AnnotateState) throws -> AnnotateAgentToolResult {
    let ids: Set<UUID>
    if args.ids.map({ $0.lowercased() }) == ["all"] {
      ids = Set(state.annotations.map(\.id))
    } else {
      ids = Set(try args.ids.map { try existingID($0, state: state) })
    }
    guard !ids.isEmpty else { return .success(["deleted": 0]) }
    recordUndoIfNeeded(state)
    state.removeAnnotationsWithoutUndo(ids)
    createdAnnotationIDs.removeAll { ids.contains($0) }
    changeCount += 1
    onEvent?(.annotationsRemoved(Array(ids)))
    return .success(["deleted": ids.count])
  }

  private func arrange(_ args: ArrangeArguments, state: AnnotateState) throws -> AnnotateAgentToolResult {
    let action: AnnotationArrangeAction
    switch args.order.lowercased() {
    case "front": action = .bringToFront
    case "forward": action = .bringForward
    case "backward": action = .sendBackward
    case "back": action = .sendToBack
    default: throw AnnotateAgentToolError.invalidArguments("order must be front, forward, backward or back.")
    }
    let ids = Set(try args.ids.map { try existingID($0, state: state) })
    let before = state.annotations
    state.arrangeAnnotationsWithoutUndo(ids, action: action)
    let changed = commitChange(state, annotationsBefore: before)
    if changed {
      onEvent?(.annotationsUpdated(Array(ids)))
    }
    return .success(["changed": changed])
  }

  private func select(_ args: IDsArguments, state: AnnotateState) throws -> AnnotateAgentToolResult {
    let ids = Set(try args.ids.map { try existingID($0, state: state) })
    state.setSelectedAnnotationIds(ids)
    return .success(["selected": ids.count])
  }

  private func setCanvas(_ args: CanvasArguments, state: AnnotateState) throws -> AnnotateAgentToolResult {
    let background = try args.background.map(Self.parseBackground)
    let alignment: ImageAlignment? = try args.alignment.map {
      guard let parsed = ImageAlignment(rawValue: $0) else {
        throw AnnotateAgentToolError.invalidArguments("alignment must be one of \(ImageAlignment.allCases.map(\.rawValue).joined(separator: ", ")).")
      }
      return parsed
    }
    guard background != nil || args.padding != nil || args.inset != nil || args.shadow != nil
      || args.cornerRadius != nil || alignment != nil else {
      throw AnnotateAgentToolError.invalidArguments("Give at least one setting to change.")
    }

    if canvasBeforeRun == nil {
      canvasBeforeRun = CanvasSnapshot(state: state)
    }
    if let background {
      state.backgroundStyle = background
      if background != .none, args.padding == nil, state.padding < 16 {
        state.padding = 48
      }
    }
    if let padding = args.padding { state.padding = min(max(padding, 0), 100) }
    if let inset = args.inset { state.inset = min(max(inset, 0), 50) }
    if let shadow = args.shadow { state.shadowIntensity = min(max(shadow, 0), 1) }
    if let radius = args.cornerRadius { state.cornerRadius = min(max(radius, 0), 32) }
    if let alignment { state.imageAlignment = alignment }

    changeCount += 1
    onEvent?(.canvasChanged)
    return .success([:])
  }

  // MARK: - Insertion

  private func insert(_ item: AnnotationItem?, state: AnnotateState) throws -> AnnotateAgentToolResult {
    guard let item else { throw AnnotateAgentToolError.invalidArguments("Could not create that annotation.") }
    return try insert([item], state: state)
  }

  private func insert(_ items: [AnnotationItem], state: AnnotateState) throws -> AnnotateAgentToolResult {
    recordUndoIfNeeded(state)
    state.annotations.append(contentsOf: items)
    state.hasUnsavedChanges = true
    createdAnnotationIDs.append(contentsOf: items.map(\.id))
    changeCount += 1
    for item in items {
      onEvent?(.annotationAdded(item.id))
    }
    let references = items.map { reference(for: $0.id) }
    if references.count == 1 {
      return .success(["id": references[0]])
    }
    return .success(["ids": references])
  }

  private func recordUndoIfNeeded(_ state: AnnotateState) {
    guard !didRecordUndo else { return }
    state.saveState()
    didRecordUndo = true
  }

  private func createShape(_ tool: AnnotationToolType, in rect: CGRect, context: AnnotationFactory.CreationContext) -> AnnotationItem? {
    AnnotationFactory.createAnnotation(
      tool: tool,
      from: CGPoint(x: rect.minX, y: rect.minY),
      to: CGPoint(x: rect.maxX, y: rect.maxY),
      path: [],
      context: context
    )
  }

  private func creationContext(for tool: AnnotationToolType, state: AnnotateState) -> AnnotationFactory.CreationContext {
    AnnotationFactory.CreationContext(
      properties: state.annotationCreationProperties(for: tool),
      arrowStyle: state.arrowStyle,
      arrowType: state.arrowType,
      arrowBendDirection: state.arrowBendDirection,
      arrowStartHead: state.arrowStartHead,
      arrowEndHead: state.arrowEndHead,
      blurType: state.blurType,
      counterValue: state.nextCounterValue(),
      watermarkText: state.watermarkText,
      activeAnnotationBounds: state.activeAnnotationBounds
    )
  }

  private func applyStyle(
    color: String?,
    strokeWidth: CGFloat?,
    to properties: inout AnnotationProperties,
    tool: AnnotationToolType
  ) throws {
    if let color {
      let parsed = try Self.parseColor(color)
      properties.strokeColor = parsed
      if tool == .filledRectangle { properties.fillColor = parsed }
    }
    if let strokeWidth {
      properties.strokeWidth = AnnotationProperties.clampedControlValue(strokeWidth)
    }
  }

  // MARK: - Targets

  /// Target → annotate-space rect (empty size for points). Announces it to the overlay.
  func resolve(_ target: AnnotateAgentTarget, state: AnnotateState) throws -> CGRect {
    let rect = try resolveWithoutEvent(target, state: state)
    onEvent?(.targetResolved(rect))
    return rect
  }

  private func resolveWithoutEvent(_ target: AnnotateAgentTarget, state: AnnotateState) throws -> CGRect {
    let imageBounds = state.sourceImageBounds
    switch target {
    case .text(let query):
      guard let index = AnnotateAgentTextMatcher.matches(query, in: analysis.textBlocks.map(\.text)).first else {
        throw AnnotateAgentToolError.targetNotFound("no text matching \"\(query)\"")
      }
      return analysis.textBlocks[index].bounds
    case .reference(let raw):
      let reference = raw.lowercased()
      guard let kind = reference.first, let number = Int(reference.dropFirst()), number > 0 else {
        throw AnnotateAgentToolError.targetNotFound("'\(raw)'")
      }
      switch kind {
      case "t":
        guard number <= analysis.textBlocks.count else { throw AnnotateAgentToolError.targetNotFound("text block \(raw)") }
        return analysis.textBlocks[number - 1].bounds
      case "e":
        guard number <= analysis.elements.count else { throw AnnotateAgentToolError.targetNotFound("element \(raw)") }
        return analysis.elements[number - 1]
      default:
        let id = try existingID(raw, state: state)
        guard let item = state.annotations.first(where: { $0.id == id }) else {
          throw AnnotateAgentToolError.targetNotFound("annotation \(raw)")
        }
        return item.bounds
      }
    case .rect(let agentRect):
      let rect = AnnotateAgentCoordinates.annotateRect(fromAgent: agentRect.standardized, imageHeight: state.imageHeight)
        .intersection(imageBounds)
      guard !rect.isNull, rect.width >= 1, rect.height >= 1 else {
        throw AnnotateAgentToolError.invalidArguments("rect \(Self.format(agentRect)) is outside the \(Int(imageBounds.width))×\(Int(imageBounds.height)) image.")
      }
      return rect
    case .point(let agentPoint):
      let point = AnnotateAgentCoordinates.annotatePoint(fromAgent: agentPoint, imageHeight: state.imageHeight)
      guard imageBounds.insetBy(dx: -1, dy: -1).contains(point) else {
        throw AnnotateAgentToolError.invalidArguments("point [\(Self.whole(agentPoint.x)), \(Self.whole(agentPoint.y))] is outside the \(Int(imageBounds.width))×\(Int(imageBounds.height)) image.")
      }
      return CGRect(origin: point, size: .zero)
    }
  }

  /// Text targets highlight row by row; anything else is one bar over the rect.
  private func resolveRows(_ target: AnnotateAgentTarget, state: AnnotateState) throws -> [CGRect] {
    let rect = try resolve(target, state: state)
    if let block = analysis.textBlocks.first(where: { $0.bounds == rect }) {
      return block.rows
    }
    guard !rect.isEmpty else {
      throw AnnotateAgentToolError.invalidArguments("a highlight needs text or a rect, not a point.")
    }
    return [rect]
  }

  private func existingID(_ reference: String, state: AnnotateState) throws -> UUID {
    guard let id = annotationID(for: reference), state.annotations.contains(where: { $0.id == id }) else {
      throw AnnotateAgentToolError.targetNotFound("annotation \(reference)")
    }
    return id
  }

  // MARK: - Geometry

  private func center(of rect: CGRect) -> CGPoint {
    CGPoint(x: rect.midX, y: rect.midY)
  }

  /// Pads a target; a point grows into a default-size box around it. Stays on the image.
  private func expanded(_ rect: CGRect, by padding: CGFloat, minimum: CGSize, state: AnnotateState) -> CGRect {
    let padding = min(max(padding, 0), 200)
    let bounds = state.activeAnnotationBounds
    if rect.isEmpty {
      // A point grows into a default box, shifted (not shrunk) to stay on the canvas.
      let box = CGRect(x: rect.midX - minimum.width / 2, y: rect.midY - minimum.height / 2, width: minimum.width, height: minimum.height)
      return Self.clamped(box, to: bounds)
    }
    let result = rect.insetBy(dx: -padding, dy: -padding).intersection(bounds)
    if result.isNull || result.width < 8 || result.height < 8 {
      return Self.clamped(CGRect(x: rect.midX - 8, y: rect.midY - 8, width: 16, height: 16), to: bounds)
    }
    return result
  }

  /// Where an arrow without `from` starts: the free direction with the most room, outside text.
  private func autoArrowStart(pointingAt target: CGRect, state: AnnotateState) -> CGPoint {
    let bounds = state.activeAnnotationBounds
    let length = min(max(min(bounds.width, bounds.height) * 0.16, 60), 200)
    let c = center(of: target)
    // Preference order when scores tie: diagonals from below, then sides. Annotate y grows up.
    let directions: [CGVector] = [
      CGVector(dx: 1, dy: -1), CGVector(dx: -1, dy: -1), CGVector(dx: 1, dy: 1), CGVector(dx: -1, dy: 1),
      CGVector(dx: 1, dy: 0), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1), CGVector(dx: 0, dy: 1),
    ]
    var best: (point: CGPoint, score: CGFloat)?
    for (order, raw) in directions.enumerated() {
      let norm = hypot(raw.dx, raw.dy)
      let direction = CGVector(dx: raw.dx / norm, dy: raw.dy / norm)
      let far = CGPoint(x: c.x + direction.dx * 10_000, y: c.y + direction.dy * 10_000)
      let edge = Self.edgePoint(of: target, toward: far, gap: 0)
      let start = CGPoint(x: edge.x + direction.dx * length, y: edge.y + direction.dy * length)
      let margin = min(start.x - bounds.minX, bounds.maxX - start.x, start.y - bounds.minY, bounds.maxY - start.y)
      var score = margin >= 12 ? 1_000 : margin * 4
      if analysis.textBlocks.contains(where: { $0.bounds.insetBy(dx: -4, dy: -4).contains(start) }) {
        score -= 400
      }
      score += min(margin, 120) * 0.2 - CGFloat(order) * 2
      if best == nil || score > best!.score {
        best = (start, score)
      }
    }
    return Self.clamped(point: best?.point ?? c, to: bounds.insetBy(dx: 4, dy: 4))
  }

  /// Point on `rect`'s border on the way from its center to `point`, pushed out by `gap`.
  nonisolated static func edgePoint(of rect: CGRect, toward point: CGPoint, gap: CGFloat) -> CGPoint {
    let c = CGPoint(x: rect.midX, y: rect.midY)
    let v = CGVector(dx: point.x - c.x, dy: point.y - c.y)
    let length = hypot(v.dx, v.dy)
    guard length > 0.001 else { return c }
    let halfWidth = rect.width / 2
    let halfHeight = rect.height / 2
    let scaleX = abs(v.dx) > 0.0001 ? halfWidth / abs(v.dx) : .infinity
    let scaleY = abs(v.dy) > 0.0001 ? halfHeight / abs(v.dy) : .infinity
    let scale = min(scaleX, scaleY)
    guard scale < 1 else { return c } // `point` is inside the rect
    let edge = CGPoint(x: c.x + v.dx * scale, y: c.y + v.dy * scale)
    return CGPoint(x: edge.x + v.dx / length * gap, y: edge.y + v.dy / length * gap)
  }

  nonisolated enum Placement: String {
    case auto, above, below, left, right, over
  }

  private static func placement(_ raw: String?) throws -> Placement {
    guard let raw else { return .auto }
    guard let placement = Placement(rawValue: raw.lowercased()) else {
      throw AnnotateAgentToolError.invalidArguments("placement must be auto, above, below, left, right or over.")
    }
    return placement
  }

  /// Origin (annotate space) for a box of `size` next to `target`. "above" is visually
  /// above, i.e. larger y in annotate space.
  nonisolated static func place(
    size: CGSize,
    near target: CGRect,
    placement: Placement,
    gap: CGFloat,
    within bounds: CGRect,
    autoOrder: [Placement] = [.right, .below, .above, .left]
  ) -> CGPoint {
    func origin(_ side: Placement) -> CGPoint {
      switch side {
      case .above: CGPoint(x: target.midX - size.width / 2, y: target.maxY + gap)
      case .below: CGPoint(x: target.midX - size.width / 2, y: target.minY - gap - size.height)
      case .left: CGPoint(x: target.minX - gap - size.width, y: target.midY - size.height / 2)
      case .right: CGPoint(x: target.maxX + gap, y: target.midY - size.height / 2)
      case .over, .auto: CGPoint(x: target.midX - size.width / 2, y: target.midY - size.height / 2)
      }
    }
    guard placement == .auto else { return origin(placement) }
    for side in autoOrder {
      let candidate = CGRect(origin: origin(side), size: size)
      if bounds.contains(candidate) { return candidate.origin }
    }
    return origin(.over)
  }

  nonisolated static func clamped(_ rect: CGRect, to bounds: CGRect) -> CGRect {
    var result = rect
    result.size.width = min(result.width, bounds.width)
    result.size.height = min(result.height, bounds.height)
    result.origin.x = min(max(result.minX, bounds.minX), bounds.maxX - result.width)
    result.origin.y = min(max(result.minY, bounds.minY), bounds.maxY - result.height)
    return result
  }

  nonisolated static func clamped(point: CGPoint, to bounds: CGRect) -> CGPoint {
    CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
  }

  // MARK: - Parsing & description

  nonisolated static func parseColor(_ raw: String) throws -> Color {
    guard let color = AnnotateAgentColor.parse(raw) else {
      throw AnnotateAgentToolError.invalidArguments("color '\(raw)' — use \(AnnotateAgentColor.validValuesDescription).")
    }
    return color
  }

  nonisolated static func parseBackground(_ raw: String) throws -> BackgroundStyle {
    let key = raw.lowercased().filter { $0.isLetter || $0.isNumber }
    if key == "none" { return .none }
    if let gradient = GradientPreset.allCases.first(where: { $0.rawValue.lowercased() == key }) {
      return .gradient(gradient)
    }
    if let color = AnnotateAgentColor.parse(raw) {
      return .solidColor(color)
    }
    throw AnnotateAgentToolError.invalidArguments(
      "background '\(raw)' — use none, a gradient (\(GradientPreset.allCases.map(\.rawValue).joined(separator: ", "))) or a color."
    )
  }

  nonisolated static func contrastingTextColor(on fill: Color) -> Color {
    let color = NSColor(fill).usingColorSpace(.sRGB) ?? .black
    let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
    return luminance > 0.6 ? .black : .white
  }

  private static func describe(_ style: BackgroundStyle) -> String {
    switch style {
    case .none: "none"
    case .gradient(let preset): preset.rawValue
    case .solidColor(let color): AnnotateAgentColor.describe(color)
    case .wallpaper: "wallpaper"
    case .blurred: "blurred wallpaper"
    }
  }

  private static func colorDescription(of item: AnnotationItem) -> String? {
    switch item.type {
    case .blur, .spotlight, .embeddedImage, .translation:
      return nil
    case .text where item.properties.textPresentation != .plain:
      return AnnotateAgentColor.describe(item.properties.fillColor)
    default:
      return AnnotateAgentColor.describe(item.properties.strokeColor)
    }
  }

  private static func textContent(of item: AnnotationItem) -> String? {
    switch item.type {
    case .text(let text): text
    case .watermark(let text): text
    case .counter(let value): "\(value)"
    case .translation(let block): block.translatedText
    default: nil
    }
  }

  /// Whole number for messages; never traps on huge or non-finite model input.
  nonisolated static func whole(_ value: CGFloat) -> Int {
    guard value.isFinite else { return 0 }
    return Int(min(max(value, -1_000_000_000), 1_000_000_000).rounded())
  }

  nonisolated private static func format(_ rect: CGRect) -> String {
    "[\(whole(rect.minX)), \(whole(rect.minY)), \(whole(rect.width)), \(whole(rect.height))]"
  }

  nonisolated private static func describe(_ error: DecodingError) -> String {
    switch error {
    case .keyNotFound(let key, _):
      return "missing '\(key.stringValue)'."
    case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
      let path = context.codingPath.map(\.stringValue).joined(separator: ".")
      return path.isEmpty ? context.debugDescription : "'\(path)': \(context.debugDescription)"
    @unknown default:
      return "could not read the arguments."
    }
  }
}

// MARK: - Canvas snapshot

@MainActor
private struct CanvasSnapshot {
  let backgroundStyle: BackgroundStyle
  let padding: CGFloat
  let inset: CGFloat
  let shadowIntensity: CGFloat
  let cornerRadius: CGFloat
  let imageAlignment: ImageAlignment

  init(state: AnnotateState) {
    backgroundStyle = state.backgroundStyle
    padding = state.padding
    inset = state.inset
    shadowIntensity = state.shadowIntensity
    cornerRadius = state.cornerRadius
    imageAlignment = state.imageAlignment
  }

  func apply(to state: AnnotateState) {
    state.backgroundStyle = backgroundStyle
    state.padding = padding
    state.inset = inset
    state.shadowIntensity = shadowIntensity
    state.cornerRadius = cornerRadius
    state.imageAlignment = imageAlignment
  }
}

// MARK: - Arguments

private struct FindTextArguments: Decodable {
  let query: String
}

private struct BoxArguments: Decodable {
  let target: AnnotateAgentTarget
  let color: String?
  let filled: Bool?
  let strokeWidth: CGFloat?
  let cornerRadius: CGFloat?
  let padding: CGFloat?
}

private struct OvalArguments: Decodable {
  let target: AnnotateAgentTarget
  let color: String?
  let strokeWidth: CGFloat?
  let padding: CGFloat?
}

private struct ArrowArguments: Decodable {
  let to: AnnotateAgentTarget
  let from: AnnotateAgentTarget?
  let color: String?
  let strokeWidth: CGFloat?
  let style: String?
}

private struct LineArguments: Decodable {
  let from: AnnotateAgentTarget
  let to: AnnotateAgentTarget
  let color: String?
  let strokeWidth: CGFloat?
  let dashed: Bool?
}

private struct TextArguments: Decodable {
  let text: String
  let target: AnnotateAgentTarget?
  let placement: String?
  let style: String?
  let color: String?
  let fontSize: CGFloat?
}

private struct HighlightArguments: Decodable {
  let target: AnnotateAgentTarget
  let color: String?
}

private struct BlurArguments: Decodable {
  let target: AnnotateAgentTarget
  let kind: String?
}

private struct SpotlightArguments: Decodable {
  let target: AnnotateAgentTarget
  let padding: CGFloat?
}

private struct CounterArguments: Decodable {
  let target: AnnotateAgentTarget
  let number: Int?
  let color: String?
  let placement: String?
}

private struct WatermarkArguments: Decodable {
  let text: String
  let style: String?
}

private struct UpdateArguments: Decodable {
  let id: String
  let color: String?
  let strokeWidth: CGFloat?
  let fontSize: CGFloat?
  let opacity: CGFloat?
  let text: String?
  let style: String?
  let moveTo: AnnotateAgentTarget?
}

/// Accepts `"ids": ["a1"]` or a single `"ids": "a1"`.
private struct IDsArguments: Decodable {
  let ids: [String]

  private enum CodingKeys: String, CodingKey { case ids }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let single = try? container.decode(String.self, forKey: .ids) {
      ids = [single]
    } else {
      ids = try container.decode([String].self, forKey: .ids)
    }
  }
}

private struct ArrangeArguments: Decodable {
  let ids: [String]
  let order: String

  private enum CodingKeys: String, CodingKey { case ids, order }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let single = try? container.decode(String.self, forKey: .ids) {
      ids = [single]
    } else {
      ids = try container.decode([String].self, forKey: .ids)
    }
    order = try container.decode(String.self, forKey: .order)
  }
}

private struct CanvasArguments: Decodable {
  let background: String?
  let padding: CGFloat?
  let inset: CGFloat?
  let shadow: CGFloat?
  let cornerRadius: CGFloat?
  let alignment: String?
}
