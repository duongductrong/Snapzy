//
//  AutomationCanvasNodeView.swift
//  Snapzy
//
//  One node card. Drawn at the current zoom (sizes multiplied by `scale`)
//  instead of being scaled as a bitmap, so text stays sharp at any zoom.
//

import SwiftUI

/// What a node shows.
struct AutomationCanvasNodeInfo {
  var symbol: String
  var title: String
  var subtitle: String
  var caption: String
  var tint: PreferencesIconTint
  /// The subtitle is an empty-state hint (e.g. no trigger yet), drawn as a call to action.
  var isPlaceholder = false
}

extension AutomationCanvasNodeInfo {
  static let coordinateSpace = "automationCanvas"

  @MainActor
  static func make(for node: AutomationCanvasNodeID, model: AutomationCanvasEditorModel) -> AutomationCanvasNodeInfo {
    let automation = model.automation
    switch node {
    case .trigger:
      return AutomationCanvasNodeInfo(
        symbol: automation.isSystemDefault ? "camera.shutter.button" : "bolt.fill",
        title: L10n.Automations.canvasTriggerNode,
        subtitle: automation.isSystemDefault ? L10n.Automations.canvasAfterCapture : triggerSummary(automation),
        caption: L10n.Automations.canvasTriggerCaption,
        tint: PreferencesIconTint(hue: 40, saturation: 0.85),
        isPlaceholder: !automation.isSystemDefault && triggerParts(automation).isEmpty
      )
    case .source:
      let title: String = switch automation.source {
      case .capture(let spec): spec.mode.displayName
      case .input: L10n.Automations.sourceInputShort
      case .clipboardImage: L10n.Automations.sourceClipboard
      case .unsupported: L10n.Automations.unsupported
      }
      let subtitle: String = switch automation.source {
      case .capture(let spec) where spec.mode.isRecording: spec.recordingOutput.displayName
      default: ""
      }
      return AutomationCanvasNodeInfo(
        symbol: automation.sourceSymbol,
        title: title,
        subtitle: subtitle,
        caption: L10n.Automations.sourceLabel,
        tint: PreferencesIconTint(hue: 186, saturation: 0.65)
      )
    case .step(let id):
      guard let step = model.step(id), let action = step.action else {
        return AutomationCanvasNodeInfo(
          symbol: "questionmark.square.dashed",
          title: L10n.Automations.unsupported,
          subtitle: "",
          caption: "",
          tint: .graphite
        )
      }
      let group = AutomationStepGroup.group(of: action.kind)
      let summary = action.configSummary
      return AutomationCanvasNodeInfo(
        symbol: action.kind.symbol,
        title: action.kind.displayName,
        subtitle: summary,
        caption: group?.title ?? "",
        tint: group?.canvasTint ?? .graphite
      )
    }
  }

  @MainActor
  private static func triggerSummary(_ automation: Automation) -> String {
    let parts = triggerParts(automation)
    return parts.isEmpty ? L10n.Automations.canvasTriggerNone : parts.joined(separator: " · ")
  }

  @MainActor
  private static func triggerParts(_ automation: Automation) -> [String] {
    var parts: [String] = []
    if let hotkey = automation.hotkey { parts.append(hotkey.displayString) }
    if automation.showsInMenuBar { parts.append(L10n.Automations.canvasTriggerMenuBar) }
    if automation.showsInQuickAccess { parts.append(L10n.Automations.canvasTriggerQuickAccess) }
    if automation.showsInHistory { parts.append(L10n.Automations.canvasTriggerHistory) }
    if automation.showsInFinder { parts.append(L10n.Automations.canvasTriggerFinder) }
    if automation.showsInCaptureToolbar { parts.append(L10n.Automations.canvasTriggerCaptureToolbar) }
    if automation.externalInvocation { parts.append(L10n.Automations.canvasTriggerExternal) }
    return parts
  }
}

extension AutomationStepGroup {
  static func group(of kind: AutomationStepKind) -> AutomationStepGroup? {
    allCases.first { $0.kinds.contains(kind) }
  }

