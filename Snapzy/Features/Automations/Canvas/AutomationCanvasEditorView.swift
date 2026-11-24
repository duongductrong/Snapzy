//
//  AutomationCanvasEditorView.swift
//  Snapzy
//
//  Window content of the canvas editor. The canvas fills the whole window, title
//  bar included; everything else floats over it on Liquid Glass: the header
//  (name, add, tidy up, zoom, save, more, inspector) along the top, issues and
//  the zoom pop-up along the bottom, and the inspector as a panel on the right. The canvas model knows which
//  area these cover so fitting and revealing aim for the part left visible.
//

import SwiftUI

struct AutomationCanvasEditorView: View {
  @ObservedObject var model: AutomationCanvasEditorModel
  @ObservedObject var titlebar: AutomationCanvasTitlebarMetrics
  let isCloudConfigured: Bool
  let onSave: () -> Void
  let onOpenInList: (() -> Void)?

  private static let margin: CGFloat = 12

  /// Top of the header: centered on the traffic lights, or the margin when they
  /// are hidden.
  private var headerTop: CGFloat {
    guard let centerY = titlebar.buttonsCenterY else { return Self.margin }
    return max(0, centerY - AutomationCanvasTheme.headerHeight / 2)
  }

  /// Leading inset of the header, past the traffic lights.
  private var headerLeading: CGFloat {
    guard let trailingX = titlebar.buttonsTrailingX else { return 0 }
    return max(0, trailingX + 16 - Self.margin)
  }

  var body: some View {
    ZStack {
      AutomationCanvasView(model: model, camera: model.camera)
        .ignoresSafeArea()
      chrome
    }
    .background(shortcuts)
    .frame(minWidth: 760, minHeight: 480)
  }

  /// Floating bars and the inspector panel. Empty space passes clicks through to
  /// the canvas.
  private var chrome: some View {
    VStack(spacing: Self.margin) {
      AutomationCanvasTopBar(model: model, onSave: onSave, onOpenInList: onOpenInList)
        .padding(.leading, headerLeading)
      // Two layers: the bottom bar (zoom, status, minimap) spans the full width,
      // and the inspector floats above it at full height, overlapping the
      // minimap in the corner rather than pushing it aside.
      ZStack(alignment: .bottomTrailing) {
        HStack(alignment: .bottom, spacing: 8) {
          AutomationCanvasZoomMenu(model: model, camera: model.camera)
          AutomationCanvasStatusPill(model: model)
          Spacer(minLength: 8)
          AutomationCanvasMinimapSlot(model: model, camera: model.camera)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        if model.isInspectorVisible {
          AutomationCanvasInspector(model: model, isCloudConfigured: isCloudConfigured)
            .frame(width: AutomationCanvasEditorModel.inspectorWidth)
            .frame(maxHeight: .infinity)
            .background(
              GeometryReader { proxy in
                Color.clear
                  .onAppear { model.inspectorFrame = proxy.frame(in: .global) }
                  .onChange(of: proxy.frame(in: .global)) { model.inspectorFrame = $0 }
                  .onDisappear { model.inspectorFrame = .null }
              }
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
      }
      .frame(maxHeight: .infinity)
    }
    .padding([.horizontal, .bottom], Self.margin)
    .padding(.top, headerTop)
    .ignoresSafeArea(.container, edges: .top)
    .animation(.easeOut(duration: 0.18), value: model.isInspectorVisible)
  }

  /// Keyboard shortcuts of the bar actions.
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
      Button(L10n.Automations.canvasToggleInspector) { model.isInspectorVisible.toggle() }
        .keyboardShortcut("i", modifiers: [.command, .option])
    }
    .opacity(0)
    .frame(width: 0, height: 0)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

private let barShape = Capsule(style: .continuous)

/// A run of header buttons sharing one glass capsule, sized like a macOS 26
/// toolbar item group.
private struct AutomationCanvasBarGroup<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    HStack(spacing: 0) { content }
      .buttonStyle(AutomationCanvasHeaderButtonStyle())
      .padding(.horizontal, AutomationCanvasTheme.headerHoverInset)
      .frame(height: AutomationCanvasTheme.headerHeight)
      .canvasFloating(barShape)
  }
}

/// Hairline between buttons of one group, like zoom out | zoom in.
private struct AutomationCanvasBarDivider: View {
  var body: some View {
    Rectangle()
      .fill(AutomationCanvasTheme.hairline)
      .frame(width: 1, height: 18)
      .padding(.horizontal, 2)
  }
}

private struct AutomationCanvasBarIcon: View {
  let symbol: String
  let help: String
  var isActive = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .foregroundStyle(isActive ? Color.accentColor : Color.primary)
    }
    .help(help)
    .accessibilityLabel(help)
  }
}

