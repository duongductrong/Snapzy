//
//  AutomationCanvasEditorView.swift
//  Snapzy
//
//  Window content of the canvas editor, laid out like a native document window:
//  the canvas on the left, an inspector sidebar on the right (toggled from the
//  toolbar), and a thin status bar along the bottom with issues and zoom. The
//  window's toolbar (AppKit) holds the actions; see AutomationCanvasWindowController.
//

import SwiftUI

struct AutomationCanvasEditorView: View {
  @ObservedObject var model: AutomationCanvasEditorModel
  let isCloudConfigured: Bool
  let onSave: () -> Void

  private static let inspectorWidth: CGFloat = 300

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        ZStack(alignment: .bottomTrailing) {
          AutomationCanvasView(model: model, camera: model.camera)
          AutomationCanvasMinimapSlot(model: model, camera: model.camera)
            .padding(12)
        }
        if model.isInspectorVisible {
          Divider()
          AutomationCanvasInspector(model: model, isCloudConfigured: isCloudConfigured)
            .frame(width: Self.inspectorWidth)
        }
      }
      Divider()
      AutomationCanvasStatusBar(model: model)
    }
    .background(shortcuts)
    .frame(minWidth: 760, minHeight: 480)
  }

  /// Keyboard shortcuts of the toolbar actions (AppKit toolbar items have none).
  private var shortcuts: some View {
    ZStack {
      Button(L10n.Common.save, action: onSave)
        .keyboardShortcut("s", modifiers: .command)
      Button(L10n.Automations.canvasZoomIn) { model.zoom(by: 1.25) }
        .keyboardShortcut("=", modifiers: .command)
      Button(L10n.Automations.canvasZoomOut) { model.zoom(by: 1 / 1.25) }
        .keyboardShortcut("-", modifiers: .command)
      Button(L10n.Automations.canvasZoomToFit) { model.zoomToFit() }
        .keyboardShortcut("0", modifiers: .command)
    }
    .opacity(0)
    .frame(width: 0, height: 0)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

// MARK: - Status bar

/// Bottom bar: the first issue (click to jump to it), unconnected steps, zoom.
private struct AutomationCanvasStatusBar: View {
  @ObservedObject var model: AutomationCanvasEditorModel

  var body: some View {
    HStack(spacing: 12) {
      if let issue = model.issues.first {
        Button {
          model.selection = .step(issue.stepID)
          model.isInspectorVisible = true
          model.reveal(.step(issue.stepID))
        } label: {
          HStack(spacing: 4) {
            Image(systemName: issue.blocksRun ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
              .symbolRenderingMode(.multicolor)
            Text(L10n.Automations.issuesSummary(model.issues.count, issue.message))
              .lineLimit(1)
              .truncationMode(.tail)
          }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
      }
      if model.detachedCount > 0 {
        Label(L10n.Automations.canvasDetachedCount(model.detachedCount), systemImage: "link.badge.plus")
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 8)
      AutomationCanvasZoomMenu(model: model, camera: model.camera)
    }
    .font(.system(size: 11))
    .padding(.horizontal, 10)
    .frame(height: 24)
    .background(Color(nsColor: .windowBackgroundColor))
  }
}

/// Zoom percentage as a pop-up, like Preview and Pages.
private struct AutomationCanvasZoomMenu: View {
  @ObservedObject var model: AutomationCanvasEditorModel
  @ObservedObject var camera: AutomationCanvasCamera

  private static let levels: [CGFloat] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2]

  var body: some View {
    Menu {
      Button(L10n.Automations.canvasZoomToFit) { model.zoomToFit() }
      Button(L10n.Automations.canvasActualSize) { model.resetZoom() }
      Divider()
      ForEach(Self.levels, id: \.self) { level in
        Button(Self.percent(level)) { model.zoom(by: level / camera.viewport.scale) }
      }
    } label: {
      Text(verbatim: Self.percent(camera.viewport.scale))
        .monospacedDigit()
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .help(L10n.Automations.canvasZoomToFit)
  }

  private static func percent(_ scale: CGFloat) -> String {
    "\(Int((scale * 100).rounded()))%"
  }
}

// MARK: - Inspector

/// Sidebar inspector: the selected node's settings, or the automation's own when
/// nothing is selected.
private struct AutomationCanvasInspector: View {
  @ObservedObject var model: AutomationCanvasEditorModel
  let isCloudConfigured: Bool

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      content
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }

  // MARK: Header

  @ViewBuilder
  private var header: some View {
    HStack(spacing: 10) {
      if let node = model.selection {
        let info = AutomationCanvasNodeInfo.make(for: node, model: model)
        icon(info.symbol, tint: info.tint)
        VStack(alignment: .leading, spacing: 0) {
          Text(info.title)
            .font(.headline)
            .lineLimit(1)
          if !info.caption.isEmpty {
            Text(info.caption)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        Spacer(minLength: 8)
        if node.stepID != nil {
          Button {
            model.delete(node)
          } label: {
            Image(systemName: "trash")
          }
          .buttonStyle(.borderless)
          .help(L10n.Common.delete)
          .accessibilityLabel(L10n.Common.delete)
        }
      } else {
        icon(model.automation.symbol ?? model.automation.sourceSymbol, tint: PreferencesTab.automations.iconTint)
        Text(model.automation.displayName)
          .font(.headline)
          .lineLimit(1)
        Spacer(minLength: 0)
      }
    }
    .padding(.horizontal, 14)
    .frame(height: 48)
  }

  private func icon(_ symbol: String, tint: PreferencesIconTint) -> some View {
    RoundedRectangle(cornerRadius: Radius.controlXS, style: .continuous)
      .fill(tint.gradient)
      .frame(width: 24, height: 24)
      .overlay(
        Image(systemName: symbol)
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(.white)
      )
  }

  // MARK: Content

  @ViewBuilder
  private var content: some View {
    switch model.selection {
    case .trigger?:
      if model.automation.isSystemDefault {
        placeholder(L10n.Automations.systemDefaultEditorNote)
      } else {
        AutomationTriggersInspector(
          automation: $model.automation,
          shortcutIssue: $model.shortcutIssue,
          part: .triggers
        )
      }
    case .source?:
      if model.automation.isSystemDefault {
        placeholder(L10n.Automations.systemDefaultEditorNote)
      } else {
        AutomationTriggersInspector(
          automation: $model.automation,
          shortcutIssue: $model.shortcutIssue,
          part: .source,
          lastCaptureSpec: $model.lastCaptureSpec
        )
      }
    case .step(let id)?:
      if model.step(id) != nil {
        VStack(spacing: 0) {
          if model.detachedIDs.contains(id) {
            Label(L10n.Automations.canvasDetachedHelp, systemImage: "link.badge.plus")
              .font(.callout)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 14)
              .padding(.vertical, 10)
            Divider()
          }
          AutomationStepInspector(
            step: model.stepBinding(id),
            issues: model.issues.filter { $0.stepID == id },
            isCloudConfigured: isCloudConfigured,
            automationID: model.automation.id,
            stepsAfter: model.stepsAfter(id)
          )
          .id(id)
        }
      } else {
        placeholder(L10n.Automations.inspectorEmpty)
      }
    case nil:
      automationSettings
    }
  }

  private var automationSettings: some View {
    Form {
      Section {
        if model.automation.isSystemDefault {
          LabeledContent(L10n.Automations.nameLabel, value: model.automation.displayName)
        } else {
          TextField(L10n.Automations.nameLabel, text: $model.automation.name, prompt: Text(L10n.Automations.defaultName))
          if model.hasDuplicateName {
            Label(L10n.Automations.duplicateNameWarning, systemImage: "exclamationmark.triangle.fill")
              .symbolRenderingMode(.multicolor)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
      } footer: {
        Text(L10n.Automations.canvasInspectorHint)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .formStyle(.grouped)
  }

  private func placeholder(_ text: String) -> some View {
    Text(text)
      .font(.callout)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      .padding(24)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Minimap

/// Shows the minimap only when it is turned on and some node is off screen.
private struct AutomationCanvasMinimapSlot: View {
  @ObservedObject var model: AutomationCanvasEditorModel
  @ObservedObject var camera: AutomationCanvasCamera

  var body: some View {
    let visible = CGRect(origin: .zero, size: camera.canvasSize)
    let offscreen = !visible.contains(camera.viewport.toScreen(model.graph.bounds))
    if model.isMinimapVisible && offscreen {
      AutomationCanvasMinimap(model: model, camera: camera)
    }
  }
}

/// Overview of every node with the visible area; click or drag to move there.
struct AutomationCanvasMinimap: View {
  @ObservedObject var model: AutomationCanvasEditorModel
  @ObservedObject var camera: AutomationCanvasCamera
  static let size = CGSize(width: 180, height: 116)
  /// The mapped area is frozen while dragging, or it would shift under the pointer.
  @State private var dragWorld: CGRect?

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.controlS, style: .continuous)
    let world = dragWorld ?? worldRect
    Canvas { context, size in
      let map = mapping(world: world, size: size)
      for node in model.graph.allNodes {
        if model.automation.isSystemDefault && node == .trigger { continue }
        let rect = map(model.graph.frame(of: node))
        let color: Color = model.selection == node ? .accentColor : .secondary.opacity(0.5)
        context.fill(Path(roundedRect: rect, cornerRadius: min(2, rect.height / 3)), with: .color(color))
      }
      let frame = Path(map(visibleRect))
      context.stroke(frame, with: .color(.accentColor), lineWidth: 1)
    }
    .padding(8)
    .frame(width: Self.size.width, height: Self.size.height)
    .background(shape.fill(AutomationCanvasTheme.card))
    .overlay(shape.strokeBorder(AutomationCanvasTheme.hairline, lineWidth: 0.5))
    .shadow(color: AutomationCanvasTheme.shadow, radius: 2, y: 1)
    .contentShape(shape)
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { value in
          if dragWorld == nil { dragWorld = worldRect }
          let world = dragWorld ?? worldRect
          let inner = CGSize(width: Self.size.width - 16, height: Self.size.height - 16)
          let local = CGPoint(x: value.location.x - 8, y: value.location.y - 8)
          model.center(on: unmap(local, world: world, size: inner))
        }
        .onEnded { _ in dragWorld = nil }
    )
    .help(L10n.Automations.canvasMinimap)
    .accessibilityLabel(L10n.Automations.canvasMinimap)
  }

  private var visibleRect: CGRect {
    let origin = camera.viewport.toCanvas(.zero)
    let end = camera.viewport.toCanvas(CGPoint(x: camera.canvasSize.width, y: camera.canvasSize.height))
    return CGRect(x: origin.x, y: origin.y, width: end.x - origin.x, height: end.y - origin.y)
  }

  /// Nodes plus the visible area, padded.
  private var worldRect: CGRect {
    model.graph.bounds.union(visibleRect).insetBy(dx: -80, dy: -80)
  }

  private func mapping(world: CGRect, size: CGSize) -> (CGRect) -> CGRect {
    let scale = min(size.width / max(1, world.width), size.height / max(1, world.height))
    let dx = (size.width - world.width * scale) / 2
    let dy = (size.height - world.height * scale) / 2
    return { rect in
      CGRect(
        x: (rect.minX - world.minX) * scale + dx,
        y: (rect.minY - world.minY) * scale + dy,
        width: max(2, rect.width * scale),
        height: max(2, rect.height * scale)
      )
    }
  }

  private func unmap(_ point: CGPoint, world: CGRect, size: CGSize) -> CGPoint {
    let scale = min(size.width / max(1, world.width), size.height / max(1, world.height))
    let dx = (size.width - world.width * scale) / 2
    let dy = (size.height - world.height * scale) / 2
    return CGPoint(x: (point.x - dx) / scale + world.minX, y: (point.y - dy) / scale + world.minY)
  }
}