  var canvasTint: PreferencesIconTint {
    switch self {
    case .transform: PreferencesIconTint(hue: 214)
    case .deliver: PreferencesIconTint(hue: 145, saturation: 0.6)
    case .integrations: PreferencesIconTint(hue: 282, saturation: 0.55)
    case .control: PreferencesIconTint(hue: 24, saturation: 0.8)
    }
  }
}

/// One node card, drawn like a native control: a control-background card with a
/// hairline, a small icon tile in the step group's color, the title and a secondary
/// summary. Selection is an accent outline. Drawn at the current zoom (sizes times
/// `scale`) instead of scaling a bitmap, so text stays sharp at any zoom.
struct AutomationCanvasNodeView: View {
  let info: AutomationCanvasNodeInfo
  let scale: CGFloat
  var stepNumber: Int?
  var isSelected = false
  var isDetached = false
  var isDisabled = false
  var isDropTarget = false
  var isDragging = false
  var issue: AutomationChainIssue?
  var hasInput = true
  var hasOutput = true
  /// The output handle can start a link (not on the trigger, whose link is fixed).
  var canDragOutput = true
  /// Draws a "+" past the output handle (nothing linked after this node).
  var showsAddButton = false
  var onOutputDrag: (CGPoint) -> Void = { _ in }
  var onOutputDragEnd: (CGPoint) -> Void = { _ in }
  var onAdd: () -> Void = {}

  @State private var isHovering = false