/// Button of the header groups: a toolbar-sized symbol with a capsule hover
/// highlight inside the group's glass.
private struct AutomationCanvasHeaderButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    AutomationCanvasHeaderButtonBody(configuration: configuration)
  }
}

private struct AutomationCanvasHeaderButtonBody: View {
  let configuration: ButtonStyleConfiguration
  @Environment(\.isEnabled) private var isEnabled
  @State private var isHovered = false

  var body: some View {
    configuration.label
      .font(.system(size: AutomationCanvasTheme.headerIconSize, weight: .regular))
      .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.6))
      .frame(minWidth: AutomationCanvasTheme.headerButtonSize, minHeight: AutomationCanvasTheme.headerButtonSize)
      .background(
        Capsule(style: .continuous)
          .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : (isHovered && isEnabled ? 0.08 : 0)))
          .padding(AutomationCanvasTheme.headerHoverInset)
      )
      .contentShape(Capsule(style: .continuous))
      .onHover { isHovered = $0 }
  }
}

// MARK: - Top bar

/// The window's header, floating: the automation's name (with "Unsaved
/// changes" under it), add and tidy up on the left; zoom, fit, save, more and
/// the inspector toggle on the right.
private struct AutomationCanvasTopBar: View {
  @ObservedObject var model: AutomationCanvasEditorModel
  let onSave: () -> Void
  let onOpenInList: (() -> Void)?

  private var canSave: Bool {
    model.hasUnsavedChanges && !model.issues.contains(where: \.blocksRun)
  }

