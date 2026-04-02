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

  /// Vibrant gradient tints per severity — provides visual distinction on the neutral background.
  var iconGradientColors: [Color] {
    switch self {
    case .info: return [Color.blue, Color.cyan]
    case .success: return [Color.green, Color.mint]
    case .warning: return [Color.orange, Color.yellow]
    case .error: return [Color.red, Color.pink]
    }
  }

  // MARK: - Appearance-adaptive colors (inverted from system theme)

  /// Neutral background — dark on Light mode, light on Dark mode.
  var backgroundColor: NSColor {
    NSColor(name: nil) { appearance in
      if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
        return NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 0.97)
      } else {
        return NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 0.97)
      }
    }
  }

  var borderColor: NSColor {
    NSColor(name: nil) { appearance in
      if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
        return NSColor(srgbRed: 0.82, green: 0.82, blue: 0.84, alpha: 0.25)
      } else {
        return NSColor(srgbRed: 0.30, green: 0.30, blue: 0.32, alpha: 0.35)
      }
    }
  }

  var textColor: NSColor {
    NSColor(name: nil) { appearance in
      if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
        return NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
      } else {
        return NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1.0)
      }
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
  @State private var appeared = false

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      Image(systemName: style.iconName)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(
          LinearGradient(
            colors: style.iconGradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )

      Text(message)
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(Color(nsColor: style.textColor))
        .lineLimit(3)
        .multilineTextAlignment(.leading)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color(nsColor: style.backgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(Color(nsColor: style.borderColor), lineWidth: 0.5)
    )
    .scaleEffect(appeared ? 1.0 : 0.96)
    .onAppear {
      withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
        appeared = true
      }
    }
  }
}