  private var size: CGSize {
    CGSize(
      width: AutomationCanvasGraph.nodeSize.width * scale,
      height: AutomationCanvasGraph.nodeSize.height * scale
    )
  }

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: Radius.controlM * scale, style: .continuous)
  }

  var body: some View {
    card
      .frame(width: size.width, height: size.height)
      .overlay(alignment: .leading) {
        if hasInput { inputPort.offset(x: -portSize / 2) }
      }
      .overlay(alignment: .leading) {
        // Leading-aligned so the handle's center sits exactly on the right edge.
        if hasOutput { outputHandle.offset(x: size.width - handleSize / 2) }
      }
      .onHover { isHovering = $0 }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(accessibilityText)
      .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }

  private var accessibilityText: String {
    var parts: [String] = []
    if let stepNumber { parts.append("\(stepNumber)") }
    parts.append(info.title)
    if !info.subtitle.isEmpty { parts.append(info.subtitle) }
    return parts.joined(separator: ", ")
  }

  // MARK: Card

  private var card: some View {
    HStack(spacing: 9 * scale) {
      iconTile
      VStack(alignment: .leading, spacing: 1 * scale) {
        Text(info.title)
          .font(.system(size: 13 * scale, weight: .medium))
          .foregroundStyle(isDisabled ? Color.secondary : Color.primary)
          .lineLimit(1)
        if !info.subtitle.isEmpty {
          subtitle
        }
      }
      Spacer(minLength: 2 * scale)
      trailingAccessory
    }
    .padding(.leading, 10 * scale)
    .padding(.trailing, 10 * scale)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      shape
        .fill(AutomationCanvasTheme.card)
        .shadow(color: AutomationCanvasTheme.shadow, radius: (isDragging ? 6 : 1.5) * scale, y: (isDragging ? 3 : 0.5) * scale)
    )
    .overlay(border)
    .opacity(isDetached && !isSelected ? 0.75 : 1)
    .contentShape(shape)
  }

  @ViewBuilder
  private var subtitle: some View {
    Text(info.subtitle)
      .font(.system(size: 11 * scale))
      .foregroundStyle(info.isPlaceholder ? Color.accentColor : Color.secondary)
      .lineLimit(1)
      .truncationMode(.tail)
  }

  private var iconTile: some View {
    let side = 26 * scale
    return RoundedRectangle(cornerRadius: Radius.ornament * 1.5 * scale, style: .continuous)
      .fill(info.tint.gradient)
      .frame(width: side, height: side)
      .overlay(
        Image(systemName: info.symbol)
          .font(.system(size: 12.5 * scale, weight: .semibold))
          .foregroundStyle(.white)
      )
      .saturation(isDisabled ? 0 : 1)
      .opacity(isDisabled ? 0.55 : 1)
  }

  // MARK: Accessories

  @ViewBuilder
  private var trailingAccessory: some View {
    let side = 16 * scale
    if let issue {
      Image(systemName: issue.blocksRun ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
        .font(.system(size: 12 * scale))
        .symbolRenderingMode(.multicolor)
        .frame(width: side, height: side)
        .help(issue.message)
    } else if isDisabled {
      Image(systemName: "pause.circle")
        .font(.system(size: 12 * scale))
        .foregroundStyle(.secondary)
        .frame(width: side, height: side)
        .help(L10n.Automations.canvasStepDisabled)
    } else if isDetached {
      Image(systemName: "link.badge.plus")
        .font(.system(size: 11 * scale))
        .foregroundStyle(.secondary)
        .frame(width: side, height: side)
        .help(L10n.Automations.canvasDetachedHelp)
    } else if let stepNumber {
      Text("\(stepNumber)")
        .font(.system(size: 11 * scale).monospacedDigit())
        .foregroundStyle(.tertiary)
    }
  }

  @ViewBuilder
  private var border: some View {
    if isSelected || isDropTarget {
      shape.strokeBorder(Color.accentColor, lineWidth: max(1.5, 2 * scale))
    } else if let issue {
      shape.strokeBorder(issue.blocksRun ? Color.red : Color.orange, lineWidth: max(1, scale))
    } else if isDetached {
      shape.strokeBorder(AutomationCanvasTheme.port, style: StrokeStyle(lineWidth: max(0.75, scale), dash: [4 * scale, 3 * scale]))
    } else {
      shape.strokeBorder(AutomationCanvasTheme.hairline, lineWidth: max(0.5, 0.5 * scale))
    }
  }

  // MARK: Ports

  private var portSize: CGFloat { max(6, 8 * scale) }
  /// Hit area around the output port.
  private var handleSize: CGFloat { portSize + 14 }

  private func port(highlighted: Bool) -> some View {
    Circle()
      .fill(highlighted ? Color.accentColor : AutomationCanvasTheme.card)
      .overlay(
        Circle().strokeBorder(
          highlighted ? Color.accentColor : AutomationCanvasTheme.port,
          lineWidth: max(1, 1.25 * scale)
        )
      )
      .frame(width: portSize, height: portSize)
  }

  private var inputPort: some View {
    port(highlighted: isDropTarget)
  }

  private var outputHandle: some View {
    let isHot = isHovering && canDragOutput
    return HStack(spacing: 10 * scale) {
      port(highlighted: isHot)
        .frame(width: handleSize, height: handleSize)
        .contentShape(Circle())
        .highPriorityGesture(outputDrag, including: canDragOutput ? .all : .none)
        .help(canDragOutput ? L10n.Automations.canvasConnectHelp : "")

      if showsAddButton {
        AutomationCanvasAddHandle(scale: scale, action: onAdd)
      }
    }
    .fixedSize()
  }

  private var outputDrag: some Gesture {
    DragGesture(minimumDistance: 2, coordinateSpace: .named(AutomationCanvasNodeInfo.coordinateSpace))
      .onChanged { onOutputDrag($0.location) }
      .onEnded { onOutputDragEnd($0.location) }
  }
}

/// "+" after the last node of a chain.
private struct AutomationCanvasAddHandle: View {
  let scale: CGFloat
  let action: () -> Void
  @State private var isHovering = false

  var body: some View {
    let side = max(18, 22 * scale)
    Button(action: action) {
      Image(systemName: "plus")
        .font(.system(size: max(9, 11 * scale), weight: .semibold))
        .foregroundStyle(isHovering ? Color.accentColor : Color.secondary)
        .frame(width: side, height: side)
        .background(Circle().fill(AutomationCanvasTheme.card))
        .overlay(Circle().strokeBorder(isHovering ? Color.accentColor : AutomationCanvasTheme.hairline, lineWidth: 1))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .help(L10n.Automations.addStep)
    .accessibilityLabel(L10n.Automations.addStep)
  }
}