  var body: some View {
    HStack(spacing: 10) {
      title
      AutomationCanvasBarGroup {
        AutomationCanvasBarIcon(symbol: "plus", help: L10n.Automations.canvasAddStepHelp) {
          model.openPicker(after: model.selection)
        }
        .disabled(!model.canAddStep)
        AutomationCanvasBarIcon(symbol: "rectangle.3.group", help: L10n.Automations.canvasTidyUp) {
          model.tidyUp()
        }
      }
      Spacer(minLength: 8)
      AutomationCanvasBarGroup {
        AutomationCanvasBarIcon(symbol: "minus.magnifyingglass", help: L10n.Automations.canvasZoomOut) {
          withAnimation(.easeOut(duration: 0.15)) { model.zoom(by: 1 / 1.25) }
        }
        AutomationCanvasBarDivider()
        AutomationCanvasBarIcon(symbol: "plus.magnifyingglass", help: L10n.Automations.canvasZoomIn) {
          withAnimation(.easeOut(duration: 0.15)) { model.zoom(by: 1.25) }
        }
      }
      AutomationCanvasBarGroup {
        AutomationCanvasBarIcon(
          symbol: "arrow.up.left.and.down.right.magnifyingglass",
          help: L10n.Automations.canvasZoomToFit
        ) {
          withAnimation(.easeOut(duration: 0.2)) { model.zoomToFit() }
        }
      }
      AutomationCanvasBarGroup {
        Button(action: onSave) {
          Text(L10n.Common.save)
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 12)
        }
        .disabled(!canSave)
        .help(L10n.Common.save)
      }
      AutomationCanvasBarGroup {
        Menu {
          if let onOpenInList {
            Button(L10n.Automations.canvasOpenInList, action: onOpenInList)
            Divider()
          }
          Toggle(L10n.Automations.canvasShowMinimap, isOn: $model.isMinimapVisible)
        } label: {
          Image(systemName: "ellipsis.circle")
            .font(.system(size: AutomationCanvasTheme.headerIconSize, weight: .regular))
            .frame(width: AutomationCanvasTheme.headerButtonSize, height: AutomationCanvasTheme.headerButtonSize)
            .contentShape(Capsule(style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.Automations.moreActions)
        .accessibilityLabel(L10n.Automations.moreActions)
        AutomationCanvasBarIcon(
          symbol: "sidebar.right",
          help: L10n.Automations.canvasToggleInspector,
          isActive: model.isInspectorVisible
        ) {
          model.isInspectorVisible.toggle()
        }
      }
    }
  }

  /// Name and subtitle, like a window title; clicking shows the automation's own
  /// settings in the inspector.
  /// The name as shown, or `nil` while it is blank.
  private var displayName: String? {
    let name = model.automation.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? nil : name
  }

  private var title: some View {
    Button {
      model.selection = nil
      model.isInspectorVisible = true
    } label: {
      // One line, centered on the traffic lights: the name (or the default
      // name, dimmed, while it is empty) and a small badge for unsaved edits.
      HStack(spacing: 8) {
        Text(displayName ?? L10n.Automations.defaultName)
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(displayName == nil ? Color.secondary : Color.primary)
          .lineLimit(1)
          .truncationMode(.tail)
          .layoutPriority(1)
        if model.hasUnsavedChanges {
          HStack(spacing: 4) {
            Circle()
              .fill(Color.orange)
              .frame(width: 6, height: 6)
            Text(L10n.Automations.canvasUnsaved)
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          .padding(.horizontal, 8)
          .frame(height: 20)
          .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.07)))
          .fixedSize()
          .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
      }
      .animation(.easeOut(duration: 0.15), value: model.hasUnsavedChanges)
      .frame(height: AutomationCanvasTheme.headerHeight)
      .frame(maxWidth: 360, alignment: .leading)
      .fixedSize(horizontal: true, vertical: false)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(L10n.Automations.nameLabel)
  }
}

// MARK: - Bottom bar

/// The first issue (click to jump to it) and the count of unconnected steps;
/// hidden when there is nothing to report.
private struct AutomationCanvasStatusPill: View {
  @ObservedObject var model: AutomationCanvasEditorModel

  var body: some View {
    let issue = model.issues.first
    if issue != nil || model.detachedCount > 0 {
      HStack(spacing: 12) {
        if let issue {
          Button {
            model.selection = .step(issue.stepID)
            model.isInspectorVisible = true
            model.reveal(.step(issue.stepID))
          } label: {
            HStack(spacing: 5) {
              Image(systemName: issue.blocksRun ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
              Text(L10n.Automations.issuesSummary(model.issues.count, issue.message))
                .lineLimit(1)
                .truncationMode(.tail)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
        if model.detachedCount > 0 {
          Label(L10n.Automations.canvasDetachedCount(model.detachedCount), systemImage: "link.badge.plus")
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .font(.system(size: 11))
      .padding(.horizontal, 12)
      .frame(height: 26)
      .frame(maxWidth: 480, alignment: .leading)
      .fixedSize(horizontal: true, vertical: false)
      .canvasFloating(barShape)
      .transition(.opacity)
    }
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
        .font(.system(size: 11).monospacedDigit())
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .padding(.horizontal, 12)
    .frame(height: 26)
    .canvasFloating(barShape)
    .help(L10n.Automations.canvasZoomToFit)
  }

  private static func percent(_ scale: CGFloat) -> String {
    "\(Int((scale * 100).rounded()))%"
  }
}

// MARK: - Inspector

/// Floating inspector panel: the selected node's settings, or the automation's
/// own when nothing is selected.
private struct AutomationCanvasInspector: View {
  @ObservedObject var model: AutomationCanvasEditorModel
  let isCloudConfigured: Bool

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
    VStack(spacing: 0) {
      header
      Divider()
      content
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .clipShape(shape)
    .canvasFloating(shape)
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
    let visible = model.unobscuredRect
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
    let shape = RoundedRectangle(cornerRadius: Radius.controlL, style: .continuous)
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
    .canvasFloating(shape)
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
