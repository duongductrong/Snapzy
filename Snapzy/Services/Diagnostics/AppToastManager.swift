//
//  AppToastManager.swift
//  Snapzy
//
//  Global lightweight toast presenter for non-blocking user feedback.
//

import AppKit
import SwiftUI

enum AppToastStyle {
  case info
  case success
  case warning
  case error

  var iconName: String {
    switch self {
    case .info: return "info.circle.fill"
    case .success: return "checkmark.circle.fill"
    case .warning: return "exclamationmark.triangle.fill"
    case .error: return "xmark.octagon.fill"
    }
  }

  var backgroundColor: NSColor {
    switch self {
    case .info: return NSColor(calibratedRed: 0.15, green: 0.35, blue: 0.75, alpha: 0.95)
    case .success: return NSColor(calibratedRed: 0.10, green: 0.50, blue: 0.20, alpha: 0.95)
    case .warning: return NSColor(calibratedRed: 0.75, green: 0.45, blue: 0.08, alpha: 0.95)
    case .error: return NSColor(calibratedRed: 0.65, green: 0.20, blue: 0.18, alpha: 0.95)
    }
  }

  var borderColor: NSColor {
    switch self {
    case .info: return NSColor(calibratedRed: 0.60, green: 0.75, blue: 0.95, alpha: 0.55)
    case .success: return NSColor(calibratedRed: 0.65, green: 0.90, blue: 0.70, alpha: 0.55)
    case .warning: return NSColor(calibratedRed: 0.95, green: 0.80, blue: 0.55, alpha: 0.55)
    case .error: return NSColor(calibratedRed: 0.95, green: 0.65, blue: 0.60, alpha: 0.55)
    }
  }
}

enum AppToastPosition {
  case topCenter
  case bottomCenter
}

@MainActor
final class AppToastManager {
  static let shared = AppToastManager()

  private var panel: NSPanel?
  private var dismissTask: Task<Void, Never>?
  private var activePresentationID = UUID()

  private init() {}

  func show(
    message: String,
    style: AppToastStyle = .error,
    position: AppToastPosition = .bottomCenter,
    duration: TimeInterval = 2.5
  ) {
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    guard let frame = frameForToast(message: trimmed, position: position) else { return }

    dismissTask?.cancel()
    let presentationID = UUID()
    activePresentationID = presentationID

    let contentView = NSHostingView(rootView: AppToastView(message: trimmed, style: style))

    if let panel {
      panel.contentView = contentView
      panel.setFrame(frame, display: true)
      if !panel.isVisible {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
      }
    } else {
      let newPanel = NSPanel(
        contentRect: frame,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
      )
      newPanel.level = .statusBar
      newPanel.isOpaque = false
      newPanel.backgroundColor = .clear
      newPanel.hasShadow = true
      newPanel.hidesOnDeactivate = false
      newPanel.ignoresMouseEvents = true
      newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
      newPanel.contentView = contentView
      newPanel.alphaValue = 0
      newPanel.orderFrontRegardless()
      panel = newPanel
    }

    if let panel {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.16
        panel.animator().alphaValue = 1
      }
    }

    dismissTask = Task { [weak self] in
      let delay = max(0.8, duration)
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      await self?.dismissIfNeeded(presentationID: presentationID)
    }
  }

  private func dismissIfNeeded(presentationID: UUID) {
    guard presentationID == activePresentationID else { return }
    guard let panel else { return }

    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.16
      panel.animator().alphaValue = 0
    }, completionHandler: {
      panel.orderOut(nil)
    })
  }

  private func frameForToast(message: String, position: AppToastPosition) -> CGRect? {
    guard let screen = targetScreen() else { return nil }
    let visibleFrame = screen.visibleFrame
    let maxWidth = min(560, visibleFrame.width - 32)
    let size = measuredToastSize(for: message, maxWidth: maxWidth)

    let x = visibleFrame.midX - size.width / 2
    let y: CGFloat
    switch position {
    case .topCenter:
      y = visibleFrame.maxY - size.height - 36
    case .bottomCenter:
      y = visibleFrame.minY + 36
    }

    return CGRect(x: x, y: y, width: size.width, height: size.height)
  }

  private func measuredToastSize(for message: String, maxWidth: CGFloat) -> CGSize {
    let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    let horizontalPadding: CGFloat = 56
    let verticalPadding: CGFloat = 20
    let minWidth: CGFloat = 240
    let maxTextWidth = max(120, maxWidth - horizontalPadding)
    let attributed = NSAttributedString(string: message, attributes: [.font: font])
    let textBounds = attributed.boundingRect(
      with: NSSize(width: maxTextWidth, height: CGFloat.greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    let width = min(maxWidth, max(minWidth, ceil(textBounds.width) + horizontalPadding))
    let height = max(44, ceil(textBounds.height) + verticalPadding)
    return CGSize(width: width, height: height)
  }

  private func targetScreen() -> NSScreen? {
    let mouseLocation = NSEvent.mouseLocation
    if let hovered = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
      return hovered
    }
    return NSScreen.main ?? NSScreen.screens.first
  }
}

private struct AppToastView: View {
  let message: String
  let style: AppToastStyle

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      Image(systemName: style.iconName)
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.white)

      Text(message)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.white)
        .lineLimit(3)
        .multilineTextAlignment(.center)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color(nsColor: style.backgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(Color(nsColor: style.borderColor), lineWidth: 1)
    )
  }
}
